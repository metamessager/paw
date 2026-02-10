import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/message.dart';
import '../models/channel.dart';
import '../models/remote_agent.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_search_delegate.dart';
import '../widgets/voice_record_overlay.dart';
import '../services/chat_service.dart';
import '../services/local_database_service.dart';
import '../services/token_service.dart';
import '../services/remote_agent_service.dart';
import '../services/attachment_service.dart';
import '../services/message_search_service.dart';
import '../services/local_file_storage_service.dart';
import '../services/audio_recording_service.dart';
import '../services/file_download_service.dart';
import '../services/a2a_protocol_service.dart';
import '../utils/message_utils.dart';
import 'agent_detail_screen.dart';

/// Intent for sending a message via Enter key shortcut.
class _SendMessageIntent extends Intent {
  const _SendMessageIntent();
}

class ChatScreen extends StatefulWidget {
  final String? agentId;
  final String? agentName;
  final String? agentAvatar;
  final String? channelId;

  const ChatScreen({
    Key? key,
    this.agentId,
    this.agentName,
    this.agentAvatar,
    this.channelId,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Message> _messages = [];
  Map<String, Message> _messageIdMap = {};
  bool _isLoading = false;
  bool _isSearching = false;
  String _searchQuery = '';
  String? _streamingMessageId;
  String _streamingContent = '';

  // 消息处理和队列
  bool _isProcessing = false;
  StreamCancellationToken? _cancellationToken;
  List<String> _messageQueue = [];

  // Agent 在线状态
  bool _isAgentOnline = false;
  bool _isCheckingHealth = true;
  Timer? _healthCheckTimer;

  // Quote reply state
  Message? _replyingToMessage;
  String? _highlightedMessageId;

  late ChatService _chatService;
  late AttachmentService _attachmentService;
  late MessageSearchService _searchService;
  String? _currentChannelId;

  // Voice recording
  late AudioRecordingService _audioRecordingService;
  late FileDownloadService _fileDownloadService;
  StreamSubscription<RecordingState>? _recordingSubscription;
  bool _isRecording = false;
  bool _isCancelZone = false;
  Duration _recordingElapsed = Duration.zero;
  double _recordingAmplitude = 0.0;
  bool _hasText = false;

  // Emoji picker
  bool _showEmojiPicker = false;
  final FocusNode _textFieldFocusNode = FocusNode();

  // Smart scroll: track whether user has scrolled away from bottom
  bool _isUserScrolledUp = false;
  int _unreadMessageCount = 0;

  // History request tracking
  int _historySentCount = 40;  // number of history messages already sent to agent
  String? _lastUserQuestion;   // last user question (for re-answer)
  Map<String, dynamic>? _pendingHistoryRequest;  // captured from SSE callback

  @override
  void initState() {
    super.initState();
    final databaseService = LocalDatabaseService();
    _chatService = ChatService(databaseService);
    _attachmentService = AttachmentService(
      LocalFileStorageService(),
      databaseService,
    );
    _searchService = MessageSearchService(databaseService);
    _audioRecordingService = AudioRecordingService();
    _fileDownloadService = FileDownloadService();
    _recordingSubscription = _audioRecordingService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isRecording = state.isRecording;
          _recordingElapsed = state.elapsed;
          _recordingAmplitude = state.amplitude;
        });
      }
    });
    _messageController.addListener(_onTextChanged);
    _scrollController.addListener(_onScroll);
    _textFieldFocusNode.addListener(_onFocusChanged);
    _loadMessages();
    _checkAgentHealth();
    // 预请求麦克风权限，避免长按录音时弹权限弹窗导致手势中断
    _audioRecordingService.requestPermission();

    // 定期检查 Agent 健康状态（每30秒）
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkAgentHealth();
    });
  }

  @override
  void dispose() {
    _cancellationToken?.cancel();
    _messageQueue.clear();
    _healthCheckTimer?.cancel();
    _recordingSubscription?.cancel();
    _audioRecordingService.dispose();
    _messageController.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScroll);
    _textFieldFocusNode.removeListener(_onFocusChanged);
    _textFieldFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _chatService.dispose();
    super.dispose();
  }

  /// 检查 Agent 在线状态
  Future<void> _checkAgentHealth() async {
    if (widget.agentId == null) return;

    try {
      final databaseService = LocalDatabaseService();
      final tokenService = TokenService(databaseService);
      final remoteAgentService = RemoteAgentService(databaseService, tokenService);
      final isOnline = await remoteAgentService.checkAgentHealth(
        widget.agentId!,
        timeout: const Duration(seconds: 3),
      );
      if (mounted) {
        setState(() {
          _isAgentOnline = isOnline;
          _isCheckingHealth = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAgentOnline = false;
          _isCheckingHealth = false;
        });
      }
    }
  }

  /// Load message history
  Future<void> _loadMessages() async {
    if (widget.agentId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentUser?.id ?? 'user';

      // Determine channel ID
      if (widget.channelId != null) {
        _currentChannelId = widget.channelId;
      } else {
        // 优先使用最近活跃的会话，而非固定的默认 channel
        final latestChannelId = await _chatService.getLatestActiveChannelId(userId, widget.agentId!);
        _currentChannelId = latestChannelId ?? _chatService.generateChannelId(userId, widget.agentId!);
      }

      final messages = await _chatService.loadChannelMessages(
        _currentChannelId!,
      );

      setState(() {
        _messages = messages;
        _rebuildMessageIdMap();
        _isLoading = false;
      });

      // Scroll to bottom
      _scrollToBottom(force: true);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load messages: $e')),
      );
    }
  }

  /// Send message to agent
  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    print('🎯 [ChatScreen] 用户尝试发送消息');
    print('   - Content: $content');
    print('   - Agent ID: ${widget.agentId}');
    print('   - Agent Name: ${widget.agentName}');

    if (content.isEmpty) {
      print('⚠️ [ChatScreen] 消息内容为空，取消发送');
      return;
    }

    if (widget.agentId == null) {
      print('❌ [ChatScreen] 未选择 Agent');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No agent selected')),
      );
      return;
    }

    _messageController.clear();

    // Capture reply state before clearing
    final replyToId = _replyingToMessage?.id;
    _cancelReply();

    // 如果正在处理消息，将新消息加入队列
    if (_isProcessing) {
      setState(() {
        _messageQueue.add(content);
      });
      print('📋 [ChatScreen] 消息加入队列，队列长度: ${_messageQueue.length}');
      return;
    }

    await _processMessage(content, replyToId: replyToId);
  }

  /// 停止当前流式回复
  void _stopStreaming() {
    print('🛑 [ChatScreen] 用户停止流式回复');
    _cancellationToken?.cancel();
  }

  /// 处理队列中的下一条消息
  Future<void> _processNextInQueue() async {
    if (_messageQueue.isEmpty) return;

    final nextContent = _messageQueue.removeAt(0);
    if (mounted) {
      setState(() {});
    }
    await _processMessage(nextContent);
  }

  /// 实际处理消息发送
  Future<void> _processMessage(String content, {String? replyToId}) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    print('   - User ID: $userId');
    print('   - User Name: $userName');

    setState(() {
      _isProcessing = true;
    });

    // Save the last user question for potential re-answer after history supplement
    _lastUserQuestion = content;

    // 创建取消令牌
    _cancellationToken = StreamCancellationToken();

    try {
      // Get RemoteAgent directly from database
      final databaseService = LocalDatabaseService();
      print('🔍 [ChatScreen] 从数据库获取 Agent 信息...');

      final remoteAgent = await databaseService.getRemoteAgentById(widget.agentId!);

      if (remoteAgent == null) {
        print('❌ [ChatScreen] Agent 在数据库中不存在');
        throw Exception('Agent not found');
      }

      print('✅ [ChatScreen] Agent 信息获取成功');
      print('   - ID: ${remoteAgent.id}');
      print('   - Name: ${remoteAgent.name}');
      print('   - Protocol: ${remoteAgent.protocol}');
      print('   - Status: ${remoteAgent.status}');
      print('   - Endpoint: ${remoteAgent.endpoint}');
      print('   - Token: ${remoteAgent.token.isNotEmpty ? "有" : "无"}');

      // Check if agent has valid endpoint
      if (remoteAgent.endpoint.isEmpty) {
        print('❌ [ChatScreen] Agent 没有有效的端点');
        throw Exception('Agent has no valid endpoint');
      }

      // If agent is not online, try health check first
      if (!remoteAgent.isOnline) {
        print('⚠️ [ChatScreen] Agent 离线，尝试健康检查...');

        // Import RemoteAgentService
        final remoteAgentService = RemoteAgentService(
          databaseService,
          TokenService(databaseService),
        );

        // Show loading indicator while checking health
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('Checking agent health...'),
                ],
              ),
              duration: Duration(seconds: 2),
            ),
          );
        }

        // Perform health check
        final isOnline = await remoteAgentService.checkAgentHealth(widget.agentId!);

        if (!isOnline) {
          print('❌ [ChatScreen] 健康检查失败，Agent 仍离线');
          throw Exception('Agent is not online. Please check if the agent server is running.');
        }

        print('✅ [ChatScreen] 健康检查成功，Agent 在线');

        // Reload agent data after health check
        final updatedAgent = await databaseService.getRemoteAgentById(widget.agentId!);
        if (updatedAgent == null || !updatedAgent.isOnline) {
          print('❌ [ChatScreen] 重新加载 Agent 失败');
          throw Exception('Failed to connect to agent');
        }

        print('✅ [ChatScreen] Agent 重新加载成功，状态: ${updatedAgent.status}');
      }

      // Add user message to UI immediately
      final userMessage = Message(
        id: 'temp_user_${DateTime.now().millisecondsSinceEpoch}',
        content: content,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        from: MessageFrom(id: userId, type: 'user', name: userName),
        to: MessageFrom(id: remoteAgent.id, type: 'agent', name: remoteAgent.name),
        type: MessageType.text,
        replyTo: replyToId,
      );

      // Create streaming placeholder for agent response
      _streamingMessageId = 'streaming_${DateTime.now().millisecondsSinceEpoch}';
      _streamingContent = '';
      final streamingMessage = Message(
        id: _streamingMessageId!,
        content: '',
        timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
        from: MessageFrom(id: remoteAgent.id, type: 'agent', name: remoteAgent.name),
        to: MessageFrom(id: userId, type: 'user', name: userName),
        type: MessageType.text,
      );

      setState(() {
        _messages.add(userMessage);
        _messages.add(streamingMessage);
        _messageIdMap[userMessage.id] = userMessage;
        _messageIdMap[streamingMessage.id] = streamingMessage;
      });
      _scrollToBottom(force: true);

      // Send message to agent via ChatService with streaming callback
      print('📤 [ChatScreen] 开始发送消息...');

      // Track how many history messages the agent already has (up to 40 are
      // sent with each normal task).  Use the actual message count so the
      // offset is correct when the agent requests more history later.
      if (_currentChannelId != null) {
        final currentMessages = await _chatService.loadChannelMessages(
          _currentChannelId!, limit: 40,
        );
        _historySentCount = currentMessages.where((m) => m.type == MessageType.text).length;
      }

      final agentResponse = await _chatService.sendMessageToAgent(
        content: content,
        agent: remoteAgent,
        userId: userId,
        userName: userName,
        channelId: _currentChannelId,
        replyToId: replyToId,
        cancellationToken: _cancellationToken,
        onStreamChunk: (chunk) {
          if (!mounted) return;
          _streamingContent += chunk;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
            if (idx != -1) {
              final updated = Message(
                id: _streamingMessageId!,
                content: _streamingContent,
                timestampMs: _messages[idx].timestampMs,
                from: _messages[idx].from,
                to: _messages[idx].to,
                type: MessageType.text,
                metadata: _messages[idx].metadata,
              );
              _messages[idx] = updated;
              _messageIdMap[updated.id] = updated;
            }
          });
          _scrollToBottom();
        },
        onActionConfirmation: (actionData) {
          if (!mounted) return;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
            if (idx != -1) {
              final updated = Message(
                id: _streamingMessageId!,
                content: _streamingContent,
                timestampMs: _messages[idx].timestampMs,
                from: _messages[idx].from,
                to: _messages[idx].to,
                type: MessageType.text,
                metadata: {'action_confirmation': Map<String, dynamic>.from(actionData)},
              );
              _messages[idx] = updated;
              _messageIdMap[updated.id] = updated;
            }
          });
        },
        onSingleSelect: (selectData) {
          if (!mounted) return;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
            if (idx != -1) {
              final updated = Message(
                id: _streamingMessageId!,
                content: _streamingContent,
                timestampMs: _messages[idx].timestampMs,
                from: _messages[idx].from,
                to: _messages[idx].to,
                type: MessageType.text,
                metadata: {'single_select': Map<String, dynamic>.from(selectData)},
              );
              _messages[idx] = updated;
              _messageIdMap[updated.id] = updated;
            }
          });
        },
        onMultiSelect: (selectData) {
          if (!mounted) return;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
            if (idx != -1) {
              final updated = Message(
                id: _streamingMessageId!,
                content: _streamingContent,
                timestampMs: _messages[idx].timestampMs,
                from: _messages[idx].from,
                to: _messages[idx].to,
                type: MessageType.text,
                metadata: {'multi_select': Map<String, dynamic>.from(selectData)},
              );
              _messages[idx] = updated;
              _messageIdMap[updated.id] = updated;
            }
          });
        },
        onFileUpload: (uploadData) {
          if (!mounted) return;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
            if (idx != -1) {
              final updated = Message(
                id: _streamingMessageId!,
                content: _streamingContent,
                timestampMs: _messages[idx].timestampMs,
                from: _messages[idx].from,
                to: _messages[idx].to,
                type: MessageType.text,
                metadata: {'file_upload': Map<String, dynamic>.from(uploadData)},
              );
              _messages[idx] = updated;
              _messageIdMap[updated.id] = updated;
            }
          });
        },
        onForm: (formData) {
          if (!mounted) return;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
            if (idx != -1) {
              final updated = Message(
                id: _streamingMessageId!,
                content: _streamingContent,
                timestampMs: _messages[idx].timestampMs,
                from: _messages[idx].from,
                to: _messages[idx].to,
                type: MessageType.text,
                metadata: {'form': Map<String, dynamic>.from(formData)},
              );
              _messages[idx] = updated;
              _messageIdMap[updated.id] = updated;
            }
          });
        },
        onFileMessage: (fileData) async {
          if (!mounted) return;
          try {
            final url = fileData['url'] as String?;
            final filename = fileData['filename'] as String?;
            final fileMimeType = fileData['mime_type'] as String?;
            final size = fileData['size'] as int?;

            if (url == null || url.isEmpty) {
              print('   [ChatScreen] FILE_MESSAGE missing url');
              return;
            }

            print('   [ChatScreen] Downloading file from: $url');

            final result = await _fileDownloadService.downloadAndSave(
              url,
              fileName: filename,
              mimeType: fileMimeType,
              expectedSize: size,
            );

            if (!mounted) return;

            // Build metadata matching existing image/file format
            final metadata = <String, dynamic>{
              'path': result.relativePath,
              'name': result.fileName,
              'type': result.mimeType,
              'size': result.fileSize,
              'source_url': url,
            };

            final msgType = result.isImage ? MessageType.image : MessageType.file;
            final databaseService = LocalDatabaseService();
            final agentId = widget.agentId ?? '';
            final agentName = widget.agentName ?? 'Agent';

            final messageId = 'file_${DateTime.now().millisecondsSinceEpoch}';
            await databaseService.createMessage(
              id: messageId,
              channelId: _currentChannelId ?? '',
              senderId: agentId,
              senderType: 'agent',
              senderName: agentName,
              content: result.isImage
                  ? '[Image: ${result.fileName}]'
                  : '[File: ${result.fileName}]',
              messageType: msgType.toString().split('.').last,
              metadata: metadata,
            );

            print('   [ChatScreen] File message saved: ${result.fileName}');
            await _loadMessages();
          } catch (e) {
            print('   [ChatScreen] File download failed: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('File download failed: $e')),
              );
            }
          }
        },
        onMessageMetadata: (metadata) {
          if (!mounted) return;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
            if (idx != -1) {
              final existingMetadata = Map<String, dynamic>.from(_messages[idx].metadata ?? {});
              existingMetadata.addAll(metadata);
              final updated = Message(
                id: _streamingMessageId!,
                content: _messages[idx].content,
                timestampMs: _messages[idx].timestampMs,
                from: _messages[idx].from,
                to: _messages[idx].to,
                type: _messages[idx].type,
                metadata: existingMetadata,
              );
              _messages[idx] = updated;
              _messageIdMap[updated.id] = updated;
            }
          });
        },
        onRequestHistory: (historyData) {
          // Capture the request — handled after sendMessageToAgent returns
          // so that _isProcessing / _cancellationToken remain valid.
          _pendingHistoryRequest = Map<String, dynamic>.from(historyData);
        },
      );

      // Handle pending history request (if agent asked for more context)
      bool _handledHistorySupplement = false;
      if (_pendingHistoryRequest != null && mounted) {
        final historyData = _pendingHistoryRequest!;
        _pendingHistoryRequest = null;

        // Delete the original agent response from DB — it only contains the
        // request_history directive text (e.g. "Task completed"), not a real answer.
        if (agentResponse != null) {
          try {
            await _chatService.deleteMessage(agentResponse.id);
          } catch (_) {}
        }

        final reason = historyData['reason'] as String? ?? 'Agent 需要更多上下文';
        final requestId = historyData['request_id'] as String? ?? '';
        final requestedCount = historyData['requested_count'] as int? ?? 40;

        // 1. Show system hint
        _addSystemHint('🔍 $reason');

        // 2. Show approval dialog
        final approved = await _showHistoryRequestDialog(reason);

        if (approved && mounted) {
          _handledHistorySupplement = true;
          // 3. Show loading hint
          _addSystemHint('📚 正在加载更多聊天记录...');

          // 4. Reset streaming state for the re-answer
          _streamingMessageId = 'streaming_reanswer_${DateTime.now().millisecondsSinceEpoch}';
          _streamingContent = '';
          _cancellationToken = StreamCancellationToken();
          final streamingMessage = Message(
            id: _streamingMessageId!,
            content: '',
            timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
            from: MessageFrom(id: remoteAgent.id, type: 'agent', name: remoteAgent.name),
            to: MessageFrom(id: userId, type: 'user', name: userName),
            type: MessageType.text,
          );
          setState(() {
            _messages.add(streamingMessage);
            _messageIdMap[streamingMessage.id] = streamingMessage;
          });
          _scrollToBottom(force: true);

          // 5. Send history supplement
          try {
            final supplementResult = await _chatService.sendHistorySupplement(
              agent: remoteAgent,
              sessionId: _currentChannelId!,
              requestId: requestId,
              originalQuestion: _lastUserQuestion ?? '',
              offset: _historySentCount,
              batchSize: requestedCount,
              onStreamChunk: (chunk) {
                if (!mounted) return;
                _streamingContent += chunk;
                setState(() {
                  final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
                  if (idx != -1) {
                    final updated = Message(
                      id: _streamingMessageId!,
                      content: _streamingContent,
                      timestampMs: _messages[idx].timestampMs,
                      from: _messages[idx].from,
                      to: _messages[idx].to,
                      type: MessageType.text,
                    );
                    _messages[idx] = updated;
                    _messageIdMap[updated.id] = updated;
                  }
                });
                _scrollToBottom();
              },
              cancellationToken: _cancellationToken,
            );

            if (supplementResult != null) {
              _historySentCount += supplementResult.actualSentCount;
              _addSystemHint('✅ 历史记录已加载，Agent 正在重新回答...');
            } else {
              _addSystemHint('⚠️ 没有更多历史记录可加载');
              // Remove the empty streaming placeholder
              setState(() {
                _messages.removeWhere((m) => m.id == _streamingMessageId);
                _messageIdMap.remove(_streamingMessageId);
              });
            }
          } catch (e) {
            print('❌ [ChatScreen] History supplement failed: $e');
            _addSystemHint('❌ 加载历史记录失败: $e');
            // Remove the empty streaming placeholder on error
            setState(() {
              _messages.removeWhere((m) => m.id == _streamingMessageId);
              _messageIdMap.remove(_streamingMessageId);
            });
          }
        } else {
          _addSystemHint('已忽略历史记录请求');
        }
      }

      // Replace temp messages with actual messages from database
      if (_handledHistorySupplement) {
        // History supplement flow handled the response — skip normal checks
        print('✅ [ChatScreen] History supplement handled, skipping normal response check');
      } else if (agentResponse != null) {
        print('✅ [ChatScreen] 收到 Agent 响应');
      } else {
        print('⚠️ [ChatScreen] 未收到 Agent 响应');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to get response from ${widget.agentName ?? "Agent"}')),
          );
        }
      }
      // Agent 响应成功，确认在线状态
      if (mounted) {
        setState(() {
          _isAgentOnline = true;
        });
      }
      // Reload all messages from DB to get canonical state
      await _loadMessages();
    } catch (e, stackTrace) {
      print('❌ [ChatScreen] 发送消息失败');
      print('   - Error: $e');
      print('   - Stack trace: $stackTrace');

      // 出错时清空队列，避免级联失败
      _messageQueue.clear();

      // Reload messages to show error message
      await _loadMessages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      _cancellationToken = null;
      _streamingMessageId = null;
      _streamingContent = '';
      _pendingHistoryRequest = null;
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
      // 处理队列中的下一条消息
      _processNextInQueue();
    }
  }

  /// Handle action confirmation button tap
  Future<void> _handleActionSelected(
    Message originalMessage,
    String confirmationId,
    String actionId,
    String actionLabel,
  ) async {
    if (_isProcessing) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    // Optimistic UI: immediately update message with selected action
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == originalMessage.id);
      if (idx != -1) {
        final updatedMetadata = Map<String, dynamic>.from(originalMessage.metadata ?? {});
        final actionConfirmation = Map<String, dynamic>.from(
          updatedMetadata['action_confirmation'] as Map<String, dynamic>? ?? {},
        );
        actionConfirmation['selected_action_id'] = actionId;
        actionConfirmation['selected_at'] = DateTime.now().millisecondsSinceEpoch;
        updatedMetadata['action_confirmation'] = actionConfirmation;

        final updated = Message(
          id: originalMessage.id,
          content: originalMessage.content,
          timestampMs: originalMessage.timestampMs,
          from: originalMessage.from,
          to: originalMessage.to,
          type: originalMessage.type,
          replyTo: originalMessage.replyTo,
          metadata: updatedMetadata,
        );
        _messages[idx] = updated;
        _messageIdMap[updated.id] = updated;
      }
      _isProcessing = true;
    });

    _cancellationToken = StreamCancellationToken();

    try {
      final databaseService = LocalDatabaseService();
      final remoteAgent = await databaseService.getRemoteAgentById(widget.agentId!);
      if (remoteAgent == null) throw Exception('Agent not found');

      // Create streaming placeholder for follow-up response
      _streamingMessageId = 'streaming_${DateTime.now().millisecondsSinceEpoch}';
      _streamingContent = '';
      final streamingMessage = Message(
        id: _streamingMessageId!,
        content: '',
        timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
        from: MessageFrom(id: remoteAgent.id, type: 'agent', name: remoteAgent.name),
        to: MessageFrom(id: userId, type: 'user', name: userName),
        type: MessageType.text,
      );

      setState(() {
        _messages.add(streamingMessage);
        _messageIdMap[streamingMessage.id] = streamingMessage;
      });
      _scrollToBottom(force: true);

      await _chatService.submitActionConfirmationResponse(
        originalMessage: originalMessage,
        confirmationId: confirmationId,
        selectedActionId: actionId,
        selectedActionLabel: actionLabel,
        agent: remoteAgent,
        userId: userId,
        userName: userName,
        channelId: _currentChannelId,
        cancellationToken: _cancellationToken,
        onStreamChunk: (chunk) {
          if (!mounted) return;
          _streamingContent += chunk;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
            if (idx != -1) {
              final updated = Message(
                id: _streamingMessageId!,
                content: _streamingContent,
                timestampMs: _messages[idx].timestampMs,
                from: _messages[idx].from,
                to: _messages[idx].to,
                type: MessageType.text,
              );
              _messages[idx] = updated;
              _messageIdMap[updated.id] = updated;
            }
          });
          _scrollToBottom();
        },
      );

      await _loadMessages();
    } catch (e) {
      print('Error handling action selection: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      await _loadMessages();
    } finally {
      _cancellationToken = null;
      _streamingMessageId = null;
      _streamingContent = '';
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// Handle single-select submission
  Future<void> _handleSingleSelectSubmitted(
    Message originalMessage,
    String selectId,
    String optionId,
    String optionLabel,
  ) async {
    if (_isProcessing) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    // Optimistic UI: immediately update message with selected option
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == originalMessage.id);
      if (idx != -1) {
        final updatedMetadata = Map<String, dynamic>.from(originalMessage.metadata ?? {});
        final singleSelect = Map<String, dynamic>.from(
          updatedMetadata['single_select'] as Map<String, dynamic>? ?? {},
        );
        singleSelect['selected_option_id'] = optionId;
        singleSelect['selected_at'] = DateTime.now().millisecondsSinceEpoch;
        updatedMetadata['single_select'] = singleSelect;

        final updated = Message(
          id: originalMessage.id,
          content: originalMessage.content,
          timestampMs: originalMessage.timestampMs,
          from: originalMessage.from,
          to: originalMessage.to,
          type: originalMessage.type,
          replyTo: originalMessage.replyTo,
          metadata: updatedMetadata,
        );
        _messages[idx] = updated;
        _messageIdMap[updated.id] = updated;
      }
      _isProcessing = true;
    });

    _cancellationToken = StreamCancellationToken();

    try {
      final databaseService = LocalDatabaseService();
      final remoteAgent = await databaseService.getRemoteAgentById(widget.agentId!);
      if (remoteAgent == null) throw Exception('Agent not found');

      _streamingMessageId = 'streaming_${DateTime.now().millisecondsSinceEpoch}';
      _streamingContent = '';
      final streamingMessage = Message(
        id: _streamingMessageId!,
        content: '',
        timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
        from: MessageFrom(id: remoteAgent.id, type: 'agent', name: remoteAgent.name),
        to: MessageFrom(id: userId, type: 'user', name: userName),
        type: MessageType.text,
      );

      setState(() {
        _messages.add(streamingMessage);
        _messageIdMap[streamingMessage.id] = streamingMessage;
      });
      _scrollToBottom(force: true);

      await _chatService.submitSelectResponse(
        originalMessage: originalMessage,
        metadataKey: 'single_select',
        selectedData: {'selected_option_id': optionId},
        responseText: 'Selected: $optionLabel',
        agent: remoteAgent,
        userId: userId,
        userName: userName,
        channelId: _currentChannelId,
        cancellationToken: _cancellationToken,
        onStreamChunk: (chunk) {
          if (!mounted) return;
          _streamingContent += chunk;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
            if (idx != -1) {
              final updated = Message(
                id: _streamingMessageId!,
                content: _streamingContent,
                timestampMs: _messages[idx].timestampMs,
                from: _messages[idx].from,
                to: _messages[idx].to,
                type: MessageType.text,
              );
              _messages[idx] = updated;
              _messageIdMap[updated.id] = updated;
            }
          });
          _scrollToBottom();
        },
      );

      await _loadMessages();
    } catch (e) {
      print('Error handling single-select submission: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      await _loadMessages();
    } finally {
      _cancellationToken = null;
      _streamingMessageId = null;
      _streamingContent = '';
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// Handle multi-select submission
  Future<void> _handleMultiSelectSubmitted(
    Message originalMessage,
    String selectId,
    List<String> optionIds,
    String summary,
  ) async {
    if (_isProcessing) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    // Optimistic UI: immediately update message with selected options
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == originalMessage.id);
      if (idx != -1) {
        final updatedMetadata = Map<String, dynamic>.from(originalMessage.metadata ?? {});
        final multiSelect = Map<String, dynamic>.from(
          updatedMetadata['multi_select'] as Map<String, dynamic>? ?? {},
        );
        multiSelect['selected_option_ids'] = optionIds;
        multiSelect['selected_at'] = DateTime.now().millisecondsSinceEpoch;
        updatedMetadata['multi_select'] = multiSelect;

        final updated = Message(
          id: originalMessage.id,
          content: originalMessage.content,
          timestampMs: originalMessage.timestampMs,
          from: originalMessage.from,
          to: originalMessage.to,
          type: originalMessage.type,
          replyTo: originalMessage.replyTo,
          metadata: updatedMetadata,
        );
        _messages[idx] = updated;
        _messageIdMap[updated.id] = updated;
      }
      _isProcessing = true;
    });

    _cancellationToken = StreamCancellationToken();

    try {
      final databaseService = LocalDatabaseService();
      final remoteAgent = await databaseService.getRemoteAgentById(widget.agentId!);
      if (remoteAgent == null) throw Exception('Agent not found');

      _streamingMessageId = 'streaming_${DateTime.now().millisecondsSinceEpoch}';
      _streamingContent = '';
      final streamingMessage = Message(
        id: _streamingMessageId!,
        content: '',
        timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
        from: MessageFrom(id: remoteAgent.id, type: 'agent', name: remoteAgent.name),
        to: MessageFrom(id: userId, type: 'user', name: userName),
        type: MessageType.text,
      );

      setState(() {
        _messages.add(streamingMessage);
        _messageIdMap[streamingMessage.id] = streamingMessage;
      });
      _scrollToBottom(force: true);

      await _chatService.submitSelectResponse(
        originalMessage: originalMessage,
        metadataKey: 'multi_select',
        selectedData: {'selected_option_ids': optionIds},
        responseText: 'Selected: $summary',
        agent: remoteAgent,
        userId: userId,
        userName: userName,
        channelId: _currentChannelId,
        cancellationToken: _cancellationToken,
        onStreamChunk: (chunk) {
          if (!mounted) return;
          _streamingContent += chunk;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
            if (idx != -1) {
              final updated = Message(
                id: _streamingMessageId!,
                content: _streamingContent,
                timestampMs: _messages[idx].timestampMs,
                from: _messages[idx].from,
                to: _messages[idx].to,
                type: MessageType.text,
              );
              _messages[idx] = updated;
              _messageIdMap[updated.id] = updated;
            }
          });
          _scrollToBottom();
        },
      );

      await _loadMessages();
    } catch (e) {
      print('Error handling multi-select submission: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      await _loadMessages();
    } finally {
      _cancellationToken = null;
      _streamingMessageId = null;
      _streamingContent = '';
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// Handle file upload submission
  Future<void> _handleFileUploadSubmitted(
    Message originalMessage,
    String uploadId,
    List<Map<String, dynamic>> files,
    String summary,
  ) async {
    if (_isProcessing) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    // Optimistic UI: immediately update message with uploaded files
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == originalMessage.id);
      if (idx != -1) {
        final updatedMetadata = Map<String, dynamic>.from(originalMessage.metadata ?? {});
        final fileUpload = Map<String, dynamic>.from(
          updatedMetadata['file_upload'] as Map<String, dynamic>? ?? {},
        );
        fileUpload['uploaded_files'] = files;
        fileUpload['uploaded_at'] = DateTime.now().millisecondsSinceEpoch;
        updatedMetadata['file_upload'] = fileUpload;

        final updated = Message(
          id: originalMessage.id,
          content: originalMessage.content,
          timestampMs: originalMessage.timestampMs,
          from: originalMessage.from,
          to: originalMessage.to,
          type: originalMessage.type,
          replyTo: originalMessage.replyTo,
          metadata: updatedMetadata,
        );
        _messages[idx] = updated;
        _messageIdMap[updated.id] = updated;
      }
      _isProcessing = true;
    });

    _cancellationToken = StreamCancellationToken();

    try {
      final databaseService = LocalDatabaseService();
      final remoteAgent = await databaseService.getRemoteAgentById(widget.agentId!);
      if (remoteAgent == null) throw Exception('Agent not found');

      _streamingMessageId = 'streaming_${DateTime.now().millisecondsSinceEpoch}';
      _streamingContent = '';
      final streamingMessage = Message(
        id: _streamingMessageId!,
        content: '',
        timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
        from: MessageFrom(id: remoteAgent.id, type: 'agent', name: remoteAgent.name),
        to: MessageFrom(id: userId, type: 'user', name: userName),
        type: MessageType.text,
      );

      setState(() {
        _messages.add(streamingMessage);
        _messageIdMap[streamingMessage.id] = streamingMessage;
      });
      _scrollToBottom(force: true);

      await _chatService.submitSelectResponse(
        originalMessage: originalMessage,
        metadataKey: 'file_upload',
        selectedData: {'uploaded_files': files},
        responseText: 'Uploaded files: $summary',
        agent: remoteAgent,
        userId: userId,
        userName: userName,
        channelId: _currentChannelId,
        cancellationToken: _cancellationToken,
        onStreamChunk: (chunk) {
          if (!mounted) return;
          _streamingContent += chunk;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
            if (idx != -1) {
              final updated = Message(
                id: _streamingMessageId!,
                content: _streamingContent,
                timestampMs: _messages[idx].timestampMs,
                from: _messages[idx].from,
                to: _messages[idx].to,
                type: MessageType.text,
              );
              _messages[idx] = updated;
              _messageIdMap[updated.id] = updated;
            }
          });
          _scrollToBottom();
        },
      );

      await _loadMessages();
    } catch (e) {
      print('Error handling file upload submission: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      await _loadMessages();
    } finally {
      _cancellationToken = null;
      _streamingMessageId = null;
      _streamingContent = '';
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// Handle form submission
  Future<void> _handleFormSubmitted(
    Message originalMessage,
    String formId,
    Map<String, dynamic> values,
    String summary,
  ) async {
    if (_isProcessing) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    // Optimistic UI: immediately update message with submitted values
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == originalMessage.id);
      if (idx != -1) {
        final updatedMetadata = Map<String, dynamic>.from(originalMessage.metadata ?? {});
        final formMeta = Map<String, dynamic>.from(
          updatedMetadata['form'] as Map<String, dynamic>? ?? {},
        );
        formMeta['submitted_values'] = values;
        formMeta['submitted_at'] = DateTime.now().millisecondsSinceEpoch;
        updatedMetadata['form'] = formMeta;

        final updated = Message(
          id: originalMessage.id,
          content: originalMessage.content,
          timestampMs: originalMessage.timestampMs,
          from: originalMessage.from,
          to: originalMessage.to,
          type: originalMessage.type,
          replyTo: originalMessage.replyTo,
          metadata: updatedMetadata,
        );
        _messages[idx] = updated;
        _messageIdMap[updated.id] = updated;
      }
      _isProcessing = true;
    });

    _cancellationToken = StreamCancellationToken();

    try {
      final databaseService = LocalDatabaseService();
      final remoteAgent = await databaseService.getRemoteAgentById(widget.agentId!);
      if (remoteAgent == null) throw Exception('Agent not found');

      _streamingMessageId = 'streaming_${DateTime.now().millisecondsSinceEpoch}';
      _streamingContent = '';
      final streamingMessage = Message(
        id: _streamingMessageId!,
        content: '',
        timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
        from: MessageFrom(id: remoteAgent.id, type: 'agent', name: remoteAgent.name),
        to: MessageFrom(id: userId, type: 'user', name: userName),
        type: MessageType.text,
      );

      setState(() {
        _messages.add(streamingMessage);
        _messageIdMap[streamingMessage.id] = streamingMessage;
      });
      _scrollToBottom(force: true);

      await _chatService.submitSelectResponse(
        originalMessage: originalMessage,
        metadataKey: 'form',
        selectedData: {'submitted_values': values},
        responseText: 'Form submitted: $summary',
        agent: remoteAgent,
        userId: userId,
        userName: userName,
        channelId: _currentChannelId,
        cancellationToken: _cancellationToken,
        onStreamChunk: (chunk) {
          if (!mounted) return;
          _streamingContent += chunk;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
            if (idx != -1) {
              final updated = Message(
                id: _streamingMessageId!,
                content: _streamingContent,
                timestampMs: _messages[idx].timestampMs,
                from: _messages[idx].from,
                to: _messages[idx].to,
                type: MessageType.text,
              );
              _messages[idx] = updated;
              _messageIdMap[updated.id] = updated;
            }
          });
          _scrollToBottom();
        },
      );

      await _loadMessages();
    } catch (e) {
      print('Error handling form submission: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      await _loadMessages();
    } finally {
      _cancellationToken = null;
      _streamingMessageId = null;
      _streamingContent = '';
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// Rebuild the message ID lookup map from the current _messages list
  void _rebuildMessageIdMap() {
    _messageIdMap = {for (final m in _messages) m.id: m};
  }

  /// 文本变化监听
  void _onTextChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  /// Start replying to a message
  void _startReply(Message message) {
    setState(() {
      _replyingToMessage = message;
    });
  }

  /// Cancel the current reply
  void _cancelReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  /// Scroll to a specific message and highlight it
  void _scrollToMessage(String messageId) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    _scrollController.animateTo(
      index * 80.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    setState(() {
      _highlightedMessageId = messageId;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });
  }

  /// Build reply preview bar above input
  Widget _buildReplyPreview() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    final msg = _replyingToMessage!;
    final previewText = msg.content.length > 80
        ? '${msg.content.substring(0, 80)}...'
        : msg.content;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          top: BorderSide(color: Colors.grey[200]!, width: 1),
          left: BorderSide(color: Theme.of(context).primaryColor, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg.from.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  previewText,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _cancelReply,
            child: Icon(
              Icons.close,
              size: 20,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// 发送语音消息
  Future<void> _sendVoiceMessage() async {
    final result = await _audioRecordingService.stopRecording();
    if (result == null) return;

    // 最短 1 秒
    if (result.durationMs < 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice message too short')),
      );
      // 删除临时文件
      try {
        await File(result.filePath).delete();
      } catch (_) {}
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    final message = await _attachmentService.saveVoiceMessage(
      filePath: result.filePath,
      durationMs: result.durationMs,
      waveform: result.waveform,
      channelId: _currentChannelId ?? '',
      userId: userId,
      userName: userName,
      agentId: widget.agentId ?? '',
    );

    if (message != null) {
      setState(() {
        _messages.add(message);
        _messageIdMap[message.id] = message;
      });
      _scrollToBottom(force: true);
    }
  }

  /// 添加系统提示消息（灰色居中小字）
  void _addSystemHint(String text) {
    if (!mounted) return;
    setState(() {
      final hint = Message(
        id: 'hint_${DateTime.now().millisecondsSinceEpoch}',
        content: text,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        from: MessageFrom(id: 'system', type: 'system', name: 'System'),
        type: MessageType.system,
      );
      _messages.add(hint);
      _messageIdMap[hint.id] = hint;
    });
    _scrollToBottom();
  }

  /// 显示历史请求审批对话框
  Future<bool> _showHistoryRequestDialog(String reason) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Agent 请求查看更多聊天记录'),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('忽略'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('同意'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 监听用户滚动，判断是否已主动上滑
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // 距离底部超过 150px 则认为用户主动上滑
    final isAtBottom = position.pixels >= position.maxScrollExtent - 150;
    if (_isUserScrolledUp && isAtBottom) {
      setState(() {
        _isUserScrolledUp = false;
        _unreadMessageCount = 0;
      });
    } else if (!_isUserScrolledUp && !isAtBottom) {
      setState(() {
        _isUserScrolledUp = true;
      });
    }
  }

  /// 滚动到底部
  void _scrollToBottom({bool force = false, bool isNewMessage = false}) {
    if (!force && _isUserScrolledUp) {
      // 用户主动上滑中，不强制滚动
      // 仅在新增消息时才增加未读计数（流式更新同一条消息不重复计数）
      if (isNewMessage) {
        setState(() {
          _unreadMessageCount++;
        });
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 用户点击"回到底部"按钮
  void _jumpToBottom() {
    setState(() {
      _isUserScrolledUp = false;
      _unreadMessageCount = 0;
    });
    if (_scrollController.hasClients) {
      // 先立即跳到当前已知的最底部
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      // 帧渲染后再次确认滚到真正底部（maxScrollExtent 可能因 rebuild 更新）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  /// 选择和发送图片
  Future<void> _pickAndSendImage() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    try {
      // 选择图片
      final image = await _attachmentService.pickImage();
      if (image == null) return;

      // 发送图片
      final message = await _attachmentService.saveAttachment(
        file: image,
        channelId: _currentChannelId ?? '',
        userId: userId,
        userName: userName,
        agentId: widget.agentId ?? '',
      );

      if (message != null) {
        setState(() {
          _messages.add(message);
          _messageIdMap[message.id] = message;
        });
        _scrollToBottom(force: true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending image: $e')),
      );
    }
  }

  /// 选择和发送文件
  Future<void> _pickAndSendFile() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    try {
      // 选择文件
      final file = await _attachmentService.pickFile();
      if (file == null) return;

      // 发送文件
      final message = await _attachmentService.saveAttachment(
        file: file,
        channelId: _currentChannelId ?? '',
        userId: userId,
        userName: userName,
        agentId: widget.agentId ?? '',
      );

      if (message != null) {
        setState(() {
          _messages.add(message);
          _messageIdMap[message.id] = message;
        });
        _scrollToBottom(force: true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending file: $e')),
      );
    }
  }

  /// 显示附件选项
  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo Library'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('File'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 搜索消息
  Future<void> _searchMessages(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchQuery = '';
        _isSearching = false;
      });
      await _loadMessages();
      return;
    }

    setState(() {
      _isSearching = true;
      _searchQuery = query;
    });

    try {
      final results = await _searchService.searchMessages(
        query: query,
        channelId: _currentChannelId,
      );

      setState(() {
        _messages = results.map((r) => r.message).toList();
        _rebuildMessageIdMap();
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search error: $e')),
      );
    }
  }

  /// 显示搜索对话框 - 搜索该 agent 所有 session 的消息
  void _showSearchDialog() async {
    // 获取该 agent 的所有 channel IDs
    List<String>? agentChannelIds;
    if (widget.agentId != null) {
      try {
        final databaseService = LocalDatabaseService();
        final channels = await databaseService.getChannelsForAgent(widget.agentId!);
        agentChannelIds = channels.map((c) => c.id).toList();
      } catch (_) {
        // fallback: 只搜索当前 channel
      }
    }

    if (!mounted) return;

    showSearch(
      context: context,
      delegate: MessageSearchDelegate(
        searchService: _searchService,
        channelIds: agentChannelIds,
        onResultTap: (message, channelId) {
          if (channelId != null && channelId != _currentChannelId) {
            // 跳转到对应 session
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(
                  agentId: widget.agentId,
                  agentName: widget.agentName,
                  agentAvatar: widget.agentAvatar,
                  channelId: channelId,
                ),
              ),
            );
          } else {
            // 当前会话内滚动到消息
            final index = _messages.indexWhere((m) => m.id == message.id);
            if (index != -1) {
              _scrollController.animateTo(
                index * 80.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          }
        },
      ),
    );
  }

  /// 删除消息
  Future<void> _deleteMessage(Message message) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';

    if (!MessageUtils.canDeleteMessage(message, userId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete this message')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (message.type == MessageType.image || message.type == MessageType.file || message.type == MessageType.audio) {
        await _attachmentService.deleteAttachment(message);
      } else {
        await _chatService.deleteMessage(message.id);
      }

      setState(() {
        _messages.removeWhere((m) => m.id == message.id);
        _messageIdMap.remove(message.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message deleted')),
      );
    }
  }

  /// Rollback: 删除此消息及之后的所有消息，可选填充输入框
  Future<void> _rollbackMessage(Message message, {bool reEdit = false}) async {
    if (widget.agentId == null || _currentChannelId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(reEdit ? 'Re-edit Message' : 'Rollback Messages'),
        content: const Text(
          'This will delete this message and all messages after it. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: Text(reEdit ? 'Re-edit' : 'Rollback'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final databaseService = LocalDatabaseService();
      final remoteAgent = await databaseService.getRemoteAgentById(widget.agentId!);
      if (remoteAgent == null) throw Exception('Agent not found');

      await _chatService.rollbackFromMessage(
        messageId: message.id,
        channelId: _currentChannelId!,
        agent: remoteAgent,
      );

      await _loadMessages();

      if (reEdit && mounted) {
        _messageController.text = message.content;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reEdit
                ? 'Messages rolled back. Edit and resend your message.'
                : 'Messages rolled back successfully.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rollback failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 1,
        title: Row(
            children: [
              // Agent头像
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.grey[200],
                child: widget.agentAvatar != null && widget.agentAvatar!.length > 2
                    ? ClipOval(
                        child: Image.network(
                          widget.agentAvatar!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Text(
                              widget.agentName?.isNotEmpty == true
                                  ? widget.agentName![0]
                                  : 'A',
                              style: const TextStyle(fontSize: 28),
                            );
                          },
                        ),
                      )
                    : Text(
                        widget.agentAvatar ??
                        (widget.agentName?.isNotEmpty == true
                            ? widget.agentName![0]
                            : 'A'),
                        style: const TextStyle(fontSize: 28),
                      ),
              ),
            const SizedBox(width: 12),
            // Agent名称和状态
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.agentName ?? 'AI Agent',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isProcessing) ...[
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'typing...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).primaryColor,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ] else if (_isCheckingHealth) ...[
                        Text(
                          'connecting...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ] else ...[
                        Text(
                          _isAgentOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 12,
                            color: _isAgentOnline ? Colors.green : Colors.grey,
                          ),
                        ),
                      ],
                      if (_currentChannelId != null) ...[
                        Text(
                          '  |  ',
                          style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                        ),
                        Flexible(
                          child: Text(
                            _shortSessionId(_currentChannelId!),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              _showAgentMenu();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Message list
          Expanded(
            child: Stack(
              children: [
                _messages.isEmpty && !_isLoading
                    ? _buildEmptyState()
                    : _buildMessageList(),
                // Scroll-to-bottom button
                if (_isUserScrolledUp)
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: _buildScrollToBottomButton(),
                  ),
              ],
            ),
          ),

          // Voice record overlay
          if (_isRecording)
            VoiceRecordOverlay(
              elapsed: _recordingElapsed,
              amplitude: _recordingAmplitude,
              isCancelZone: _isCancelZone,
            ),

          // Reply preview bar
          _buildReplyPreview(),

          // Queue indicator
          _buildQueueIndicator(),

          // Input area
          _buildInputArea(),

          // Emoji picker panel
          if (_showEmojiPicker)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                onEmojiSelected: _onEmojiSelected,
                onBackspacePressed: _onBackspacePressed,
                config: Config(
                  height: 250,
                  emojiViewConfig: EmojiViewConfig(
                    emojiSizeMax: 28 * (Platform.isIOS ? 1.30 : 1.0),
                    backgroundColor: Colors.white,
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    indicatorColor: Theme.of(context).primaryColor,
                    iconColorSelected: Theme.of(context).primaryColor,
                    backgroundColor: Colors.white,
                  ),
                  searchViewConfig: const SearchViewConfig(),
                  bottomActionBarConfig: const BottomActionBarConfig(
                    enabled: false,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 回到底部按钮（含未读消息计数）
  Widget _buildScrollToBottomButton() {
    return GestureDetector(
      onTap: _jumpToBottom,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_unreadMessageCount > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _unreadMessageCount > 99 ? '99+' : '$_unreadMessageCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: Colors.grey[700],
            ),
          ],
        ),
      ),
    );
  }

  /// 空状态
  Widget _buildMessageList() {
    // Pre-compute image messages list and index map for gallery support
    final allImageMessages = <Message>[];
    final imageIndexMap = <String, int>{};
    for (final msg in _messages) {
      if (msg.type == MessageType.image) {
        imageIndexMap[msg.id] = allImageMessages.length;
        allImageMessages.add(msg);
      }
    }

    // Pre-compute consecutive image groups from the same sender.
    // Maps the index of the first message in a group -> list of grouped messages.
    // Maps the index of subsequent messages in a group -> null (merged, should shrink).
    final imageGroupMap = <int, List<Message>>{};
    final mergedIndices = <int>{};

    int i = 0;
    while (i < _messages.length) {
      final msg = _messages[i];
      if (msg.type == MessageType.image) {
        // Collect consecutive images from the same sender
        final group = <Message>[msg];
        int j = i + 1;
        while (j < _messages.length &&
            _messages[j].type == MessageType.image &&
            _messages[j].from.id == msg.from.id) {
          group.add(_messages[j]);
          j++;
        }
        if (group.length > 1) {
          imageGroupMap[i] = group;
          for (int k = i + 1; k < j; k++) {
            mergedIndices.add(k);
          }
        }
        i = j;
      } else {
        i++;
      }
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMyMessage = message.from.type == 'user';

        // Check if we should show date separator
        final previousMessage = index > 0 ? _messages[index - 1] : null;
        final showDateSeparator = MessageUtils.shouldShowDateSeparator(
          previousMessage,
          message,
        );

        // If this message is merged into a previous image group, hide it
        // but still render date separators if needed.
        if (mergedIndices.contains(index)) {
          if (showDateSeparator) {
            return _buildDateSeparator(message.dateTime);
          }
          return const SizedBox.shrink();
        }

        // Look up quoted message from in-memory map
        Message? quotedMessage;
        final isReplyToPrevious = message.replyTo != null &&
            previousMessage != null &&
            previousMessage.id == message.replyTo;
        if (message.replyTo != null && !isReplyToPrevious) {
          quotedMessage = _messageIdMap[message.replyTo];
        }

        final isHighlighted = _highlightedMessageId == message.id;

        return RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showDateSeparator)
                _buildDateSeparator(message.dateTime),

              DecoratedBox(
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? Theme.of(context).primaryColor.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: GestureDetector(
                  onLongPress: () {
                    _showMessageMenu(message);
                  },
                  child: MessageBubble(
                    message: message,
                    isMyMessage: isMyMessage,
                    isStreaming: message.id == _streamingMessageId,
                    onStop: message.id == _streamingMessageId ? _stopStreaming : null,
                    onActionSelected: (confirmationId, actionId, actionLabel) {
                      _handleActionSelected(message, confirmationId, actionId, actionLabel);
                    },
                    onSingleSelectSubmitted: (selectId, optionId, optionLabel) {
                      _handleSingleSelectSubmitted(message, selectId, optionId, optionLabel);
                    },
                    onMultiSelectSubmitted: (selectId, optionIds, summary) {
                      _handleMultiSelectSubmitted(message, selectId, optionIds, summary);
                    },
                    onFileUploadSubmitted: (uploadId, files, summary) {
                      _handleFileUploadSubmitted(message, uploadId, files, summary);
                    },
                    onFormSubmitted: (formId, values, summary) {
                      _handleFormSubmitted(message, formId, values, summary);
                    },
                    quotedMessage: quotedMessage,
                    showQuote: !isReplyToPrevious,
                    onQuoteTap: message.replyTo != null
                        ? () => _scrollToMessage(message.replyTo!)
                        : null,
                    allImageMessages: allImageMessages,
                    imageIndex: imageIndexMap[message.id] ?? 0,
                    imageIndexMap: imageIndexMap,
                    groupedImageMessages: imageGroupMap[index],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.grey[200],
              child: widget.agentAvatar != null && widget.agentAvatar!.length > 2
                  ? ClipOval(
                      child: Image.network(
                        widget.agentAvatar!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Text(
                            widget.agentName?.isNotEmpty == true
                                ? widget.agentName![0]
                                : 'A',
                            style: const TextStyle(fontSize: 56),
                          );
                        },
                      ),
                    )
                  : Text(
                      widget.agentAvatar ??
                      (widget.agentName?.isNotEmpty == true
                          ? widget.agentName![0]
                          : 'A'),
                      style: const TextStyle(fontSize: 56),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.agentName ?? 'AI Agent',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message to start chatting',
              style: TextStyle(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
    );
  }

  /// 队列指示器
  Widget _buildQueueIndicator() {
    if (_messageQueue.isEmpty) return const SizedBox.shrink();

    final count = _messageQueue.length;
    final preview = _messageQueue.first.length > 40
        ? '${_messageQueue.first.substring(0, 40)}...'
        : _messageQueue.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border(
          top: BorderSide(color: Colors.blue[100]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.queue, size: 16, color: Colors.blue[400]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count == 1
                      ? '1 message queued'
                      : '$count messages queued',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.blue[700],
                  ),
                ),
                Text(
                  preview,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue[400],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (count > 1)
            GestureDetector(
              onTap: () {
                setState(() {
                  _messageQueue.clear();
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red[400],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 输入区域
  void _onFocusChanged() {
    if (_textFieldFocusNode.hasFocus && _showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
    }
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
      _textFieldFocusNode.requestFocus();
    } else {
      _textFieldFocusNode.unfocus();
      setState(() {
        _showEmojiPicker = true;
      });
    }
  }

  void _onEmojiSelected(Category? category, Emoji emoji) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursorPos = selection.baseOffset;

    if (cursorPos < 0) {
      _messageController.text = text + emoji.emoji;
      _messageController.selection = TextSelection.collapsed(
        offset: _messageController.text.length,
      );
    } else {
      final newText = text.substring(0, cursorPos) +
          emoji.emoji +
          text.substring(cursorPos);
      _messageController.text = newText;
      final newCursorPos = cursorPos + emoji.emoji.length;
      _messageController.selection = TextSelection.collapsed(
        offset: newCursorPos,
      );
    }
  }

  void _onBackspacePressed() {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursorPos = selection.baseOffset;

    if (cursorPos > 0 && text.isNotEmpty) {
      final newText = text.substring(0, cursorPos - 1) +
          text.substring(cursorPos);
      _messageController.text = newText;
      _messageController.selection = TextSelection.collapsed(
        offset: cursorPos - 1,
      );
    }
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 附件按钮
            IconButton(
              icon: const Icon(Icons.attach_file),
              color: Colors.grey[600],
              onPressed: _showAttachmentOptions,
            ),

            // Emoji 按钮
            IconButton(
              icon: Icon(
                _showEmojiPicker
                    ? Icons.keyboard
                    : Icons.emoji_emotions_outlined,
              ),
              color: Colors.grey[600],
              onPressed: _toggleEmojiPicker,
            ),

            // 输入框
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Shortcuts(
                  shortcuts: <ShortcutActivator, Intent>{
                    const SingleActivator(LogicalKeyboardKey.enter): const _SendMessageIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      _SendMessageIntent: CallbackAction<_SendMessageIntent>(
                        onInvoke: (_) {
                          _sendMessage();
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      controller: _messageController,
                      focusNode: _textFieldFocusNode,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      enabled: !_isLoading,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // 发送按钮或麦克风按钮
            _isLoading
                ? Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  )
                : (_hasText || _isProcessing)
                    ? IconButton(
                        icon: const Icon(Icons.send),
                        color: Theme.of(context).primaryColor,
                        onPressed: _hasText ? _sendMessage : null,
                      )
                    : GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Hold to record a voice message'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        onLongPressStart: (_) {
                          setState(() {
                            _isCancelZone = false;
                          });
                          _audioRecordingService.startRecording().then((success) {
                            if (!success && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cannot start recording. Microphone may not be available on this device.'),
                                ),
                              );
                            }
                          });
                        },
                        onLongPressMoveUpdate: (details) {
                          final inCancel = details.localOffsetFromOrigin.dy < -50;
                          if (inCancel != _isCancelZone) {
                            setState(() {
                              _isCancelZone = inCancel;
                            });
                          }
                        },
                        onLongPressEnd: (_) async {
                          if (_isCancelZone) {
                            await _audioRecordingService.cancelRecording();
                            setState(() {
                              _isCancelZone = false;
                            });
                          } else {
                            if (_audioRecordingService.currentState.isRecording) {
                              await _sendVoiceMessage();
                            }
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(
                            _isRecording ? Icons.mic : Icons.mic_none,
                            color: _isRecording ? Colors.red : Colors.grey[600],
                          ),
                        ),
                      ),
          ],
        ),
      ),
    );
  }

  /// 显示Agent菜单
  void _showAgentMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Reset Session'),
              onTap: () {
                Navigator.pop(context);
                _resetSession();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('New Session'),
              onTap: () {
                Navigator.pop(context);
                _createNewSession();
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Session List'),
              onTap: () {
                Navigator.pop(context);
                _showSessionList();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('View Details'),
              onTap: () async {
                Navigator.pop(context);
                if (widget.agentId == null) return;
                final databaseService = LocalDatabaseService();
                final agent = await databaseService.getAgentById(widget.agentId!);
                if (agent != null && mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AgentDetailScreen(agent: agent),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search Messages'),
              onTap: () {
                Navigator.pop(context);
                _showSearchDialog();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined, color: Colors.orange),
              title: const Text('Clear Session History'),
              subtitle: const Text('Clear current session and reset remote agent'),
              onTap: () {
                Navigator.pop(context);
                _confirmClearCurrentSession();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
              title: const Text('Clear All Sessions', style: TextStyle(color: Colors.red)),
              subtitle: const Text('Clear all sessions and reset remote agent'),
              onTap: () {
                Navigator.pop(context);
                _confirmClearAllSessions();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 从 channelId 中提取简短的会话标识
  String _shortSessionId(String channelId) {
    // channelId 格式: dm_userId_agentId 或 dm_userId_agentId_timestamp
    final parts = channelId.split('_');
    if (parts.length > 3) {
      // 有 timestamp 后缀，取最后的时间戳作为区分
      return 'Session #${parts.last.substring(parts.last.length > 6 ? parts.last.length - 6 : 0)}';
    }
    return 'Session #default';
  }

  /// 重置会话 - 发送 /reset 命令
  void _resetSession() {
    _messageController.text = '/reset';
    _sendMessage();
  }

  /// 确认清除当前会话记录
  void _confirmClearCurrentSession() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Session History'),
        content: const Text(
          'This will send a /reset command to the remote agent and clear all messages in the current session. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearCurrentSessionHistory();
            },
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  /// 确认清除所有会话记录
  void _confirmClearAllSessions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Sessions'),
        content: const Text(
          'This will send a /reset-all command to the remote agent and clear all session history for this agent. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearAllSessionsHistory();
            },
            child: const Text(
              'Clear All',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  /// 清除当前会话记录 - 发送 /reset 并清除本地消息
  /// 如果有多个会话，删除当前会话并跳转到其他会话
  /// 如果只有一个会话，仅清除消息记录保留会话
  Future<void> _clearCurrentSessionHistory() async {
    if (widget.agentId == null) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';
    final sessionId = _currentChannelId ?? _chatService.generateChannelId(userId, widget.agentId!);

    // Show loading overlay
    _showClearingOverlay('Clearing session...');

    try {
      // Send /reset command to remote agent with session_id
      final databaseService = LocalDatabaseService();
      final remoteAgent = await databaseService.getRemoteAgentById(widget.agentId!);

      if (remoteAgent != null && remoteAgent.isOnline) {
        try {
          await _chatService.sendMessageToAgent(
            content: '/reset',
            agent: remoteAgent,
            userId: userId,
            userName: userName,
            channelId: sessionId,
          );
        } catch (_) {
          // Remote reset failed, continue with local cleanup
        }
      }

      // Get all sessions for this agent
      final sessions = await _chatService.getAgentSessions(agentId: widget.agentId!);

      if (sessions.length > 1) {
        // Multiple sessions: delete current session and navigate to another
        await databaseService.deleteChannelMessages(sessionId);
        await databaseService.deleteChannel(sessionId);

        // Find next session to navigate to
        final remaining = sessions.where((s) => s.id != sessionId).toList();
        final targetSession = remaining.first;

        if (mounted) {
          Navigator.of(context).pop(); // dismiss overlay
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Session cleared. Switching to ${_shortSessionId(targetSession.id)}'),
              duration: const Duration(seconds: 2),
            ),
          );
          // Navigate to the other session with animation
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
                agentId: widget.agentId,
                agentName: widget.agentName,
                agentAvatar: widget.agentAvatar,
                channelId: targetSession.id,
              ),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.05),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                    child: child,
                  ),
                );
              },
              transitionDuration: const Duration(milliseconds: 350),
            ),
          );
        }
      } else {
        // Only one session: just clear messages, keep the session
        await databaseService.deleteChannelMessages(sessionId);

        if (mounted) {
          Navigator.of(context).pop(); // dismiss overlay
          setState(() {
            _messages.clear();
            _messageIdMap.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session history cleared')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // dismiss overlay
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear session: $e')),
        );
      }
    }
  }

  /// 清除所有会话记录 - 发送 /reset-all 并清除所有本地会话
  /// 保留一个空白会话，确保至少有一个会话存在
  Future<void> _clearAllSessionsHistory() async {
    if (widget.agentId == null) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';
    final sessionId = _currentChannelId ?? _chatService.generateChannelId(userId, widget.agentId!);

    // Show loading overlay
    _showClearingOverlay('Clearing all sessions...');

    try {
      // Send /reset-all command to remote agent with session_id
      final databaseService = LocalDatabaseService();
      final remoteAgent = await databaseService.getRemoteAgentById(widget.agentId!);

      if (remoteAgent != null && remoteAgent.isOnline) {
        try {
          await _chatService.sendMessageToAgent(
            content: '/reset-all',
            agent: remoteAgent,
            userId: userId,
            userName: userName,
            channelId: sessionId,
          );
        } catch (_) {
          // Remote reset failed, continue with local cleanup
        }
      }

      // Get all sessions, delete all but keep the default channel
      final sessions = await _chatService.getAgentSessions(agentId: widget.agentId!);
      final defaultChannelId = _chatService.generateChannelId(userId, widget.agentId!);

      for (final session in sessions) {
        await databaseService.deleteChannelMessages(session.id);
        if (session.id != defaultChannelId) {
          await databaseService.deleteChannel(session.id);
        }
      }

      // Ensure the default channel exists
      final defaultChannel = await databaseService.getChannelById(defaultChannelId);
      if (defaultChannel == null) {
        // All sessions were non-default; create a fresh default channel
        final channel = Channel.withMemberIds(
          id: defaultChannelId,
          name: 'Chat with ${widget.agentName ?? 'Agent'}',
          type: 'dm',
          memberIds: [userId, widget.agentId!],
          isPrivate: true,
        );
        await databaseService.createChannel(channel, userId);
      }

      if (mounted) {
        Navigator.of(context).pop(); // dismiss overlay
        final isAlreadyDefault = _currentChannelId == defaultChannelId;

        if (isAlreadyDefault) {
          // Already on the default channel, just clear UI
          setState(() {
            _messages.clear();
            _messageIdMap.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All session history cleared')),
          );
        } else {
          // Navigate to default channel
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('All sessions cleared. Switching to ${_shortSessionId(defaultChannelId)}'),
              duration: const Duration(seconds: 2),
            ),
          );
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
                agentId: widget.agentId,
                agentName: widget.agentName,
                agentAvatar: widget.agentAvatar,
                channelId: defaultChannelId,
              ),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.05),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                    child: child,
                  ),
                );
              },
              transitionDuration: const Duration(milliseconds: 350),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // dismiss overlay
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear all sessions: $e')),
        );
      }
    }
  }

  /// 显示清理中的加载覆盖层
  void _showClearingOverlay(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 新建会话
  Future<void> _createNewSession() async {
    if (widget.agentId == null) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    try {
      final newChannelId = await _chatService.createNewSession(
        userId: userId,
        userName: userName,
        agentId: widget.agentId!,
        agentName: widget.agentName ?? 'Agent',
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              agentId: widget.agentId,
              agentName: widget.agentName,
              agentAvatar: widget.agentAvatar,
              channelId: newChannelId,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create new session: $e')),
        );
      }
    }
  }

  /// 显示会话列表
  Future<void> _showSessionList() async {
    if (widget.agentId == null) return;

    try {
      final sessions = await _chatService.getAgentSessions(agentId: widget.agentId!);
      if (!mounted) return;

      final databaseService = LocalDatabaseService();

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text(
                      'Sessions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${sessions.length} sessions',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Session list
              Expanded(
                child: sessions.isEmpty
                    ? Center(
                        child: Text(
                          'No sessions yet',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: sessions.length,
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          final isCurrent = session.id == _currentChannelId;
                          return FutureBuilder<Map<String, dynamic>?>(
                            future: databaseService.getLatestChannelMessage(session.id),
                            builder: (context, snapshot) {
                              return _buildSessionTile(
                                session,
                                isCurrent,
                                snapshot.data,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load sessions: $e')),
        );
      }
    }
  }

  /// 构建会话列表项
  Widget _buildSessionTile(Channel session, bool isCurrentSession, Map<String, dynamic>? latestMessage) {
    final preview = latestMessage?['content'] as String? ?? 'No messages';
    final createdAtStr = latestMessage?['created_at'] as String?;
    String timeText = '';
    if (createdAtStr != null) {
      try {
        final dt = DateTime.parse(createdAtStr);
        final now = DateTime.now();
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
          timeText = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        } else {
          timeText = '${dt.month}/${dt.day}';
        }
      } catch (_) {}
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isCurrentSession ? Theme.of(context).primaryColor : Colors.grey[300],
        child: Icon(
          Icons.chat_bubble_outline,
          color: isCurrentSession ? Colors.white : Colors.grey[600],
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              session.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCurrentSession)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Current',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey[600],
        ),
      ),
      trailing: timeText.isNotEmpty
          ? Text(
              timeText,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            )
          : null,
      onTap: isCurrentSession
          ? () => Navigator.pop(context)
          : () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    agentId: widget.agentId,
                    agentName: widget.agentName,
                    agentAvatar: widget.agentAvatar,
                    channelId: session.id,
                  ),
                ),
              );
            },
    );
  }

  /// 构建日期分隔符
  Widget _buildDateSeparator(DateTime date) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          MessageUtils.getDateDisplayText(date),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// 显示消息菜单
  void _showMessageMenu(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                // Copy to clipboard
                Clipboard.setData(ClipboardData(text: message.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
            ),
            if (!message.from.isUser)
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(context);
                  _startReply(message);
                },
              ),
            if (message.type == MessageType.image || message.type == MessageType.file)
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Download'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Feature coming soon')),
                  );
                },
              ),
            if (message.from.isUser) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.replay, color: Colors.orange),
                title: const Text('Rollback', style: TextStyle(color: Colors.orange)),
                subtitle: const Text('Delete this and all later messages'),
                onTap: () {
                  Navigator.pop(context);
                  _rollbackMessage(message);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note, color: Colors.blue),
                title: const Text('Re-edit', style: TextStyle(color: Colors.blue)),
                subtitle: const Text('Rollback and edit this message'),
                onTap: () {
                  Navigator.pop(context);
                  _rollbackMessage(message, reEdit: true);
                },
              ),
            ],
            if (MessageUtils.canDeleteMessage(
              message,
              Provider.of<AppState>(context, listen: false).currentUser?.id ?? 'user',
            ))
              const Divider(),
            if (MessageUtils.canDeleteMessage(
              message,
              Provider.of<AppState>(context, listen: false).currentUser?.id ?? 'user',
            ))
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(message);
                },
              ),
          ],
        ),
      ),
    );
  }
}
