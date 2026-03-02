import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/message.dart';
import '../models/channel.dart';
import '../models/pending_attachment.dart';
import '../services/os_tool_executor.dart' as os_exec;
import '../widgets/os_tool_confirmation_dialog.dart';
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
import '../services/acp_agent_connection.dart';
import '../services/local_llm_agent_service.dart';
import '../models/attachment_data.dart';
import '../utils/layout_utils.dart';
import '../services/app_lifecycle_service.dart';
import '../services/notification_service.dart';
import '../utils/message_utils.dart';
import '../l10n/app_localizations.dart';
import 'remote_agent_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  final String? agentId;
  final String? agentName;
  final String? agentAvatar;
  final String? channelId;

  /// When true, the screen is embedded inside a desktop split-panel layout.
  /// Back button is hidden; closing/deletion calls [onClose] instead of
  /// Navigator.pop; session switches call [onSwitchChannel] instead of
  /// pushReplacement.
  final bool embedded;

  /// Called when the chat should be closed in embedded mode (e.g. agent deleted).
  final VoidCallback? onClose;

  /// Called when a session switch is needed in embedded mode.
  /// The parent updates the selected conversation, which triggers a new
  /// ChatScreen via ValueKey change.
  final ValueChanged<String>? onSwitchChannel;

  const ChatScreen({
    Key? key,
    this.agentId,
    this.agentName,
    this.agentAvatar,
    this.channelId,
    this.embedded = false,
    this.onClose,
    this.onSwitchChannel,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  List<Message> _messages = [];
  Map<String, Message> _messageIdMap = {};
  bool _isLoading = false;
  bool _isSearching = false;
  String _searchQuery = '';
  String? _streamingMessageId;
  String _streamingContent = '';

  // 消息处理和队列
  bool _isProcessing = false;
  ACPCancellationToken? _acpCancellationToken;
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
  late LocalDatabaseService _localDatabaseService;
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

  // Pending attachments (desktop: stage before send)
  List<PendingAttachment> _pendingAttachments = [];
  bool get _canSend => _hasText || _pendingAttachments.isNotEmpty;
  static const int _maxPendingAttachments = 9;

  // Emoji picker
  bool _showEmojiPicker = false;
  final FocusNode _textFieldFocusNode = FocusNode();

  // Smart scroll: track whether user has scrolled away from bottom
  bool _isUserScrolledUp = false;
  int _unreadMessageCount = 0;

  // App lifecycle: 页面是否处于前台激活状态
  bool _isAppActive = true;

  // History request tracking
  int _historySentCount = 40;  // number of history messages already sent to agent
  String? _lastUserQuestion;   // last user question (for re-answer)
  Map<String, dynamic>? _pendingHistoryRequest;  // captured from ACP callback

  // Mutable agent info (updated after editing in detail screen)
  String? _agentName;
  String? _agentAvatar;

  // Group mode state
  bool _isGroupMode = false;
  Channel? _groupChannel;
  List<RemoteAgent> _groupAgents = [];
  Set<String> _respondingAgentNames = {};
  bool _mentionOnlyMode = false;
  String? _groupAdminAgentId;
  Set<String> _groupStreamingMessageIds = {};

  // Frame coalescing for group streaming chunk rebuilds
  bool _pendingStreamingRebuild = false;

  // Mention picker state
  bool _showMentionPicker = false;
  String _mentionQuery = '';
  int _mentionTriggerOffset = -1;
  int _mentionSelectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _agentName = widget.agentName;
    _agentAvatar = widget.agentAvatar;
    WidgetsBinding.instance.addObserver(this);
    final databaseService = LocalDatabaseService();
    _localDatabaseService = databaseService;
    _chatService = ChatService();
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
    _itemPositionsListener.itemPositions.addListener(_onScroll);
    _textFieldFocusNode.addListener(_onFocusChanged);
    // 桌面端注册全局键盘监听，用于拦截 Cmd+V 粘贴图片
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    }
    _loadMessages();
    _refreshAgentStatus();
    // 预请求麦克风权限，避免长按录音时弹权限弹窗导致手势中断
    _audioRecordingService.requestPermission();

    // 定期从数据库刷新 Agent 状态（与列表页保持一致）
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshAgentStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Clear active channel for notification suppression
    AppLifecycleService().setActiveChannel(null);

    // Don't cancel the task — let it continue in the background.
    // Detach UI callbacks so the background task stops forwarding to this widget.
    if (_currentChannelId != null) {
      _chatService.detachTaskUI(_currentChannelId!);
      _chatService.detachGroupTaskUI(_currentChannelId!);
    }
    _messageQueue.clear();
    // Clean up clipboard temp files from pending attachments
    for (final att in _pendingAttachments) {
      if (att.isFromClipboard) {
        try { att.file.deleteSync(); } catch (_) {}
      }
    }
    _pendingAttachments.clear();
    _healthCheckTimer?.cancel();
    _recordingSubscription?.cancel();
    _audioRecordingService.dispose();
    _messageController.removeListener(_onTextChanged);
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    _textFieldFocusNode.removeListener(_onFocusChanged);
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    }
    _textFieldFocusNode.dispose();
    _messageController.dispose();
    // Only close the message stream controller for this specific channel.
    // Do NOT call _chatService.detachUI() here — that is a global teardown
    // which destroys controllers and task callbacks for ALL channels, breaking
    // any new ChatScreen that was already initialised for a different
    // conversation (e.g. during rapid conversation switching on desktop).
    if (_currentChannelId != null) {
      _chatService.closeChannelStream(_currentChannelId!);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = _isAppActive;
    _isAppActive = state == AppLifecycleState.resumed;
    // 从后台回到前台，且滚动条在底部，标记消息已读
    if (_isAppActive && !wasActive) {
      _markMessagesAsReadIfAtBottom();
    }
  }

  /// 判断是否处于底部，若是则标记 channel 消息为已读
  Future<void> _markMessagesAsReadIfAtBottom() async {
    if (_currentChannelId == null) return;
    if (!_isAppActive) return;
    if (_isUserScrolledUp) return;
    await _localDatabaseService.markChannelMessagesAsRead(_currentChannelId!);
  }

  /// 从数据库读取 Agent 在线状态（与列表页使用同一数据源）
  Future<void> _refreshAgentStatus() async {
    if (widget.agentId == null) return;

    try {
      final agent = await _localDatabaseService.getAgentById(widget.agentId!);
      if (mounted && agent != null) {
        setState(() {
          _isAgentOnline = agent.status.isOnline;
          _isCheckingHealth = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCheckingHealth = false;
        });
      }
    }
  }

  /// Load message history
  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentUser?.id ?? 'user';

      // Determine channel ID
      if (widget.channelId != null) {
        _currentChannelId = widget.channelId;
      } else if (widget.agentId != null) {
        // 优先使用最近活跃的会话，而非固定的默认 channel
        final latestChannelId = await _chatService.getLatestActiveChannelId(userId, widget.agentId!);
        _currentChannelId = latestChannelId ?? _chatService.generateChannelId(userId, widget.agentId!);
      } else {
        setState(() { _isLoading = false; });
        return;
      }

      // Track active channel for notification suppression
      AppLifecycleService().setActiveChannel(_currentChannelId);
      NotificationService().cancelNotification(_currentChannelId.hashCode);

      // Detect group mode
      final channel = await _localDatabaseService.getChannelById(_currentChannelId!);
      if (channel != null && channel.isGroup) {
        _isGroupMode = true;
        _groupChannel = channel;
        // Load agent members
        final agentIds = channel.memberIds.where((id) => id != userId && id != 'user').toList();
        final agents = <RemoteAgent>[];
        for (final agentId in agentIds) {
          final agent = await _localDatabaseService.getRemoteAgentById(agentId);
          if (agent != null) agents.add(agent);
        }
        _groupAgents = agents;
        _groupAdminAgentId = channel.adminAgentId;
      }

      final messages = await _chatService.loadChannelMessages(
        _currentChannelId!,
      );

      setState(() {
        _messages = messages;
        _rebuildMessageIdMap();
        _isLoading = false;
      });

      // 初次加载滚动到底部，标记所有消息为已读
      _markMessagesAsReadIfAtBottom();

      // 自动聚焦输入框，使其处于输入状态
      _textFieldFocusNode.requestFocus();

      // Scroll to bottom — 放在 requestFocus 之后，确保键盘弹起后仍能滚到底部
      _scrollToBottom(force: true);
      // 额外延迟一帧：等待键盘弹起导致的布局变化完成后，再次确保在底部
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _scrollToBottom(force: true);
      });

      // Re-attach to a background task if one is running for this channel (DM only)
      if (!_isGroupMode) {
        _reattachToActiveTask();
      }

      // Re-attach to background group tasks if any are running
      if (_isGroupMode) {
        _reattachToGroupActiveTasks();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      final l10nErr = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10nErr.chat_loadFailed(e.toString()))),
      );
    }
  }

  /// Re-attach to a background task that is still running for this channel.
  /// Called at the end of _loadMessages() so the UI picks up where it left off.
  void _reattachToActiveTask() {
    if (_currentChannelId == null) return;

    final activeTask = _chatService.getActiveTask(_currentChannelId!);
    if (activeTask == null) return;

    // Restore streaming state from the background task
    _streamingContent = activeTask.accumulatedContent;
    _streamingMessageId = 'streaming_reattach_${DateTime.now().millisecondsSinceEpoch}';

    final streamingMessage = Message(
      id: _streamingMessageId!,
      content: _streamingContent,
      timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
      from: MessageFrom(
        id: activeTask.agentId,
        type: 'agent',
        name: activeTask.agentName,
      ),
      to: MessageFrom(
        id: activeTask.userId,
        type: 'user',
        name: activeTask.userName,
      ),
      type: MessageType.text,
    );

    setState(() {
      _isProcessing = true;
      _messages.add(streamingMessage);
      _messageIdMap[streamingMessage.id] = streamingMessage;
    });
    _scrollToBottom(force: true);

    // Create a new cancellation token bound to the existing task's connection
    _acpCancellationToken = ACPCancellationToken();

    // Attach new UI callbacks
    _chatService.attachTaskUI(
      _currentChannelId!,
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
              type: _messages[idx].type,
            );
            _messages[idx] = updated;
            _messageIdMap[updated.id] = updated;
          }
        });
        _scrollToBottom();
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
      onTaskFinished: () async {
        if (!mounted) return;
        // Wait for the DB save to complete before reloading
        await activeTask.dbSaveCompleter.future;
        if (!mounted) return;
        _acpCancellationToken = null;
        _streamingMessageId = null;
        _streamingContent = '';
        await _loadMessages();
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
      },
    );
  }

  /// Re-attach to background group tasks that are still running for this channel.
  /// Called at the end of _loadMessages() in group mode so the UI picks up
  /// in-progress streaming from agents that continued while the user was away.
  void _reattachToGroupActiveTasks() {
    if (_currentChannelId == null) return;

    final activeTasks = _chatService.getActiveGroupTasks(_currentChannelId!);
    if (activeTasks.isEmpty) return;

    // Per-agent streaming state for reattached tasks
    final streamingIds = <String, String>{};
    final streamingContents = <String, String>{};

    // For each active task, create a streaming message placeholder with
    // the content accumulated so far.
    for (final entry in activeTasks.entries) {
      final agentId = entry.key;
      final task = entry.value;
      final sid = 'group_streaming_${agentId}_${DateTime.now().millisecondsSinceEpoch}';
      streamingIds[agentId] = sid;
      streamingContents[agentId] = task.accumulatedContent;

      final streamingMessage = Message(
        id: sid,
        content: task.accumulatedContent,
        timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
        from: MessageFrom(id: agentId, type: 'agent', name: task.agentName),
        type: MessageType.text,
      );

      setState(() {
        _isProcessing = true;
        _respondingAgentNames.add(task.agentName);
        _groupStreamingMessageIds.add(sid);
        _messages.add(streamingMessage);
        _messageIdMap[streamingMessage.id] = streamingMessage;
      });
    }
    _scrollToBottom(force: true);

    // Attach UI callbacks to all active group tasks
    _chatService.attachGroupTaskUI(
      _currentChannelId!,
      onStreamChunk: (agentId, agentName, chunk) {
        if (!mounted) return;
        final sid = streamingIds[agentId];
        if (sid == null) return;
        streamingContents[agentId] = (streamingContents[agentId] ?? '') + chunk;
        final updatedContent = streamingContents[agentId]!;
        final existing = _messageIdMap[sid];
        if (existing != null) {
          final idx = _messages.indexOf(existing);
          if (idx != -1) {
            final updated = Message(
              id: sid,
              content: updatedContent,
              timestampMs: _messages[idx].timestampMs,
              from: _messages[idx].from,
              to: _messages[idx].to,
              type: MessageType.text,
            );
            _messages[idx] = updated;
            _messageIdMap[updated.id] = updated;
          }
        }
        _scheduleStreamingRebuild();
        _scrollToBottom();
      },
      onTaskFinished: (agentId, agentName) {
        if (!mounted) return;
        final sid = streamingIds[agentId];
        if (sid != null) {
          setState(() {
            _groupStreamingMessageIds.remove(sid);
          });
        }
        streamingIds.remove(agentId);
        streamingContents.remove(agentId);
        setState(() {
          _respondingAgentNames.remove(agentName);
        });
        // When all reattached tasks are done, reload from DB
        if (streamingIds.isEmpty) {
          _reconcileGroupMessages().then((_) {
            if (mounted) {
              setState(() {
                _isProcessing = false;
                _respondingAgentNames.clear();
                _groupStreamingMessageIds.clear();
              });
            }
          });
        }
      },
    );
  }

  /// Send message to agent
  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    final hasPendingAttachments = _pendingAttachments.isNotEmpty;
    print('[ChatScreen] 用户尝试发送消息');
    print('   - Content: $content');
    print('   - Group mode: $_isGroupMode');
    print('   - Pending attachments: ${_pendingAttachments.length}');

    if (content.isEmpty && !hasPendingAttachments) {
      return;
    }

    if (!_isGroupMode && widget.agentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).chat_noAgentSelected)),
      );
      return;
    }

    _messageController.clear();

    // Snapshot and clear pending attachments
    final attachmentsToSend = List<PendingAttachment>.from(_pendingAttachments);
    setState(() {
      _pendingAttachments.clear();
    });

    // Dismiss mention picker if open
    if (_showMentionPicker) {
      setState(() {
        _showMentionPicker = false;
        _mentionTriggerOffset = -1;
        _mentionQuery = '';
      });
    }

    // Capture reply state before clearing
    final replyToId = _replyingToMessage?.id;
    _cancelReply();

    // Send all pending attachments first
    if (attachmentsToSend.isNotEmpty) {
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentUser?.id ?? 'user';
      final userName = appState.currentUser?.username ?? 'User';

      for (final att in attachmentsToSend) {
        final message = await _attachmentService.saveAttachment(
          file: att.file,
          channelId: _currentChannelId ?? '',
          userId: userId,
          userName: userName,
          agentId: widget.agentId ?? '',
        );
        // Clean up clipboard temp files
        if (att.isFromClipboard) {
          try { att.file.deleteSync(); } catch (_) {}
        }
        if (message != null && mounted) {
          setState(() {
            _messages.add(message);
            _messageIdMap[message.id] = message;
          });
          _scrollToBottom(force: true);
          // Send attachment to agent (non-group only)
          if (!_isGroupMode) {
            _sendAttachmentToAgent(message);
          }
        }
      }
    }

    // Then send text message if any
    if (content.isEmpty) return;

    // 如果正在处理消息，将新消息加入队列
    if (_isProcessing) {
      setState(() {
        _messageQueue.add(content);
      });
      return;
    }

    if (_isGroupMode) {
      await _processGroupMessage(content, replyToId: replyToId);
    } else {
      await _processMessage(content, replyToId: replyToId);
    }
  }

  /// 停止当前流式回复
  void _stopStreaming() {
    print('🛑 [ChatScreen] 用户停止流式回复');

    // Immediately update UI: append [Stopped] and clear streaming state so the
    // stop button disappears and the user sees feedback right away, even if the
    // underlying HTTP connection takes a moment to tear down.
    if (_streamingMessageId != null && mounted) {
      final stoppedId = _streamingMessageId!;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == stoppedId);
        if (idx != -1) {
          final current = _messages[idx];
          final stoppedContent = _streamingContent.isNotEmpty
              ? '$_streamingContent\n\n[Stopped]'
              : '[Stopped]';
          _messages[idx] = Message(
            id: current.id,
            content: stoppedContent,
            timestampMs: current.timestampMs,
            from: current.from,
            to: current.to,
            type: current.type,
            metadata: current.metadata,
          );
          _messageIdMap[current.id] = _messages[idx];
        }
        _streamingMessageId = null;
        _streamingContent = '';
      });
    }

    _acpCancellationToken?.cancel();
  }

  /// 处理队列中的下一条消息
  Future<void> _processNextInQueue() async {
    if (_messageQueue.isEmpty) return;

    final nextContent = _messageQueue.removeAt(0);
    if (mounted) {
      setState(() {});
    }
    if (_isGroupMode) {
      await _processGroupMessage(nextContent);
    } else {
      await _processMessage(nextContent);
    }
  }

  /// Process a message in group mode — orchestrate multi-agent responses.
  Future<void> _processGroupMessage(String content, {String? replyToId}) async {
    if (_currentChannelId == null || _groupAgents.isEmpty) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    setState(() {
      _isProcessing = true;
    });

    // Add user message to UI immediately
    final userMessage = Message(
      id: 'temp_user_${DateTime.now().millisecondsSinceEpoch}',
      content: content,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      from: MessageFrom(id: userId, type: 'user', name: userName),
      type: MessageType.text,
      replyTo: replyToId,
    );
    setState(() {
      _messages.add(userMessage);
      _messageIdMap[userMessage.id] = userMessage;
    });
    _scrollToBottom(force: true);

    // Per-agent streaming state for concurrent responses
    final streamingIds = <String, String>{};       // agentId -> streaming message id
    final streamingContents = <String, String>{};  // agentId -> accumulated content

    try {
      final agentIds = _groupAgents.map((a) => a.id).toList();
      final mentionedAgentIds = _parseMentionedAgentIds(content);

      await _chatService.sendMessageToGroup(
        channelId: _currentChannelId!,
        content: content,
        userId: userId,
        userName: userName,
        agentIds: agentIds,
        mentionedAgentIds: mentionedAgentIds,
        mentionOnlyMode: _mentionOnlyMode,
        adminAgentId: _groupAdminAgentId,
        replyToId: replyToId,
        onAgentStart: (agentId, agentName) {
          if (!mounted) return;
          final sid = 'group_streaming_${agentId}_${DateTime.now().millisecondsSinceEpoch}';
          streamingIds[agentId] = sid;
          streamingContents[agentId] = '';
          final streamingMessage = Message(
            id: sid,
            content: '',
            timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
            from: MessageFrom(id: agentId, type: 'agent', name: agentName),
            to: MessageFrom(id: userId, type: 'user', name: userName),
            type: MessageType.text,
          );
          setState(() {
            _respondingAgentNames.add(agentName);
            _groupStreamingMessageIds.add(sid);
            _messages.add(streamingMessage);
            _messageIdMap[streamingMessage.id] = streamingMessage;
          });
          _scrollToBottom(force: true);
        },
        onStreamChunk: (agentId, agentName, chunk) {
          if (!mounted) return;
          final sid = streamingIds[agentId];
          if (sid == null) return;
          streamingContents[agentId] = (streamingContents[agentId] ?? '') + chunk;
          final updatedContent = streamingContents[agentId]!;
          // Mutate in-place without setState — coalesce via frame callback
          final existing = _messageIdMap[sid];
          if (existing != null) {
            final idx = _messages.indexOf(existing);
            if (idx != -1) {
              final updated = Message(
                id: sid,
                content: updatedContent,
                timestampMs: _messages[idx].timestampMs,
                from: _messages[idx].from,
                to: _messages[idx].to,
                type: MessageType.text,
              );
              _messages[idx] = updated;
              _messageIdMap[updated.id] = updated;
            }
          }
          _scheduleStreamingRebuild();
          _scrollToBottom();
        },
        onAgentDone: (agentId, agentName, skipped) {
          if (!mounted) return;
          final sid = streamingIds[agentId];
          if (skipped && sid != null) {
            setState(() {
              _messages.removeWhere((m) => m.id == sid);
              _messageIdMap.remove(sid);
              _groupStreamingMessageIds.remove(sid);
            });
          } else if (sid != null) {
            setState(() {
              _groupStreamingMessageIds.remove(sid);
            });
          }
          streamingIds.remove(agentId);
          streamingContents.remove(agentId);
          if (mounted) {
            setState(() {
              _respondingAgentNames.remove(agentName);
            });
          }
        },
        onAllDone: () {
          // Will be handled in finally block below
        },
      );

      // Reconcile temp streaming IDs with canonical DB IDs in-place.
      // Unlike _loadMessages() which replaces the entire list (causing visual
      // flash), this matches temp messages to DB counterparts and swaps IDs.
      await _reconcileGroupMessages();
      _markMessagesAsReadIfAtBottom();
    } catch (e) {
      print('[ChatScreen] Group message error: $e');
      // Do NOT reload from DB here — that would destroy streaming placeholders
      // that may contain valid content. Individual agent errors are already
      // handled inside _processGroupAgent / catchError wrappers.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_groupChatError('$e'))),
        );
      }
    } finally {
      _streamingMessageId = null;
      _streamingContent = '';
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _respondingAgentNames.clear();
          _groupStreamingMessageIds.clear();
        });
      }
      _processNextInQueue();
    }
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
    _acpCancellationToken = ACPCancellationToken();

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

      // Local LLM agents don't need endpoint or online status checks
      final isLocal = LocalLLMAgentService.instance.isLocalAgent(remoteAgent);

      // Check if agent has valid endpoint (skip for local agents)
      if (!isLocal && remoteAgent.endpoint.isEmpty) {
        print('❌ [ChatScreen] Agent 没有有效的端点');
        throw Exception('Agent has no valid endpoint');
      }

      // If agent is not online, try health check first (skip for local agents)
      if (!isLocal && !remoteAgent.isOnline) {
        print('⚠️ [ChatScreen] Agent 离线，尝试健康检查...');

        // Import RemoteAgentService
        final remoteAgentService = RemoteAgentService(
          databaseService,
          TokenService(databaseService),
        );

        // Show loading indicator while checking health
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(AppLocalizations.of(context).chat_checkingHealth),
                ],
              ),
              duration: const Duration(seconds: 2),
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
        acpCancellationToken: _acpCancellationToken,
        onOsToolConfirmation: (toolName, args, risk) async {
          if (!mounted) return false;
          final result = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => OsToolConfirmationDialog(
              toolName: toolName,
              args: args,
              risk: risk,
            ),
          );
          return result ?? false;
        },
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
            final thumbnailBase64 = fileData['thumbnail_base64'] as String?;

            if (url == null || url.isEmpty) {
              print('   [ChatScreen] FILE_MESSAGE missing url');
              return;
            }

            print('   [ChatScreen] File message received (pending download): $url');

            // Extract file_id from URL (e.g. http://host/files/{file_id})
            String? fileId;
            try {
              final uri = Uri.parse(url);
              if (uri.pathSegments.length >= 2 &&
                  uri.pathSegments[uri.pathSegments.length - 2] == 'files') {
                fileId = uri.pathSegments.last;
              }
            } catch (_) {}

            // Determine message type from MIME
            final isImage = fileMimeType != null && fileMimeType.startsWith('image/');
            final msgType = isImage ? MessageType.image : MessageType.file;

            // Build metadata with pending download status (no auto-download)
            final metadata = <String, dynamic>{
              'source_url': url,
              'download_status': 'pending',
              'name': filename ?? 'file',
              'type': fileMimeType ?? 'application/octet-stream',
              'size': size ?? 0,
            };

            if (thumbnailBase64 != null && thumbnailBase64.isNotEmpty) {
              metadata['thumbnail_base64'] = thumbnailBase64;
            }

            if (fileId != null) {
              metadata['file_id'] = fileId;
            }

            final databaseService = LocalDatabaseService();
            final agentId = widget.agentId ?? '';
            final agentName = _agentName ?? 'Agent';

            final messageId = 'file_${DateTime.now().millisecondsSinceEpoch}';
            await databaseService.createMessage(
              id: messageId,
              channelId: _currentChannelId ?? '',
              senderId: agentId,
              senderType: 'agent',
              senderName: agentName,
              content: isImage
                  ? '[Image: ${filename ?? "image"}]'
                  : '[File: ${filename ?? "file"}]',
              messageType: msgType.toString().split('.').last,
              metadata: metadata,
            );

            print('   [ChatScreen] File message saved (pending): ${filename ?? "file"}');
            await _loadMessages();
          } catch (e) {
            print('   [ChatScreen] File message handling failed: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context).chat_fileMessageFailed('$e'))),
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
          // so that _isProcessing remains valid.
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
      
          _acpCancellationToken = ACPCancellationToken();
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

          // 5. Send history supplement (loop to handle recursive requests)
          int currentRequestedCount = requestedCount;
          const int maxSupplementRounds = 3;
          try {
            for (int round = 0; round < maxSupplementRounds; round++) {
              final supplementResult = await _chatService.sendHistorySupplement(
                agent: remoteAgent,
                sessionId: _currentChannelId!,
                requestId: requestId,
                originalQuestion: _lastUserQuestion ?? '',
                offset: _historySentCount,
                batchSize: currentRequestedCount,
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
                        acpCancellationToken: _acpCancellationToken,
              );

              if (supplementResult == null) {
                _addSystemHint('⚠️ 没有更多历史记录可加载');
                setState(() {
                  _messages.removeWhere((m) => m.id == _streamingMessageId);
                  _messageIdMap.remove(_streamingMessageId);
                });
                break;
              }

              _historySentCount += supplementResult.actualSentCount;

              // If the agent asked for even more history during this round, loop again
              if (supplementResult.pendingHistoryRequest != null && mounted) {
                final nextReason = supplementResult.pendingHistoryRequest!['reason'] as String? ?? 'Agent 需要更多上下文';
                currentRequestedCount = supplementResult.pendingHistoryRequest!['requested_count'] as int? ?? 40;
                // Delete the empty placeholder message from this round
                if (supplementResult.message.content.isEmpty) {
                  try { await _chatService.deleteMessage(supplementResult.message.id); } catch (_) {}
                }
                _addSystemHint('🔍 $nextReason');
                _addSystemHint('📚 正在加载更多聊天记录...');
                // Reset streaming for next round
                _streamingContent = '';
            
                _acpCancellationToken = ACPCancellationToken();
                continue;
              }

              _addSystemHint('✅ 历史记录已加载，Agent 正在重新回答...');
              break;
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
            SnackBar(content: Text(AppLocalizations.of(context).chat_responseError(_agentName ?? 'Agent'))),
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
          SnackBar(content: Text(AppLocalizations.of(context).common_error('$e'))),
        );
      }
    } finally {

      _acpCancellationToken = null;
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
    String actionLabel, {
    String? confirmationContext,
  }) async {
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


    _acpCancellationToken = ACPCancellationToken();

    try {
      final databaseService = LocalDatabaseService();
      final remoteAgent = await databaseService.getRemoteAgentById(widget.agentId!);
      if (remoteAgent == null) throw Exception('Agent not found');

      final isMacTool = confirmationContext == 'mac_tool';

      if (isMacTool) {
        // mac_tool confirmations: send in-band, no new chat message needed.
        // The already-running task continues streaming tool execution results.
        await _chatService.submitActionConfirmationResponse(
          originalMessage: originalMessage,
          confirmationId: confirmationId,
          selectedActionId: actionId,
          selectedActionLabel: actionLabel,
          agent: remoteAgent,
          userId: userId,
          userName: userName,
          channelId: _currentChannelId,
          confirmationContext: confirmationContext,
        );
      } else {
        // Normal action confirmation: create streaming placeholder for follow-up
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
          confirmationContext: confirmationContext,
          acpCancellationToken: _acpCancellationToken,
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
      }

      await _loadMessages();
    } catch (e) {
      print('Error handling action selection: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).common_error('$e'))),
        );
      }
      await _loadMessages();
    } finally {

      _acpCancellationToken = null;
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


    _acpCancellationToken = ACPCancellationToken();

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
        acpCancellationToken: _acpCancellationToken,
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
          SnackBar(content: Text(AppLocalizations.of(context).common_error('$e'))),
        );
      }
      await _loadMessages();
    } finally {

      _acpCancellationToken = null;
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


    _acpCancellationToken = ACPCancellationToken();

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
        acpCancellationToken: _acpCancellationToken,
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
          SnackBar(content: Text(AppLocalizations.of(context).common_error('$e'))),
        );
      }
      await _loadMessages();
    } finally {

      _acpCancellationToken = null;
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


    _acpCancellationToken = ACPCancellationToken();

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
        acpCancellationToken: _acpCancellationToken,
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
          SnackBar(content: Text(AppLocalizations.of(context).common_error('$e'))),
        );
      }
      await _loadMessages();
    } finally {

      _acpCancellationToken = null;
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


    _acpCancellationToken = ACPCancellationToken();

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
        acpCancellationToken: _acpCancellationToken,
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
          SnackBar(content: Text(AppLocalizations.of(context).common_error('$e'))),
        );
      }
      await _loadMessages();
    } finally {

      _acpCancellationToken = null;
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

  /// Coalesce multiple streaming chunk updates into a single setState per frame.
  /// This prevents N agents × M chunks/sec from each triggering a full rebuild.
  void _scheduleStreamingRebuild() {
    if (_pendingStreamingRebuild) return;
    _pendingStreamingRebuild = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pendingStreamingRebuild = false;
      setState(() {});
    });
  }

  /// Reconcile in-memory temp messages (both user and streaming agent messages)
  /// with DB messages after group chat completes. Instead of replacing the
  /// entire _messages list (which causes visual flash), this matches temp
  /// messages to their DB counterparts by (senderId, content) and swaps
  /// in-place.
  Future<void> _reconcileGroupMessages() async {
    if (_currentChannelId == null) return;

    final dbMessages = await _chatService.loadChannelMessages(_currentChannelId!);

    // Build a lookup for ALL temp messages (both temp_user_ and group_streaming_)
    final tempMessages = <String, int>{}; // tempId -> index in _messages
    for (int i = 0; i < _messages.length; i++) {
      final id = _messages[i].id;
      if (id.startsWith('group_streaming_') || id.startsWith('temp_user_')) {
        tempMessages[id] = i;
      }
    }

    // If there are no temp messages, just do a normal load
    if (tempMessages.isEmpty) {
      setState(() {
        _messages = dbMessages;
        _rebuildMessageIdMap();
      });
      return;
    }

    // Match DB messages to temp messages by (senderId, content).
    // Use trimmed comparison to handle whitespace differences between
    // streaming content and DB content (which is .trim()ed on save).
    final matchedDbIds = <String>{}; // DB message IDs that were matched
    final usedTempIds = <String>{};  // temp IDs that were matched

    for (final dbMsg in dbMessages) {
      if (matchedDbIds.contains(dbMsg.id)) continue;
      // Find a matching temp message with same sender and content
      String? matchedTempId;
      for (final entry in tempMessages.entries) {
        if (usedTempIds.contains(entry.key)) continue;
        final tempMsg = _messages[entry.value];
        if (tempMsg.from.id == dbMsg.from.id &&
            tempMsg.content.trim() == dbMsg.content.trim()) {
          matchedTempId = entry.key;
          break;
        }
      }
      if (matchedTempId != null) {
        // Replace the temp message in-place with the DB version
        final idx = tempMessages[matchedTempId]!;
        _messages[idx] = dbMsg;
        matchedDbIds.add(dbMsg.id);
        usedTempIds.add(matchedTempId);
      }
    }

    // Remove ALL orphaned temp messages that were NOT matched to any DB message
    _messages.removeWhere((m) =>
        (m.id.startsWith('group_streaming_') || m.id.startsWith('temp_user_')) &&
        !usedTempIds.contains(m.id));

    // Append DB messages that were not matched to any temp message
    final existingIds = _messages.map((m) => m.id).toSet();
    for (final dbMsg in dbMessages) {
      if (!existingIds.contains(dbMsg.id) && !matchedDbIds.contains(dbMsg.id)) {
        _messages.add(dbMsg);
      }
    }

    // Re-sort by timestamp
    _messages.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

    setState(() {
      _rebuildMessageIdMap();
    });
  }

  /// 文本变化监听
  void _onTextChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
    if (_isGroupMode) {
      _detectMentionTrigger();
    }
  }

  /// Start replying to a message
  void _startReply(Message message) {
    setState(() {
      _replyingToMessage = message;
    });

    // 群聊模式下，如果回复的是 agent 消息，自动插入 @mention
    if (_isGroupMode && message.from.isAgent) {
      final agentName = message.from.name;
      final currentText = _messageController.text;
      final mentionText = '@$agentName ';
      // 避免重复插入
      if (!currentText.contains(mentionText)) {
        _messageController.text = mentionText + currentText;
        _messageController.selection = TextSelection.collapsed(
          offset: _messageController.text.length,
        );
      }
    }

    _textFieldFocusNode.requestFocus();
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

    _itemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.3,
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
        SnackBar(content: Text(AppLocalizations.of(context).chat_voiceTooShort)),
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
      // Send to agent
      _sendAttachmentToAgent(message);
    }
  }

  /// Send an already-saved attachment message to the agent.
  ///
  /// Builds the [AttachmentData] from the local file, creates a streaming
  /// placeholder for the agent response, and calls [ChatService.sendMessageToAgent]
  /// with the pre-existing user message so it's not duplicated.
  Future<void> _sendAttachmentToAgent(Message attachmentMessage) async {
    // Build attachment data from saved file
    final attachmentData = await _attachmentService.buildAttachmentData(attachmentMessage);
    if (attachmentData == null) {
      debugPrint('Failed to build attachment data, skipping agent send');
      return;
    }

    // Check size limit
    if (attachmentData.exceedsSizeLimit) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File too large (max 20MB) to send to agent')),
        );
      }
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    setState(() {
      _isProcessing = true;
    });

    _acpCancellationToken = ACPCancellationToken();

    try {
      final databaseService = LocalDatabaseService();
      final remoteAgent = await databaseService.getRemoteAgentById(widget.agentId!);

      if (remoteAgent == null) {
        throw Exception('Agent not found');
      }

      final isLocal = LocalLLMAgentService.instance.isLocalAgent(remoteAgent);

      if (!isLocal && remoteAgent.endpoint.isEmpty) {
        throw Exception('Agent has no valid endpoint');
      }

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
        _messages.add(streamingMessage);
        _messageIdMap[streamingMessage.id] = streamingMessage;
      });
      _scrollToBottom(force: true);

      final agentResponse = await _chatService.sendMessageToAgent(
        content: attachmentMessage.content,
        agent: remoteAgent,
        userId: userId,
        userName: userName,
        channelId: _currentChannelId,
        acpCancellationToken: _acpCancellationToken,
        attachments: [attachmentData],
        existingUserMessage: attachmentMessage,
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
      );

      // Update streaming message with final response
      if (agentResponse != null && mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
          if (idx != -1) {
            _messages[idx] = agentResponse;
            _messageIdMap.remove(_streamingMessageId);
            _messageIdMap[agentResponse.id] = agentResponse;
          }
        });
      } else if (mounted) {
        // Remove empty streaming placeholder
        setState(() {
          _messages.removeWhere((m) => m.id == _streamingMessageId);
          _messageIdMap.remove(_streamingMessageId);
        });
      }
    } catch (e) {
      debugPrint('Error sending attachment to agent: $e');
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == _streamingMessageId);
          _messageIdMap.remove(_streamingMessageId);
        });
      }
    } finally {
      _streamingMessageId = null;
      _streamingContent = '';
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
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
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.chat_historyRequestTitle),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.chat_historyIgnore),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.chat_historyApprove),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 监听用户滚动，判断是否已主动上滑
  void _onScroll() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || _messages.isEmpty) return;
    // 检查最后一条消息是否在可视范围内
    final lastIndex = _messages.length - 1;
    final isAtBottom = positions.any((pos) => pos.index == lastIndex);
    if (_isUserScrolledUp && isAtBottom) {
      setState(() {
        _isUserScrolledUp = false;
        _unreadMessageCount = 0;
      });
      _markMessagesAsReadIfAtBottom();
    } else if (!_isUserScrolledUp && !isAtBottom) {
      setState(() {
        _isUserScrolledUp = true;
      });
    }
  }

  /// 滚动到底部
  void _scrollToBottom({bool force = false, bool isNewMessage = false}) {
    if (_messages.isEmpty) return;
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
    // 在底部收到新消息，自动标记已读
    if (isNewMessage) {
      _markMessagesAsReadIfAtBottom();
    }
    final lastIndex = _messages.length - 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _messages.isEmpty) return;
      if (force) {
        _itemScrollController.jumpTo(index: lastIndex, alignment: 0.0);
      } else {
        _itemScrollController.scrollTo(
          index: lastIndex,
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
    // 手动跳到底部，标记所有消息为已读
    _markMessagesAsReadIfAtBottom();
    if (_messages.isNotEmpty) {
      _itemScrollController.jumpTo(index: _messages.length - 1, alignment: 0.0);
    }
  }

  /// 全局硬件键盘事件处理，用于捕获 Cmd+V / Ctrl+V 粘贴图片
  /// HardwareKeyboard handler 在平台文本输入处理之前触发，可以可靠拦截粘贴操作
  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // 只在输入框获得焦点时处理
    if (!_textFieldFocusNode.hasFocus) return false;

    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isMetaPressed ||
         HardwareKeyboard.instance.isControlPressed)) {
      _handleDesktopPaste();
      // 返回 false，让文本粘贴继续正常工作（如果剪贴板是文本的话）
      return false;
    }
    return false;
  }

  /// 桌面端粘贴图片处理 — 暂存到预览列表，不直接发送
  Future<void> _handleDesktopPaste() async {
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes == null || imageBytes.isEmpty) return;

      // Save clipboard image to a temp file for staging
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/paste_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(imageBytes);

      await _addPendingAttachment(tempFile, isFromClipboard: true);
    } catch (e) {
      debugPrint('Error pasting image from clipboard: $e');
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
        // Send to agent
        _sendAttachmentToAgent(message);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).chat_sendImageError('$e'))),
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
        // Send to agent
        _sendAttachmentToAgent(message);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).chat_sendFileError('$e'))),
      );
    }
  }

  /// 桌面端：暂存附件到预览列表（不直接发送）
  Future<void> _addPendingAttachment(File file, {bool isFromClipboard = false}) async {
    if (_pendingAttachments.length >= _maxPendingAttachments) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_maxAttachments(_maxPendingAttachments))),
        );
      }
      return;
    }
    try {
      final attachment = await PendingAttachment.fromFile(
        file,
        isFromClipboard: isFromClipboard,
      );
      if (mounted) {
        setState(() {
          _pendingAttachments.add(attachment);
        });
      }
    } catch (e) {
      debugPrint('Error staging attachment: $e');
    }
  }

  /// 移除一个暂存附件
  void _removePendingAttachment(String id) {
    setState(() {
      final idx = _pendingAttachments.indexWhere((a) => a.id == id);
      if (idx != -1) {
        final att = _pendingAttachments.removeAt(idx);
        if (att.isFromClipboard) {
          try { att.file.deleteSync(); } catch (_) {}
        }
      }
    });
  }

  /// 桌面端：选择文件后暂存到预览列表
  Future<void> _pickAndStageFile() async {
    try {
      final file = await _attachmentService.pickFile();
      if (file == null) return;
      await _addPendingAttachment(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_sendFileError('$e'))),
        );
      }
    }
  }

  /// 显示附件选项
  void _showAttachmentOptions() {
    // Desktop: stage file to preview list instead of sending directly
    if (LayoutUtils.isDesktopLayout(context)) {
      _pickAndStageFile();
      return;
    }

    final l10n = AppLocalizations.of(context);
    LayoutUtils.showAdaptivePanel(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: Text(l10n.chat_photoLibrary),
            onTap: () {
              Navigator.pop(context);
              _pickAndSendImage();
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: Text(l10n.chat_camera),
            onTap: () {
              Navigator.pop(context);
              _pickAndSendImage();
            },
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file),
            title: Text(l10n.chat_file),
            onTap: () {
              Navigator.pop(context);
              _pickAndSendFile();
            },
          ),
        ],
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
        SnackBar(content: Text(AppLocalizations.of(context).chat_searchError('$e'))),
      );
    }
  }

  /// 显示搜索对话框 - 搜索该 agent 所有 session 的消息
  void _showSearchDialog() async {
    // 获取搜索范围的 channel IDs
    List<String>? agentChannelIds;
    if (_isGroupMode && _currentChannelId != null) {
      // 群聊模式：只搜索当前群的聊天记录
      agentChannelIds = [_currentChannelId!];
    } else if (widget.agentId != null) {
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
            if (widget.embedded) {
              widget.onSwitchChannel?.call(channelId);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    agentId: widget.agentId,
                    agentName: _agentName,
                    agentAvatar: _agentAvatar,
                    channelId: channelId,
                  ),
                ),
              );
            }
          } else {
            // 当前会话内滚动到消息
            final index = _messages.indexWhere((m) => m.id == message.id);
            if (index != -1) {
              _itemScrollController.scrollTo(
                index: index,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                alignment: 0.3,
              );
            }
          }
        },
      ),
    );
  }

  /// 删除消息
  Future<void> _deleteMessage(Message message) async {
    final l10n = AppLocalizations.of(context);
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';

    if (!MessageUtils.canDeleteMessage(message, userId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.chat_cannotDelete)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dialogL10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dialogL10n.chat_deleteTitle),
          content: Text(dialogL10n.chat_deleteContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dialogL10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(dialogL10n.common_delete),
            ),
          ],
        );
      },
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
        SnackBar(content: Text(l10n.chat_deleted)),
      );
    }
  }

  /// Rollback: 删除此消息及之后的所有消息，可选填充输入框
  Future<void> _rollbackMessage(Message message, {bool reEdit = false}) async {
    if (widget.agentId == null || _currentChannelId == null) return;

    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dialogL10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(reEdit ? dialogL10n.chat_reEditTitle : dialogL10n.chat_rollbackTitle),
          content: Text(dialogL10n.chat_rollbackContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dialogL10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: Text(reEdit ? dialogL10n.chat_reEdit : dialogL10n.chat_rollback),
            ),
          ],
        );
      },
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
                ? l10n.chat_reEditSuccess(0)
                : l10n.chat_rollbackSuccess(0)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.chat_rollbackFailed('$e'))),
        );
      }
    }
  }

  /// Build AppBar title for group chat mode.
  Widget _buildGroupAppBarTitle() {
    final groupName = _groupChannel?.name ?? 'Group';
    final memberCount = _groupAgents.length;

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.blue[100],
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.group, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                groupName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (_isProcessing && _respondingAgentNames.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${_respondingAgentNames.join(', ')} typing...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).primaryColor,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Text(
                      _mentionOnlyMode
                          ? '$memberCount agents · @mention mode'
                          : '$memberCount agents',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                    if (_currentChannelId != null && _groupChannel?.parentGroupId != null) ...[
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
    );
  }

  /// Build AppBar title for DM (1-on-1) chat mode.
  Widget _buildDMAppBarTitle() {
    return Row(
      children: [
        // Agent头像（可点击进入详情页）
        GestureDetector(
          onTap: _navigateToAgentDetail,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: _agentAvatar != null && _agentAvatar!.length > 2
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _agentAvatar!.startsWith('/') && !_agentAvatar!.startsWith('http')
                        ? Image.file(
                            File(_agentAvatar!),
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Text(
                                _agentName?.isNotEmpty == true
                                    ? _agentName![0]
                                    : 'A',
                                style: const TextStyle(fontSize: 28),
                              );
                            },
                          )
                        : Image.network(
                            _agentAvatar!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Text(
                                _agentName?.isNotEmpty == true
                                    ? _agentName![0]
                                    : 'A',
                                style: const TextStyle(fontSize: 28),
                              );
                            },
                          ),
                  )
                : Text(
                    _agentAvatar ??
                    (_agentName?.isNotEmpty == true
                        ? _agentName![0]
                        : 'A'),
                    style: const TextStyle(fontSize: 28),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        // Agent名称和状态
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _agentName ?? 'AI Agent',
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
                      AppLocalizations.of(context).widget_typing,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).primaryColor,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ] else if (_isCheckingHealth) ...[
                    Text(
                      AppLocalizations.of(context).status_connecting,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ] else ...[
                    Text(
                      _isAgentOnline
                          ? AppLocalizations.of(context).status_online
                          : AppLocalizations.of(context).status_offline,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 1,
        automaticallyImplyLeading: !widget.embedded,
        title: _isGroupMode ? _buildGroupAppBarTitle() : _buildDMAppBarTitle(),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, size: 20),
            tooltip: AppLocalizations.of(context).chat_sessionList,
            onPressed: _isGroupMode ? _showGroupSessionList : _showSessionList,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _isGroupMode ? _showGroupMenu : _showAgentMenu,
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

          // Mention picker overlay (group mode) — always in tree to preserve focus
          Offstage(
            offstage: !_showMentionPicker,
            child: _buildMentionPicker(),
          ),

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

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      initialScrollIndex: _messages.isNotEmpty ? _messages.length - 1 : 0,
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
          key: ValueKey(message.id),
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
                    isStreaming: message.id == _streamingMessageId || _groupStreamingMessageIds.contains(message.id),
                    onStop: message.id == _streamingMessageId ? _stopStreaming : null,
                    onActionSelected: (confirmationId, actionId, actionLabel) {
                      final confirmationContext = (message.metadata?['action_confirmation']
                          as Map<String, dynamic>?)?['confirmation_context'] as String?;
                      _handleActionSelected(message, confirmationId, actionId, actionLabel,
                          confirmationContext: confirmationContext);
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
                    onAvatarTap: message.from.isAgent
                        ? () => _navigateToAgentDetailById(message.from.id)
                        : null,
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
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: _agentAvatar != null && _agentAvatar!.length > 2
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: _agentAvatar!.startsWith('/') && !_agentAvatar!.startsWith('http')
                          ? Image.file(
                              File(_agentAvatar!),
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Text(
                                  _agentName?.isNotEmpty == true
                                      ? _agentName![0]
                                      : 'A',
                                  style: const TextStyle(fontSize: 56),
                                );
                              },
                            )
                          : Image.network(
                              _agentAvatar!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Text(
                                  _agentName?.isNotEmpty == true
                                      ? _agentName![0]
                                      : 'A',
                                  style: const TextStyle(fontSize: 56),
                                );
                              },
                            ),
                    )
                  : Text(
                      _agentAvatar ??
                      (_agentName?.isNotEmpty == true
                          ? _agentName![0]
                          : 'A'),
                      style: const TextStyle(fontSize: 56),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              _agentName ?? 'AI Agent',
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

  /// Detect @ mention trigger in text field
  void _detectMentionTrigger() {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursorPos = selection.baseOffset;

    if (cursorPos < 0 || cursorPos > text.length) {
      if (_showMentionPicker) {
        setState(() {
          _showMentionPicker = false;
        });
      }
      return;
    }

    // Walk backwards from cursor to find @
    int atPos = -1;
    for (int i = cursorPos - 1; i >= 0; i--) {
      final char = text[i];
      if (char == '@') {
        // Must be preceded by whitespace or be at start of string
        if (i == 0 || text[i - 1] == ' ' || text[i - 1] == '\n') {
          atPos = i;
        }
        break;
      }
      // Stop if we hit whitespace (no @ trigger)
      if (char == ' ' || char == '\n') break;
    }

    if (atPos >= 0) {
      final query = text.substring(atPos + 1, cursorPos).toLowerCase();
      final totalCount = _getMentionPickerItemCount(query);

      if (totalCount > 0) {
        final queryChanged = query != _mentionQuery;
        setState(() {
          _showMentionPicker = true;
          _mentionQuery = query;
          _mentionTriggerOffset = atPos;
          if (queryChanged) {
            _mentionSelectedIndex = 0;
          }
          if (_mentionSelectedIndex >= totalCount) {
            _mentionSelectedIndex = totalCount - 1;
          }
        });
        return;
      }
    }

    if (_showMentionPicker) {
      setState(() {
        _showMentionPicker = false;
      });
    }
  }

  /// Whether the "All" option matches the current query.
  bool _mentionAllMatches(String query) {
    return 'all'.contains(query);
  }

  /// Get total item count for mention picker (including "All" if it matches).
  int _getMentionPickerItemCount(String query) {
    final q = query.toLowerCase();
    final agentCount = _groupAgents.where(
      (a) => a.name.toLowerCase().contains(q),
    ).length;
    final allCount = _mentionAllMatches(q) ? 1 : 0;
    return allCount + agentCount;
  }

  /// Get filtered agents list for mention picker.
  List<RemoteAgent> _getFilteredMentionAgents() {
    return _groupAgents.where(
      (a) => a.name.toLowerCase().contains(_mentionQuery.toLowerCase()),
    ).toList();
  }

  /// Insert @AgentName at cursor, replacing the current @ trigger text.
  void _insertMentionAtCursor(RemoteAgent agent) {
    _insertMentionText('@${agent.name} ');
  }

  /// Insert @all at cursor, replacing the current @ trigger text.
  void _insertMentionAll() {
    _insertMentionText('@all ');
  }

  /// Shared logic: replace the @-trigger region with [mentionText] and dismiss picker.
  void _insertMentionText(String mentionText) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursorPos = selection.baseOffset;

    if (_mentionTriggerOffset >= 0 && cursorPos >= 0) {
      final newText = text.substring(0, _mentionTriggerOffset) +
          mentionText +
          text.substring(cursorPos);
      _messageController.text = newText;
      final newCursorPos = _mentionTriggerOffset + mentionText.length;
      _messageController.selection = TextSelection.collapsed(offset: newCursorPos);
    } else {
      _messageController.text = text + mentionText;
      _messageController.selection = TextSelection.collapsed(
        offset: _messageController.text.length,
      );
    }

    setState(() {
      _showMentionPicker = false;
      _mentionTriggerOffset = -1;
      _mentionQuery = '';
      _mentionSelectedIndex = 0;
    });

    _textFieldFocusNode.requestFocus();
  }

  /// Build the mention picker overlay widget.
  Widget _buildMentionPicker() {
    final showAll = _mentionAllMatches(_mentionQuery.toLowerCase());
    final filtered = _getFilteredMentionAgents();
    final totalCount = (showAll ? 1 : 0) + filtered.length;

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: totalCount,
        itemBuilder: (context, index) {
          // "All" is always the first item when visible
          if (showAll && index == 0) {
            final isSelected = _mentionSelectedIndex == 0;
            return ListTile(
              dense: true,
              selected: isSelected,
              selectedTileColor: Colors.blue.withOpacity(0.1),
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.orange[200] : Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.group, size: 16, color: Colors.orange[800]),
              ),
              title: Text(
                AppLocalizations.of(context).chat_mentionAll,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                AppLocalizations.of(context).chat_mentionAllSub(_groupAgents.length),
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              onTap: _insertMentionAll,
            );
          }

          final agentIndex = showAll ? index - 1 : index;
          final agent = filtered[agentIndex];
          final isSelected = index == _mentionSelectedIndex;
          return ListTile(
            dense: true,
            selected: isSelected,
            selectedTileColor: Colors.blue.withOpacity(0.1),
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue[200] : Colors.blue[100],
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                agent.name.isNotEmpty ? agent.name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            title: Text(
              agent.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            onTap: () => _insertMentionAtCursor(agent),
          );
        },
      ),
    );
  }

  /// Show group members panel.
  void _showGroupMembersPanel() {
    LayoutUtils.showAdaptivePanel(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _GroupMembersSheet(
        groupAgents: _groupAgents,
        channelId: _currentChannelId!,
        adminAgentId: _groupAdminAgentId,
        channelMembers: _groupChannel?.members ?? [],
        onAddMember: _addGroupMember,
        onRemoveMember: _removeGroupMember,
        onSaveGroupBio: _saveMemberGroupBio,
        onChangeAdmin: (agent) async {
          if (agent.id == _groupAdminAgentId) return;
          final parentGroupId = _groupChannel?.groupFamilyId ?? _currentChannelId!;
          final sessions = await _localDatabaseService.getGroupSessions(parentGroupId);
          for (final session in sessions) {
            if (_groupAdminAgentId != null) {
              await _localDatabaseService.updateChannelMemberRole(session.id, _groupAdminAgentId!, 'member');
            }
            await _localDatabaseService.updateChannelMemberRole(session.id, agent.id, 'admin');
          }
          await _refreshGroupMembers();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context).chat_adminChanged(agent.name))),
            );
          }
        },
        onMentionAgent: (agent) {
          Navigator.pop(sheetContext);
          _insertMentionAtCursor(agent);
          _textFieldFocusNode.requestFocus();
        },
      ),
    );
  }

  /// Add a member to the current group.
  Future<void> _addGroupMember() async {
    final l10n = AppLocalizations.of(context);
    // Load all available remote agents
    final allAgents = await _localDatabaseService.getAllRemoteAgents();
    final currentIds = _groupAgents.map((a) => a.id).toSet();
    final available = allAgents.where((a) => !currentIds.contains(a.id)).toList();

    if (!mounted) return;

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.chat_noMoreAgents)),
      );
      return;
    }

    final selected = await LayoutUtils.showAdaptivePanel<RemoteAgent>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.chat_addMember,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            ...available.map((agent) => ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  agent.name.isNotEmpty ? agent.name[0].toUpperCase() : '?',
                  style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(agent.name),
              subtitle: agent.bio != null && agent.bio!.isNotEmpty
                  ? Text(agent.bio!, maxLines: 1, overflow: TextOverflow.ellipsis)
                  : null,
              onTap: () => Navigator.pop(ctx, agent),
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;

    await _localDatabaseService.addChannelMember(_currentChannelId!, selected.id);

    // Notify group members and insert system message
    final systemMsg = await _chatService.notifyGroupMembershipChange(
      _currentChannelId!,
      selected.id,
      selected.name,
      isJoin: true,
    );
    if (mounted) {
      setState(() {
        _messages.add(systemMsg);
        _messageIdMap[systemMsg.id] = systemMsg;
      });
      _scrollToBottom();
    }

    await _refreshGroupMembers();

    if (mounted) {
      // Re-open the members panel to show updated list
      _showGroupMembersPanel();
    }
  }

  /// Remove a member from the current group.
  Future<void> _removeGroupMember(RemoteAgent agent) async {
    final l10n = AppLocalizations.of(context);
    if (_groupAgents.length <= 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.chat_cannotRemoveLast)),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogL10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(dialogL10n.chat_removeMember),
          content: Text(dialogL10n.chat_removeMemberContent(agent.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(dialogL10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(dialogL10n.chat_removeButton),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await _localDatabaseService.removeChannelMember(_currentChannelId!, agent.id);

    // Notify remaining group members and insert system message
    final systemMsg = await _chatService.notifyGroupMembershipChange(
      _currentChannelId!,
      agent.id,
      agent.name,
      isJoin: false,
    );
    if (mounted) {
      setState(() {
        _messages.add(systemMsg);
        _messageIdMap[systemMsg.id] = systemMsg;
      });
      _scrollToBottom();
    }

    await _refreshGroupMembers();

    if (mounted) {
      // Re-open the members panel to show updated list
      _showGroupMembersPanel();
    }
  }

  /// Reload group members from the database.
  Future<void> _refreshGroupMembers() async {
    if (_currentChannelId == null) return;
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';

    final channel = await _localDatabaseService.getChannelById(_currentChannelId!);
    final memberIds = await _localDatabaseService.getChannelMemberIds(_currentChannelId!);
    final agentIds = memberIds.where((id) => id != userId && id != 'user').toList();
    final agents = <RemoteAgent>[];
    for (final agentId in agentIds) {
      final agent = await _localDatabaseService.getRemoteAgentById(agentId);
      if (agent != null) agents.add(agent);
    }

    if (mounted) {
      setState(() {
        _groupAgents = agents;
        _groupChannel = channel;
        _groupAdminAgentId = channel?.adminAgentId;
      });
    }
  }

  /// Save a member's group bio and return the updated member list (for inline editing).
  Future<List<ChannelMember>> _saveMemberGroupBio(RemoteAgent agent, String? newGroupBio) async {
    if (_currentChannelId == null) return _groupChannel?.members ?? [];

    // Update all sessions in the group family
    final parentGroupId = _groupChannel?.groupFamilyId ?? _currentChannelId!;
    final sessions = await _localDatabaseService.getGroupSessions(parentGroupId);
    for (final session in sessions) {
      await _localDatabaseService.updateChannelMemberGroupBio(session.id, agent.id, newGroupBio);
    }

    await _refreshGroupMembers();
    return _groupChannel?.members ?? [];
  }

  /// Parse @mentions from message content, returning matching agent IDs.
  List<String> _parseMentionedAgentIds(String content) {
    // @all mentions every agent in the group
    if (content.contains('@all')) {
      return _groupAgents.map((a) => a.id).toList();
    }
    final mentioned = <String>[];
    for (final agent in _groupAgents) {
      if (content.contains('@${agent.name}')) {
        mentioned.add(agent.id);
      }
    }
    return mentioned;
  }

  Widget _buildInputArea() {
    final isDesktop = LayoutUtils.isDesktopLayout(context);

    if (isDesktop) {
      return _buildDesktopInputArea();
    }
    return _buildMobileInputArea();
  }

  /// 桌面端：暂存附件预览区域（水平滚动，显示在工具栏和输入框之间）
  Widget _buildPendingAttachmentsPreview() {
    if (_pendingAttachments.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
        ),
      ),
      child: SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pendingAttachments.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final att = _pendingAttachments[index];
            if (att.type == PendingAttachmentType.image) {
              return _buildImagePreviewItem(att);
            } else {
              return _buildFilePreviewItem(att);
            }
          },
        ),
      ),
    );
  }

  Widget _buildImagePreviewItem(PendingAttachment att) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: att.thumbnailBytes != null
              ? Image.memory(
                  att.thumbnailBytes!,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                )
              : Container(
                  width: 80,
                  height: 80,
                  color: Colors.grey[200],
                  child: const Icon(Icons.image, color: Colors.grey),
                ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => _removePendingAttachment(att.id),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilePreviewItem(PendingAttachment att) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 160,
          height: 80,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              Icon(Icons.insert_drive_file, size: 32, color: Colors.blue[400]),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      att.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      PendingAttachment.formatFileSize(att.fileSize),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => _removePendingAttachment(att.id),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  /// 桌面端输入区域 - 参考微信布局：工具栏在输入框顶部，输入框更大
  Widget _buildDesktopInputArea() {
    return Container(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部工具栏：表情、附件
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _showEmojiPicker
                        ? Icons.keyboard
                        : Icons.emoji_emotions_outlined,
                    size: 22,
                  ),
                  color: Colors.grey[600],
                  onPressed: _toggleEmojiPicker,
                  tooltip: 'Emoji',
                  splashRadius: 18,
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file, size: 22),
                  color: Colors.grey[600],
                  onPressed: _showAttachmentOptions,
                  tooltip: 'Attachment',
                  splashRadius: 18,
                ),
              ],
            ),
          ),
          // 暂存附件预览区域
          _buildPendingAttachmentsPreview(),
          // 输入框区域
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleInputKeyEvent,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 80,
                        maxHeight: 200,
                      ),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _textFieldFocusNode,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context).chat_messageHint,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        enabled: !_isLoading,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 桌面端只显示发送按钮，不显示语音按钮
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _isLoading
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
                      : IconButton(
                          icon: const Icon(Icons.send),
                          color: _canSend
                              ? Theme.of(context).primaryColor
                              : Colors.grey[400],
                          onPressed: _canSend ? _sendMessage : null,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 移动端输入区域 - 保留原有布局
  Widget _buildMobileInputArea() {
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
                child: Focus(
                  onKeyEvent: _handleInputKeyEvent,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: TextField(
                      controller: _messageController,
                      focusNode: _textFieldFocusNode,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).chat_messageHint,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
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
                            SnackBar(
                              content: Text(AppLocalizations.of(context).chat_holdToRecord),
                              duration: const Duration(seconds: 1),
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
                                SnackBar(
                                  content: Text(AppLocalizations.of(context).chat_micNotAvailable),
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

  /// 输入框键盘事件处理（Enter 发送、Arrow 选择 mention）
  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    // Only handle KeyDown events (not KeyUp/KeyRepeat)
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // --- Enter key ---
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      // IME composing (e.g. Chinese candidate selection) → don't intercept
      if (_messageController.value.composing != TextRange.empty) {
        return KeyEventResult.ignored;
      }
      // Shift+Enter → newline (let TextField handle it)
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      // Mention picker open → confirm selection
      if (_showMentionPicker) {
        final showAll = _mentionAllMatches(_mentionQuery.toLowerCase());
        if (showAll && _mentionSelectedIndex == 0) {
          _insertMentionAll();
        } else {
          final filtered = _getFilteredMentionAgents();
          final agentIndex = showAll ? _mentionSelectedIndex - 1 : _mentionSelectedIndex;
          if (agentIndex >= 0 && agentIndex < filtered.length) {
            _insertMentionAtCursor(filtered[agentIndex]);
          }
        }
        return KeyEventResult.handled;
      }
      _sendMessage();
      return KeyEventResult.handled;
    }

    // --- Arrow keys for mention picker ---
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && _showMentionPicker) {
      final totalCount = _getMentionPickerItemCount(_mentionQuery);
      if (totalCount > 0) {
        setState(() {
          _mentionSelectedIndex = (_mentionSelectedIndex - 1).clamp(0, totalCount - 1);
        });
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && _showMentionPicker) {
      final totalCount = _getMentionPickerItemCount(_mentionQuery);
      if (totalCount > 0) {
        setState(() {
          _mentionSelectedIndex = (_mentionSelectedIndex + 1).clamp(0, totalCount - 1);
        });
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// 导航到 Agent 详情页
  Future<void> _navigateToAgentDetail() async {
    if (widget.agentId == null) return;
    await _navigateToAgentDetailById(widget.agentId!);
  }

  /// 通过 Agent ID 导航到详情页
  Future<void> _navigateToAgentDetailById(String agentId) async {
    final remoteAgent = await _localDatabaseService.getRemoteAgentById(agentId);
    if (remoteAgent != null && mounted) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RemoteAgentDetailScreen(agent: remoteAgent),
        ),
      );
      if (result == 'deleted' && mounted) {
        if (_isGroupMode) {
          await _refreshGroupMembers();
        } else {
          if (widget.embedded) {
            widget.onClose?.call();
          } else {
            Navigator.pop(context);
          }
        }
      } else if (mounted) {
        // Re-read agent from DB to pick up any avatar/name changes
        final updated = await _localDatabaseService.getRemoteAgentById(agentId);
        if (updated != null) {
          setState(() {
            _agentName = updated.name;
            _agentAvatar = updated.avatar;
          });
        }
      }
    }
  }

  /// Edit group name, description, and system prompt.
  Future<void> _editGroupInfo() async {
    if (LayoutUtils.isDesktopLayout(context)) {
      _editGroupInfoDesktop();
    } else {
      _editGroupInfoDialog();
    }
  }

  /// Desktop: edit group info in a right sidebar panel.
  void _editGroupInfoDesktop() {
    final nameController = TextEditingController(text: _groupChannel?.name ?? '');
    final descController = TextEditingController(text: _groupChannel?.description ?? '');
    final systemPromptController = TextEditingController(text: _groupChannel?.systemPrompt ?? '');

    LayoutUtils.showRightDrawer(
      context: context,
      builder: (ctx) {
        final panelL10n = AppLocalizations.of(ctx);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      panelL10n.chat_editGroupInfo,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: panelL10n.chat_groupName,
                        border: const OutlineInputBorder(),
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descController,
                      decoration: InputDecoration(
                        labelText: panelL10n.chat_groupDescriptionOptional,
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: systemPromptController,
                      decoration: InputDecoration(
                        labelText: panelL10n.chat_groupSystemPrompt,
                        hintText: panelL10n.chat_groupSystemPromptHint,
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(panelL10n.common_cancel),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () async {
                            final newName = nameController.text.trim();
                            if (newName.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text(panelL10n.chat_groupNameEmpty)),
                              );
                              return;
                            }
                            final old = _groupChannel!;
                            final newSystemPrompt = systemPromptController.text.trim();
                            final updated = Channel(
                              id: old.id,
                              name: newName,
                              type: old.type,
                              members: old.members,
                              createdBy: old.createdBy,
                              createdAt: old.createdAt,
                              description: descController.text.trim().isNotEmpty ? descController.text.trim() : null,
                              systemPrompt: newSystemPrompt.isNotEmpty ? newSystemPrompt : null,
                              avatar: old.avatar,
                              isPrivate: old.isPrivate,
                            );
                            await _localDatabaseService.updateChannel(updated);
                            if (mounted) {
                              setState(() {
                                _groupChannel = updated;
                              });
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: Text(panelL10n.common_save),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Mobile / fallback: edit group info in a dialog.
  Future<void> _editGroupInfoDialog() async {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController(text: _groupChannel?.name ?? '');
    final descController = TextEditingController(text: _groupChannel?.description ?? '');
    final systemPromptController = TextEditingController(text: _groupChannel?.systemPrompt ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogL10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(dialogL10n.chat_editGroupInfo),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: dialogL10n.chat_groupName,
                    border: const OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: InputDecoration(
                    labelText: dialogL10n.chat_groupDescriptionOptional,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: systemPromptController,
                  decoration: InputDecoration(
                    labelText: dialogL10n.chat_groupSystemPrompt,
                    hintText: dialogL10n.chat_groupSystemPromptHint,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(dialogL10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(dialogL10n.common_save),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final newName = nameController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.chat_groupNameEmpty)),
      );
      return;
    }

    final old = _groupChannel!;
    final newSystemPrompt = systemPromptController.text.trim();
    final updated = Channel(
      id: old.id,
      name: newName,
      type: old.type,
      members: old.members,
      createdBy: old.createdBy,
      createdAt: old.createdAt,
      description: descController.text.trim().isNotEmpty ? descController.text.trim() : null,
      systemPrompt: newSystemPrompt.isNotEmpty ? newSystemPrompt : null,
      avatar: old.avatar,
      isPrivate: old.isPrivate,
    );
    await _localDatabaseService.updateChannel(updated);

    if (mounted) {
      setState(() {
        _groupChannel = updated;
      });
    }
  }

  /// 显示群聊菜单
  void _showGroupMenu() {
    if (LayoutUtils.isDesktopLayout(context)) {
      _showGroupMenuDesktop();
    } else {
      _showGroupMenuMobile();
    }
  }

  void _showGroupMenuDesktop() {
    final menuL10n = AppLocalizations.of(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final screenSize = overlay.size;

    // Position the menu at top-right, below the AppBar
    final RelativeRect position = RelativeRect.fromLTRB(
      screenSize.width - 280, // right-aligned with 280px width
      kToolbarHeight + MediaQuery.of(context).padding.top,
      0,
      0,
    );

    showMenu<String>(
      context: context,
      position: position,
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 280),
      items: [
        PopupMenuItem(value: 'editGroup', child: ListTile(dense: true, leading: const Icon(Icons.edit), title: Text(menuL10n.chat_editGroupInfo))),
        PopupMenuItem(value: 'members', child: ListTile(dense: true, leading: const Icon(Icons.group), title: Text(menuL10n.chat_groupMembers))),
        PopupMenuItem(value: 'addMember', child: ListTile(dense: true, leading: const Icon(Icons.person_add), title: Text(menuL10n.chat_addMember))),
        PopupMenuItem(value: 'search', child: ListTile(dense: true, leading: const Icon(Icons.search), title: Text(menuL10n.chat_searchMessages))),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'editGroup': _editGroupInfo();
        case 'members': _showGroupMembersPanel();
        case 'addMember': _addGroupMember();
        case 'search': _showSearchDialog();
      }
    });
  }

  void _showGroupMenuMobile() {
    final menuL10n = AppLocalizations.of(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final screenSize = overlay.size;

    final RelativeRect position = RelativeRect.fromLTRB(
      screenSize.width - 280,
      kToolbarHeight + MediaQuery.of(context).padding.top,
      0,
      0,
    );

    showMenu<String>(
      context: context,
      position: position,
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 280),
      items: [
        PopupMenuItem(value: 'editGroup', child: ListTile(dense: true, leading: const Icon(Icons.edit), title: Text(menuL10n.chat_editGroupInfo))),
        PopupMenuItem(value: 'members', child: ListTile(dense: true, leading: const Icon(Icons.group), title: Text(menuL10n.chat_groupMembers))),
        PopupMenuItem(value: 'addMember', child: ListTile(dense: true, leading: const Icon(Icons.person_add), title: Text(menuL10n.chat_addMember))),
        PopupMenuItem(value: 'search', child: ListTile(dense: true, leading: const Icon(Icons.search), title: Text(menuL10n.chat_searchMessages))),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'editGroup': _editGroupInfo();
        case 'members': _showGroupMembersPanel();
        case 'addMember': _addGroupMember();
        case 'search': _showSearchDialog();
      }
    });
  }

  /// 显示Agent菜单
  void _showAgentMenu() {
    if (LayoutUtils.isDesktopLayout(context)) {
      _showAgentMenuDesktop();
    } else {
      _showAgentMenuMobile();
    }
  }

  void _showAgentMenuDesktop() {
    final menuL10n = AppLocalizations.of(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final screenSize = overlay.size;

    final RelativeRect position = RelativeRect.fromLTRB(
      screenSize.width - 280,
      kToolbarHeight + MediaQuery.of(context).padding.top,
      0,
      0,
    );

    showMenu<String>(
      context: context,
      position: position,
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 280),
      items: [
        PopupMenuItem(value: 'reset', child: ListTile(dense: true, leading: const Icon(Icons.refresh), title: Text(menuL10n.chat_resetSession))),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'details', child: ListTile(dense: true, leading: const Icon(Icons.info_outline), title: Text(menuL10n.chat_viewDetails))),
        PopupMenuItem(value: 'search', child: ListTile(dense: true, leading: const Icon(Icons.search), title: Text(menuL10n.chat_searchMessages))),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'reset': _resetSession();
        case 'details': _navigateToAgentDetail();
        case 'search': _showSearchDialog();
      }
    });
  }

  void _showAgentMenuMobile() {
    final menuL10n = AppLocalizations.of(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final screenSize = overlay.size;

    final RelativeRect position = RelativeRect.fromLTRB(
      screenSize.width - 280,
      kToolbarHeight + MediaQuery.of(context).padding.top,
      0,
      0,
    );

    showMenu<String>(
      context: context,
      position: position,
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 280),
      items: [
        PopupMenuItem(value: 'reset', child: ListTile(dense: true, leading: const Icon(Icons.refresh), title: Text(menuL10n.chat_resetSession))),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'details', child: ListTile(dense: true, leading: const Icon(Icons.info_outline), title: Text(menuL10n.chat_viewDetails))),
        PopupMenuItem(value: 'search', child: ListTile(dense: true, leading: const Icon(Icons.search), title: Text(menuL10n.chat_searchMessages))),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'reset': _resetSession();
        case 'details': _navigateToAgentDetail();
        case 'search': _showSearchDialog();
      }
    });
  }

  /// 从 channelId 中提取简短的会话标识
  String _shortSessionId(String channelId) {
    // Group channels: use creation time from channel object if available
    if (_isGroupMode && _groupChannel != null) {
      // For group sessions, show a readable label
      if (_groupChannel!.parentGroupId == null && channelId == _groupChannel!.id) {
        return 'Session #default';
      }
    }
    // channelId 格式: dm_userId_agentId 或 dm_userId_agentId_timestamp
    //                  group_<uuid>
    final parts = channelId.split('_');
    if (parts.length > 3) {
      // DM with timestamp suffix
      return 'Session #${parts.last.substring(parts.last.length > 6 ? parts.last.length - 6 : 0)}';
    }
    if (channelId.startsWith('group_') && parts.length == 2) {
      // group_<uuid> - show last 6 chars of uuid
      final uuid = parts[1];
      return 'Session #${uuid.substring(uuid.length > 6 ? uuid.length - 6 : 0)}';
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
      builder: (context) {
        final dialogL10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dialogL10n.chat_clearSessionHistory),
          content: Text(dialogL10n.chat_clearSessionContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(dialogL10n.common_cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _clearCurrentSessionHistory();
              },
              child: Text(
                dialogL10n.common_clear,
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 确认清除所有会话记录
  void _confirmClearAllSessions() {
    showDialog(
      context: context,
      builder: (context) {
        final dialogL10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dialogL10n.chat_clearAllSessions),
          content: Text(dialogL10n.chat_clearAllSessionsContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(dialogL10n.common_cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _clearAllSessionsHistory();
              },
              child: Text(
                dialogL10n.chat_clearAllSessions,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
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
    // Use current session channel; fall back to active session lookup
    final sessionId = _currentChannelId
        ?? await _chatService.getLatestActiveChannelId(userId, widget.agentId!)
        ?? _chatService.generateChannelId(userId, widget.agentId!);

    // Show loading overlay
    _showClearingOverlay(AppLocalizations.of(context).chat_clearingSession);

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
              content: Text(AppLocalizations.of(context).chat_switchSession(_shortSessionId(targetSession.id))),
              duration: const Duration(seconds: 2),
            ),
          );
          // Navigate to the other session with animation
          if (widget.embedded) {
            widget.onSwitchChannel?.call(targetSession.id);
          } else {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
                  agentId: widget.agentId,
                  agentName: _agentName,
                  agentAvatar: _agentAvatar,
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
            SnackBar(content: Text(AppLocalizations.of(context).chat_sessionCleared)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // dismiss overlay
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_clearSessionFailed('$e'))),
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
    // Use current session channel; fall back to active session lookup
    final sessionId = _currentChannelId
        ?? await _chatService.getLatestActiveChannelId(userId, widget.agentId!)
        ?? _chatService.generateChannelId(userId, widget.agentId!);

    // Show loading overlay
    _showClearingOverlay(AppLocalizations.of(context).chat_clearingAllSessions);

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
          name: 'Chat with ${_agentName ?? 'Agent'}',
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
            SnackBar(content: Text(AppLocalizations.of(context).chat_allSessionsCleared)),
          );
        } else {
          // Navigate to default channel
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).chat_allSessionsSwitched(_shortSessionId(defaultChannelId))),
              duration: const Duration(seconds: 2),
            ),
          );
          if (widget.embedded) {
            widget.onSwitchChannel?.call(defaultChannelId);
          } else {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
                  agentId: widget.agentId,
                  agentName: _agentName,
                  agentAvatar: _agentAvatar,
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
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // dismiss overlay
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_clearAllSessionsFailed('$e'))),
        );
      }
    }
  }

  /// 显示清理中的加载覆盖层
  void _showClearingOverlay(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
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

  /// 新建群聊会话
  Future<void> _createNewGroupSession() async {
    if (_groupChannel == null || _currentChannelId == null) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';

    try {
      final newChannelId = await _chatService.createNewGroupSession(
        channelId: _currentChannelId!,
        userId: userId,
      );

      await _localDatabaseService.touchChannelUpdatedAt(newChannelId);

      if (mounted) {
        if (widget.embedded) {
          widget.onSwitchChannel?.call(newChannelId);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(channelId: newChannelId),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_newGroupSessionFailed('$e'))),
        );
      }
    }
  }

  /// 显示群聊会话列表
  Future<void> _showGroupSessionList() async {
    if (_groupChannel == null) return;

    try {
      final parentGroupId = _groupChannel!.groupFamilyId;
      final sessions = await _chatService.getGroupSessions(parentGroupId: parentGroupId);
      if (!mounted) return;

      final databaseService = LocalDatabaseService();
      final currentChannelId = _currentChannelId;

      Widget buildSessionListContent(BuildContext context, {ScrollController? scrollController}) {
        return StatefulBuilder(
          builder: (context, setInnerState) {
            var isSelectionMode = false;
            var selectedIds = <String>{};

            return StatefulBuilder(
              builder: (context, setState) {
                final l10n = AppLocalizations.of(context);

                Widget buildHeader() {
                  if (isSelectionMode) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                  isSelectionMode = false;
                                  selectedIds.clear();
                                }),
                              ),
                              Text(
                                l10n.chat_selectSessions,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () => setState(() {
                                  selectedIds = sessions
                                      .where((s) => s.id != currentChannelId)
                                      .map((s) => s.id)
                                      .toSet();
                                }),
                                child: Text(l10n.osTool_selectAll),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  final newSet = <String>{};
                                  for (final s in sessions) {
                                    if (s.id == currentChannelId) continue;
                                    if (!selectedIds.contains(s.id)) {
                                      newSet.add(s.id);
                                    }
                                  }
                                  selectedIds = newSet;
                                }),
                                child: Text(l10n.chat_invertSelection),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 16, bottom: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l10n.chat_selectedCount(selectedIds.length),
                                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(
                      children: [
                        Text(
                          l10n.chat_groupSessions,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        if (sessions.length > 1)
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: l10n.chat_selectSessions,
                            onPressed: () => setState(() {
                              isSelectionMode = true;
                            }),
                          ),
                        Text(
                          l10n.chat_sessionsCount(sessions.length),
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                Widget buildNewSessionItem() {
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.add,
                        color: Theme.of(context).primaryColor,
                        size: 24,
                      ),
                    ),
                    title: Text(
                      l10n.chat_newSession,
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _createNewGroupSession();
                    },
                  );
                }

                Widget buildList() {
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: sessions.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        if (isSelectionMode) return const SizedBox.shrink();
                        return buildNewSessionItem();
                      }
                      final session = sessions[index - 1];
                      final isCurrent = session.id == currentChannelId;
                      return FutureBuilder<Map<String, dynamic>?>(
                        future: databaseService.getLatestChannelMessage(session.id),
                        builder: (context, snapshot) {
                          final tile = _buildGroupSessionTile(session, isCurrent, snapshot.data, popContext: context);
                          if (!isSelectionMode) return tile;
                          return ListTile(
                            leading: Checkbox(
                              value: selectedIds.contains(session.id),
                              onChanged: isCurrent
                                  ? null
                                  : (val) => setState(() {
                                        if (val == true) {
                                          selectedIds.add(session.id);
                                        } else {
                                          selectedIds.remove(session.id);
                                        }
                                      }),
                            ),
                            title: tile,
                            contentPadding: EdgeInsets.zero,
                            onTap: isCurrent
                                ? null
                                : () => setState(() {
                                      if (selectedIds.contains(session.id)) {
                                        selectedIds.remove(session.id);
                                      } else {
                                        selectedIds.add(session.id);
                                      }
                                    }),
                          );
                        },
                      );
                    },
                  );
                }

                Widget? buildBottomBar() {
                  if (!isSelectionMode) return null;
                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.delete_outline),
                          label: Text(l10n.chat_deleteSelected(selectedIds.length)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  _batchDeleteSessions(selectedIds.toList(), isGroup: true);
                                },
                        ),
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    buildHeader(),
                    const Divider(height: 1),
                    Expanded(child: buildList()),
                    if (buildBottomBar() != null) buildBottomBar()!,
                  ],
                );
              },
            );
          },
        );
      }

      if (LayoutUtils.isDesktopLayout(context)) {
        LayoutUtils.showRightDrawer(
          context: context,
          builder: (context) => buildSessionListContent(context),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: Text(AppLocalizations.of(context).chat_sessionList),
                elevation: 1,
              ),
              body: buildSessionListContent(context),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_loadGroupSessionsFailed('$e'))),
        );
      }
    }
  }

  /// 构建群聊会话列表项
  ///
  /// [popContext] — see [_buildSessionTile] for explanation.
  Widget _buildGroupSessionTile(Channel session, bool isCurrentSession, Map<String, dynamic>? latestMessage, {BuildContext? popContext}) {
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

    final isParent = session.parentGroupId == null;
    final label = isParent ? 'Session #default' : _shortSessionId(session.id);

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isCurrentSession ? Theme.of(context).primaryColor : Colors.grey[300],
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.group,
          color: isCurrentSession ? Colors.white : Colors.grey[600],
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${session.name} ($label)',
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
          ? () => Navigator.of(popContext ?? context).pop()
          : () async {
              await _localDatabaseService.touchChannelUpdatedAt(session.id);
              Navigator.of(popContext ?? context).pop();
              if (widget.embedded) {
                widget.onSwitchChannel?.call(session.id);
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(channelId: session.id),
                  ),
                );
              }
            },
    );
  }

  /// 确认清除当前群聊会话记录
  void _confirmClearGroupSession() {
    showDialog(
      context: context,
      builder: (context) {
        final dialogL10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dialogL10n.chat_clearSessionHistory),
          content: Text(dialogL10n.chat_clearSessionGroupContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(dialogL10n.common_cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _clearGroupSessionHistory();
              },
              child: Text(
                dialogL10n.common_clear,
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 确认清除所有群聊会话记录
  void _confirmClearAllGroupSessions() {
    showDialog(
      context: context,
      builder: (context) {
        final dialogL10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dialogL10n.chat_clearAllSessions),
          content: Text(dialogL10n.chat_clearAllGroupSessionsContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(dialogL10n.common_cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _clearAllGroupSessionsHistory();
              },
              child: Text(
                dialogL10n.chat_clearAllSessions,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 清除当前群聊会话记录
  Future<void> _clearGroupSessionHistory() async {
    if (_groupChannel == null || _currentChannelId == null) return;

    _showClearingOverlay(AppLocalizations.of(context).chat_clearingGroupSession);

    try {
      final agentIds = _groupAgents.map((a) => a.id).toList();
      final parentGroupId = _groupChannel!.groupFamilyId;

      // Get all sessions to check if there are multiple
      final sessions = await _chatService.getGroupSessions(parentGroupId: parentGroupId);

      if (sessions.length > 1) {
        // Multiple sessions: clear and delete current, navigate to another
        await _chatService.clearGroupSessionHistory(
          channelId: _currentChannelId!,
          agentIds: agentIds,
        );
        await _localDatabaseService.deleteChannel(_currentChannelId!);

        final remaining = sessions.where((s) => s.id != _currentChannelId).toList();
        final targetSession = remaining.first;

        if (mounted) {
          Navigator.of(context).pop(); // dismiss overlay
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).chat_switchSession(_shortSessionId(targetSession.id))),
              duration: const Duration(seconds: 2),
            ),
          );
          if (widget.embedded) {
            widget.onSwitchChannel?.call(targetSession.id);
          } else {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
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
        }
      } else {
        // Only one session: just clear messages
        await _chatService.clearGroupSessionHistory(
          channelId: _currentChannelId!,
          agentIds: agentIds,
        );

        if (mounted) {
          Navigator.of(context).pop(); // dismiss overlay
          setState(() {
            _messages.clear();
            _messageIdMap.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).chat_groupSessionCleared)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // dismiss overlay
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_clearGroupSessionFailed('$e'))),
        );
      }
    }
  }

  /// 清除所有群聊会话记录
  Future<void> _clearAllGroupSessionsHistory() async {
    if (_groupChannel == null || _currentChannelId == null) return;

    _showClearingOverlay(AppLocalizations.of(context).chat_clearingAllGroupSessions);

    try {
      final agentIds = _groupAgents.map((a) => a.id).toList();
      final parentGroupId = _groupChannel!.groupFamilyId;

      await _chatService.clearAllGroupSessions(
        parentGroupId: parentGroupId,
        currentChannelId: _currentChannelId!,
        agentIds: agentIds,
      );

      if (mounted) {
        Navigator.of(context).pop(); // dismiss overlay
        final isAlreadyParent = _currentChannelId == parentGroupId;

        if (isAlreadyParent) {
          // Already on the parent channel, just clear UI
          setState(() {
            _messages.clear();
            _messageIdMap.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).chat_allGroupSessionsCleared)),
          );
        } else {
          // Navigate to parent channel
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('All sessions cleared. Switching to ${_shortSessionId(parentGroupId)}'),
              duration: const Duration(seconds: 2),
            ),
          );
          if (widget.embedded) {
            widget.onSwitchChannel?.call(parentGroupId);
          } else {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
                  channelId: parentGroupId,
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
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // dismiss overlay
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_clearAllGroupSessionsFailed('$e'))),
        );
      }
    }
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
        agentName: _agentName ?? 'Agent',
      );

      await _localDatabaseService.touchChannelUpdatedAt(newChannelId);

      if (mounted) {
        if (widget.embedded) {
          widget.onSwitchChannel?.call(newChannelId);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                agentId: widget.agentId,
                agentName: _agentName,
                agentAvatar: _agentAvatar,
                channelId: newChannelId,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_newSessionFailed('$e'))),
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
      final currentChannelId = _currentChannelId;

      Widget buildSessionListContent(BuildContext context, {ScrollController? scrollController}) {
        return StatefulBuilder(
          builder: (context, setInnerState) {
            var isSelectionMode = false;
            var selectedIds = <String>{};

            return StatefulBuilder(
              builder: (context, setState) {
                final l10n = AppLocalizations.of(context);

                Widget buildHeader() {
                  if (isSelectionMode) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                  isSelectionMode = false;
                                  selectedIds.clear();
                                }),
                              ),
                              Text(
                                l10n.chat_selectSessions,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () => setState(() {
                                  selectedIds = sessions
                                      .where((s) => s.id != currentChannelId)
                                      .map((s) => s.id)
                                      .toSet();
                                }),
                                child: Text(l10n.osTool_selectAll),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  final newSet = <String>{};
                                  for (final s in sessions) {
                                    if (s.id == currentChannelId) continue;
                                    if (!selectedIds.contains(s.id)) {
                                      newSet.add(s.id);
                                    }
                                  }
                                  selectedIds = newSet;
                                }),
                                child: Text(l10n.chat_invertSelection),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 16, bottom: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l10n.chat_selectedCount(selectedIds.length),
                                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(
                      children: [
                        Text(
                          l10n.chat_sessions,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        if (sessions.length > 1)
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: l10n.chat_selectSessions,
                            onPressed: () => setState(() {
                              isSelectionMode = true;
                            }),
                          ),
                        Text(
                          l10n.chat_sessionsCount(sessions.length),
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                Widget buildNewSessionItem() {
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.add,
                        color: Theme.of(context).primaryColor,
                        size: 24,
                      ),
                    ),
                    title: Text(
                      l10n.chat_newSession,
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _createNewSession();
                    },
                  );
                }

                Widget buildList() {
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: sessions.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        if (isSelectionMode) return const SizedBox.shrink();
                        return buildNewSessionItem();
                      }
                      final session = sessions[index - 1];
                      final isCurrent = session.id == currentChannelId;
                      return FutureBuilder<Map<String, dynamic>?>(
                        future: databaseService.getLatestChannelMessage(session.id),
                        builder: (context, snapshot) {
                          final tile = _buildSessionTile(session, isCurrent, snapshot.data, popContext: context);
                          if (!isSelectionMode) return tile;
                          return ListTile(
                            leading: Checkbox(
                              value: selectedIds.contains(session.id),
                              onChanged: isCurrent
                                  ? null
                                  : (val) => setState(() {
                                        if (val == true) {
                                          selectedIds.add(session.id);
                                        } else {
                                          selectedIds.remove(session.id);
                                        }
                                      }),
                            ),
                            title: tile,
                            contentPadding: EdgeInsets.zero,
                            onTap: isCurrent
                                ? null
                                : () => setState(() {
                                      if (selectedIds.contains(session.id)) {
                                        selectedIds.remove(session.id);
                                      } else {
                                        selectedIds.add(session.id);
                                      }
                                    }),
                          );
                        },
                      );
                    },
                  );
                }

                Widget? buildBottomBar() {
                  if (!isSelectionMode) return null;
                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.delete_outline),
                          label: Text(l10n.chat_deleteSelected(selectedIds.length)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  _batchDeleteSessions(selectedIds.toList(), isGroup: false);
                                },
                        ),
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    buildHeader(),
                    const Divider(height: 1),
                    Expanded(child: buildList()),
                    if (buildBottomBar() != null) buildBottomBar()!,
                  ],
                );
              },
            );
          },
        );
      }

      if (LayoutUtils.isDesktopLayout(context)) {
        LayoutUtils.showRightDrawer(
          context: context,
          builder: (context) => buildSessionListContent(context),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: Text(AppLocalizations.of(context).chat_sessionList),
                elevation: 1,
              ),
              body: buildSessionListContent(context),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_loadSessionsFailed('$e'))),
        );
      }
    }
  }

  /// 批量删除选中的会话
  Future<void> _batchDeleteSessions(List<String> sessionIds, {required bool isGroup}) async {
    if (sessionIds.isEmpty) return;

    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dialogL10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dialogL10n.chat_deleteSession),
          content: Text(dialogL10n.chat_batchDeleteContent(sessionIds.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dialogL10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                dialogL10n.common_delete,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    _showClearingOverlay(l10n.chat_clearingAllSessions);

    try {
      for (final id in sessionIds) {
        await _localDatabaseService.deleteChannelMessages(id);
        await _localDatabaseService.deleteChannel(id);
      }

      if (mounted) {
        Navigator.pop(context); // dismiss overlay
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.chat_batchDeleteSuccess(sessionIds.length))),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // dismiss overlay
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.chat_clearSessionFailed('$e'))),
        );
      }
    }
  }

  /// 构建会话列表项
  ///
  /// [popContext] is the BuildContext used to dismiss the session list overlay.
  /// On desktop the session list lives on the root Navigator (via showGeneralDialog),
  /// so we must pop using the dialog's context rather than [State.context] which
  /// belongs to the nested right-panel Navigator.
  Widget _buildSessionTile(Channel session, bool isCurrentSession, Map<String, dynamic>? latestMessage, {BuildContext? popContext}) {
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
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isCurrentSession ? Theme.of(context).primaryColor : Colors.grey[300],
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
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
          ? () => Navigator.of(popContext ?? context).pop()
          : () async {
              Navigator.of(popContext ?? context).pop();
              await _localDatabaseService.touchChannelUpdatedAt(session.id);
              if (!mounted) return;
              if (widget.embedded) {
                widget.onSwitchChannel?.call(session.id);
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      agentId: widget.agentId,
                      agentName: _agentName,
                      agentAvatar: _agentAvatar,
                      channelId: session.id,
                    ),
                  ),
                );
              }
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
      builder: (context) {
        final menuL10n = AppLocalizations.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(menuL10n.common_copy),
                onTap: () {
                  Navigator.pop(context);
                  // Copy to clipboard
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(menuL10n.chat_copiedToClipboard)),
                  );
                },
              ),
              if (!message.from.isUser || _isGroupMode)
                ListTile(
                  leading: const Icon(Icons.reply),
                  title: Text(menuL10n.common_reply),
                  onTap: () {
                    Navigator.pop(context);
                    _startReply(message);
                  },
                ),
              if (message.type == MessageType.image || message.type == MessageType.file)
                ListTile(
                  leading: const Icon(Icons.download),
                  title: Text(menuL10n.chat_download),
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(menuL10n.common_featureComingSoon)),
                    );
                  },
                ),
              if (message.from.isUser) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.replay, color: Colors.orange),
                  title: Text(menuL10n.chat_rollback, style: const TextStyle(color: Colors.orange)),
                  subtitle: Text(menuL10n.chat_rollbackSub),
                  onTap: () {
                    Navigator.pop(context);
                    _rollbackMessage(message);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note, color: Colors.blue),
                  title: Text(menuL10n.chat_reEdit, style: const TextStyle(color: Colors.blue)),
                  subtitle: Text(menuL10n.chat_reEditSub),
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
                  title: Text(menuL10n.common_delete, style: const TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteMessage(message);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Stateful bottom sheet for group members with add/remove support.
class _GroupMembersSheet extends StatefulWidget {
  final List<RemoteAgent> groupAgents;
  final String channelId;
  final String? adminAgentId;
  final List<ChannelMember> channelMembers;
  final Future<void> Function() onAddMember;
  final Future<void> Function(RemoteAgent agent) onRemoveMember;
  /// Saves the group bio for [agent]. Returns the updated ChannelMember list
  /// so the sheet can refresh inline.
  final Future<List<ChannelMember>> Function(RemoteAgent agent, String? newGroupBio) onSaveGroupBio;
  final Future<void> Function(RemoteAgent agent) onChangeAdmin;
  final void Function(RemoteAgent agent) onMentionAgent;

  const _GroupMembersSheet({
    required this.groupAgents,
    required this.channelId,
    this.adminAgentId,
    this.channelMembers = const [],
    required this.onAddMember,
    required this.onRemoveMember,
    required this.onSaveGroupBio,
    required this.onChangeAdmin,
    required this.onMentionAgent,
  });

  @override
  State<_GroupMembersSheet> createState() => _GroupMembersSheetState();
}

class _GroupMembersSheetState extends State<_GroupMembersSheet> {
  /// Which agent is currently being edited inline (null = none).
  String? _editingAgentId;
  late TextEditingController _editController;
  late List<ChannelMember> _channelMembers;
  /// Tracks admin selection during editing; null means no change.
  bool _editingIsAdmin = false;
  /// Current admin agent id, updated locally after save.
  late String? _currentAdminAgentId;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _channelMembers = List.of(widget.channelMembers);
    _currentAdminAgentId = widget.adminAgentId;
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _startEditing(RemoteAgent agent) {
    final member = _channelMembers.where((m) => m.id == agent.id).firstOrNull;
    _editController.text = member?.groupBio ?? '';
    setState(() {
      _editingAgentId = agent.id;
      _editingIsAdmin = _currentAdminAgentId == agent.id;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingAgentId = null;
    });
  }

  Future<void> _saveEditing(RemoteAgent agent) async {
    final text = _editController.text.trim();
    final newGroupBio = text.isEmpty ? null : text;
    final updatedMembers = await widget.onSaveGroupBio(agent, newGroupBio);
    // Handle admin change
    final wasAdmin = _currentAdminAgentId == agent.id;
    if (_editingIsAdmin && !wasAdmin) {
      await widget.onChangeAdmin(agent);
      if (mounted) {
        setState(() {
          _currentAdminAgentId = agent.id;
        });
      }
    }
    if (mounted) {
      setState(() {
        _channelMembers = updatedMembers;
        _editingAgentId = null;
      });
    }
  }

  Future<void> _resetGroupBio(RemoteAgent agent) async {
    final updatedMembers = await widget.onSaveGroupBio(agent, null);
    if (mounted) {
      setState(() {
        _channelMembers = updatedMembers;
        _editingAgentId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Group Members (${widget.groupAgents.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onAddMember();
                  },
                  icon: const Icon(Icons.person_add, size: 20),
                  label: Text(l10n.chat_add),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...widget.groupAgents.map((agent) {
            final member = _channelMembers.where((m) => m.id == agent.id).firstOrNull;
            final groupBio = member?.groupBio;
            final displayBio = groupBio ?? agent.bio;
            final hasGroupBio = groupBio != null && groupBio.isNotEmpty;
            final isEditing = _editingAgentId == agent.id;

            if (isEditing) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            agent.name.isNotEmpty ? agent.name[0].toUpperCase() : '?',
                            style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.chat_groupRoleTitle(agent.name),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    if (agent.bio != null && agent.bio!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Default: ${agent.bio}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _editController,
                      maxLines: 3,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: l10n.chat_groupCapabilityLabel,
                        hintText: l10n.chat_groupCapabilityHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _editingIsAdmin = !_editingIsAdmin;
                        });
                      },
                      child: Row(
                        children: [
                          SizedBox(
                            height: 32,
                            width: 40,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Switch(
                                value: _editingIsAdmin,
                                onChanged: (v) {
                                  setState(() {
                                    _editingIsAdmin = v;
                                  });
                                },
                                activeTrackColor: Colors.orange[200],
                                activeThumbColor: Colors.orange[700],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.admin_panel_settings, size: 18, color: _editingIsAdmin ? Colors.orange[700] : Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(
                            l10n.createGroup_setAsAdmin,
                            style: TextStyle(
                              fontSize: 13,
                              color: _editingIsAdmin ? Colors.orange[700] : Colors.grey[600],
                              fontWeight: _editingIsAdmin ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _cancelEditing,
                          child: Text(l10n.common_cancel),
                        ),
                        if (hasGroupBio)
                          TextButton(
                            onPressed: () => _resetGroupBio(agent),
                            child: Text(l10n.chat_resetButton, style: TextStyle(color: Colors.orange[700])),
                          ),
                        TextButton(
                          onPressed: () => _saveEditing(agent),
                          child: Text(l10n.common_save),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                  ],
                ),
              );
            }

            return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                agent.name.isNotEmpty ? agent.name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    agent.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_currentAdminAgentId == agent.id) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Admin',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[800],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: displayBio != null && displayBio.isNotEmpty
                ? Text(
                    displayBio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: hasGroupBio
                        ? TextStyle(color: Colors.blue[600], fontStyle: FontStyle.italic)
                        : null,
                  )
                : Text(
                    'Set group role...',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.edit_note, size: 20, color: Colors.blue[300]),
                  tooltip: 'Edit group role',
                  onPressed: () => _startEditing(agent),
                ),
                IconButton(
                  icon: Icon(Icons.remove_circle_outline, color: Colors.red[300]),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onRemoveMember(agent);
                  },
                ),
              ],
            ),
            onTap: () => widget.onMentionAgent(agent),
          );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
