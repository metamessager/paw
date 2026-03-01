import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/channel.dart';
import '../models/remote_agent.dart';
import '../models/acp_protocol.dart';
import '../models/llm_stream_event.dart';
import '../models/attachment_data.dart';
import 'local_database_service.dart';
import 'acp_agent_connection.dart';
import 'local_llm_agent_service.dart';
import 'notification_service.dart';
import 'app_lifecycle_service.dart';
import '../providers/notification_provider.dart';
import 'os_tool_registry.dart';
import 'os_tool_executor.dart' as os_exec;
import 'skill_registry.dart';
import 'ui_component_registry.dart';
import 'inference_log_service.dart';
import '../models/inference_log_entry.dart';

/// Result of a history supplement request, carrying both the agent's
/// re-answer message and how many history entries were actually sent.
class HistorySupplementResult {
  final Message message;
  final int actualSentCount;
  /// Non-null when the agent asked for even more history during this supplement.
  final Map<String, dynamic>? pendingHistoryRequest;
  const HistorySupplementResult({
    required this.message,
    required this.actualSentCount,
    this.pendingHistoryRequest,
  });
}

/// Tracks an in-flight ACP task so it can continue in the background
/// when the user navigates away from the chat screen.
class ActiveTask {
  final String taskId;
  final String agentId;
  final String agentName;
  final String channelId;
  final String userMessageId;
  final String userId;
  final String userName;

  String accumulatedContent = '';
  Map<String, dynamic>? metadata;
  bool isComplete = false;
  String? errorMessage;

  /// Completes after the agent response has been persisted to the database.
  /// UI should await this before reloading messages.
  final Completer<void> dbSaveCompleter = Completer<void>();

  // Detachable UI callbacks — set to null when user leaves the screen
  void Function(String chunk)? onStreamChunk;
  void Function(Map<String, dynamic>)? onActionConfirmation;
  void Function(Map<String, dynamic>)? onSingleSelect;
  void Function(Map<String, dynamic>)? onMultiSelect;
  void Function(Map<String, dynamic>)? onFileUpload;
  void Function(Map<String, dynamic>)? onForm;
  Future<void> Function(Map<String, dynamic>)? onFileMessage;
  void Function(Map<String, dynamic>)? onMessageMetadata;
  void Function(Map<String, dynamic>)? onRequestHistory;

  /// OS tool confirmation callback — returns true if user approves.
  Future<bool> Function(String toolName, Map<String, dynamic> args, os_exec.RiskLevel risk)? onOsToolConfirmation;

  /// Called when the task finishes (complete or error) so the UI can refresh.
  void Function()? onTaskFinished;

  ActiveTask({
    required this.taskId,
    required this.agentId,
    required this.agentName,
    required this.channelId,
    required this.userMessageId,
    required this.userId,
    required this.userName,
  });

  void detachUI() {
    onStreamChunk = null;
    onActionConfirmation = null;
    onSingleSelect = null;
    onMultiSelect = null;
    onFileUpload = null;
    onForm = null;
    onFileMessage = null;
    onMessageMetadata = null;
    onRequestHistory = null;
    onOsToolConfirmation = null;
    onTaskFinished = null;
  }
}

/// Tracks an in-flight group agent task so it can continue in the background
/// when the user navigates away from the chat screen.
/// Unlike [ActiveTask] (keyed by channelId, one per channel), group chats may
/// have multiple concurrent agents per channel, so these are keyed by
/// channelId -> agentId.
class GroupActiveTask {
  final String agentId;
  final String agentName;
  final String channelId;
  String accumulatedContent = '';
  bool isComplete = false;

  // Detachable UI callbacks — set to null when user leaves the screen
  void Function(String chunk)? onStreamChunk;
  void Function()? onTaskFinished;

  GroupActiveTask({
    required this.agentId,
    required this.agentName,
    required this.channelId,
  });

  void detachUI() {
    onStreamChunk = null;
    onTaskFinished = null;
  }
}

/// Chat Service
/// Handles message sending and receiving with agents
class ChatService {
  static final ChatService _instance = ChatService._internal(LocalDatabaseService());
  factory ChatService([LocalDatabaseService? db]) => _instance;

  final LocalDatabaseService _databaseService;
  final Uuid _uuid = const Uuid();

  // Stream controllers for real-time updates
  final Map<String, StreamController<List<Message>>> _messageControllers = {};

  // ACP connection pool (keyed by agent ID)
  final Map<String, ACPAgentConnection> _acpConnections = {};

  // Active tasks (keyed by channelId) — survives UI detach/reattach
  final Map<String, ActiveTask> _activeTasks = {};

  // Active group tasks: channelId -> { agentId -> GroupActiveTask }
  final Map<String, Map<String, GroupActiveTask>> _activeGroupTasks = {};

  /// Notifier that emits the set of agent IDs currently typing (have active tasks).
  final ValueNotifier<Set<String>> typingAgentIds = ValueNotifier<Set<String>>({});

  ChatService._internal(this._databaseService);

  /// Notification provider, injected from the widget layer.
  NotificationProvider? _notificationProvider;

  void setNotificationProvider(NotificationProvider provider) {
    _notificationProvider = provider;
  }

  /// Recompute and notify [typingAgentIds] based on current active tasks.
  void _updateTypingAgentIds() {
    final ids = _activeTasks.values
        .where((t) => !t.isComplete)
        .map((t) => t.agentId)
        .toSet();
    // Include group active tasks
    for (final agentMap in _activeGroupTasks.values) {
      for (final task in agentMap.values) {
        if (!task.isComplete) ids.add(task.agentId);
      }
    }
    typingAgentIds.value = ids;
  }

  /// Query whether there is an in-progress task for [channelId].
  ActiveTask? getActiveTask(String channelId) {
    final task = _activeTasks[channelId];
    if (task != null && !task.isComplete) return task;
    return null;
  }

  /// Re-attach UI callbacks to a running background task.
  /// Returns the content accumulated so far, or null if no active task.
  String? attachTaskUI(
    String channelId, {
    void Function(String chunk)? onStreamChunk,
    void Function(Map<String, dynamic>)? onActionConfirmation,
    void Function(Map<String, dynamic>)? onSingleSelect,
    void Function(Map<String, dynamic>)? onMultiSelect,
    void Function(Map<String, dynamic>)? onFileUpload,
    void Function(Map<String, dynamic>)? onForm,
    Future<void> Function(Map<String, dynamic>)? onFileMessage,
    void Function(Map<String, dynamic>)? onMessageMetadata,
    void Function(Map<String, dynamic>)? onRequestHistory,
    void Function()? onTaskFinished,
  }) {
    final task = _activeTasks[channelId];
    if (task == null || task.isComplete) return null;

    task.onStreamChunk = onStreamChunk;
    task.onActionConfirmation = onActionConfirmation;
    task.onSingleSelect = onSingleSelect;
    task.onMultiSelect = onMultiSelect;
    task.onFileUpload = onFileUpload;
    task.onForm = onForm;
    task.onFileMessage = onFileMessage;
    task.onMessageMetadata = onMessageMetadata;
    task.onRequestHistory = onRequestHistory;
    task.onTaskFinished = onTaskFinished;

    return task.accumulatedContent;
  }

  /// Detach UI callbacks from the task on [channelId] without cancelling it.
  void detachTaskUI(String channelId) {
    _activeTasks[channelId]?.detachUI();
  }

  /// Get all active (non-complete) group tasks for a channel.
  Map<String, GroupActiveTask> getActiveGroupTasks(String channelId) {
    final agentMap = _activeGroupTasks[channelId];
    if (agentMap == null) return const {};
    // Return only tasks that are still in-progress
    final active = <String, GroupActiveTask>{};
    for (final entry in agentMap.entries) {
      if (!entry.value.isComplete) {
        active[entry.key] = entry.value;
      }
    }
    return active;
  }

  /// Attach UI callbacks to active group tasks for [channelId].
  /// Returns a map of agentId -> accumulated content so far.
  Map<String, String> attachGroupTaskUI(
    String channelId, {
    void Function(String agentId, String agentName, String chunk)? onStreamChunk,
    void Function(String agentId, String agentName)? onTaskFinished,
  }) {
    final agentMap = _activeGroupTasks[channelId];
    if (agentMap == null) return const {};
    final accumulated = <String, String>{};
    for (final entry in agentMap.entries) {
      final task = entry.value;
      if (task.isComplete) continue;
      accumulated[entry.key] = task.accumulatedContent;
      task.onStreamChunk = (chunk) {
        onStreamChunk?.call(task.agentId, task.agentName, chunk);
      };
      task.onTaskFinished = () {
        onTaskFinished?.call(task.agentId, task.agentName);
      };
    }
    return accumulated;
  }

  /// Detach UI callbacks from all group tasks for [channelId].
  void detachGroupTaskUI(String channelId) {
    final agentMap = _activeGroupTasks[channelId];
    if (agentMap == null) return;
    for (final task in agentMap.values) {
      task.detachUI();
    }
  }

  /// Close the message stream controller for a single [channelId].
  /// Use this when a ChatScreen for that channel is disposed, instead of
  /// the global [detachUI] which tears down controllers for every channel.
  void closeChannelStream(String channelId) {
    final controller = _messageControllers.remove(channelId);
    controller?.close();
  }

  /// Get message stream for a channel
  Stream<List<Message>> getMessageStream(String channelId) {
    if (!_messageControllers.containsKey(channelId)) {
      _messageControllers[channelId] = StreamController<List<Message>>.broadcast();
    }
    return _messageControllers[channelId]!.stream;
  }

  /// Send message to agent and get response
  Future<Message?> sendMessageToAgent({
    required String content,
    required RemoteAgent agent,
    required String userId,
    required String userName,
    String? channelId,
    String? replyToId,
    void Function(String chunk)? onStreamChunk,
    void Function(Map<String, dynamic> actionData)? onActionConfirmation,
    void Function(Map<String, dynamic> selectData)? onSingleSelect,
    void Function(Map<String, dynamic> selectData)? onMultiSelect,
    void Function(Map<String, dynamic> uploadData)? onFileUpload,
    void Function(Map<String, dynamic> formData)? onForm,
    Future<void> Function(Map<String, dynamic> fileData)? onFileMessage,
    void Function(Map<String, dynamic> metadata)? onMessageMetadata,
    void Function(Map<String, dynamic> historyRequestData)? onRequestHistory,
    Future<bool> Function(String toolName, Map<String, dynamic> args, os_exec.RiskLevel risk)? onOsToolConfirmation,
    ACPCancellationToken? acpCancellationToken,
    List<AttachmentData>? attachments,
    Message? existingUserMessage,
  }) async {
    print('🚀 [ChatService] 开始发送消息到 Agent');
    print('   - Agent ID: ${agent.id}');
    print('   - Agent Name: ${agent.name}');
    print('   - Agent Protocol: ${agent.protocol}');
    print('   - Agent Status: ${agent.status}');
    print('   - Agent Endpoint: ${agent.endpoint}');
    print('   - Message Content: $content');

    try {
      // Check if this is a local LLM agent — bypass status/endpoint checks
      if (LocalLLMAgentService.instance.isLocalAgent(agent)) {
        print('🏠 [ChatService] Detected local LLM agent, using local LLM path');
        return await _sendViaLocalLLM(
          content: content,
          agent: agent,
          userId: userId,
          userName: userName,
          channelId: channelId,
          replyToId: replyToId,
          onStreamChunk: onStreamChunk,
          onActionConfirmation: onActionConfirmation,
          onSingleSelect: onSingleSelect,
          onMultiSelect: onMultiSelect,
          onFileUpload: onFileUpload,
          onForm: onForm,
          onFileMessage: onFileMessage,
          onMessageMetadata: onMessageMetadata,
          onOsToolConfirmation: onOsToolConfirmation,
          acpCancellationToken: acpCancellationToken,
          attachments: attachments,
          existingUserMessage: existingUserMessage,
        );
      }

      // Check if agent is online
      if (agent.status != AgentStatus.online) {
        print('❌ [ChatService] Agent ${agent.name} is not online (status: ${agent.status})');
        throw Exception('Agent ${agent.name} is not online');
      }
      print('✅ [ChatService] Agent is online');

      // Check if agent has valid endpoint
      if (agent.endpoint.isEmpty) {
        print('❌ [ChatService] Agent ${agent.name} has no valid endpoint');
        throw Exception('Agent ${agent.name} has no valid endpoint');
      }
      print('✅ [ChatService] Endpoint is valid');

      // Create user message (skip if pre-existing attachment message provided)
      Message userMessage;
      if (existingUserMessage != null) {
        userMessage = existingUserMessage;
        print('📝 [ChatService] Using existing user message: ${userMessage.id}');
      } else {
        userMessage = Message(
          id: _uuid.v4(),
          content: content,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          from: MessageFrom(
            id: userId,
            type: 'user',
            name: userName,
          ),
          to: MessageFrom(
            id: agent.id,
            type: 'agent',
            name: agent.name,
          ),
          type: MessageType.text,
          replyTo: replyToId,
        );

        print('📝 [ChatService] Created user message: ${userMessage.id}');

        // Save user message to database
        await _saveMessageToChannel(userMessage, agent.id, channelId: channelId);
        print('💾 [ChatService] User message saved to database');
      }

      // Resolve quoted message content so agent understands reply context
      Message messageToSend = userMessage;
      if (replyToId != null) {
        final quotedMsg = await getMessageById(replyToId);
        if (quotedMsg != null) {
          messageToSend = Message(
            id: userMessage.id,
            content: '[引用 ${quotedMsg.from.name} 的消息: "${quotedMsg.content}"]\n\n${userMessage.content}',
            timestampMs: userMessage.timestampMs,
            from: userMessage.from,
            to: userMessage.to,
            type: userMessage.type,
            replyTo: userMessage.replyTo,
          );
        }
      }

      // Send message to agent based on protocol
      Message? agentResponse;
      print('🔄 [ChatService] Preparing to send message via ${agent.protocol} protocol...');

      if (agent.protocol == ProtocolType.acp) {
        print('   - Using ACP protocol');
        agentResponse = await _sendViaACPProtocol(
          messageToSend, agent,
          onStreamChunk: onStreamChunk,
          onActionConfirmation: onActionConfirmation,
          onSingleSelect: onSingleSelect,
          onMultiSelect: onMultiSelect,
          onFileUpload: onFileUpload,
          onForm: onForm,
          onFileMessage: onFileMessage,
          onMessageMetadata: onMessageMetadata,
          onRequestHistory: onRequestHistory,
          sessionId: channelId,
          acpCancellationToken: acpCancellationToken,
          attachments: attachments,
        );
      } else {
        // For other protocols, use generic HTTP POST
        print('   - Using generic protocol');
        agentResponse = await _sendViaGenericProtocol(messageToSend, agent);
      }

      // Save agent response if received
      if (agentResponse != null) {
        print('✅ [ChatService] Received agent response: ${agentResponse.id}');
        print('   - Response content: ${agentResponse.content}');
        await _saveMessageToChannel(agentResponse, agent.id, channelId: channelId);
        print('💾 [ChatService] Agent response saved to database');
      } else {
        print('⚠️ [ChatService] No agent response received');
      }

      // Signal the active task that DB save is done, then clean up
      if (channelId != null) {
        final task = _activeTasks.remove(channelId);
        _updateTypingAgentIds();
        if (task != null && !task.dbSaveCompleter.isCompleted) {
          task.dbSaveCompleter.complete();
        }
      }

      return agentResponse;
    } catch (e, stackTrace) {
      print('❌ [ChatService] 发送消息失败');
      print('   - Error: $e');
      print('   - Stack trace: $stackTrace');

      // Create error message
      final errorMessage = Message(
        id: _uuid.v4(),
        content: 'Error: Failed to send message to ${agent.name}. Details: $e',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        from: MessageFrom(
          id: 'system',
          type: 'system',
          name: 'System',
        ),
        type: MessageType.system,
      );
      await _saveMessageToChannel(errorMessage, agent.id, channelId: channelId);

      // Signal the active task that DB save is done (even on error), then clean up
      if (channelId != null) {
        final task = _activeTasks.remove(channelId);
        _updateTypingAgentIds();
        if (task != null && !task.dbSaveCompleter.isCompleted) {
          task.dbSaveCompleter.complete();
        }
      }
      return null;
    }
  }

  /// Send message via ACP WebSocket protocol
  Future<Message?> _sendViaACPProtocol(Message userMessage, RemoteAgent agent, {
    void Function(String chunk)? onStreamChunk,
    void Function(Map<String, dynamic> actionData)? onActionConfirmation,
    void Function(Map<String, dynamic> selectData)? onSingleSelect,
    void Function(Map<String, dynamic> selectData)? onMultiSelect,
    void Function(Map<String, dynamic> uploadData)? onFileUpload,
    void Function(Map<String, dynamic> formData)? onForm,
    Future<void> Function(Map<String, dynamic> fileData)? onFileMessage,
    void Function(Map<String, dynamic> metadata)? onMessageMetadata,
    void Function(Map<String, dynamic> historyRequestData)? onRequestHistory,
    String? sessionId,
    ACPCancellationToken? acpCancellationToken,
    List<AttachmentData>? attachments,
  }) async {
    print('🔌 [ACPProtocol] Starting ACP WebSocket protocol');
    print('   - Agent Endpoint: ${agent.endpoint}');

    try {
      // Get or create connection for this agent
      final connection = await _getOrCreateACPConnection(agent);

      // Create task ID
      final taskId = _uuid.v4();

      // Bind cancellation token
      acpCancellationToken?.bind(connection, taskId);

      // Create ActiveTask for background tracking
      final effectiveChannelId = sessionId ?? '';
      final activeTask = ActiveTask(
        taskId: taskId,
        agentId: agent.id,
        agentName: agent.name,
        channelId: effectiveChannelId,
        userMessageId: userMessage.id,
        userId: userMessage.from.id,
        userName: userMessage.from.name,
      );

      // Attach initial UI callbacks
      activeTask.onStreamChunk = onStreamChunk;
      activeTask.onActionConfirmation = onActionConfirmation;
      activeTask.onSingleSelect = onSingleSelect;
      activeTask.onMultiSelect = onMultiSelect;
      activeTask.onFileUpload = onFileUpload;
      activeTask.onForm = onForm;
      activeTask.onFileMessage = onFileMessage;
      activeTask.onMessageMetadata = onMessageMetadata;
      activeTask.onRequestHistory = onRequestHistory;

      // Register active task
      if (effectiveChannelId.isNotEmpty) {
        _activeTasks[effectiveChannelId] = activeTask;
        _updateTypingAgentIds();
      }

      // Task completion tracking
      final taskCompleter = Completer<void>();
      Map<String, dynamic>? actionConfirmationData;
      Map<String, dynamic>? singleSelectData;
      Map<String, dynamic>? multiSelectData;
      Map<String, dynamic>? fileUploadData;
      Map<String, dynamic>? formDataCapture;
      Map<String, dynamic>? messageMetadataExtra;

      // Hook cancellation token so the completer resolves immediately on cancel.
      acpCancellationToken?.onCancelled = () {
        activeTask.isComplete = true;
        if (!taskCompleter.isCompleted) {
          taskCompleter.complete();
        }
      };

      // Set up connection callbacks — accumulate in ActiveTask, then forward to UI
      connection.onTextContent = (data) {
        final content = data['content'] as String? ?? '';
        activeTask.accumulatedContent += content;
        activeTask.onStreamChunk?.call(content);
      };

      connection.onActionConfirmation = (data) {
        actionConfirmationData = Map<String, dynamic>.from(data);
        activeTask.onActionConfirmation?.call(data);
      };

      connection.onSingleSelect = (data) {
        singleSelectData = Map<String, dynamic>.from(data);
        activeTask.onSingleSelect?.call(data);
      };

      connection.onMultiSelect = (data) {
        multiSelectData = Map<String, dynamic>.from(data);
        activeTask.onMultiSelect?.call(data);
      };

      connection.onFileUpload = (data) {
        fileUploadData = Map<String, dynamic>.from(data);
        activeTask.onFileUpload?.call(data);
      };

      connection.onForm = (data) {
        formDataCapture = Map<String, dynamic>.from(data);
        activeTask.onForm?.call(data);
      };

      connection.onFileMessage = (data) {
        activeTask.onFileMessage?.call(data);
      };

      connection.onMessageMetadata = (data) {
        messageMetadataExtra = Map<String, dynamic>.from(data);
        activeTask.onMessageMetadata?.call(data);
      };

      connection.onRequestHistory = (data) {
        activeTask.onRequestHistory?.call(data);
      };

      connection.onTaskCompleted = (data) {
        activeTask.isComplete = true;
        activeTask.onTaskFinished?.call();
        if (!taskCompleter.isCompleted) {
          taskCompleter.complete();
        }
      };

      connection.onTaskError = (data) {
        activeTask.isComplete = true;
        activeTask.errorMessage = data['message'] as String? ?? 'Task error';
        activeTask.onTaskFinished?.call();
        if (!taskCompleter.isCompleted) {
          taskCompleter.completeError(
            Exception(data['message'] ?? 'Task error'),
          );
        }
      };

      // Load history — exclude the current user message to avoid duplication
      // (the agent receives it separately via the `message` parameter).
      // Include attachment messages (image/audio/file) so agent has context.
      List<Map<String, String>>? chatHistory;
      int? totalMessageCount;
      if (sessionId != null) {
        final messages = await loadChannelMessages(sessionId, limit: 40);
        if (messages.isNotEmpty) {
          chatHistory = messages
              .where((m) => m.type != MessageType.system && m.type != MessageType.permissionAudit && m.id != userMessage.id)
              .map((m) => <String, String>{
                    'role': m.from.isAgent ? 'assistant' : 'user',
                    'content': m.content,
                  })
              .toList();
        }
        totalMessageCount = await _databaseService.getChannelMessageCount(sessionId);
      }

      // Serialize attachments for ACP protocol
      final serializedAttachments = attachments
          ?.where((a) => !a.exceedsSizeLimit)
          .map((a) => a.toJson())
          .toList();

      // Send chat message
      await connection.sendChatMessage(
        taskId: taskId,
        sessionId: sessionId ?? '',
        message: userMessage.content,
        userId: userMessage.from.id,
        messageId: userMessage.id,
        history: chatHistory,
        totalMessageCount: totalMessageCount,
        systemPrompt: agent.metadata['system_prompt'] as String?,
        attachments: serializedAttachments,
      );

      // Wait for task.completed, task.error, or local cancellation
      await taskCompleter.future.timeout(
        const Duration(seconds: 300),
        onTimeout: () {
          throw TimeoutException('ACP task timed out');
        },
      );

      // If cancelled, clean up callbacks and return partial content.
      if (acpCancellationToken?.isCancelled == true) {
        _clearACPCallbacks(connection);
        final responseContent = activeTask.accumulatedContent;
        return Message(
          id: _uuid.v4(),
          content: responseContent.isNotEmpty
              ? '$responseContent\n\n[Stopped]'
              : '[Stopped]',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          from: MessageFrom(id: agent.id, type: 'agent', name: agent.name),
          to: MessageFrom(id: userMessage.from.id, type: 'user', name: userMessage.from.name),
          type: MessageType.text,
          replyTo: userMessage.id,
        );
      }

      // Build metadata
      Map<String, dynamic>? messageMetadata;
      if (actionConfirmationData != null || singleSelectData != null ||
          multiSelectData != null || fileUploadData != null ||
          formDataCapture != null || messageMetadataExtra != null) {
        final meta = <String, dynamic>{};
        if (messageMetadataExtra != null) {
          meta.addAll(messageMetadataExtra!);
        }
        if (actionConfirmationData != null) {
          meta['action_confirmation'] = actionConfirmationData;
        }
        if (singleSelectData != null) {
          meta['single_select'] = singleSelectData;
        }
        if (multiSelectData != null) {
          meta['multi_select'] = multiSelectData;
        }
        if (fileUploadData != null) {
          meta['file_upload'] = fileUploadData;
        }
        if (formDataCapture != null) {
          meta['form'] = formDataCapture;
        }
        messageMetadata = meta;
      }
      activeTask.metadata = messageMetadata;

      // Clear callbacks and remove from active tasks
      _clearACPCallbacks(connection);
      // NOTE: Don't remove from _activeTasks here — sendMessageToAgent will
      // do it after persisting the response to DB so the UI can await the save.

      final responseContent = activeTask.accumulatedContent;
      return Message(
        id: _uuid.v4(),
        content: responseContent.isNotEmpty ? responseContent : 'Task completed',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        from: MessageFrom(
          id: agent.id,
          type: 'agent',
          name: agent.name,
        ),
        to: MessageFrom(
          id: userMessage.from.id,
          type: 'user',
          name: userMessage.from.name,
        ),
        type: MessageType.text,
        replyTo: userMessage.id,
        metadata: messageMetadata,
      );
    } catch (e, stackTrace) {
      print('❌ [ACPProtocol] Error: $e');
      print('   - Stack trace: $stackTrace');
      // Don't remove from _activeTasks here — sendMessageToAgent's catch
      // will handle DB save and cleanup via dbSaveCompleter.
      throw Exception('ACP protocol error: $e');
    }
  }

  /// Get or create an ACP connection for a given agent.
  Future<ACPAgentConnection> _getOrCreateACPConnection(RemoteAgent agent) async {
    var connection = _acpConnections[agent.id];

    if (connection != null && connection.isConnected) {
      return connection;
    }

    // Create new connection
    connection = ACPAgentConnection(agentId: agent.id);
    _acpConnections[agent.id] = connection;

    // 监听连接状态变化，实时更新 Agent 在线/离线状态
    connection.onConnectionStateChanged = (bool connected) {
      if (!connected) {
        _databaseService.updateRemoteAgentStatus(agent.id, 'offline').catchError((_) {});
        _acpConnections.remove(agent.id);
        print('[ChatService] ACP connection offline: ${agent.name}');
      }
    };

    // Build the WebSocket URL
    String wsUrl;
    if (agent.endpoint.startsWith('ws://') || agent.endpoint.startsWith('wss://')) {
      wsUrl = agent.endpoint;
    } else {
      // Convert http(s) to ws(s)
      wsUrl = agent.endpoint
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      if (!wsUrl.contains('/acp/ws')) {
        wsUrl = wsUrl.endsWith('/') ? '${wsUrl}acp/ws' : '$wsUrl/acp/ws';
      }
    }

    await connection.connect(wsUrl, agent.token);
    return connection;
  }

  /// Clear all UI callbacks from an ACP connection.
  void _clearACPCallbacks(ACPAgentConnection connection) {
    connection.onTextContent = null;
    connection.onActionConfirmation = null;
    connection.onSingleSelect = null;
    connection.onMultiSelect = null;
    connection.onFileUpload = null;
    connection.onForm = null;
    connection.onFileMessage = null;
    connection.onMessageMetadata = null;
    connection.onRequestHistory = null;
    connection.onTaskStarted = null;
    connection.onTaskCompleted = null;
    connection.onTaskError = null;
    connection.onFileChunk = null;
    connection.onFileTransferComplete = null;
    connection.onFileTransferError = null;
  }

  /// Get the active ACP connection for a given agent ID, or null.
  ACPAgentConnection? getACPConnection(String agentId) {
    final conn = _acpConnections[agentId];
    return (conn != null && conn.isConnected) ? conn : null;
  }

  /// Send message via generic HTTP protocol
  Future<Message?> _sendViaGenericProtocol(Message userMessage, RemoteAgent agent) async {
    try {
      // This is a placeholder for custom protocol implementations
      // For now, return a simple response
      return Message(
        id: _uuid.v4(),
        content: 'Received your message: ${userMessage.content}',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        from: MessageFrom(
          id: agent.id,
          type: 'agent',
          name: agent.name,
        ),
        to: MessageFrom(
          id: userMessage.from.id,
          type: 'user',
          name: userMessage.from.name,
        ),
        type: MessageType.text,
        replyTo: userMessage.id,
      );
    } catch (e) {
      throw Exception('Generic protocol error: $e');
    }
  }

  /// Send message via local LLM API (no WebSocket, no endpoint required).
  ///
  /// Supports multi-round tool calling: when the LLM invokes OS tools, we
  /// execute them (with confirmation for high-risk ops), feed results back,
  /// and let the LLM continue reasoning until it produces a final text reply
  /// or invokes a UI tool (which is fire-and-forget, ending the loop).
  Future<Message?> _sendViaLocalLLM({
    required String content,
    required RemoteAgent agent,
    required String userId,
    required String userName,
    String? channelId,
    String? replyToId,
    void Function(String chunk)? onStreamChunk,
    void Function(Map<String, dynamic>)? onActionConfirmation,
    void Function(Map<String, dynamic>)? onSingleSelect,
    void Function(Map<String, dynamic>)? onMultiSelect,
    void Function(Map<String, dynamic>)? onFileUpload,
    void Function(Map<String, dynamic>)? onForm,
    Future<void> Function(Map<String, dynamic>)? onFileMessage,
    void Function(Map<String, dynamic>)? onMessageMetadata,
    Future<bool> Function(String, Map<String, dynamic>, os_exec.RiskLevel)? onOsToolConfirmation,
    ACPCancellationToken? acpCancellationToken,
    List<AttachmentData>? attachments,
    Message? existingUserMessage,
  }) async {
    print('🏠 [LocalLLM] Starting local LLM chat');

    // Create and save user message (skip if pre-existing attachment message provided)
    Message userMessage;
    if (existingUserMessage != null) {
      userMessage = existingUserMessage;
      print('📝 [LocalLLM] Using existing user message: ${userMessage.id}');
    } else {
      userMessage = Message(
        id: _uuid.v4(),
        content: content,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        from: MessageFrom(id: userId, type: 'user', name: userName),
        to: MessageFrom(id: agent.id, type: 'agent', name: agent.name),
        type: MessageType.text,
        replyTo: replyToId,
      );
      await _saveMessageToChannel(userMessage, agent.id, channelId: channelId);
      print('💾 [LocalLLM] User message saved');
    }

    // Create ActiveTask for background tracking
    final effectiveChannelId = channelId ?? '';
    final activeTask = ActiveTask(
      taskId: _uuid.v4(),
      agentId: agent.id,
      agentName: agent.name,
      channelId: effectiveChannelId,
      userMessageId: userMessage.id,
      userId: userId,
      userName: userName,
    );
    activeTask.onStreamChunk = onStreamChunk;
    activeTask.onActionConfirmation = onActionConfirmation;
    activeTask.onSingleSelect = onSingleSelect;
    activeTask.onMultiSelect = onMultiSelect;
    activeTask.onFileUpload = onFileUpload;
    activeTask.onForm = onForm;
    activeTask.onFileMessage = onFileMessage;
    activeTask.onMessageMetadata = onMessageMetadata;
    activeTask.onOsToolConfirmation = onOsToolConfirmation;

    if (effectiveChannelId.isNotEmpty) {
      _activeTasks[effectiveChannelId] = activeTask;
      _updateTypingAgentIds();
    }

    try {
      // Determine provider type for message format
      final providerType = agent.metadata['llm_provider'] as String? ?? 'openai';
      final isClaude = providerType == 'claude';

      // Determine enabled OS tools
      final enabledOsTools = agent.enabledOsTools;
      final hasOsTools = enabledOsTools.isNotEmpty;
      final osRegistry = OsToolRegistry.instance;

      // Determine enabled skills
      final enabledSkills = agent.enabledSkills;
      final hasSkills = enabledSkills.isNotEmpty;
      final skillRegistry = SkillRegistry.instance;

      // Build combined tool list (UI + OS + Skills)
      final List<Map<String, dynamic>> combinedTools;
      if (isClaude) {
        combinedTools = [
          ...UIComponentRegistry.instance.claudeTools(),
          if (hasOsTools) ...osRegistry.claudeTools(enabledTools: enabledOsTools),
          if (hasSkills) ...skillRegistry.claudeTools(enabledSkills: enabledSkills),
        ];
      } else {
        combinedTools = [
          ...UIComponentRegistry.instance.openAITools(),
          if (hasOsTools) ...osRegistry.openAITools(enabledTools: enabledOsTools),
          if (hasSkills) ...skillRegistry.openAITools(enabledSkills: enabledSkills),
        ];
      }

      // Build system prompt
      final baseSystemPrompt = agent.metadata['system_prompt'] as String? ?? '';
      final systemPrompt = '$baseSystemPrompt'
          '${UIComponentRegistry.instance.systemPromptSuffix}'
          '${hasOsTools ? osRegistry.systemPromptSuffix(enabledOsTools) : ''}'
          '${hasSkills ? skillRegistry.systemPromptSuffix(enabledSkills) : ''}';

      // Load history — include attachment messages for context
      final historyLimit = 20;
      final List<Map<String, dynamic>> chatHistory = [];
      if (channelId != null) {
        final messages = await loadChannelMessages(channelId, limit: historyLimit);
        if (messages.isNotEmpty) {
          for (final m in messages) {
            if (m.type != MessageType.system && m.type != MessageType.permissionAudit && m.id != userMessage.id) {
              chatHistory.add(<String, dynamic>{
                'role': m.from.isAgent ? 'assistant' : 'user',
                'content': m.content,
              });
            }
          }
        }
      }

      // Build initial message list
      final List<Map<String, dynamic>> roundMessages = [];
      if (!isClaude && systemPrompt.isNotEmpty) {
        roundMessages.add({'role': 'system', 'content': systemPrompt});
      }
      roundMessages.addAll(chatHistory);
      roundMessages.add(_buildUserMessageContent(
        content, attachments, isClaude,
      ));

      // Hook cancellation token
      acpCancellationToken?.onCancelled = () {
        LocalLLMAgentService.instance.abort();
      };

      // If no OS tools and no skills, fall back to the simpler single-round path
      if (!hasOsTools && !hasSkills) {
        return await _sendViaLocalLLMSingleRound(
          agent: agent,
          content: content,
          userId: userId,
          userName: userName,
          channelId: channelId,
          userMessage: userMessage,
          activeTask: activeTask,
          effectiveChannelId: effectiveChannelId,
          acpCancellationToken: acpCancellationToken,
          attachments: attachments,
        );
      }

      // ======= Multi-round tool calling loop =======
      final infLog = InferenceLogService.instance;
      infLog.beginSession(
        sessionId: activeTask.taskId,
        agentId: agent.id,
        agentName: agent.name,
        channelId: channelId ?? effectiveChannelId,
        provider: agent.metadata['llm_provider'] as String?,
        model: agent.metadata['llm_model'] as String?,
        userMessage: content,
        systemPrompt: systemPrompt,
      );

      final responseBuffer = StringBuffer();
      Map<String, dynamic>? actionConfirmationData;
      Map<String, dynamic>? singleSelectData;
      Map<String, dynamic>? multiSelectData;
      Map<String, dynamic>? fileUploadData;
      Map<String, dynamic>? formDataCapture;
      Map<String, dynamic>? messageMetadataExtra;
      bool fileMessageHandled = false;

      const maxToolRounds = 10;
      bool uiToolEncountered = false;

      for (int round = 0; round < maxToolRounds; round++) {
        if (acpCancellationToken?.isCancelled == true) break;

        infLog.beginRound(requestSummary: 'Round ${round + 1}');

        // Collect events from this round
        final toolCallEvents = <LLMToolCallEvent>[];
        LLMDoneEvent? doneEvent;

        await for (final event in LocalLLMAgentService.instance.chatRound(
          agent: agent,
          messages: roundMessages,
          tools: combinedTools,
          systemPrompt: isClaude ? systemPrompt : null,
        )) {
          if (acpCancellationToken?.isCancelled == true) break;

          switch (event) {
            case LLMTextEvent():
              responseBuffer.write(event.text);
              activeTask.accumulatedContent += event.text;
              activeTask.onStreamChunk?.call(event.text);
              infLog.onTextChunk(event.text);
              break;

            case LLMToolCallEvent():
              toolCallEvents.add(event);
              infLog.onToolCall(id: event.id, name: event.name, arguments: event.arguments);
              break;

            case LLMDoneEvent():
              doneEvent = event;
              infLog.endRound(stopReason: event.stopReason);
              break;
          }
        }

        // If cancelled or no tool calls, we're done
        if (acpCancellationToken?.isCancelled == true) break;
        if (toolCallEvents.isEmpty) break;

        // Separate UI tool calls from OS tool calls and skill tool calls
        final uiToolCalls = <LLMToolCallEvent>[];
        final osToolCalls = <LLMToolCallEvent>[];
        final skillToolCalls = <LLMToolCallEvent>[];
        for (final tc in toolCallEvents) {
          if (_isUiTool(tc.name)) {
            uiToolCalls.add(tc);
          } else if (osRegistry.isOsTool(tc.name)) {
            osToolCalls.add(tc);
          } else if (skillRegistry.isSkillTool(tc.name)) {
            skillToolCalls.add(tc);
          }
        }

        // Handle UI tool calls (fire-and-forget, ends the loop)
        if (uiToolCalls.isNotEmpty) {
          for (final tc in uiToolCalls) {
            _dispatchUiToolCall(
              tc, activeTask,
              actionConfirmationData: actionConfirmationData,
              singleSelectData: singleSelectData,
              multiSelectData: multiSelectData,
              fileUploadData: fileUploadData,
              formDataCapture: formDataCapture,
              messageMetadataExtra: messageMetadataExtra,
              onCaptured: ({
                Map<String, dynamic>? ac,
                Map<String, dynamic>? ss,
                Map<String, dynamic>? ms,
                Map<String, dynamic>? fu,
                Map<String, dynamic>? fd,
                Map<String, dynamic>? mm,
                bool? fmh,
              }) {
                if (ac != null) actionConfirmationData = ac;
                if (ss != null) singleSelectData = ss;
                if (ms != null) multiSelectData = ms;
                if (fu != null) fileUploadData = fu;
                if (fd != null) formDataCapture = fd;
                if (mm != null) messageMetadataExtra = mm;
                if (fmh == true) fileMessageHandled = true;
              },
            );
          }
          uiToolEncountered = true;
          break; // UI tools end the loop
        }

        // Handle OS tool calls and skill tool calls (execute and feed results back)
        final executableToolCalls = [...osToolCalls, ...skillToolCalls];
        if (executableToolCalls.isNotEmpty && doneEvent?.rawAssistantMessage != null) {
          final toolResults = <Map<String, dynamic>>[];

          for (final tc in executableToolCalls) {
            // Check if this is a skill tool call
            if (skillRegistry.isSkillTool(tc.name)) {
              final def = skillRegistry.getDefinition(tc.name);
              final skillName = def?.displayName ?? tc.name;
              activeTask.accumulatedContent += '\n[Loading skill: $skillName]\n';
              activeTask.onStreamChunk?.call('\n[Loading skill: $skillName]\n');
              responseBuffer.write('\n[Loading skill: $skillName]\n');

              final content = await skillRegistry.readSkillContent(tc.name);
              toolResults.add({
                'tool_call_id': tc.id,
                'name': tc.name,
                'result': content,
              });
              infLog.onToolResult(toolCallId: tc.id, name: tc.name, result: content);
              continue;
            }

            // OS tool call — existing risk/confirmation/execution logic
            // Classify risk
            final risk = os_exec.classifyRisk(tc.name, tc.arguments);

            // For high-risk, ask for confirmation
            if (risk == os_exec.RiskLevel.highRisk) {
              final approved = await activeTask.onOsToolConfirmation
                  ?.call(tc.name, tc.arguments, risk) ?? false;
              if (!approved) {
                final deniedResult = jsonEncode({
                    'success': false,
                    'error': 'User denied this operation.',
                  });
                toolResults.add({
                  'tool_call_id': tc.id,
                  'name': tc.name,
                  'result': deniedResult,
                });
                infLog.onToolResult(toolCallId: tc.id, name: tc.name, result: deniedResult);
                continue;
              }
            }

            // Notify user for low-risk operations
            if (risk == os_exec.RiskLevel.lowRisk) {
              final desc = os_exec.getRiskDescription(risk, tc.name, tc.arguments);
              activeTask.accumulatedContent += '\n[Executing: $desc]\n';
              activeTask.onStreamChunk?.call('\n[Executing: $desc]\n');
              responseBuffer.write('\n[Executing: $desc]\n');
            }

            // Execute the tool
            final result = await os_exec.runTool(tc.name, tc.arguments);
            final resultJson = jsonEncode(result);
            toolResults.add({
              'tool_call_id': tc.id,
              'name': tc.name,
              'result': resultJson,
            });
            infLog.onToolResult(toolCallId: tc.id, name: tc.name, result: resultJson);
          }

          // Append assistant message + tool results to message history
          if (isClaude) {
            _appendToolRoundClaude(roundMessages, doneEvent!.rawAssistantMessage!, executableToolCalls, toolResults);
          } else {
            _appendToolRoundOpenAI(roundMessages, doneEvent!.rawAssistantMessage!, executableToolCalls, toolResults);
          }

          // Continue to next round
          continue;
        }

        // No actionable tool calls — done
        break;
      }

      activeTask.isComplete = true;
      activeTask.onTaskFinished?.call();

      final wasCancelled = acpCancellationToken?.isCancelled == true;
      infLog.endSession(wasCancelled ? InferenceStatus.cancelled : InferenceStatus.completed);

      // Build metadata
      Map<String, dynamic>? messageMetadata;
      if (actionConfirmationData != null || singleSelectData != null ||
          multiSelectData != null || fileUploadData != null ||
          formDataCapture != null || messageMetadataExtra != null) {
        final meta = <String, dynamic>{};
        if (messageMetadataExtra != null) meta.addAll(messageMetadataExtra!);
        if (actionConfirmationData != null) meta['action_confirmation'] = actionConfirmationData;
        if (singleSelectData != null) meta['single_select'] = singleSelectData;
        if (multiSelectData != null) meta['multi_select'] = multiSelectData;
        if (fileUploadData != null) meta['file_upload'] = fileUploadData;
        if (formDataCapture != null) meta['form'] = formDataCapture;
        messageMetadata = meta;
      }
      activeTask.metadata = messageMetadata;

      final responseContent = responseBuffer.toString();
      final String displayContent;
      if (wasCancelled) {
        displayContent = responseContent.isNotEmpty
            ? '$responseContent\n\n[Stopped]'
            : '[Stopped]';
      } else if (fileMessageHandled && responseContent.trim().isEmpty) {
        displayContent = '[Used file_message tool]';
      } else {
        displayContent = responseContent.isNotEmpty ? responseContent : 'Task completed';
      }

      final agentResponse = Message(
        id: _uuid.v4(),
        content: displayContent,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        from: MessageFrom(id: agent.id, type: 'agent', name: agent.name),
        to: MessageFrom(id: userId, type: 'user', name: userName),
        type: MessageType.text,
        replyTo: userMessage.id,
        metadata: messageMetadata,
      );

      await _saveMessageToChannel(agentResponse, agent.id, channelId: channelId);
      print('💾 [LocalLLM] Agent response saved');

      if (effectiveChannelId.isNotEmpty) {
        final task = _activeTasks.remove(effectiveChannelId);
        _updateTypingAgentIds();
        if (task != null && !task.dbSaveCompleter.isCompleted) {
          task.dbSaveCompleter.complete();
        }
      }

      return agentResponse;
    } catch (e, stackTrace) {
      print('❌ [LocalLLM] Error: $e');
      print('   - Stack trace: $stackTrace');

      InferenceLogService.instance.endSession(InferenceStatus.error, error: e.toString());

      activeTask.isComplete = true;
      activeTask.errorMessage = e.toString();
      activeTask.onTaskFinished?.call();

      final errorMsg = Message(
        id: _uuid.v4(),
        content: 'Error: Failed to get response from LLM. Details: $e',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        from: MessageFrom(id: 'system', type: 'system', name: 'System'),
        type: MessageType.system,
      );
      await _saveMessageToChannel(errorMsg, agent.id, channelId: channelId);

      if (effectiveChannelId.isNotEmpty) {
        final task = _activeTasks.remove(effectiveChannelId);
        _updateTypingAgentIds();
        if (task != null && !task.dbSaveCompleter.isCompleted) {
          task.dbSaveCompleter.complete();
        }
      }

      return null;
    }
  }

  /// Simple single-round path (no OS tools) — preserves original behavior.
  Future<Message?> _sendViaLocalLLMSingleRound({
    required RemoteAgent agent,
    required String content,
    required String userId,
    required String userName,
    String? channelId,
    required Message userMessage,
    required ActiveTask activeTask,
    required String effectiveChannelId,
    ACPCancellationToken? acpCancellationToken,
    List<AttachmentData>? attachments,
  }) async {
    final historyLimit = 20;
    List<Map<String, String>>? chatHistory;
    if (channelId != null) {
      final messages = await loadChannelMessages(channelId, limit: historyLimit);
      if (messages.isNotEmpty) {
        chatHistory = messages
            .where((m) => m.type != MessageType.system && m.type != MessageType.permissionAudit && m.id != userMessage.id)
            .map((m) => <String, String>{
                  'role': m.from.isAgent ? 'assistant' : 'user',
                  'content': m.content,
                })
            .toList();
      }
    }

    final responseBuffer = StringBuffer();
    final infLog = InferenceLogService.instance;
    infLog.beginSession(
      sessionId: activeTask.taskId,
      agentId: agent.id,
      agentName: agent.name,
      channelId: channelId ?? effectiveChannelId,
      provider: agent.metadata['llm_provider'] as String?,
      model: agent.metadata['llm_model'] as String?,
      userMessage: content,
    );
    infLog.beginRound(requestSummary: 'Single round');

    Map<String, dynamic>? actionConfirmationData;
    Map<String, dynamic>? singleSelectData;
    Map<String, dynamic>? multiSelectData;
    Map<String, dynamic>? fileUploadData;
    Map<String, dynamic>? formDataCapture;
    Map<String, dynamic>? messageMetadataExtra;
    bool fileMessageHandled = false;

    await for (final event
        in LocalLLMAgentService.instance.chat(
          agent: agent,
          message: content,
          history: chatHistory,
          attachments: attachments,
        )) {
      if (acpCancellationToken?.isCancelled == true) break;

      switch (event) {
        case LLMTextEvent():
          responseBuffer.write(event.text);
          activeTask.accumulatedContent += event.text;
          activeTask.onStreamChunk?.call(event.text);
          infLog.onTextChunk(event.text);
          break;

        case LLMToolCallEvent():
          infLog.onToolCall(id: event.id, name: event.name, arguments: event.arguments);
          final args = event.arguments;
          switch (event.name) {
            case 'action_confirmation':
              actionConfirmationData = Map<String, dynamic>.from(args);
              activeTask.onActionConfirmation?.call(args);
              break;
            case 'single_select':
              singleSelectData = Map<String, dynamic>.from(args);
              activeTask.onSingleSelect?.call(args);
              break;
            case 'multi_select':
              multiSelectData = Map<String, dynamic>.from(args);
              activeTask.onMultiSelect?.call(args);
              break;
            case 'file_upload':
              fileUploadData = Map<String, dynamic>.from(args);
              activeTask.onFileUpload?.call(args);
              break;
            case 'form':
              formDataCapture = Map<String, dynamic>.from(args);
              activeTask.onForm?.call(args);
              break;
            case 'file_message':
              fileMessageHandled = true;
              await activeTask.onFileMessage?.call(args);
              break;
            case 'message_metadata':
              messageMetadataExtra = Map<String, dynamic>.from(args);
              activeTask.onMessageMetadata?.call(args);
              break;
          }
          break;

        case LLMDoneEvent():
          infLog.endRound(stopReason: event.stopReason);
          break;
      }
    }

    final wasCancelledSR = acpCancellationToken?.isCancelled == true;
    infLog.endSession(wasCancelledSR ? InferenceStatus.cancelled : InferenceStatus.completed);

    activeTask.isComplete = true;
    activeTask.onTaskFinished?.call();

    final wasCancelled = acpCancellationToken?.isCancelled == true;

    Map<String, dynamic>? messageMetadata;
    if (actionConfirmationData != null || singleSelectData != null ||
        multiSelectData != null || fileUploadData != null ||
        formDataCapture != null || messageMetadataExtra != null) {
      final meta = <String, dynamic>{};
      if (messageMetadataExtra != null) meta.addAll(messageMetadataExtra!);
      if (actionConfirmationData != null) meta['action_confirmation'] = actionConfirmationData;
      if (singleSelectData != null) meta['single_select'] = singleSelectData;
      if (multiSelectData != null) meta['multi_select'] = multiSelectData;
      if (fileUploadData != null) meta['file_upload'] = fileUploadData;
      if (formDataCapture != null) meta['form'] = formDataCapture;
      messageMetadata = meta;
    }
    activeTask.metadata = messageMetadata;

    final responseContent = responseBuffer.toString();
    final String displayContent;
    if (wasCancelled) {
      displayContent = responseContent.isNotEmpty
          ? '$responseContent\n\n[Stopped]'
          : '[Stopped]';
    } else if (fileMessageHandled && responseContent.trim().isEmpty) {
      displayContent = '[Used file_message tool]';
    } else {
      displayContent = responseContent.isNotEmpty ? responseContent : 'Task completed';
    }

    final agentResponse = Message(
      id: _uuid.v4(),
      content: displayContent,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      from: MessageFrom(id: agent.id, type: 'agent', name: agent.name),
      to: MessageFrom(id: userId, type: 'user', name: userName),
      type: MessageType.text,
      replyTo: userMessage.id,
      metadata: messageMetadata,
    );

    await _saveMessageToChannel(agentResponse, agent.id, channelId: channelId);
    print('💾 [LocalLLM] Agent response saved');

    if (effectiveChannelId.isNotEmpty) {
      final task = _activeTasks.remove(effectiveChannelId);
      _updateTypingAgentIds();
      if (task != null && !task.dbSaveCompleter.isCompleted) {
        task.dbSaveCompleter.complete();
      }
    }

    return agentResponse;
  }

  // ---------------------------------------------------------------------------
  // Multi-round helpers
  // ---------------------------------------------------------------------------

  /// Build a user message map, potentially with multimodal content for
  /// image attachments (used in multi-round tool calling path).
  Map<String, dynamic> _buildUserMessageContent(
    String text,
    List<AttachmentData>? attachments,
    bool isClaude,
  ) {
    if (attachments == null || attachments.isEmpty) {
      return {'role': 'user', 'content': text};
    }

    final imageAttachments = attachments.where((a) => a.isImage && !a.exceedsSizeLimit).toList();
    final nonImageAttachments = attachments.where((a) => !a.isImage).toList();

    // Prepend non-image attachment descriptions to the text
    String effectiveText = text;
    if (nonImageAttachments.isNotEmpty) {
      final descriptions = nonImageAttachments.map((a) => a.textDescription).join('\n');
      effectiveText = '$descriptions\n\n$effectiveText';
    }

    if (imageAttachments.isEmpty) {
      return {'role': 'user', 'content': effectiveText};
    }

    if (isClaude) {
      // Claude multimodal format
      final contentParts = <Map<String, dynamic>>[
        for (final img in imageAttachments)
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': img.mimeType,
              'data': img.base64Data,
            },
          },
        {'type': 'text', 'text': effectiveText},
      ];
      return {'role': 'user', 'content': contentParts};
    } else {
      // OpenAI Vision format
      final contentParts = <Map<String, dynamic>>[
        {'type': 'text', 'text': effectiveText},
        for (final img in imageAttachments)
          {
            'type': 'image_url',
            'image_url': {'url': 'data:${img.mimeType};base64,${img.base64Data}'},
          },
      ];
      return {'role': 'user', 'content': contentParts};
    }
  }

  /// Known UI tool names.
  static const _uiToolNames = {
    'action_confirmation', 'single_select', 'multi_select',
    'file_upload', 'form', 'file_message', 'message_metadata',
  };

  bool _isUiTool(String name) => _uiToolNames.contains(name);

  /// Dispatch a UI tool call to the appropriate callback.
  void _dispatchUiToolCall(
    LLMToolCallEvent tc,
    ActiveTask activeTask, {
    Map<String, dynamic>? actionConfirmationData,
    Map<String, dynamic>? singleSelectData,
    Map<String, dynamic>? multiSelectData,
    Map<String, dynamic>? fileUploadData,
    Map<String, dynamic>? formDataCapture,
    Map<String, dynamic>? messageMetadataExtra,
    required void Function({
      Map<String, dynamic>? ac,
      Map<String, dynamic>? ss,
      Map<String, dynamic>? ms,
      Map<String, dynamic>? fu,
      Map<String, dynamic>? fd,
      Map<String, dynamic>? mm,
      bool? fmh,
    }) onCaptured,
  }) {
    final args = tc.arguments;
    switch (tc.name) {
      case 'action_confirmation':
        onCaptured(ac: Map<String, dynamic>.from(args));
        activeTask.onActionConfirmation?.call(args);
        break;
      case 'single_select':
        onCaptured(ss: Map<String, dynamic>.from(args));
        activeTask.onSingleSelect?.call(args);
        break;
      case 'multi_select':
        onCaptured(ms: Map<String, dynamic>.from(args));
        activeTask.onMultiSelect?.call(args);
        break;
      case 'file_upload':
        onCaptured(fu: Map<String, dynamic>.from(args));
        activeTask.onFileUpload?.call(args);
        break;
      case 'form':
        onCaptured(fd: Map<String, dynamic>.from(args));
        activeTask.onForm?.call(args);
        break;
      case 'file_message':
        onCaptured(fmh: true);
        activeTask.onFileMessage?.call(args);
        break;
      case 'message_metadata':
        onCaptured(mm: Map<String, dynamic>.from(args));
        activeTask.onMessageMetadata?.call(args);
        break;
    }
  }

  /// Append a tool round to the message history for OpenAI-compatible APIs.
  void _appendToolRoundOpenAI(
    List<Map<String, dynamic>> messages,
    Map<String, dynamic> rawAssistantMsg,
    List<LLMToolCallEvent> toolCalls,
    List<Map<String, dynamic>> toolResults,
  ) {
    // Append the assistant message (with tool_calls)
    messages.add(rawAssistantMsg);

    // Append tool result messages
    for (final result in toolResults) {
      messages.add({
        'role': 'tool',
        'tool_call_id': result['tool_call_id'],
        'content': result['result'] as String,
      });
    }
  }

  /// Append a tool round to the message history for Claude (Anthropic) API.
  void _appendToolRoundClaude(
    List<Map<String, dynamic>> messages,
    Map<String, dynamic> rawAssistantMsg,
    List<LLMToolCallEvent> toolCalls,
    List<Map<String, dynamic>> toolResults,
  ) {
    // Append the assistant message (with content blocks)
    messages.add(rawAssistantMsg);

    // Append user message with tool_result blocks
    final toolResultBlocks = <Map<String, dynamic>>[];
    for (final result in toolResults) {
      toolResultBlocks.add({
        'type': 'tool_result',
        'tool_use_id': result['tool_call_id'],
        'content': result['result'] as String,
      });
    }
    messages.add({
      'role': 'user',
      'content': toolResultBlocks,
    });
  }

  /// Send additional history to agent as a supplement after REQUEST_HISTORY.
  /// Returns the agent's re-answer message, or null if no more history is
  /// available.  The caller receives `actualSentCount` via the returned
  /// [HistorySupplementResult] so it can update its offset correctly.
  Future<HistorySupplementResult?> sendHistorySupplement({
    required RemoteAgent agent,
    required String sessionId,
    required String requestId,
    required String originalQuestion,
    required int offset,
    required int batchSize,
    void Function(String chunk)? onStreamChunk,
    void Function(Map<String, dynamic>)? onRequestHistory,
    ACPCancellationToken? acpCancellationToken,
  }) async {
    // 1. Load ALL messages from DB so we can slice correctly.
    //    `offset` = number of most-recent messages already sent to agent.
    //    We want the `batchSize` messages right before those.
    final allMessages = await loadChannelMessages(sessionId, limit: offset + batchSize);
    // allMessages is sorted by time ascending
    final total = allMessages.length;

    // Already-sent region: the last `offset` messages (may be fewer if total < offset)
    final sentStart = (total - offset).clamp(0, total);
    // New region: up to `batchSize` messages before the already-sent ones
    final newStart = (sentStart - batchSize).clamp(0, total);
    final newEnd = sentStart;

    if (newStart >= newEnd) return null; // no more history

    final additionalMessages = allMessages.sublist(newStart, newEnd);
    final chatHistory = additionalMessages
        .where((m) => m.type == MessageType.text)
        .map((m) {
          return {
            'role': m.from.isAgent ? 'assistant' : 'user',
            'content': m.content,
          };
        })
        .toList();

    if (chatHistory.isEmpty) return null;

    return await _sendHistorySupplementViaACP(
      agent: agent,
      sessionId: sessionId,
      chatHistory: chatHistory,
      originalQuestion: originalQuestion,
      offset: offset,
      onStreamChunk: onStreamChunk,
      onRequestHistory: onRequestHistory,
      acpCancellationToken: acpCancellationToken,
    );
  }

  /// Send history supplement via ACP WebSocket protocol.
  Future<HistorySupplementResult?> _sendHistorySupplementViaACP({
    required RemoteAgent agent,
    required String sessionId,
    required List<Map<String, String>> chatHistory,
    required String originalQuestion,
    required int offset,
    void Function(String chunk)? onStreamChunk,
    void Function(Map<String, dynamic>)? onRequestHistory,
    ACPCancellationToken? acpCancellationToken,
  }) async {
    final connection = await _getOrCreateACPConnection(agent);
    final taskId = _uuid.v4();
    acpCancellationToken?.bind(connection, taskId);

    final taskCompleter = Completer<void>();
    String responseContent = '';
    Map<String, dynamic>? capturedHistoryRequest;

    // Hook cancellation token so the completer resolves immediately on cancel.
    acpCancellationToken?.onCancelled = () {
      if (!taskCompleter.isCompleted) {
        taskCompleter.complete();
      }
    };

    connection.onTextContent = (data) {
      final content = data['content'] as String? ?? '';
      responseContent += content;
      onStreamChunk?.call(content);
    };

    connection.onRequestHistory = (data) {
      capturedHistoryRequest = Map<String, dynamic>.from(data);
      onRequestHistory?.call(data);
    };

    connection.onTaskCompleted = (data) {
      if (!taskCompleter.isCompleted) taskCompleter.complete();
    };

    connection.onTaskError = (data) {
      if (!taskCompleter.isCompleted) {
        taskCompleter.completeError(Exception(data['message'] ?? 'Task error'));
      }
    };

    await connection.sendChatMessage(
      taskId: taskId,
      sessionId: sessionId,
      message: '[HISTORY_SUPPLEMENT]',
      userId: '',
      messageId: _uuid.v4(),
      historySupplement: true,
      additionalHistory: chatHistory,
      originalQuestion: originalQuestion,
    );

    await taskCompleter.future.timeout(const Duration(seconds: 300));

    _clearACPCallbacks(connection);

    // If cancelled, return partial content immediately.
    if (acpCancellationToken?.isCancelled == true) {
      final responseMessage = Message(
        id: _uuid.v4(),
        content: responseContent.isNotEmpty ? responseContent : '[Stopped]',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        from: MessageFrom(id: agent.id, type: 'agent', name: agent.name),
        type: MessageType.text,
      );
      if (responseContent.isNotEmpty) {
        await _saveMessageToChannel(responseMessage, agent.id, channelId: sessionId);
      }
      return HistorySupplementResult(
        message: responseMessage,
        actualSentCount: chatHistory.length,
      );
    }

    // If the agent's entire response was a request_history directive (no text),
    // don't save a meaningless placeholder message.
    if (responseContent.isEmpty && capturedHistoryRequest != null) {
      return HistorySupplementResult(
        message: Message(
          id: _uuid.v4(),
          content: '',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          from: MessageFrom(id: agent.id, type: 'agent', name: agent.name),
          type: MessageType.text,
        ),
        actualSentCount: chatHistory.length,
        pendingHistoryRequest: capturedHistoryRequest,
      );
    }

    final responseMessage = Message(
      id: _uuid.v4(),
      content: responseContent.isNotEmpty ? responseContent : 'Task completed',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      from: MessageFrom(id: agent.id, type: 'agent', name: agent.name),
      type: MessageType.text,
    );

    await _saveMessageToChannel(responseMessage, agent.id, channelId: sessionId);

    return HistorySupplementResult(
      message: responseMessage,
      actualSentCount: chatHistory.length,
      pendingHistoryRequest: capturedHistoryRequest,
    );
  }

  /// Submit action confirmation response
  /// Updates the original message's metadata and sends a new request to the agent.
  /// When confirmationContext is "mac_tool", the response is sent via
  /// connection.submitResponse() (in-band) rather than creating a new chat message.
  Future<Message?> submitActionConfirmationResponse({
    required Message originalMessage,
    required String confirmationId,
    required String selectedActionId,
    required String selectedActionLabel,
    required RemoteAgent agent,
    required String userId,
    required String userName,
    String? channelId,
    String? confirmationContext,
    void Function(String chunk)? onStreamChunk,
    ACPCancellationToken? acpCancellationToken,
  }) async {
    print('🔘 [ChatService] Submitting action confirmation response');
    print('   - Confirmation ID: $confirmationId');
    print('   - Selected Action: $selectedActionId ($selectedActionLabel)');
    print('   - Confirmation Context: $confirmationContext');

    // Update original message's metadata in DB
    final updatedMetadata = Map<String, dynamic>.from(originalMessage.metadata ?? {});
    final actionConfirmation = Map<String, dynamic>.from(
      updatedMetadata['action_confirmation'] as Map<String, dynamic>? ?? {},
    );
    actionConfirmation['selected_action_id'] = selectedActionId;
    actionConfirmation['selected_at'] = DateTime.now().millisecondsSinceEpoch;
    updatedMetadata['action_confirmation'] = actionConfirmation;

    await _databaseService.updateMessage(
      messageId: originalMessage.id,
      content: originalMessage.content,
      metadata: updatedMetadata,
    );

    // mac_tool confirmations: send in-band via submitResponse (no new chat message)
    if (confirmationContext == 'mac_tool') {
      final connection = _acpConnections[agent.id];
      if (connection != null && connection.isConnected) {
        final activeTask = getActiveTask(channelId ?? '');
        final taskId = activeTask?.taskId ?? '';
        await connection.submitResponse(
          taskId: taskId,
          responseType: 'action_confirmation',
          responseData: {
            'confirmation_id': confirmationId,
            'selected_action_id': selectedActionId,
            'selected_action_label': selectedActionLabel,
          },
        );
        print('🔘 [ChatService] Sent mac_tool confirmation via submitResponse');
        return null; // No new message created for in-band confirmations
      }
    }

    // Default path: send the selection as a new message to the agent
    return await sendMessageToAgent(
      content: 'Selected action: $selectedActionLabel',
      agent: agent,
      userId: userId,
      userName: userName,
      channelId: channelId,
      onStreamChunk: onStreamChunk,
      acpCancellationToken: acpCancellationToken,
    );
  }

  /// Submit single-select or multi-select response
  /// Updates the original message's metadata in DB and sends a new request to the agent
  Future<Message?> submitSelectResponse({
    required Message originalMessage,
    required String metadataKey,
    required Map<String, dynamic> selectedData,
    required String responseText,
    required RemoteAgent agent,
    required String userId,
    required String userName,
    String? channelId,
    void Function(String chunk)? onStreamChunk,
    ACPCancellationToken? acpCancellationToken,
  }) async {
    print('🔘 [ChatService] Submitting select response ($metadataKey)');
    print('   - Response text: $responseText');

    // Update original message's metadata in DB
    final updatedMetadata = Map<String, dynamic>.from(originalMessage.metadata ?? {});
    final selectMeta = Map<String, dynamic>.from(
      updatedMetadata[metadataKey] as Map<String, dynamic>? ?? {},
    );
    selectMeta.addAll(selectedData);
    selectMeta['selected_at'] = DateTime.now().millisecondsSinceEpoch;
    updatedMetadata[metadataKey] = selectMeta;

    await _databaseService.updateMessage(
      messageId: originalMessage.id,
      content: originalMessage.content,
      metadata: updatedMetadata,
    );

    // Send the selection as a new message to the agent
    return await sendMessageToAgent(
      content: responseText,
      agent: agent,
      userId: userId,
      userName: userName,
      channelId: channelId,
      onStreamChunk: onStreamChunk,
      acpCancellationToken: acpCancellationToken,
    );
  }

  /// Save message to agent channel.
  ///
  /// [channelId] should always be provided to ensure messages are saved to the
  /// correct session. The deterministic fallback is only used as a last resort
  /// for backward compatibility.
  Future<void> _saveMessageToChannel(Message message, String agentId, {String? channelId}) async {
    // Use provided channelId; fall back to the active session for this
    // user-agent pair so we don't accidentally save into the wrong session.
    final effectiveChannelId = channelId ?? await (() async {
      final otherPartyId = message.from.id == agentId ? (message.to?.id ?? message.from.id) : message.from.id;
      // Prefer the most recently active session over the deterministic channel
      final activeChannel = await getLatestActiveChannelId(otherPartyId, agentId);
      if (activeChannel != null) return activeChannel;
      return generateChannelId(otherPartyId, agentId);
    })();

    // Check if channel exists
    final existingChannel = await _databaseService.getChannelById(effectiveChannelId);

    if (existingChannel == null) {
      // Create channel if it doesn't exist
      final channel = Channel.withMemberIds(
        id: effectiveChannelId,
        name: 'Chat with ${message.from.type == 'user' ? agentId : message.from.name}',
        type: 'dm',
        memberIds: [message.from.id, agentId],
        isPrivate: true,
      );
      await _databaseService.createChannel(channel, message.from.id);
    }

    // Save message to database
    await _databaseService.createMessage(
      id: message.id,
      channelId: effectiveChannelId,
      senderId: message.from.id,
      senderType: message.from.type,
      senderName: message.from.name,
      content: message.content,
      messageType: message.type.toString().split('.').last,
      replyToId: message.replyTo,
      metadata: message.metadata,
    );

    // Update channel's updated_at so HomeScreen shows the correct active session
    await _databaseService.touchChannelUpdatedAt(effectiveChannelId);

    // 用户自己发送的消息直接标记为已读
    if (message.from.type == 'user') {
      await _databaseService.markMessageAsRead(message.id);
    }

    // Notify listeners
    _notifyChannelUpdate(effectiveChannelId);

    // Fire a local notification for non-user messages
    if (message.from.type != 'user') {
      _maybeShowNotification(
        channelId: effectiveChannelId,
        senderId: message.from.id,
        senderName: message.from.name,
        content: message.content,
      );
    }
  }

  /// Load message history for an agent.
  /// Uses the most recently active session instead of a deterministic channel
  /// to ensure messages from different sessions stay isolated.
  Future<List<Message>> loadMessageHistory({
    required String agentId,
    required String userId,
    int limit = 100,
  }) async {
    final activeChannelId = await getLatestActiveChannelId(userId, agentId);
    final channelId = activeChannelId ?? generateChannelId(userId, agentId);
    return await loadChannelMessages(channelId, limit: limit);
  }

  /// Load messages from a channel
  Future<List<Message>> loadChannelMessages(String channelId, {int limit = 100}) async {
    final messageMaps = await _databaseService.getChannelMessages(channelId, limit: limit);
    
    return messageMaps.map((map) {
      Map<String, dynamic>? metadata;
      if (map['metadata'] != null) {
        try {
          metadata = Map<String, dynamic>.from(jsonDecode(map['metadata'] as String));
        } catch (_) {}
      }

      return Message(
        id: map['id'] as String,
        from: MessageFrom(
          id: map['sender_id'] as String,
          type: map['sender_type'] as String,
          name: map['sender_name'] as String,
        ),
        channelId: channelId,
        type: _parseMessageType(map['message_type'] as String),
        content: map['content'] as String,
        timestampMs: DateTime.parse(map['created_at'] as String).millisecondsSinceEpoch,
        replyTo: map['reply_to_id'] as String?,
        metadata: metadata,
      );
    }).toList()
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
  }

  /// Get channel ID for user-agent conversation
  String generateChannelId(String userId, String agentId) {
    final ids = [userId, agentId]..sort();
    return 'dm_${ids.join('_')}';
  }

  /// Parse message type from string
  MessageType _parseMessageType(String type) {
    switch (type.toLowerCase()) {
      case 'image':
        return MessageType.image;
      case 'file':
        return MessageType.file;
      case 'audio':
        return MessageType.audio;
      case 'system':
        return MessageType.system;
      case 'permission_audit':
        return MessageType.permissionAudit;
      default:
        return MessageType.text;
    }
  }

  /// Notify channel update
  void _notifyChannelUpdate(String channelId) {
    _messageControllers[channelId]?.add([]);
  }

  /// Show a local notification if conditions are met.
  void _maybeShowNotification({
    required String channelId,
    required String senderId,
    required String senderName,
    required String content,
  }) {
    final provider = _notificationProvider;
    if (provider == null) return;
    if (!provider.shouldNotify(senderId)) return;
    if (AppLifecycleService().shouldSuppressNotification(channelId)) return;

    final body = provider.showPreview ? content : 'New message';
    NotificationService().showNotification(
      id: channelId.hashCode,
      title: senderName,
      body: body,
      playSound: provider.soundEnabled,
    );
  }

  /// Delete chat history for an agent.
  /// Deletes the most recently active session, not just the deterministic channel.
  Future<void> deleteChatHistory({
    required String agentId,
    required String userId,
  }) async {
    final activeChannelId = await getLatestActiveChannelId(userId, agentId);
    final channelId = activeChannelId ?? generateChannelId(userId, agentId);
    // Delete channel (cascades to delete messages)
    await _databaseService.deleteChannel(channelId);
    InferenceLogService.instance.removeByChannel(channelId);
  }

  /// Rollback from a specific message: delete it and all subsequent messages,
  /// then notify the remote agent.
  Future<void> rollbackFromMessage({
    required String messageId,
    required String channelId,
    required RemoteAgent agent,
  }) async {
    // 1. Look up the message's created_at
    final createdAt = await _databaseService.getMessageCreatedAt(messageId);
    if (createdAt == null) {
      throw Exception('Message not found: $messageId');
    }

    // 2. Delete that message and all subsequent messages in the channel
    await _databaseService.deleteMessagesFromTimestamp(channelId, createdAt);

    // 3. Send rollback notification to the remote agent (fire-and-forget)
    final connection = _acpConnections[agent.id];
    if (connection != null && connection.isConnected) {
      connection.rollback(
        sessionId: channelId,
        messageId: messageId,
      ).catchError((_) => ACPResponse(jsonrpc: '2.0', id: 0));
    }

    // Notify listeners
    _notifyChannelUpdate(channelId);
  }

  /// Delete a single message
  Future<void> deleteMessage(String messageId) async {
    try {
      await _databaseService.deleteMessage(messageId);
    } catch (e) {
      debugPrint('Error deleting message: $e');
      rethrow;
    }
  }

  /// Create a new session (channel) for user-agent conversation
  Future<String> createNewSession({
    required String userId,
    required String userName,
    required String agentId,
    required String agentName,
  }) async {
    final ids = [userId, agentId]..sort();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final channelId = 'dm_${ids.join('_')}_$timestamp';

    final channel = Channel.withMemberIds(
      id: channelId,
      name: 'Chat with $agentName',
      type: 'dm',
      memberIds: [userId, agentId],
      isPrivate: true,
    );
    await _databaseService.createChannel(channel, userId);
    return channelId;
  }

  /// Get the most recently active channel ID for a user-agent pair
  Future<String?> getLatestActiveChannelId(String userId, String agentId) async {
    return await _databaseService.getLatestActiveChannelForUserAndAgent(userId, agentId);
  }

  /// Get all sessions (channels) for a specific agent
  Future<List<Channel>> getAgentSessions({required String agentId}) async {
    return await _databaseService.getChannelsForAgent(agentId);
  }

  /// Get a single message by ID, converted to Message object
  Future<Message?> getMessageById(String messageId) async {
    final map = await _databaseService.getMessageById(messageId);
    if (map == null) return null;

    Map<String, dynamic>? metadata;
    if (map['metadata'] != null) {
      try {
        metadata = Map<String, dynamic>.from(jsonDecode(map['metadata'] as String));
      } catch (_) {}
    }

    return Message(
      id: map['id'] as String,
      from: MessageFrom(
        id: map['sender_id'] as String,
        type: map['sender_type'] as String,
        name: map['sender_name'] as String,
      ),
      channelId: map['channel_id'] as String?,
      type: _parseMessageType(map['message_type'] as String),
      content: map['content'] as String,
      timestampMs: DateTime.parse(map['created_at'] as String).millisecondsSinceEpoch,
      replyTo: map['reply_to_id'] as String?,
      metadata: metadata,
    );
  }

  /// Build a group-aware system prompt for a specific agent in a group chat.
  String _buildGroupSystemPrompt({
    required String groupName,
    required String groupDescription,
    required List<RemoteAgent> allAgents,
    required RemoteAgent currentAgent,
    List<ChannelMember> channelMembers = const [],
    bool isMentioned = false,
    bool isAdmin = false,
    String? customSystemPrompt,
  }) {
    final memberList = allAgents.map((a) {
      // Use group-specific bio if set, otherwise fall back to agent's own bio
      final channelMember = channelMembers.where((m) => m.id == a.id).firstOrNull;
      final groupBio = channelMember?.groupBio;
      final bio = groupBio ?? a.bio ?? '';
      final statusText = a.isOnline ? '在线' : '离线';
      final capabilitiesText = a.capabilities.isNotEmpty
          ? a.capabilities.join(', ')
          : '未指定';
      final systemPrompt = a.metadata['system_prompt'] as String? ?? '';
      final specialtyText = systemPrompt.isNotEmpty
          ? (systemPrompt.length > 200 ? '${systemPrompt.substring(0, 200)}...' : systemPrompt)
          : '未指定';

      return '- ${a.name} ($statusText)\n'
          '  描述: ${bio.isNotEmpty ? bio : '无'}\n'
          '  能力: $capabilitiesText\n'
          '  专长: $specialtyText';
    }).join('\n');

    final agentSystemPrompt = currentAgent.metadata['system_prompt'] as String? ?? '';
    // For the current agent's identity line, also prefer group bio
    final currentMember = channelMembers.where((m) => m.id == currentAgent.id).firstOrNull;
    final currentGroupBio = currentMember?.groupBio;
    final agentIdentity = currentGroupBio ?? (agentSystemPrompt.isNotEmpty ? agentSystemPrompt : (currentAgent.bio ?? ''));

    if (isAdmin) {
      final customPromptSection = (customSystemPrompt != null && customSystemPrompt.isNotEmpty)
          ? '\n\n【用户自定义约束】\n$customSystemPrompt'
          : '';

      return '''你当前处于一个群聊环境中，你是本群的**管理员/协调者**。

【群聊名称】$groupName
【群聊描述】${groupDescription.isNotEmpty ? groupDescription : '通用讨论'}
【成员数量】${allAgents.length}

【群成员列表】
$memberList

【你的身份】你是 ${currentAgent.name}（管理员）。$agentIdentity$customPromptSection

【行为准则 - 管理员】
1. 你是群聊的协调者，用户的每条消息都会首先由你处理
2. 仔细分析用户的需求，判断是否需要委派给其他成员
3. 如果需要其他成员协助，请在回复中使用 @成员名 来委派任务（例如：@AgentName 请帮忙处理...）
4. 使用 @all 可以通知所有成员
5. 你可以自己直接回答用户的问题，也可以在回答后委派部分任务给其他成员
6. 保持简洁高效，做好任务分配和协调工作
7. 直接回复内容即可，不要在回复前加上你的名字前缀（如"[${currentAgent.name}]: "），系统会自动显示你的身份
8. 当任务之间有依赖关系时（如先开发再部署），请使用【步骤N】语法来编排顺序执行，例如：【步骤1】@开发者 请完成开发 【步骤2】@运维 请部署上线
9. 当任务之间没有依赖关系时，直接使用 @成员名 进行并行委派即可，效率更高
10. 当子Agent在执行任务时需要确认或选择（如操作确认、选项选择），系统会自动询问你来代替用户做决策。请根据上下文做出合理判断，如果不确定请回复 [ASK_USER]''';
    }

    final mentionNotice = isMentioned
        ? '\n\n【注意】你被 @提到了，请务必回复，不要回复 [SKIP]'
        : '';

    final customPromptSection = (customSystemPrompt != null && customSystemPrompt.isNotEmpty)
        ? '\n\n【用户自定义约束】\n$customSystemPrompt'
        : '';

    return '''你当前处于一个群聊环境中。

【群聊名称】$groupName
【群聊描述】${groupDescription.isNotEmpty ? groupDescription : '通用讨论'}
【成员数量】${allAgents.length}

【群成员列表】
$memberList

【你的身份】你是 ${currentAgent.name}。$agentIdentity$customPromptSection

【行为准则】
1. 你被 @提到才需要回复，请专注于被委派的任务
2. 仔细阅读上下文，理解你被委派的具体任务
3. 给出专业、有价值的回复，专注于你擅长的领域
4. 保持简洁，不要重复其他成员已经给出的答案
5. 可以补充、纠正或扩展其他成员的回答
6. 直接回复内容即可，不要在回复前加上你的名字前缀（如"[${currentAgent.name}]: "），系统会自动显示你的身份$mentionNotice''';
  }

  /// Parse @mentions from an agent's response content, returning matching agent IDs.
  List<String> _parseAgentMentions(String content, List<RemoteAgent> agents) {
    if (content.contains('@all')) {
      return agents.map((a) => a.id).toList();
    }
    final mentioned = <String>[];
    for (final agent in agents) {
      if (content.contains('@${agent.name}')) {
        mentioned.add(agent.id);
      }
    }
    return mentioned;
  }

  /// Parse 【步骤N】 workflow step markers from admin response text.
  ///
  /// Returns an ordered list of maps with keys:
  ///   - `stepNumber` (int)
  ///   - `agentIds` (List<String>)
  ///   - `taskDescription` (String)
  ///
  /// Returns an empty list if no step markers are found, signalling that the
  /// caller should fall back to concurrent execution.
  List<Map<String, dynamic>> _parseWorkflowSteps(
    String content,
    List<RemoteAgent> agents,
  ) {
    final stepPattern = RegExp(r'【步骤(\d+)】');
    final matches = stepPattern.allMatches(content).toList();
    if (matches.isEmpty) return [];

    final seenAgentIds = <String>{};
    final steps = <Map<String, dynamic>>[];

    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final stepNumber = int.parse(match.group(1)!);

      // Extract text segment for this step (until next step marker or end)
      final start = match.end;
      final end = (i + 1 < matches.length) ? matches[i + 1].start : content.length;
      final segment = content.substring(start, end);

      // Parse @mentions within this segment
      List<String> agentIds;
      if (segment.contains('@all')) {
        agentIds = agents
            .map((a) => a.id)
            .where((id) => !seenAgentIds.contains(id))
            .toList();
      } else {
        agentIds = <String>[];
        for (final agent in agents) {
          if (segment.contains('@${agent.name}') &&
              !seenAgentIds.contains(agent.id)) {
            agentIds.add(agent.id);
          }
        }
      }

      seenAgentIds.addAll(agentIds);

      if (agentIds.isNotEmpty) {
        steps.add({
          'stepNumber': stepNumber,
          'agentIds': agentIds,
          'taskDescription': segment.trim(),
        });
      }
    }

    // Sort by step number
    steps.sort((a, b) =>
        (a['stepNumber'] as int).compareTo(b['stepNumber'] as int));

    return steps;
  }

  /// Format a sub-agent interaction request into a text question for the admin LLM.
  String _formatInteractionForAdmin({
    required String interactionType,
    required Map<String, dynamic> data,
    required String subAgentName,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('子Agent "$subAgentName" 在执行任务时请求你的决策：');

    switch (interactionType) {
      case 'action_confirmation':
        final title = data['title'] as String? ?? '';
        final message = data['message'] as String? ?? '';
        final actions = data['actions'] as List<dynamic>? ?? [];
        buffer.writeln('类型：操作确认');
        if (title.isNotEmpty) buffer.writeln('标题："$title"');
        if (message.isNotEmpty) buffer.writeln('问题："$message"');
        if (actions.isNotEmpty) {
          buffer.writeln('选项：');
          for (var i = 0; i < actions.length; i++) {
            final action = actions[i] as Map<String, dynamic>;
            final actionId = action['id'] as String? ?? '';
            final label = action['label'] as String? ?? '';
            buffer.writeln('${i + 1}. [$actionId] $label');
          }
        }
        buffer.writeln('请回复选项编号（如"1"）。如果你不确定，请回复 [ASK_USER]。');
        break;

      case 'single_select':
        final title = data['title'] as String? ?? '';
        final options = data['options'] as List<dynamic>? ?? [];
        buffer.writeln('类型：单选');
        if (title.isNotEmpty) buffer.writeln('问题："$title"');
        if (options.isNotEmpty) {
          buffer.writeln('选项：');
          for (var i = 0; i < options.length; i++) {
            final option = options[i] as Map<String, dynamic>;
            final optionId = option['id'] as String? ?? '';
            final label = option['label'] as String? ?? '';
            buffer.writeln('${i + 1}. [$optionId] $label');
          }
        }
        buffer.writeln('请回复选项编号（如"1"）。如果你不确定，请回复 [ASK_USER]。');
        break;

      case 'multi_select':
        final title = data['title'] as String? ?? '';
        final options = data['options'] as List<dynamic>? ?? [];
        buffer.writeln('类型：多选');
        if (title.isNotEmpty) buffer.writeln('问题："$title"');
        if (options.isNotEmpty) {
          buffer.writeln('选项：');
          for (var i = 0; i < options.length; i++) {
            final option = options[i] as Map<String, dynamic>;
            final optionId = option['id'] as String? ?? '';
            final label = option['label'] as String? ?? '';
            buffer.writeln('${i + 1}. [$optionId] $label');
          }
        }
        buffer.writeln('请回复选项编号（可用逗号分隔多个，如"1,3"）。如果你不确定，请回复 [ASK_USER]。');
        break;

      case 'form':
        final title = data['title'] as String? ?? '';
        final fields = data['fields'] as List<dynamic>? ?? [];
        buffer.writeln('类型：表单');
        if (title.isNotEmpty) buffer.writeln('标题："$title"');
        if (fields.isNotEmpty) {
          buffer.writeln('字段：');
          for (final field in fields) {
            final f = field as Map<String, dynamic>;
            buffer.writeln('- ${f['label'] ?? f['id'] ?? 'unknown'}');
          }
        }
        buffer.writeln('表单类型较复杂，请回复 [ASK_USER] 交给用户处理。');
        break;

      default:
        buffer.writeln('类型：$interactionType');
        buffer.writeln('请回复 [ASK_USER] 交给用户处理。');
    }

    return buffer.toString();
  }

  /// Try to match admin response text against options by index, ID, or label.
  ///
  /// Returns the index into [options] or -1 if no match.
  int _matchOption(String response, List<dynamic> options) {
    final trimmed = response.trim();

    // 1. Numeric index (1-based)
    final index = int.tryParse(trimmed);
    if (index != null && index >= 1 && index <= options.length) {
      return index - 1;
    }

    // 2. Exact option ID match
    for (var i = 0; i < options.length; i++) {
      final option = options[i] as Map<String, dynamic>;
      final id = option['id'] as String? ?? '';
      if (id.isNotEmpty && trimmed.toLowerCase() == id.toLowerCase()) {
        return i;
      }
    }

    // 3. Label substring match
    for (var i = 0; i < options.length; i++) {
      final option = options[i] as Map<String, dynamic>;
      final label = option['label'] as String? ?? '';
      if (label.isNotEmpty && trimmed.contains(label)) {
        return i;
      }
    }

    return -1;
  }

  /// Parse admin LLM response to extract chosen option(s).
  ///
  /// Returns formatted response data for [ACPAgentConnection.submitResponse],
  /// or null if the admin chose [ASK_USER] or parsing failed.
  Map<String, dynamic>? _parseAdminDecision({
    required String interactionType,
    required String adminResponse,
    required Map<String, dynamic> data,
  }) {
    final trimmed = adminResponse.trim();

    // Check for escalation signal
    if (trimmed.contains('[ASK_USER]')) return null;

    switch (interactionType) {
      case 'action_confirmation':
        final actions = data['actions'] as List<dynamic>? ?? [];
        if (actions.isEmpty) return null;
        final idx = _matchOption(trimmed, actions);
        if (idx < 0) return null;
        final chosen = actions[idx] as Map<String, dynamic>;
        return {
          'confirmation_id': data['confirmation_id'] ?? data['id'] ?? '',
          'selected_action_id': chosen['id'] ?? '',
          'selected_action_label': chosen['label'] ?? '',
        };

      case 'single_select':
        final options = data['options'] as List<dynamic>? ?? [];
        if (options.isEmpty) return null;
        final idx = _matchOption(trimmed, options);
        if (idx < 0) return null;
        final chosen = options[idx] as Map<String, dynamic>;
        return {
          'select_id': data['select_id'] ?? data['id'] ?? '',
          'selected_option_id': chosen['id'] ?? '',
          'selected_option_label': chosen['label'] ?? '',
        };

      case 'multi_select':
        final options = data['options'] as List<dynamic>? ?? [];
        if (options.isEmpty) return null;
        // Parse comma-separated indices like "1,3"
        final parts = trimmed.split(RegExp(r'[,，\s]+'));
        final selectedIds = <String>[];
        for (final part in parts) {
          final idx = int.tryParse(part.trim());
          if (idx != null && idx >= 1 && idx <= options.length) {
            final opt = options[idx - 1] as Map<String, dynamic>;
            selectedIds.add(opt['id'] as String? ?? '');
          }
        }
        if (selectedIds.isEmpty) return null;
        return {
          'select_id': data['select_id'] ?? data['id'] ?? '',
          'selected_option_ids': selectedIds,
        };

      case 'form':
        // Forms are too complex; always escalate
        return null;

      default:
        return null;
    }
  }

  /// Ask the admin LLM to make a decision on a sub-agent's interaction request.
  ///
  /// Returns response data suitable for [ACPAgentConnection.submitResponse],
  /// or null if the admin chose [ASK_USER] or the call failed/timed out.
  Future<Map<String, dynamic>?> _resolveInteractionViaAdmin({
    required String interactionType,
    required Map<String, dynamic> data,
    required RemoteAgent adminAgent,
    required String channelId,
    required String subAgentName,
  }) async {
    try {
      // 1. Format the question
      final question = _formatInteractionForAdmin(
        interactionType: interactionType,
        data: data,
        subAgentName: subAgentName,
      );

      // 2. Load recent chat history for context
      final recentMessages = await loadChannelMessages(channelId, limit: 10);
      final historyLines = recentMessages.map((m) {
        final tag = m.from.isAgent ? 'Agent' : 'User';
        return '[${m.from.name}($tag)]: ${m.content}';
      }).join('\n');

      final history = historyLines.isNotEmpty
          ? <Map<String, String>>[
              {'role': 'user', 'content': '以下是群聊的近期记录：\n$historyLines'},
            ]
          : <Map<String, String>>[];

      // 3. Call admin LLM with a decision-making system prompt
      const decisionSystemPrompt = '你正在代替用户为子Agent的交互请求做决策。\n'
          '根据群聊上下文和子Agent的请求，选择最合适的选项。\n'
          '规则：\n'
          '- 只回复选项编号（如"1"），不要解释\n'
          '- 如果你确实无法判断，回复 [ASK_USER]\n'
          '- 优先选择能推进任务完成的选项';

      final responseBuffer = StringBuffer();
      await for (final event in LocalLLMAgentService.instance.chat(
        agent: adminAgent,
        message: question,
        history: history.isNotEmpty ? history : null,
        enableUITools: false,
        systemPromptOverride: decisionSystemPrompt,
      ).timeout(const Duration(seconds: 30))) {
        if (event is LLMTextEvent) {
          responseBuffer.write(event.text);
        }
      }

      final adminResponse = responseBuffer.toString().trim();
      if (adminResponse.isEmpty) return null;

      print('[ChatService] Admin decision for $subAgentName ($interactionType): "$adminResponse"');

      // 4. Parse the decision
      return _parseAdminDecision(
        interactionType: interactionType,
        adminResponse: adminResponse,
        data: data,
      );
    } catch (e) {
      print('[ChatService] _resolveInteractionViaAdmin error: $e');
      return null;
    }
  }

  /// Pick a safe default option when the admin LLM cannot decide.
  ///
  /// Prevents sub-agents from hanging indefinitely on unanswered interactions.
  /// Returns null only for `form` type which cannot be auto-filled.
  Map<String, dynamic>? _pickDefaultOption(String interactionType, Map<String, dynamic> data) {
    switch (interactionType) {
      case 'action_confirmation':
        final actions = data['actions'] as List<dynamic>? ?? [];
        if (actions.isEmpty) return null;
        // Prefer 'primary' styled action, else first action
        var chosen = actions[0] as Map<String, dynamic>;
        for (final action in actions) {
          final a = action as Map<String, dynamic>;
          if (a['style'] == 'primary') {
            chosen = a;
            break;
          }
        }
        return {
          'confirmation_id': data['confirmation_id'] ?? data['id'] ?? '',
          'selected_action_id': chosen['id'] ?? '',
          'selected_action_label': chosen['label'] ?? '',
        };

      case 'single_select':
        final options = data['options'] as List<dynamic>? ?? [];
        if (options.isEmpty) return null;
        final chosen = options[0] as Map<String, dynamic>;
        return {
          'select_id': data['select_id'] ?? data['id'] ?? '',
          'selected_option_id': chosen['id'] ?? '',
          'selected_option_label': chosen['label'] ?? '',
        };

      case 'multi_select':
        final options = data['options'] as List<dynamic>? ?? [];
        if (options.isEmpty) return null;
        final first = options[0] as Map<String, dynamic>;
        return {
          'select_id': data['select_id'] ?? data['id'] ?? '',
          'selected_option_ids': [first['id'] ?? ''],
        };

      case 'form':
        print('[ChatService] Cannot auto-fill form interaction, skipping');
        return null;

      default:
        return null;
    }
  }

  /// Save a system message recording an admin's auto-decision in the group chat.
  void _saveAdminDecisionMessage({
    required String channelId,
    required String subAgentName,
    required String interactionType,
    required String chosenLabel,
  }) {
    // Fire-and-forget: save in background, don't block the interaction flow
    () async {
      try {
        final msgId = _uuid.v4();
        final typeLabel = switch (interactionType) {
          'action_confirmation' => '操作确认',
          'single_select' => '单选',
          'multi_select' => '多选',
          _ => interactionType,
        };
        final content = '[系统] 管理员代替用户为 $subAgentName 做出了决策（$typeLabel）：选择"$chosenLabel"';
        await _databaseService.createMessage(
          id: msgId,
          channelId: channelId,
          senderId: 'system',
          senderType: 'system',
          senderName: 'System',
          content: content,
          messageType: 'system',
        );
        await _databaseService.markMessageAsRead(msgId);
        _notifyChannelUpdate(channelId);
      } catch (e) {
        print('[ChatService] Failed to save admin decision message: $e');
      }
    }();
  }

  /// Notify group members about a membership change (join/leave).
  ///
  /// Persists a system message, refreshes the UI stream, and sends an ACP
  /// push notification to every connected remote agent still in the group.
  /// Returns the system [Message] so the caller can insert it into the UI.
  Future<Message> notifyGroupMembershipChange(
    String channelId,
    String memberId,
    String memberName, {
    required bool isJoin,
  }) async {
    // 1. Load channel info
    final channel = await _databaseService.getChannelById(channelId);
    final groupName = channel?.name ?? 'Group';

    // 2. Build & persist the system message
    final action = isJoin ? '加入了群聊' : '离开了群聊';
    final systemMessage = Message(
      id: _uuid.v4(),
      content: '🤖 $memberName $action',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      from: MessageFrom(id: 'system', type: 'system', name: 'System'),
      type: MessageType.system,
    );

    await _databaseService.createMessage(
      id: systemMessage.id,
      channelId: channelId,
      senderId: 'system',
      senderType: 'system',
      senderName: 'System',
      content: systemMessage.content,
      messageType: 'system',
    );
    await _databaseService.markMessageAsRead(systemMessage.id);

    // 3. Refresh the UI stream
    _notifyChannelUpdate(channelId);

    // 4. Load updated member list from DB
    final memberIds = await _databaseService.getChannelMemberIds(channelId);
    final List<Map<String, dynamic>> currentMembers = [];
    for (final id in memberIds) {
      final agent = await _databaseService.getRemoteAgentById(id);
      if (agent != null) {
        currentMembers.add({
          'id': agent.id,
          'name': agent.name,
          'type': 'agent',
          'bio': agent.bio ?? '',
          'capabilities': agent.capabilities,
          'status': agent.status.name,
        });
      }
    }

    // 5. Build notification payload
    final method = isJoin
        ? ACPMethod.groupMemberJoined
        : ACPMethod.groupMemberLeft;
    final params = {
      'group_id': channelId,
      'group_name': groupName,
      'member': {'id': memberId, 'name': memberName},
      'current_members': currentMembers,
      'member_count': currentMembers.length,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // 6. Push notification to each connected member
    for (final id in memberIds) {
      final connection = _acpConnections[id];
      if (connection != null && connection.isConnected) {
        connection.sendNotification(method, params: params);
      }
    }

    return systemMessage;
  }

  /// Send a message to a group channel, orchestrating agent responses.
  ///
  /// When [adminAgentId] is set and the user hasn't @mentioned specific agents,
  /// only the admin responds first.  If the admin @mentions other members in its
  /// reply, those members are launched in a second round.  When no admin is set,
  /// all agents respond concurrently (backward-compatible behavior).
  Future<void> sendMessageToGroup({
    required String channelId,
    required String content,
    required String userId,
    required String userName,
    required List<String> agentIds,
    List<String> mentionedAgentIds = const [],
    bool mentionOnlyMode = false,
    String? adminAgentId,
    String? replyToId,
    void Function(String agentId, String agentName, String chunk)? onStreamChunk,
    void Function(String agentId, String agentName)? onAgentStart,
    void Function(String agentId, String agentName, bool skipped)? onAgentDone,
    void Function()? onAllDone,
  }) async {
    print('[ChatService] sendMessageToGroup: $channelId, agents: $agentIds, admin: $adminAgentId');

    // 1. Save user message to the group channel
    final userMessage = Message(
      id: _uuid.v4(),
      content: content,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      from: MessageFrom(id: userId, type: 'user', name: userName),
      type: MessageType.text,
      replyTo: replyToId,
    );

    // Check if channel exists; create is handled by _saveMessageToChannel
    // but for group channels it should already exist from CreateGroupScreen
    await _databaseService.createMessage(
      id: userMessage.id,
      channelId: channelId,
      senderId: userId,
      senderType: 'user',
      senderName: userName,
      content: content,
      messageType: 'text',
      replyToId: replyToId,
    );
    await _databaseService.markMessageAsRead(userMessage.id);
    _notifyChannelUpdate(channelId);

    // 2. Load channel info for group prompt
    final channel = await _databaseService.getChannelById(channelId);
    final groupName = channel?.name ?? 'Group';
    final groupDescription = channel?.description ?? '';
    final channelMembers = channel?.members ?? <ChannelMember>[];
    final customSystemPrompt = channel?.systemPrompt;

    // 3. Load all agent RemoteAgent objects
    final List<RemoteAgent> agents = [];
    for (final agentId in agentIds) {
      final agent = await _databaseService.getRemoteAgentById(agentId);
      if (agent != null) agents.add(agent);
    }

    if (agents.isEmpty) {
      print('[ChatService] No valid agents found for group');
      onAllDone?.call();
      return;
    }

    // 4. Load conversation history ONCE before all agents start (snapshot)
    // For first-time conversations (no prior agent messages), load more history.
    final allMessages = await loadChannelMessages(channelId, limit: 100);
    final textMessages = allMessages.where((m) => m.type == MessageType.text).toList();

    // Determine which agents have prior messages in the channel
    final agentIdsWithHistory = <String>{};
    for (final m in textMessages) {
      if (m.from.isAgent) {
        agentIdsWithHistory.add(m.from.id);
      }
    }

    // Always use full history (up to 100) so agents can rebuild context
    // even after restart, rather than limiting to 40 when agents have history.
    var historyMessages = textMessages.toList();

    // Remove the current user message from history — it will be sent
    // separately as the 'message' parameter to avoid duplication.
    if (historyMessages.isNotEmpty && historyMessages.last.id == userMessage.id) {
      historyMessages = historyMessages.sublist(0, historyMessages.length - 1);
    }

    // Build message version info for agent context sync
    final messageVersion = <String, dynamic>{
      'total_count': allMessages.length,
      'latest_message_id': allMessages.isNotEmpty ? allMessages.last.id : null,
      'latest_timestamp': allMessages.isNotEmpty ? allMessages.last.timestampMs : null,
    };

    // Resolve quoted message content so agents understand reply context
    String effectiveContent = content;
    if (replyToId != null) {
      final quotedMessage = await getMessageById(replyToId);
      if (quotedMessage != null) {
        effectiveContent = '[引用 ${quotedMessage.from.name} 的消息: "${quotedMessage.content}"]\n\n$content';
      }
    }

    // 5. Route to the appropriate flow based on admin setting and @mentions
    if (mentionedAgentIds.isNotEmpty) {
      // 5a. User explicitly @mentioned agents — those agents respond directly
      final futures = <Future<void>>[];
      for (final agent in agents) {
        if (!mentionedAgentIds.contains(agent.id)) {
          onAgentDone?.call(agent.id, agent.name, true);
          continue;
        }
        onAgentStart?.call(agent.id, agent.name);
        final isFirstMessage = !agentIdsWithHistory.contains(agent.id);
        futures.add(
          _processGroupAgent(
            agent: agent,
            channelId: channelId,
            content: effectiveContent,
            userId: userId,
            userName: userName,
            groupName: groupName,
            groupDescription: groupDescription,
            allAgents: agents,
            historyMessages: historyMessages,
            mentionedAgentIds: mentionedAgentIds,
            isFirstMessage: isFirstMessage,
            messageVersion: messageVersion,
            channelMembers: channelMembers,
            customSystemPrompt: customSystemPrompt,
            onStreamChunk: onStreamChunk,
            onAgentDone: onAgentDone,
          ).catchError((e) {
            print('[ChatService] Group agent ${agent.name} uncaught error: $e');
          }),
        );
      }
      await Future.wait(futures);
    } else if (adminAgentId != null) {
      // 5b. Admin-first flow: only admin responds, then delegates via @mentions
      final adminAgent = agents.where((a) => a.id == adminAgentId).firstOrNull;
      if (adminAgent == null) {
        print('[ChatService] Admin agent not found, falling back to all-agents mode');
        // Fall through to all-agents mode below
      } else {
        // Skip non-admin agents immediately
        for (final agent in agents) {
          if (agent.id != adminAgentId) {
            onAgentDone?.call(agent.id, agent.name, true);
          }
        }

        // Launch admin agent and capture its response content
        onAgentStart?.call(adminAgent.id, adminAgent.name);
        final isFirstMessage = !agentIdsWithHistory.contains(adminAgent.id);
        String adminResponseContent = '';
        await _processGroupAgent(
          agent: adminAgent,
          channelId: channelId,
          content: effectiveContent,
          userId: userId,
          userName: userName,
          groupName: groupName,
          groupDescription: groupDescription,
          allAgents: agents,
          historyMessages: historyMessages,
          mentionedAgentIds: const [],
          isFirstMessage: isFirstMessage,
          isAdmin: true,
          messageVersion: messageVersion,
          channelMembers: channelMembers,
          customSystemPrompt: customSystemPrompt,
          onStreamChunk: (agentId, agentName, chunk) {
            adminResponseContent += chunk;
            onStreamChunk?.call(agentId, agentName, chunk);
          },
          onAgentDone: onAgentDone,
        ).catchError((e) {
          print('[ChatService] Admin agent ${adminAgent.name} uncaught error: $e');
        });

        // Parse @mentions from admin's response
        final nonAdminAgents = agents.where((a) => a.id != adminAgentId).toList();
        final delegatedIds = _parseAgentMentions(adminResponseContent, nonAdminAgents);

        if (delegatedIds.isNotEmpty) {
          // Check for sequential workflow steps (【步骤N】 markers)
          final workflowSteps = _parseWorkflowSteps(adminResponseContent, nonAdminAgents);

          if (workflowSteps.isNotEmpty) {
            // Sequential workflow: execute steps in order
            for (final step in workflowSteps) {
              final stepAgentIds = step['agentIds'] as List<String>;

              // Reload history before each step so agents see previous steps' output
              final stepMessages = await loadChannelMessages(channelId, limit: 100);
              final stepTextMessages = stepMessages.where((m) => m.type == MessageType.text).toList();
              final stepHistory = stepTextMessages.length > 40
                  ? stepTextMessages.sublist(stepTextMessages.length - 40)
                  : stepTextMessages;

              // Launch all agents within this step concurrently
              final stepFutures = <Future<void>>[];
              for (final agent in agents) {
                if (!stepAgentIds.contains(agent.id)) continue;
                onAgentStart?.call(agent.id, agent.name);
                final isFirst = !agentIdsWithHistory.contains(agent.id);
                stepFutures.add(
                  _processGroupAgent(
                    agent: agent,
                    channelId: channelId,
                    content: effectiveContent,
                    userId: userId,
                    userName: userName,
                    groupName: groupName,
                    groupDescription: groupDescription,
                    allAgents: agents,
                    historyMessages: stepHistory,
                    mentionedAgentIds: delegatedIds,
                    isFirstMessage: isFirst,
                    messageVersion: messageVersion,
                    channelMembers: channelMembers,
                    adminAgent: adminAgent,
                    customSystemPrompt: customSystemPrompt,
                    onStreamChunk: onStreamChunk,
                    onAgentDone: onAgentDone,
                  ).catchError((e) {
                    print('[ChatService] Step ${step['stepNumber']} agent ${agent.name} uncaught error: $e');
                  }),
                );
              }
              await Future.wait(stepFutures);
            }
          } else {
            // No workflow steps — fall back to concurrent execution
            final updatedMessages = await loadChannelMessages(channelId, limit: 100);
            final updatedTextMessages = updatedMessages.where((m) => m.type == MessageType.text).toList();
            var updatedHistory = updatedTextMessages.length > 40
                ? updatedTextMessages.sublist(updatedTextMessages.length - 40)
                : updatedTextMessages;

            final delegatedFutures = <Future<void>>[];
            for (final agent in agents) {
              if (!delegatedIds.contains(agent.id)) continue;
              onAgentStart?.call(agent.id, agent.name);
              final isFirst = !agentIdsWithHistory.contains(agent.id);
              delegatedFutures.add(
                _processGroupAgent(
                  agent: agent,
                  channelId: channelId,
                  content: effectiveContent,
                  userId: userId,
                  userName: userName,
                  groupName: groupName,
                  groupDescription: groupDescription,
                  allAgents: agents,
                  historyMessages: updatedHistory,
                  mentionedAgentIds: delegatedIds,
                  isFirstMessage: isFirst,
                  messageVersion: messageVersion,
                  channelMembers: channelMembers,
                  adminAgent: adminAgent,
                  customSystemPrompt: customSystemPrompt,
                  onStreamChunk: onStreamChunk,
                  onAgentDone: onAgentDone,
                ).catchError((e) {
                  print('[ChatService] Delegated agent ${agent.name} uncaught error: $e');
                }),
              );
            }
            await Future.wait(delegatedFutures);
          }
        }

        onAllDone?.call();
        return;
      }
    }

    // 5c. No admin set (backward compatibility) or admin not found — all agents respond
    if (mentionedAgentIds.isEmpty && adminAgentId == null) {
      final futures = <Future<void>>[];
      for (final agent in agents) {
        onAgentStart?.call(agent.id, agent.name);
        final isFirstMessage = !agentIdsWithHistory.contains(agent.id);
        futures.add(
          _processGroupAgent(
            agent: agent,
            channelId: channelId,
            content: effectiveContent,
            userId: userId,
            userName: userName,
            groupName: groupName,
            groupDescription: groupDescription,
            allAgents: agents,
            historyMessages: historyMessages,
            mentionedAgentIds: mentionedAgentIds,
            isFirstMessage: isFirstMessage,
            messageVersion: messageVersion,
            channelMembers: channelMembers,
            customSystemPrompt: customSystemPrompt,
            onStreamChunk: onStreamChunk,
            onAgentDone: onAgentDone,
          ).catchError((e) {
            print('[ChatService] Group agent ${agent.name} uncaught error: $e');
          }),
        );
      }
      await Future.wait(futures);
    }

    onAllDone?.call();
  }

  /// Save a file_message from an agent in a group chat to the database.
  Future<void> _saveGroupFileMessage({
    required Map<String, dynamic> fileData,
    required String agentId,
    required String agentName,
    required String channelId,
    required String userId,
    required String userName,
  }) async {
    try {
      final url = fileData['url'] as String?;
      final filename = fileData['filename'] as String?;
      final fileMimeType = fileData['mime_type'] as String?;
      final size = fileData['size'] as int?;
      final thumbnailBase64 = fileData['thumbnail_base64'] as String?;

      if (url == null || url.isEmpty) {
        print('[ChatService] Group file_message missing url from $agentName');
        return;
      }

      // Extract file_id from URL (e.g. http://host/files/{file_id})
      String? fileId;
      try {
        final uri = Uri.parse(url);
        if (uri.pathSegments.length >= 2 &&
            uri.pathSegments[uri.pathSegments.length - 2] == 'files') {
          fileId = uri.pathSegments.last;
        }
      } catch (_) {}

      final isImage = fileMimeType != null && fileMimeType.startsWith('image/');
      final msgType = isImage ? MessageType.image : MessageType.file;

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

      final messageId = 'file_${DateTime.now().millisecondsSinceEpoch}';
      await _databaseService.createMessage(
        id: messageId,
        channelId: channelId,
        senderId: agentId,
        senderType: 'agent',
        senderName: agentName,
        content: isImage
            ? '[Image: ${filename ?? "image"}]'
            : '[File: ${filename ?? "file"}]',
        messageType: msgType.toString().split('.').last,
        metadata: metadata,
      );
      await _databaseService.markMessageAsRead(messageId);
      _notifyChannelUpdate(channelId);

      print('[ChatService] Group file_message saved: ${filename ?? "file"} from $agentName');
    } catch (e) {
      print('[ChatService] Group file_message save error from $agentName: $e');
    }
  }

  /// Process a single agent's response in a group chat (called concurrently).
  Future<void> _processGroupAgent({
    required RemoteAgent agent,
    required String channelId,
    required String content,
    required String userId,
    required String userName,
    required String groupName,
    required String groupDescription,
    required List<RemoteAgent> allAgents,
    required List<Message> historyMessages,
    required List<String> mentionedAgentIds,
    required bool isFirstMessage,
    bool isAdmin = false,
    Map<String, dynamic>? messageVersion,
    List<ChannelMember> channelMembers = const [],
    RemoteAgent? adminAgent,
    String? customSystemPrompt,
    void Function(String agentId, String agentName, String chunk)? onStreamChunk,
    void Function(String agentId, String agentName, bool skipped)? onAgentDone,
  }) async {
    final systemPrompt = _buildGroupSystemPrompt(
      groupName: groupName,
      groupDescription: groupDescription,
      allAgents: allAgents,
      currentAgent: agent,
      channelMembers: channelMembers,
      isMentioned: mentionedAgentIds.contains(agent.id),
      isAdmin: isAdmin,
      customSystemPrompt: customSystemPrompt,
    );

    // Build chat history: pack the entire group conversation into a single
    // 'user' message so the LLM's identity comes solely from the system prompt.
    // Each line is tagged with the sender name so the agent can see who said
    // what, while "(我)" marks its own prior messages.
    final historyLines = historyMessages.map((m) {
      if (m.from.isAgent && m.from.id == agent.id) {
        return '[${m.from.name}(我)]: ${m.content}';
      }
      final tag = m.from.isAgent ? 'Agent' : 'User';
      return '[${m.from.name}($tag)]: ${m.content}';
    }).join('\n\n');

    final chatHistory = historyLines.isNotEmpty
        ? <Map<String, String>>[
            {'role': 'user', 'content': '以下是群聊的历史记录：\n\n$historyLines'},
          ]
        : <Map<String, String>>[];

    final responseBuffer = StringBuffer();
    bool streamingStarted = false;

    // Register a GroupActiveTask so the UI can reattach after navigating away
    final groupTask = GroupActiveTask(
      agentId: agent.id,
      agentName: agent.name,
      channelId: channelId,
    );
    _activeGroupTasks.putIfAbsent(channelId, () => {});
    _activeGroupTasks[channelId]![agent.id] = groupTask;
    _updateTypingAgentIds();

    if (LocalLLMAgentService.instance.isLocalAgent(agent)) {
      // ── Local LLM agent path ──
      try {
        await for (final event in LocalLLMAgentService.instance.chat(
          agent: agent,
          message: content,
          history: chatHistory.isNotEmpty ? chatHistory : null,
          enableUITools: true,
          systemPromptOverride: systemPrompt,
        )) {
          switch (event) {
            case LLMTextEvent():
              streamingStarted = true;
              responseBuffer.write(event.text);
              groupTask.accumulatedContent += event.text;
              groupTask.onStreamChunk?.call(event.text);
              onStreamChunk?.call(agent.id, agent.name, event.text);
              break;
            case LLMToolCallEvent():
              if (event.name == 'file_message') {
                await _saveGroupFileMessage(
                  fileData: event.arguments,
                  agentId: agent.id,
                  agentName: agent.name,
                  channelId: channelId,
                  userId: userId,
                  userName: userName,
                );
              }
              break;
            case LLMDoneEvent():
              // Ignored in group chat single-round mode
              break;
          }
        }
      } catch (e) {
        print('[ChatService] Group agent ${agent.name} stream error: $e');
        if (!streamingStarted || responseBuffer.isEmpty) {
          groupTask.isComplete = true;
          groupTask.onTaskFinished?.call();
          _activeGroupTasks[channelId]?.remove(agent.id);
          if (_activeGroupTasks[channelId]?.isEmpty == true) {
            _activeGroupTasks.remove(channelId);
          }
          _updateTypingAgentIds();
          onAgentDone?.call(agent.id, agent.name, true);
          return;
        }
      }
    } else {
      // ── Remote ACP agent path ──
      try {
        final connection = await _getOrCreateACPConnection(agent);
        final taskId = _uuid.v4();
        final taskCompleter = Completer<void>();

        connection.onTextContent = (data) {
          final chunk = data['content'] as String? ?? '';
          streamingStarted = true;
          responseBuffer.write(chunk);
          groupTask.accumulatedContent += chunk;
          groupTask.onStreamChunk?.call(chunk);
          onStreamChunk?.call(agent.id, agent.name, chunk);
        };

        connection.onTaskCompleted = (data) {
          if (!taskCompleter.isCompleted) {
            taskCompleter.complete();
          }
        };

        connection.onTaskError = (data) {
          if (!taskCompleter.isCompleted) {
            taskCompleter.completeError(
              Exception(data['message'] ?? 'Task error'),
            );
          }
        };

        // Wire interaction callbacks when admin is available for auto-decisions
        if (adminAgent != null) {
          connection.onActionConfirmation = (data) async {
            try {
              var responseData = await _resolveInteractionViaAdmin(
                interactionType: 'action_confirmation',
                data: data,
                adminAgent: adminAgent,
                channelId: channelId,
                subAgentName: agent.name,
              );
              responseData ??= _pickDefaultOption('action_confirmation', data);
              if (responseData != null) {
                await connection.submitResponse(
                  taskId: taskId,
                  responseType: 'action_confirmation',
                  responseData: responseData,
                );
                _saveAdminDecisionMessage(
                  channelId: channelId,
                  subAgentName: agent.name,
                  interactionType: 'action_confirmation',
                  chosenLabel: responseData['selected_action_label'] as String? ?? '',
                );
              }
            } catch (e) {
              print('[ChatService] Admin decision error (action_confirmation): $e');
              final fallback = _pickDefaultOption('action_confirmation', data);
              if (fallback != null) {
                try {
                  await connection.submitResponse(
                    taskId: taskId,
                    responseType: 'action_confirmation',
                    responseData: fallback,
                  );
                } catch (_) {}
              }
            }
          };

          connection.onSingleSelect = (data) async {
            try {
              var responseData = await _resolveInteractionViaAdmin(
                interactionType: 'single_select',
                data: data,
                adminAgent: adminAgent,
                channelId: channelId,
                subAgentName: agent.name,
              );
              responseData ??= _pickDefaultOption('single_select', data);
              if (responseData != null) {
                await connection.submitResponse(
                  taskId: taskId,
                  responseType: 'single_select',
                  responseData: responseData,
                );
                _saveAdminDecisionMessage(
                  channelId: channelId,
                  subAgentName: agent.name,
                  interactionType: 'single_select',
                  chosenLabel: responseData['selected_option_label'] as String? ?? '',
                );
              }
            } catch (e) {
              print('[ChatService] Admin decision error (single_select): $e');
              final fallback = _pickDefaultOption('single_select', data);
              if (fallback != null) {
                try {
                  await connection.submitResponse(
                    taskId: taskId,
                    responseType: 'single_select',
                    responseData: fallback,
                  );
                } catch (_) {}
              }
            }
          };

          connection.onMultiSelect = (data) async {
            try {
              var responseData = await _resolveInteractionViaAdmin(
                interactionType: 'multi_select',
                data: data,
                adminAgent: adminAgent,
                channelId: channelId,
                subAgentName: agent.name,
              );
              responseData ??= _pickDefaultOption('multi_select', data);
              if (responseData != null) {
                await connection.submitResponse(
                  taskId: taskId,
                  responseType: 'multi_select',
                  responseData: responseData,
                );
                final ids = responseData['selected_option_ids'] as List<dynamic>? ?? [];
                _saveAdminDecisionMessage(
                  channelId: channelId,
                  subAgentName: agent.name,
                  interactionType: 'multi_select',
                  chosenLabel: ids.join(', '),
                );
              }
            } catch (e) {
              print('[ChatService] Admin decision error (multi_select): $e');
              final fallback = _pickDefaultOption('multi_select', data);
              if (fallback != null) {
                try {
                  await connection.submitResponse(
                    taskId: taskId,
                    responseType: 'multi_select',
                    responseData: fallback,
                  );
                } catch (_) {}
              }
            }
          };

          connection.onForm = (data) async {
            // Forms are too complex for auto-decision; log and skip
            print('[ChatService] Form interaction from ${agent.name} — cannot auto-decide, skipping');
            final fallback = _pickDefaultOption('form', data);
            if (fallback != null) {
              try {
                await connection.submitResponse(
                  taskId: taskId,
                  responseType: 'form',
                  responseData: fallback,
                );
              } catch (_) {}
            }
          };

          connection.onFileUpload = (data) async {
            // File uploads cannot be auto-decided; log and skip
            print('[ChatService] File upload interaction from ${agent.name} — cannot auto-decide, skipping');
          };
        }

        // Wire file message callback (independent of admin — always handle)
        connection.onFileMessage = (data) async {
          await _saveGroupFileMessage(
            fileData: data,
            agentId: agent.id,
            agentName: agent.name,
            channelId: channelId,
            userId: userId,
            userName: userName,
          );
        };

        // Build group_context for remote agents
        final groupContext = <String, dynamic>{
          'group_id': channelId,
          'group_name': groupName,
          'group_description': groupDescription,
          'member_count': allAgents.length,
          'members': allAgents.map((a) => <String, dynamic>{
            'id': a.id,
            'name': a.name,
            'type': 'agent',
            'bio': a.bio ?? '',
            'capabilities': a.capabilities,
            'status': a.isOnline ? 'online' : 'offline',
          }).toList(),
          'is_first_message': isFirstMessage,
          if (messageVersion != null)
            'message_version': messageVersion,
        };

        await connection.sendChatMessage(
          taskId: taskId,
          sessionId: channelId,
          message: content,
          userId: userId,
          messageId: _uuid.v4(),
          history: chatHistory.isNotEmpty ? chatHistory : null,
          systemPrompt: systemPrompt,
          groupContext: groupContext,
        );

        await taskCompleter.future.timeout(
          const Duration(seconds: 300),
          onTimeout: () {
            throw TimeoutException('ACP group task timed out for ${agent.name}');
          },
        );

        _clearACPCallbacks(connection);
      } catch (e) {
        print('[ChatService] Group agent ${agent.name} ACP error: $e');
        if (!streamingStarted || responseBuffer.isEmpty) {
          groupTask.isComplete = true;
          groupTask.onTaskFinished?.call();
          _activeGroupTasks[channelId]?.remove(agent.id);
          if (_activeGroupTasks[channelId]?.isEmpty == true) {
            _activeGroupTasks.remove(channelId);
          }
          _updateTypingAgentIds();
          onAgentDone?.call(agent.id, agent.name, true);
          return;
        }
      }
    }

    var responseContent = responseBuffer.toString().trim();

    // Strip redundant agent name prefix that LLMs sometimes echo from chat history
    // e.g. "[local1]: 你好" or "[local1(Agent)]: 你好" → "你好"
    final prefixPattern = RegExp(r'^\[' + RegExp.escape(agent.name) + r'(?:\(Agent\))?\]\s*[:：]\s*');
    responseContent = responseContent.replaceFirst(prefixPattern, '');

    if (responseContent.isEmpty || responseContent.contains('[SKIP]')) {
      print('[ChatService] Agent ${agent.name} skipped');
      groupTask.isComplete = true;
      groupTask.onTaskFinished?.call();
      _activeGroupTasks[channelId]?.remove(agent.id);
      if (_activeGroupTasks[channelId]?.isEmpty == true) {
        _activeGroupTasks.remove(channelId);
      }
      _updateTypingAgentIds();
      onAgentDone?.call(agent.id, agent.name, true);
      return;
    }

    // Save to DB — failure here should NOT remove the already-displayed message
    try {
      final agentResponse = Message(
        id: _uuid.v4(),
        content: responseContent,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        from: MessageFrom(id: agent.id, type: 'agent', name: agent.name),
        to: MessageFrom(id: userId, type: 'user', name: userName),
        type: MessageType.text,
      );

      await _databaseService.createMessage(
        id: agentResponse.id,
        channelId: channelId,
        senderId: agent.id,
        senderType: 'agent',
        senderName: agent.name,
        content: responseContent,
        messageType: 'text',
      );
      // Mark as read immediately — the user is actively viewing this chat
      await _databaseService.markMessageAsRead(agentResponse.id);
      _notifyChannelUpdate(channelId);
    } catch (e) {
      print('[ChatService] Group agent ${agent.name} DB save error: $e');
      // DB save failed, but the message is already in the UI — keep it
    }

    // Mark group task complete and clean up
    groupTask.isComplete = true;
    groupTask.onTaskFinished?.call();
    _activeGroupTasks[channelId]?.remove(agent.id);
    if (_activeGroupTasks[channelId]?.isEmpty == true) {
      _activeGroupTasks.remove(channelId);
    }
    _updateTypingAgentIds();

    onAgentDone?.call(agent.id, agent.name, false);
  }

  /// Create a new group session with the same members and name as the original group.
  Future<String> createNewGroupSession({
    required String channelId,
    required String userId,
  }) async {
    final currentChannel = await _databaseService.getChannelById(channelId);
    if (currentChannel == null) throw Exception('Channel not found');

    final parentGroupId = currentChannel.groupFamilyId;
    final newChannelId = 'group_${_uuid.v4()}';

    final channel = Channel(
      id: newChannelId,
      name: currentChannel.name,
      type: 'group',
      members: currentChannel.members,
      description: currentChannel.description,
      isPrivate: currentChannel.isPrivate,
      parentGroupId: parentGroupId,
    );
    await _databaseService.createChannel(channel, userId);
    return newChannelId;
  }

  /// Get all sessions for a group (by parentGroupId).
  Future<List<Channel>> getGroupSessions({required String parentGroupId}) async {
    return await _databaseService.getGroupSessions(parentGroupId);
  }

  /// Clear current group session history: send /reset to all connected agents, delete messages.
  Future<void> clearGroupSessionHistory({
    required String channelId,
    required List<String> agentIds,
  }) async {
    // Send /reset to each connected agent (fire-and-forget)
    for (final agentId in agentIds) {
      final connection = _acpConnections[agentId];
      if (connection != null && connection.isConnected) {
        try {
          await connection.sendChatMessage(
            taskId: _uuid.v4(),
            sessionId: channelId,
            message: '/reset',
            userId: 'user',
            messageId: _uuid.v4(),
          );
        } catch (_) {
          // Ignore errors on reset
        }
      }
    }

    // Delete all messages in the channel
    await _databaseService.deleteChannelMessages(channelId);
    InferenceLogService.instance.removeByChannel(channelId);
    _notifyChannelUpdate(channelId);
  }

  /// Clear all group sessions: send /reset to all connected agents, delete all session messages.
  Future<void> clearAllGroupSessions({
    required String parentGroupId,
    required String currentChannelId,
    required List<String> agentIds,
  }) async {
    // Send /reset to each connected agent (fire-and-forget)
    for (final agentId in agentIds) {
      final connection = _acpConnections[agentId];
      if (connection != null && connection.isConnected) {
        try {
          await connection.sendChatMessage(
            taskId: _uuid.v4(),
            sessionId: currentChannelId,
            message: '/reset-all',
            userId: 'user',
            messageId: _uuid.v4(),
          );
        } catch (_) {
          // Ignore errors on reset
        }
      }
    }

    // Get all sessions, delete messages from all, delete non-parent channels
    final sessions = await _databaseService.getGroupSessions(parentGroupId);
    for (final session in sessions) {
      await _databaseService.deleteChannelMessages(session.id);
      if (session.id != parentGroupId) {
        await _databaseService.deleteChannel(session.id);
      }
    }

    // Ensure parent channel still exists
    final parentChannel = await _databaseService.getChannelById(parentGroupId);
    if (parentChannel == null && sessions.isNotEmpty) {
      // Recreate the parent from the first session's data
      final firstSession = sessions.first;
      final channel = Channel(
        id: parentGroupId,
        name: firstSession.name,
        type: 'group',
        members: firstSession.members,
        description: firstSession.description,
        isPrivate: firstSession.isPrivate,
      );
      await _databaseService.createChannel(channel, 'user');
    }

    _notifyChannelUpdate(parentGroupId);
  }

  /// 页面退出时调用，仅关闭 UI 流，ACP 连接保持存活
  void detachUI() {
    for (final controller in _messageControllers.values) {
      controller.close();
    }
    _messageControllers.clear();

    // Detach UI callbacks from active tasks but keep them running
    for (final task in _activeTasks.values) {
      task.detachUI();
    }

    // Detach UI callbacks from active group tasks
    for (final agentMap in _activeGroupTasks.values) {
      for (final task in agentMap.values) {
        task.detachUI();
      }
    }
  }

  /// Check if an existing ACP connection for [agentId] is alive.
  ///
  /// Returns `true` if there is a connected, authenticated connection and
  /// a ping succeeds.  Returns `false` otherwise (no connection, not
  /// connected, ping failed).  Does NOT create a new connection.
  Future<bool> pingAgent(String agentId) async {
    final connection = _acpConnections[agentId];
    if (connection == null || !connection.isConnected) return false;

    try {
      final resp = await connection.ping().timeout(const Duration(seconds: 5));
      return resp.isSuccess;
    } catch (_) {
      return false;
    }
  }

  /// 完整清理（App 退出时调用）
  void dispose() {
    detachUI();

    // Clean up ACP connections
    for (final connection in _acpConnections.values) {
      connection.dispose();
    }
    _acpConnections.clear();
  }
}
