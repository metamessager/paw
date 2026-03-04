import 'dart:async';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/widgets.dart';
import '../models/message.dart';
import '../models/channel.dart';
import '../models/remote_agent.dart';
import '../models/attachment_data.dart';
import '../models/pending_attachment.dart';
import '../services/chat_service.dart';
import '../services/local_database_service.dart';
import '../services/token_service.dart';
import '../services/remote_agent_service.dart';
import '../services/attachment_service.dart';
import '../services/message_search_service.dart';
import '../services/local_file_storage_service.dart';
import '../services/acp_agent_connection.dart';
import '../services/local_llm_agent_service.dart';
import '../services/app_lifecycle_service.dart';
import '../services/notification_service.dart';
import '../services/interactive_response_handler.dart';

// ---------------------------------------------------------------------------
// Events — sealed hierarchy for UI-bound side effects
// ---------------------------------------------------------------------------

sealed class ChatEvent {}

class ShowSnackBarEvent extends ChatEvent {
  final String message;
  ShowSnackBarEvent(this.message);
}

class ShowErrorSnackBarEvent extends ChatEvent {
  final String message;
  ShowErrorSnackBarEvent(this.message);
}

class ShowRetrySnackBarEvent extends ChatEvent {
  final String message;
  final String retryLabel;
  final Map<String, String> interruptedInfo;
  ShowRetrySnackBarEvent(this.message, this.retryLabel, this.interruptedInfo);
}

class NavigateToSessionEvent extends ChatEvent {
  final String channelId;
  final String? agentId;
  final String? agentName;
  final String? agentAvatar;
  final bool embedded;
  NavigateToSessionEvent({
    required this.channelId,
    this.agentId,
    this.agentName,
    this.agentAvatar,
    this.embedded = false,
  });
}

class ShowLoadingOverlayEvent extends ChatEvent {
  final String message;
  ShowLoadingOverlayEvent(this.message);
}

class DismissOverlayEvent extends ChatEvent {}

class RequestScrollToBottomEvent extends ChatEvent {
  final bool force;
  RequestScrollToBottomEvent({this.force = false});
}

class ShowHistoryRequestDialogEvent extends ChatEvent {
  final String reason;
  final Completer<bool> result;
  ShowHistoryRequestDialogEvent(this.reason) : result = Completer<bool>();
}

class ShowOsToolConfirmationEvent extends ChatEvent {
  final String toolName;
  final Map<String, dynamic> args;
  final dynamic risk;
  final Completer<bool> result;
  ShowOsToolConfirmationEvent(this.toolName, this.args, this.risk) : result = Completer<bool>();
}

class CloseScreenEvent extends ChatEvent {}

class AgentInfoUpdatedEvent extends ChatEvent {
  final String? name;
  final String? avatar;
  AgentInfoUpdatedEvent(this.name, this.avatar);
}

// ---------------------------------------------------------------------------
// ChatController
// ---------------------------------------------------------------------------

class ChatController extends ChangeNotifier with InteractiveStreamingContext {
  // ---- Constructor parameters ----
  final String? agentId;
  final String? initialAgentName;
  final String? initialAgentAvatar;
  final String? initialChannelId;
  final bool embedded;
  final VoidCallback? onClose;
  final ValueChanged<String>? onSwitchChannel;
  final String Function() getUserId;
  final String Function() getUserName;

  // ---- Services ----
  late final ChatService chatService;
  late final AttachmentService attachmentService;
  late final MessageSearchService searchService;
  late final LocalDatabaseService localDatabaseService;
  late final InteractiveResponseHandler interactiveResponseHandler;

  // ---- Event stream ----
  final _eventController = StreamController<ChatEvent>.broadcast();
  Stream<ChatEvent> get events => _eventController.stream;

  // ---- Core message state ----
  List<Message> messages = [];
  Map<String, Message> messageIdMap = {};
  bool isLoading = false;
  bool isSearching = false;
  String searchQuery = '';

  // ---- Streaming state ----
  String? streamingMessageId;
  String streamingContent = '';

  // ---- Processing / queue ----
  bool isProcessing = false;
  ACPCancellationToken? acpCancellationToken;
  List<String> messageQueue = [];

  // ---- Agent health state ----
  bool isAgentOnline = false;
  bool isCheckingHealth = true;
  Timer? _healthCheckTimer;

  // ---- Reply state ----
  Message? replyingToMessage;
  String? highlightedMessageId;

  // ---- Channel / lifecycle ----
  String? currentChannelId;
  bool isAppActive = true;
  int? backgroundedAtMs;

  // ---- History request tracking ----
  int historySentCount = 40;
  String? lastUserQuestion;
  Map<String, dynamic>? pendingHistoryRequest;

  // ---- Mutable agent info ----
  String? agentName;
  String? agentAvatar;

  // ---- Group mode state ----
  bool isGroupMode = false;
  Channel? groupChannel;
  List<RemoteAgent> groupAgents = [];
  Set<String> respondingAgentNames = {};
  bool mentionOnlyMode = false;
  String? groupAdminAgentId;
  Set<String> groupStreamingMessageIds = {};

  // ---- Frame coalescing ----
  bool _pendingStreamingRebuild = false;

  ChatController({
    required this.agentId,
    this.initialAgentName,
    this.initialAgentAvatar,
    this.initialChannelId,
    this.embedded = false,
    this.onClose,
    this.onSwitchChannel,
    required this.getUserId,
    required this.getUserName,
  }) {
    agentName = initialAgentName;
    agentAvatar = initialAgentAvatar;

    final databaseService = LocalDatabaseService();
    localDatabaseService = databaseService;
    chatService = ChatService();
    attachmentService = AttachmentService(
      LocalFileStorageService(),
      databaseService,
    );
    searchService = MessageSearchService(databaseService);
    interactiveResponseHandler = InteractiveResponseHandler(this);
  }

  /// Initialize the controller. Call this after constructing.
  Future<void> init() async {
    await loadMessages();
    refreshAgentStatus();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      refreshAgentStatus();
    });
  }

  @override
  void dispose() {
    AppLifecycleService().setActiveChannel(null);
    if (currentChannelId != null) {
      chatService.detachTaskUI(currentChannelId!);
      chatService.detachGroupTaskUI(currentChannelId!);
    }
    messageQueue.clear();
    _healthCheckTimer?.cancel();
    if (currentChannelId != null) {
      chatService.closeChannelStream(currentChannelId!);
    }
    _eventController.close();
    super.dispose();
  }

  void _emit(ChatEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  void _notify() => notifyListeners();

  // ---- InteractiveStreamingContext implementation ----
  @override
  void notifyUI() => _notify();

  @override
  void emitScrollToBottom({bool force = false}) =>
      _emit(RequestScrollToBottomEvent(force: force));

  @override
  void emitError(String message) => _emit(ShowErrorSnackBarEvent(message));

  @override
  bool get isMounted => !_eventController.isClosed;

  /// Add a message to the local list and notify listeners. Used by the UI shell
  /// for voice messages and other locally-generated messages.
  void addLocalMessage(Message message) {
    messages.add(message);
    messageIdMap[message.id] = message;
    _notify();
  }

  /// Update the group channel and notify listeners.
  void updateGroupChannelInfo(Channel updated) {
    groupChannel = updated;
    _notify();
  }

  // ---------------------------------------------------------------------------
  // App lifecycle
  // ---------------------------------------------------------------------------

  void onAppLifecycleChanged(bool resumed) {
    final wasActive = isAppActive;
    isAppActive = resumed;

    if (!resumed) {
      backgroundedAtMs ??= DateTime.now().millisecondsSinceEpoch;
    }

    if (resumed && !wasActive) {
      // Delay DB writes slightly — on iOS the SQLite file handle may still be
      // readonly for a brief moment after the app returns from background.
      Future.delayed(const Duration(milliseconds: 500), () {
        markMessagesAsReadIfAtBottom();
        handleResumeFromBackground();
      });
    }
  }

  Future<void> handleResumeFromBackground() async {
    final bgMs = backgroundedAtMs;
    backgroundedAtMs = null;
    if (bgMs == null || currentChannelId == null) return;

    final duration = Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch - bgMs,
    );

    try {
      await chatService.handleAppResumed(duration);
    } catch (e) {
      // Database may still be recovering from background on iOS.
      print('[ChatController] handleAppResumed failed: $e');
      return;
    }
    await Future.delayed(const Duration(milliseconds: 200));

    final interruptedInfo = chatService.getInterruptedTaskInfo(currentChannelId!);
    if (interruptedInfo != null) {
      chatService.clearInterruptedTaskInfo(currentChannelId!);

      streamingMessageId = null;
      streamingContent = '';
      isProcessing = false;
      _notify();

      await reloadMessagesFromDB();

      _emit(ShowRetrySnackBarEvent(
        'chat_connectionInterrupted',
        'chat_connectionInterruptedRetry',
        interruptedInfo,
      ));
    }
  }

  Future<void> retryLastUserMessage(Map<String, String> interruptedInfo) async {
    if (currentChannelId == null) return;

    final userMsgId = interruptedInfo['userMessageId'];
    if (userMsgId == null) return;

    String? messageContent;
    for (final msg in messages.reversed) {
      if (msg.id == userMsgId) {
        messageContent = msg.content;
        break;
      }
    }

    if (messageContent == null) {
      final dbMessages = await chatService.loadChannelMessages(currentChannelId!);
      for (final msg in dbMessages.reversed) {
        if (msg.id == userMsgId) {
          messageContent = msg.content;
          break;
        }
      }
    }

    if (messageContent != null && messageContent.isNotEmpty) {
      if (isGroupMode) {
        await processGroupMessage(messageContent);
      } else {
        await processMessage(messageContent);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Message loading
  // ---------------------------------------------------------------------------

  Future<void> loadMessages() async {
    isLoading = true;
    _notify();

    try {
      final userId = getUserId();

      if (initialChannelId != null && currentChannelId == null) {
        currentChannelId = initialChannelId;
      } else if (agentId != null && currentChannelId == null) {
        final latestChannelId = await chatService.getLatestActiveChannelId(userId, agentId!);
        currentChannelId = latestChannelId ?? chatService.generateChannelId(userId, agentId!);
      } else if (agentId == null && currentChannelId == null) {
        isLoading = false;
        _notify();
        return;
      }

      AppLifecycleService().setActiveChannel(currentChannelId);
      NotificationService().cancelNotification(currentChannelId.hashCode);

      // Detect group mode & resolve agent info from channel metadata
      final channel = await localDatabaseService.getChannelById(currentChannelId!);
      if (channel != null && channel.isGroup) {
        isGroupMode = true;
        groupChannel = channel;
        final agentIds = channel.memberIds.where((id) => id != userId && id != 'user').toList();
        final agents = <RemoteAgent>[];
        for (final aid in agentIds) {
          final agent = await localDatabaseService.getRemoteAgentById(aid);
          if (agent != null) agents.add(agent);
        }
        groupAgents = agents;
        groupAdminAgentId = channel.adminAgentId;
      } else if (channel != null && !channel.isGroup && agentName == null) {
        // Resolve agent name/avatar from channel when not provided
        // (e.g. navigating from search results by channelId only)
        final agentMember = channel.members.where((m) => m.isAgent).toList();
        if (agentMember.isNotEmpty) {
          final agent = await localDatabaseService.getRemoteAgentById(agentMember.first.id);
          if (agent != null) {
            agentName = agent.name;
            agentAvatar = agent.avatar;
          }
        }
      }

      final loadedMessages = await chatService.loadChannelMessages(currentChannelId!);

      messages = loadedMessages;
      rebuildMessageIdMap();
      isLoading = false;
      _notify();

      markMessagesAsReadIfAtBottom();

      _emit(RequestScrollToBottomEvent(force: true));

      if (!isGroupMode) {
        reattachToActiveTask();
      }
      if (isGroupMode) {
        reattachToGroupActiveTasks();
      }
    } catch (e) {
      isLoading = false;
      _notify();
      _emit(ShowErrorSnackBarEvent('chat_loadFailed:$e'));
    }
  }

  Future<void> reloadMessagesFromDB() async {
    if (currentChannelId == null) return;
    final dbMessages = await chatService.loadChannelMessages(currentChannelId!);
    messages.clear();
    messageIdMap.clear();
    for (final m in dbMessages) {
      messages.add(m);
      messageIdMap[m.id] = m;
    }
    _notify();
  }

  void rebuildMessageIdMap() {
    messageIdMap = {for (final m in messages) m.id: m};
  }

  // ---------------------------------------------------------------------------
  // Agent health
  // ---------------------------------------------------------------------------

  Future<void> refreshAgentStatus() async {
    if (agentId == null) return;
    try {
      final agent = await localDatabaseService.getAgentById(agentId!);
      if (agent != null) {
        isAgentOnline = agent.status.isOnline;
        isCheckingHealth = false;
        _notify();
      }
    } catch (_) {
      isCheckingHealth = false;
      _notify();
    }
  }

  // ---------------------------------------------------------------------------
  // Read status
  // ---------------------------------------------------------------------------

  bool isUserScrolledUp = false;
  int unreadMessageCount = 0;

  Future<void> markMessagesAsReadIfAtBottom() async {
    if (currentChannelId == null) return;
    if (!isAppActive) return;
    if (isUserScrolledUp) return;
    try {
      await localDatabaseService.markChannelMessagesAsRead(currentChannelId!);
    } catch (e) {
      // On iOS, SQLite can be temporarily readonly after returning from
      // background. Swallow the error — messages will be marked read on the
      // next successful attempt.
      print('[ChatController] markMessagesAsRead failed (db may be recovering): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Reattach to background tasks
  // ---------------------------------------------------------------------------

  void reattachToActiveTask() {
    if (currentChannelId == null) return;

    final activeTask = chatService.getActiveTask(currentChannelId!);
    if (activeTask == null) return;

    streamingContent = activeTask.accumulatedContent;
    streamingMessageId = 'streaming_reattach_${DateTime.now().millisecondsSinceEpoch}';

    final streamingMessage = Message(
      id: streamingMessageId!,
      content: streamingContent,
      timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
      from: MessageFrom(id: activeTask.agentId, type: 'agent', name: activeTask.agentName),
      to: MessageFrom(id: activeTask.userId, type: 'user', name: activeTask.userName),
      type: MessageType.text,
    );

    isProcessing = true;
    messages.add(streamingMessage);
    messageIdMap[streamingMessage.id] = streamingMessage;
    _notify();
    _emit(RequestScrollToBottomEvent(force: true));

    acpCancellationToken = ACPCancellationToken();

    chatService.attachTaskUI(
      currentChannelId!,
      onStreamChunk: (chunk) {
        streamingContent += chunk;
        final idx = messages.indexWhere((m) => m.id == streamingMessageId);
        if (idx != -1) {
          final updated = Message(
            id: streamingMessageId!,
            content: streamingContent,
            timestampMs: messages[idx].timestampMs,
            from: messages[idx].from,
            to: messages[idx].to,
            type: messages[idx].type,
          );
          messages[idx] = updated;
          messageIdMap[updated.id] = updated;
        }
        _notify();
        _emit(RequestScrollToBottomEvent());
      },
      onMessageMetadata: (metadata) {
        final idx = messages.indexWhere((m) => m.id == streamingMessageId);
        if (idx != -1) {
          final existingMetadata = Map<String, dynamic>.from(messages[idx].metadata ?? {});
          existingMetadata.addAll(metadata);
          final updated = Message(
            id: streamingMessageId!,
            content: messages[idx].content,
            timestampMs: messages[idx].timestampMs,
            from: messages[idx].from,
            to: messages[idx].to,
            type: messages[idx].type,
            metadata: existingMetadata,
          );
          messages[idx] = updated;
          messageIdMap[updated.id] = updated;
        }
        _notify();
      },
      onTaskFinished: () async {
        await activeTask.dbSaveCompleter.future;
        acpCancellationToken = null;
        streamingMessageId = null;
        streamingContent = '';
        await loadMessages();
        isProcessing = false;
        _notify();
      },
    );
  }

  void reattachToGroupActiveTasks() {
    if (currentChannelId == null) return;

    final activeTasks = chatService.getActiveGroupTasks(currentChannelId!);
    if (activeTasks.isEmpty) return;

    final streamingIds = <String, String>{};
    final streamingContents = <String, String>{};

    for (final entry in activeTasks.entries) {
      final aid = entry.key;
      final task = entry.value;
      final sid = 'group_streaming_${aid}_${DateTime.now().millisecondsSinceEpoch}';
      streamingIds[aid] = sid;
      streamingContents[aid] = task.accumulatedContent;

      final streamingMessage = Message(
        id: sid,
        content: task.accumulatedContent,
        timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
        from: MessageFrom(id: aid, type: 'agent', name: task.agentName),
        type: MessageType.text,
      );

      isProcessing = true;
      respondingAgentNames.add(task.agentName);
      groupStreamingMessageIds.add(sid);
      messages.add(streamingMessage);
      messageIdMap[streamingMessage.id] = streamingMessage;
    }
    _notify();
    _emit(RequestScrollToBottomEvent(force: true));

    chatService.attachGroupTaskUI(
      currentChannelId!,
      onStreamChunk: (aid, agentNameVal, chunk) {
        final sid = streamingIds[aid];
        if (sid == null) return;
        streamingContents[aid] = (streamingContents[aid] ?? '') + chunk;
        final updatedContent = streamingContents[aid]!;
        final existing = messageIdMap[sid];
        if (existing != null) {
          final idx = messages.indexOf(existing);
          if (idx != -1) {
            final updated = Message(
              id: sid,
              content: updatedContent,
              timestampMs: messages[idx].timestampMs,
              from: messages[idx].from,
              to: messages[idx].to,
              type: MessageType.text,
            );
            messages[idx] = updated;
            messageIdMap[updated.id] = updated;
          }
        }
        scheduleStreamingRebuild();
        _emit(RequestScrollToBottomEvent());
      },
      onTaskFinished: (aid, agentNameVal) {
        final sid = streamingIds[aid];
        if (sid != null) {
          groupStreamingMessageIds.remove(sid);
        }
        streamingIds.remove(aid);
        streamingContents.remove(aid);
        respondingAgentNames.remove(agentNameVal);
        _notify();

        if (streamingIds.isEmpty) {
          reconcileGroupMessages().then((_) {
            isProcessing = false;
            respondingAgentNames.clear();
            groupStreamingMessageIds.clear();
            _notify();
          });
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Sending messages
  // ---------------------------------------------------------------------------

  Future<void> sendMessage({
    required String content,
    required List<PendingAttachment> pendingAttachments,
    required VoidCallback clearMessageController,
    String? replyToId,
  }) async {
    final hasPendingAttachments = pendingAttachments.isNotEmpty;
    print('[ChatController] User sending message');

    if (content.isEmpty && !hasPendingAttachments) return;

    if (!isGroupMode && agentId == null) {
      _emit(ShowSnackBarEvent('chat_noAgentSelected'));
      return;
    }

    final attachmentsToSend = List<PendingAttachment>.from(pendingAttachments);
    pendingAttachments.clear();

    clearMessageController();

    // Capture reply state
    final capturedReplyToId = replyToId ?? replyingToMessage?.id;
    cancelReply();

    // Save all pending attachments and build AttachmentData list
    final savedAttachmentMessages = <Message>[];
    final attachmentDataList = <AttachmentData>[];
    if (attachmentsToSend.isNotEmpty) {
      final userId = getUserId();
      final userName = getUserName();

      for (final att in attachmentsToSend) {
        final message = await attachmentService.saveAttachment(
          file: att.file,
          channelId: currentChannelId ?? '',
          userId: userId,
          userName: userName,
          agentId: agentId ?? '',
        );
        if (att.isFromClipboard) {
          try { att.file.deleteSync(); } catch (_) {}
        }
        if (message != null) {
          messages.add(message);
          messageIdMap[message.id] = message;
          _notify();
          _emit(RequestScrollToBottomEvent(force: true));
          savedAttachmentMessages.add(message);

          final attData = await attachmentService.buildAttachmentData(message);
          if (attData != null && !attData.exceedsSizeLimit) {
            attachmentDataList.add(attData);
          }
        }
      }
    }

    final hasAttachments = attachmentDataList.isNotEmpty;

    // If only attachments (no text), send each attachment individually
    if (content.isEmpty) {
      if (hasAttachments && !isGroupMode) {
        for (final msg in savedAttachmentMessages) {
          await sendAttachmentToAgent(msg);
        }
      }
      return;
    }

    // Queue if processing
    if (isProcessing) {
      if (hasAttachments && !isGroupMode) {
        for (final msg in savedAttachmentMessages) {
          await sendAttachmentToAgent(msg);
        }
      }
      messageQueue.add(content);
      _notify();
      return;
    }

    if (isGroupMode) {
      print('[ChatController] sendMessage -> processGroupMessage (isGroupMode=true, groupAgents=${groupAgents.length}, adminId=$groupAdminAgentId)');
      await processGroupMessage(content, replyToId: capturedReplyToId, attachments: hasAttachments ? attachmentDataList : null);
    } else {
      await processMessage(content, replyToId: capturedReplyToId, attachments: hasAttachments ? attachmentDataList : null, attachmentMessages: hasAttachments ? savedAttachmentMessages : null);
    }
  }

  void stopStreaming() {
    print('[ChatController] Stopping streaming');

    if (streamingMessageId != null) {
      final stoppedId = streamingMessageId!;
      final idx = messages.indexWhere((m) => m.id == stoppedId);
      if (idx != -1) {
        final current = messages[idx];
        final stoppedContent = streamingContent.isNotEmpty
            ? '$streamingContent\n\n[Stopped]'
            : '[Stopped]';
        messages[idx] = Message(
          id: current.id,
          content: stoppedContent,
          timestampMs: current.timestampMs,
          from: current.from,
          to: current.to,
          type: current.type,
          metadata: current.metadata,
        );
        messageIdMap[current.id] = messages[idx];
      }
      streamingMessageId = null;
      streamingContent = '';
      _notify();
    }

    acpCancellationToken?.cancel();
  }

  void stopGroupStreaming() {
    print('[ChatController] Stopping group streaming');

    // Mark all active group streaming messages with [Stopped]
    for (final sid in groupStreamingMessageIds) {
      final existing = messageIdMap[sid];
      if (existing != null) {
        final idx = messages.indexOf(existing);
        if (idx != -1) {
          final current = messages[idx];
          final stoppedContent = current.content.isNotEmpty
              ? '${current.content}\n\n[Stopped]'
              : '[Stopped]';
          final updated = Message(
            id: current.id,
            content: stoppedContent,
            timestampMs: current.timestampMs,
            from: current.from,
            to: current.to,
            type: current.type,
            metadata: current.metadata,
          );
          messages[idx] = updated;
          messageIdMap[updated.id] = updated;
        }
      }
    }

    // Cancel the cancellation token to stop all active agent tasks
    acpCancellationToken?.cancel();

    // Reset group streaming state
    respondingAgentNames.clear();
    groupStreamingMessageIds.clear();
    isProcessing = false;
    _notify();
  }

  Future<void> processNextInQueue() async {
    if (messageQueue.isEmpty) return;

    final nextContent = messageQueue.removeAt(0);
    _notify();
    if (isGroupMode) {
      await processGroupMessage(nextContent);
    } else {
      await processMessage(nextContent);
    }
  }

  // ---------------------------------------------------------------------------
  // Process DM message
  // ---------------------------------------------------------------------------

  Future<void> processMessage(String content, {String? replyToId, List<AttachmentData>? attachments, List<Message>? attachmentMessages}) async {
    final userId = getUserId();
    final userName = getUserName();

    isProcessing = true;
    _notify();

    lastUserQuestion = content;
    acpCancellationToken = ACPCancellationToken();

    try {
      final remoteAgent = await localDatabaseService.getRemoteAgentById(agentId!);
      if (remoteAgent == null) throw Exception('Agent not found');

      final isLocal = LocalLLMAgentService.instance.isLocalAgent(remoteAgent);

      if (!isLocal && remoteAgent.endpoint.isEmpty) {
        throw Exception('Agent has no valid endpoint');
      }

      if (!isLocal && !remoteAgent.isOnline) {
        final remoteAgentService = RemoteAgentService(
          localDatabaseService,
          TokenService(localDatabaseService),
        );

        _emit(ShowSnackBarEvent('chat_checkingHealth'));

        final isOnline = await remoteAgentService.checkAgentHealth(agentId!);
        if (!isOnline) {
          throw Exception('Agent is not online. Please check if the agent server is running.');
        }

        final updatedAgent = await localDatabaseService.getRemoteAgentById(agentId!);
        if (updatedAgent == null || !updatedAgent.isOnline) {
          throw Exception('Failed to connect to agent');
        }
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

      streamingMessageId = 'streaming_${DateTime.now().millisecondsSinceEpoch}';
      streamingContent = '';
      final streamingMessage = Message(
        id: streamingMessageId!,
        content: '',
        timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
        from: MessageFrom(id: remoteAgent.id, type: 'agent', name: remoteAgent.name),
        to: MessageFrom(id: userId, type: 'user', name: userName),
        type: MessageType.text,
      );

      messages.add(userMessage);
      messages.add(streamingMessage);
      messageIdMap[userMessage.id] = userMessage;
      messageIdMap[streamingMessage.id] = streamingMessage;
      _notify();
      _emit(RequestScrollToBottomEvent(force: true));

      if (currentChannelId != null) {
        final currentMessages = await chatService.loadChannelMessages(
          currentChannelId!, limit: 40,
        );
        historySentCount = currentMessages.where((m) => m.type == MessageType.text).length;
      }

      final agentResponse = await chatService.sendMessageToAgent(
        content: content,
        agent: remoteAgent,
        userId: userId,
        userName: userName,
        channelId: currentChannelId,
        replyToId: replyToId,
        acpCancellationToken: acpCancellationToken,
        attachments: attachments,
        onOsToolConfirmation: (toolName, args, risk) async {
          final event = ShowOsToolConfirmationEvent(toolName, args, risk);
          _emit(event);
          return await event.result.future;
        },
        onStreamChunk: (chunk) {
          streamingContent += chunk;
          final idx = messages.indexWhere((m) => m.id == streamingMessageId);
          if (idx != -1) {
            final updated = Message(
              id: streamingMessageId!,
              content: streamingContent,
              timestampMs: messages[idx].timestampMs,
              from: messages[idx].from,
              to: messages[idx].to,
              type: MessageType.text,
              metadata: messages[idx].metadata,
            );
            messages[idx] = updated;
            messageIdMap[updated.id] = updated;
          }
          _notify();
          _emit(RequestScrollToBottomEvent());
        },
        onActionConfirmation: (actionData) {
          final idx = messages.indexWhere((m) => m.id == streamingMessageId);
          if (idx != -1) {
            final updated = Message(
              id: streamingMessageId!,
              content: streamingContent,
              timestampMs: messages[idx].timestampMs,
              from: messages[idx].from,
              to: messages[idx].to,
              type: MessageType.text,
              metadata: {'action_confirmation': Map<String, dynamic>.from(actionData)},
            );
            messages[idx] = updated;
            messageIdMap[updated.id] = updated;
          }
          _notify();
        },
        onSingleSelect: (selectData) {
          _updateStreamingMetadata({'single_select': Map<String, dynamic>.from(selectData)});
        },
        onMultiSelect: (selectData) {
          _updateStreamingMetadata({'multi_select': Map<String, dynamic>.from(selectData)});
        },
        onFileUpload: (uploadData) {
          _updateStreamingMetadata({'file_upload': Map<String, dynamic>.from(uploadData)});
        },
        onForm: (formData) {
          _updateStreamingMetadata({'form': Map<String, dynamic>.from(formData)});
        },
        onFileMessage: (fileData) async {
          await _handleFileMessage(fileData);
        },
        onMessageMetadata: (metadata) {
          final idx = messages.indexWhere((m) => m.id == streamingMessageId);
          if (idx != -1) {
            final existingMetadata = Map<String, dynamic>.from(messages[idx].metadata ?? {});
            existingMetadata.addAll(metadata);
            final updated = Message(
              id: streamingMessageId!,
              content: messages[idx].content,
              timestampMs: messages[idx].timestampMs,
              from: messages[idx].from,
              to: messages[idx].to,
              type: messages[idx].type,
              metadata: existingMetadata,
            );
            messages[idx] = updated;
            messageIdMap[updated.id] = updated;
          }
          _notify();
        },
        onRequestHistory: (historyData) {
          pendingHistoryRequest = Map<String, dynamic>.from(historyData);
        },
      );

      // Handle pending history request
      bool handledHistorySupplement = false;
      if (pendingHistoryRequest != null) {
        final historyData = pendingHistoryRequest!;
        pendingHistoryRequest = null;

        if (agentResponse != null) {
          try { await chatService.deleteMessage(agentResponse.id); } catch (_) {}
        }

        final reason = historyData['reason'] as String? ?? 'Agent needs more context';
        final requestId = historyData['request_id'] as String? ?? '';
        final requestedCount = historyData['requested_count'] as int? ?? 40;

        addSystemHint('$reason');

        final dialogEvent = ShowHistoryRequestDialogEvent(reason);
        _emit(dialogEvent);
        final approved = await dialogEvent.result.future;

        if (approved) {
          handledHistorySupplement = true;
          addSystemHint('Loading more chat history...');

          streamingMessageId = 'streaming_reanswer_${DateTime.now().millisecondsSinceEpoch}';
          streamingContent = '';
          acpCancellationToken = ACPCancellationToken();

          final reanswer = Message(
            id: streamingMessageId!,
            content: '',
            timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
            from: MessageFrom(id: remoteAgent.id, type: 'agent', name: remoteAgent.name),
            to: MessageFrom(id: userId, type: 'user', name: userName),
            type: MessageType.text,
          );
          messages.add(reanswer);
          messageIdMap[reanswer.id] = reanswer;
          _notify();
          _emit(RequestScrollToBottomEvent(force: true));

          int currentRequestedCount = requestedCount;
          const int maxSupplementRounds = 3;
          try {
            for (int round = 0; round < maxSupplementRounds; round++) {
              final supplementResult = await chatService.sendHistorySupplement(
                agent: remoteAgent,
                sessionId: currentChannelId!,
                requestId: requestId,
                originalQuestion: lastUserQuestion ?? '',
                offset: historySentCount,
                batchSize: currentRequestedCount,
                onStreamChunk: (chunk) {
                  streamingContent += chunk;
                  final idx = messages.indexWhere((m) => m.id == streamingMessageId);
                  if (idx != -1) {
                    final updated = Message(
                      id: streamingMessageId!,
                      content: streamingContent,
                      timestampMs: messages[idx].timestampMs,
                      from: messages[idx].from,
                      to: messages[idx].to,
                      type: MessageType.text,
                    );
                    messages[idx] = updated;
                    messageIdMap[updated.id] = updated;
                  }
                  _notify();
                  _emit(RequestScrollToBottomEvent());
                },
                acpCancellationToken: acpCancellationToken,
              );

              if (supplementResult == null) {
                addSystemHint('No more history records available');
                messages.removeWhere((m) => m.id == streamingMessageId);
                messageIdMap.remove(streamingMessageId);
                _notify();
                break;
              }

              historySentCount += supplementResult.actualSentCount;

              if (supplementResult.pendingHistoryRequest != null) {
                final nextReason = supplementResult.pendingHistoryRequest!['reason'] as String? ?? 'Agent needs more context';
                currentRequestedCount = supplementResult.pendingHistoryRequest!['requested_count'] as int? ?? 40;
                if (supplementResult.message.content.isEmpty) {
                  try { await chatService.deleteMessage(supplementResult.message.id); } catch (_) {}
                }
                addSystemHint(nextReason);
                addSystemHint('Loading more chat history...');
                streamingContent = '';
                acpCancellationToken = ACPCancellationToken();
                continue;
              }

              addSystemHint('History loaded, agent is re-answering...');
              break;
            }
          } catch (e) {
            addSystemHint('Failed to load history: $e');
            messages.removeWhere((m) => m.id == streamingMessageId);
            messageIdMap.remove(streamingMessageId);
            _notify();
          }
        } else {
          addSystemHint('History request ignored');
        }
      }

      if (!handledHistorySupplement && agentResponse == null) {
        _emit(ShowSnackBarEvent('chat_responseError'));
      }

      isAgentOnline = true;
      _notify();
      await loadMessages();
    } catch (e, stackTrace) {
      print('[ChatController] Send message failed: $e\n$stackTrace');
      messageQueue.clear();
      await loadMessages();
      _emit(ShowErrorSnackBarEvent('$e'));
    } finally {
      acpCancellationToken = null;
      streamingMessageId = null;
      streamingContent = '';
      pendingHistoryRequest = null;
      isProcessing = false;
      _notify();
      processNextInQueue();
    }
  }

  void _updateStreamingMetadata(Map<String, dynamic> metadata) {
    final idx = messages.indexWhere((m) => m.id == streamingMessageId);
    if (idx != -1) {
      final updated = Message(
        id: streamingMessageId!,
        content: streamingContent,
        timestampMs: messages[idx].timestampMs,
        from: messages[idx].from,
        to: messages[idx].to,
        type: MessageType.text,
        metadata: metadata,
      );
      messages[idx] = updated;
      messageIdMap[updated.id] = updated;
    }
    _notify();
  }

  Future<void> _handleFileMessage(Map<String, dynamic> fileData) async {
    try {
      final url = fileData['url'] as String?;
      final filename = fileData['filename'] as String?;
      final fileMimeType = fileData['mime_type'] as String?;
      final size = fileData['size'] as int?;
      final thumbnailBase64 = fileData['thumbnail_base64'] as String?;

      if (url == null || url.isEmpty) return;

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

      final currentAgentName = agentName ?? 'Agent';
      final messageId = 'file_${DateTime.now().millisecondsSinceEpoch}';
      await localDatabaseService.createMessage(
        id: messageId,
        channelId: currentChannelId ?? '',
        senderId: agentId ?? '',
        senderType: 'agent',
        senderName: currentAgentName,
        content: isImage
            ? '[Image: ${filename ?? "image"}]'
            : '[File: ${filename ?? "file"}]',
        messageType: msgType.toString().split('.').last,
        metadata: metadata,
      );

      await loadMessages();
    } catch (e) {
      _emit(ShowErrorSnackBarEvent('chat_fileMessageFailed:$e'));
    }
  }

  // ---------------------------------------------------------------------------
  // Process group message
  // ---------------------------------------------------------------------------

  Future<void> processGroupMessage(String content, {String? replyToId, List<AttachmentData>? attachments}) async {
    if (currentChannelId == null || groupAgents.isEmpty) {
      print('[ChatController] processGroupMessage ABORTED: channelId=$currentChannelId, groupAgents=${groupAgents.length}');
      return;
    }
    print('[ChatController] processGroupMessage: channelId=$currentChannelId, agents=${groupAgents.map((a) => a.name).toList()}, adminId=$groupAdminAgentId');

    final userId = getUserId();
    final userName = getUserName();

    isProcessing = true;
    acpCancellationToken = ACPCancellationToken();
    _notify();

    final userMessage = Message(
      id: 'temp_user_${DateTime.now().millisecondsSinceEpoch}',
      content: content,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      from: MessageFrom(id: userId, type: 'user', name: userName),
      type: MessageType.text,
      replyTo: replyToId,
    );
    messages.add(userMessage);
    messageIdMap[userMessage.id] = userMessage;
    _notify();
    _emit(RequestScrollToBottomEvent(force: true));

    final streamingIds = <String, String>{};
    final streamingContents = <String, String>{};

    try {
      final agentIds = groupAgents.map((a) => a.id).toList();
      final mentionedAgentIds = parseMentionedAgentIds(content);

      await chatService.sendMessageToGroup(
        channelId: currentChannelId!,
        content: content,
        userId: userId,
        userName: userName,
        agentIds: agentIds,
        mentionedAgentIds: mentionedAgentIds,
        mentionOnlyMode: mentionOnlyMode,
        adminAgentId: groupAdminAgentId,
        replyToId: replyToId,
        acpCancellationToken: acpCancellationToken,
        onAgentStart: (aid, anm) {
          final sid = 'group_streaming_${aid}_${DateTime.now().millisecondsSinceEpoch}';
          streamingIds[aid] = sid;
          streamingContents[aid] = '';
          final sm = Message(
            id: sid,
            content: '',
            timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
            from: MessageFrom(id: aid, type: 'agent', name: anm),
            to: MessageFrom(id: userId, type: 'user', name: userName),
            type: MessageType.text,
          );
          respondingAgentNames.add(anm);
          groupStreamingMessageIds.add(sid);
          messages.add(sm);
          messageIdMap[sm.id] = sm;
          _notify();
          _emit(RequestScrollToBottomEvent(force: true));
        },
        onStreamChunk: (aid, anm, chunk) {
          final sid = streamingIds[aid];
          if (sid == null) return;
          streamingContents[aid] = (streamingContents[aid] ?? '') + chunk;
          final updatedContent = streamingContents[aid]!;
          final existing = messageIdMap[sid];
          if (existing != null) {
            final idx = messages.indexOf(existing);
            if (idx != -1) {
              final updated = Message(
                id: sid,
                content: updatedContent,
                timestampMs: messages[idx].timestampMs,
                from: messages[idx].from,
                to: messages[idx].to,
                type: MessageType.text,
              );
              messages[idx] = updated;
              messageIdMap[updated.id] = updated;
            }
          }
          scheduleStreamingRebuild();
          _emit(RequestScrollToBottomEvent());
        },
        onAgentDone: (aid, anm, skipped) {
          final sid = streamingIds[aid];
          if (skipped && sid != null) {
            messages.removeWhere((m) => m.id == sid);
            messageIdMap.remove(sid);
            groupStreamingMessageIds.remove(sid);
          } else if (sid != null) {
            groupStreamingMessageIds.remove(sid);
          }
          streamingIds.remove(aid);
          streamingContents.remove(aid);
          respondingAgentNames.remove(anm);
          _notify();
        },
        onAllDone: () {},
      );

      await reconcileGroupMessages();
      markMessagesAsReadIfAtBottom();
    } catch (e, stackTrace) {
      print('[ChatController] processGroupMessage error: $e\n$stackTrace');
      _emit(ShowErrorSnackBarEvent('chat_groupChatError:$e'));
    } finally {
      acpCancellationToken = null;
      streamingMessageId = null;
      streamingContent = '';
      isProcessing = false;
      respondingAgentNames.clear();
      groupStreamingMessageIds.clear();
      _notify();
      processNextInQueue();
    }
  }

  // ---------------------------------------------------------------------------
  // Send attachment to agent
  // ---------------------------------------------------------------------------

  Future<void> sendAttachmentToAgent(Message attachmentMessage) async {
    final attachmentData = await attachmentService.buildAttachmentData(attachmentMessage);
    if (attachmentData == null) return;
    if (attachmentData.exceedsSizeLimit) {
      _emit(ShowSnackBarEvent('File too large (max 20MB) to send to agent'));
      return;
    }

    final userId = getUserId();
    final userName = getUserName();

    isProcessing = true;
    _notify();

    acpCancellationToken = ACPCancellationToken();

    try {
      final remoteAgent = await localDatabaseService.getRemoteAgentById(agentId!);
      if (remoteAgent == null) throw Exception('Agent not found');

      final isLocal = LocalLLMAgentService.instance.isLocalAgent(remoteAgent);
      if (!isLocal && remoteAgent.endpoint.isEmpty) {
        throw Exception('Agent has no valid endpoint');
      }

      streamingMessageId = 'streaming_${DateTime.now().millisecondsSinceEpoch}';
      streamingContent = '';
      final sm = Message(
        id: streamingMessageId!,
        content: '',
        timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
        from: MessageFrom(id: remoteAgent.id, type: 'agent', name: remoteAgent.name),
        to: MessageFrom(id: userId, type: 'user', name: userName),
        type: MessageType.text,
      );

      messages.add(sm);
      messageIdMap[sm.id] = sm;
      _notify();
      _emit(RequestScrollToBottomEvent(force: true));

      final agentResponse = await chatService.sendMessageToAgent(
        content: attachmentMessage.content,
        agent: remoteAgent,
        userId: userId,
        userName: userName,
        channelId: currentChannelId,
        acpCancellationToken: acpCancellationToken,
        attachments: [attachmentData],
        existingUserMessage: attachmentMessage,
        onStreamChunk: (chunk) {
          streamingContent += chunk;
          final idx = messages.indexWhere((m) => m.id == streamingMessageId);
          if (idx != -1) {
            final updated = Message(
              id: streamingMessageId!,
              content: streamingContent,
              timestampMs: messages[idx].timestampMs,
              from: messages[idx].from,
              to: messages[idx].to,
              type: MessageType.text,
              metadata: messages[idx].metadata,
            );
            messages[idx] = updated;
            messageIdMap[updated.id] = updated;
          }
          _notify();
          _emit(RequestScrollToBottomEvent());
        },
      );

      if (agentResponse != null) {
        final idx = messages.indexWhere((m) => m.id == streamingMessageId);
        if (idx != -1) {
          messages[idx] = agentResponse;
          messageIdMap.remove(streamingMessageId);
          messageIdMap[agentResponse.id] = agentResponse;
        }
        _notify();
      } else {
        messages.removeWhere((m) => m.id == streamingMessageId);
        messageIdMap.remove(streamingMessageId);
        _notify();
      }
    } catch (e) {
      messages.removeWhere((m) => m.id == streamingMessageId);
      messageIdMap.remove(streamingMessageId);
      _notify();
    } finally {
      streamingMessageId = null;
      streamingContent = '';
      isProcessing = false;
      _notify();
    }
  }

  // ---------------------------------------------------------------------------
  // Interactive response handlers (delegates to InteractiveResponseHandler)
  // ---------------------------------------------------------------------------

  Future<void> handleActionSelected(
    Message originalMessage,
    String confirmationId,
    String actionId,
    String actionLabel, {
    String? confirmationContext,
  }) async {
    if (isProcessing) return;
    try {
      await interactiveResponseHandler.handleActionConfirmation(
        originalMessage: originalMessage,
        confirmationId: confirmationId,
        actionId: actionId,
        actionLabel: actionLabel,
        confirmationContext: confirmationContext,
      );
    } catch (e) {
      _emit(ShowErrorSnackBarEvent('$e'));
    }
  }

  Future<void> handleSingleSelectSubmitted(
    Message originalMessage,
    String selectId,
    String optionId,
    String optionLabel,
  ) async {
    if (isProcessing) return;
    try {
      await interactiveResponseHandler.handleSelectResponse(
        originalMessage: originalMessage,
        metadataKey: 'single_select',
        selectedData: {'selected_option_id': optionId},
        responseText: 'Selected: $optionLabel',
      );
    } catch (e) {
      _emit(ShowErrorSnackBarEvent('$e'));
    }
  }

  Future<void> handleMultiSelectSubmitted(
    Message originalMessage,
    String selectId,
    List<String> optionIds,
    String summary,
  ) async {
    if (isProcessing) return;
    try {
      await interactiveResponseHandler.handleSelectResponse(
        originalMessage: originalMessage,
        metadataKey: 'multi_select',
        selectedData: {'selected_option_ids': optionIds},
        responseText: 'Selected: $summary',
      );
    } catch (e) {
      _emit(ShowErrorSnackBarEvent('$e'));
    }
  }

  Future<void> handleFileUploadSubmitted(
    Message originalMessage,
    String uploadId,
    List<Map<String, dynamic>> files,
    String summary,
  ) async {
    if (isProcessing) return;
    try {
      await interactiveResponseHandler.handleSelectResponse(
        originalMessage: originalMessage,
        metadataKey: 'file_upload',
        selectedData: {'uploaded_files': files},
        responseText: 'Uploaded files: $summary',
      );
    } catch (e) {
      _emit(ShowErrorSnackBarEvent('$e'));
    }
  }

  Future<void> handleFormSubmitted(
    Message originalMessage,
    String formId,
    Map<String, dynamic> values,
    String summary,
  ) async {
    if (isProcessing) return;
    try {
      await interactiveResponseHandler.handleSelectResponse(
        originalMessage: originalMessage,
        metadataKey: 'form',
        selectedData: {'submitted_values': values},
        responseText: 'Form submitted: $summary',
      );
    } catch (e) {
      _emit(ShowErrorSnackBarEvent('$e'));
    }
  }

  // ---------------------------------------------------------------------------
  // Reply
  // ---------------------------------------------------------------------------

  void startReply(Message message) {
    replyingToMessage = message;
    _notify();
  }

  void cancelReply() {
    replyingToMessage = null;
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  Future<void> searchMessages(String query) async {
    if (query.trim().isEmpty) {
      searchQuery = '';
      isSearching = false;
      _notify();
      await loadMessages();
      return;
    }

    isSearching = true;
    searchQuery = query;
    _notify();

    try {
      final results = await searchService.searchMessages(
        query: query,
        channelId: currentChannelId,
      );

      messages = results.map((r) => r.message).toList();
      rebuildMessageIdMap();
      isSearching = false;
      _notify();
    } catch (e) {
      isSearching = false;
      _notify();
      _emit(ShowErrorSnackBarEvent('chat_searchError:$e'));
    }
  }

  // ---------------------------------------------------------------------------
  // Message operations
  // ---------------------------------------------------------------------------

  Future<void> deleteMessage(Message message) async {
    if (message.type == MessageType.image || message.type == MessageType.file || message.type == MessageType.audio) {
      await attachmentService.deleteAttachment(message);
    } else {
      await chatService.deleteMessage(message.id);
    }

    messages.removeWhere((m) => m.id == message.id);
    messageIdMap.remove(message.id);
    _notify();
  }

  Future<void> rollbackMessage(Message message, {bool reEdit = false}) async {
    if (agentId == null || currentChannelId == null) return;

    try {
      final remoteAgent = await localDatabaseService.getRemoteAgentById(agentId!);
      if (remoteAgent == null) throw Exception('Agent not found');

      await chatService.rollbackFromMessage(
        messageId: message.id,
        channelId: currentChannelId!,
        agent: remoteAgent,
      );

      await loadMessages();
    } catch (e) {
      _emit(ShowErrorSnackBarEvent('chat_rollbackFailed:$e'));
    }
  }

  // ---------------------------------------------------------------------------
  // Session management
  // ---------------------------------------------------------------------------

  void resetSession(TextEditingController messageController) {
    messageController.text = '/reset';
    // The UI will call sendMessage
  }

  Future<void> createNewSession() async {
    if (agentId == null) return;

    final userId = getUserId();
    final userName = getUserName();

    try {
      final newChannelId = await chatService.createNewSession(
        userId: userId,
        userName: userName,
        agentId: agentId!,
        agentName: agentName ?? 'Agent',
      );

      await localDatabaseService.touchChannelUpdatedAt(newChannelId);

      _emit(NavigateToSessionEvent(
        channelId: newChannelId,
        agentId: agentId,
        agentName: agentName,
        agentAvatar: agentAvatar,
        embedded: embedded,
      ));
    } catch (e) {
      _emit(ShowErrorSnackBarEvent('chat_newSessionFailed:$e'));
    }
  }

  Future<void> createNewGroupSession() async {
    if (groupChannel == null || currentChannelId == null) return;

    final userId = getUserId();

    try {
      final newChannelId = await chatService.createNewGroupSession(
        channelId: currentChannelId!,
        userId: userId,
      );

      await localDatabaseService.touchChannelUpdatedAt(newChannelId);

      _emit(NavigateToSessionEvent(
        channelId: newChannelId,
        embedded: embedded,
      ));
    } catch (e) {
      _emit(ShowErrorSnackBarEvent('chat_newGroupSessionFailed:$e'));
    }
  }

  Future<void> clearCurrentSessionHistory() async {
    if (agentId == null) return;

    final userId = getUserId();
    final userName = getUserName();
    final sessionId = currentChannelId
        ?? await chatService.getLatestActiveChannelId(userId, agentId!)
        ?? chatService.generateChannelId(userId, agentId!);

    _emit(ShowLoadingOverlayEvent('chat_clearingSession'));

    try {
      final remoteAgent = await localDatabaseService.getRemoteAgentById(agentId!);

      if (remoteAgent != null && remoteAgent.isOnline) {
        try {
          await chatService.sendMessageToAgent(
            content: '/reset',
            agent: remoteAgent,
            userId: userId,
            userName: userName,
            channelId: sessionId,
          );
        } catch (_) {}
      }

      final sessions = await chatService.getAgentSessions(agentId: agentId!);

      if (sessions.length > 1) {
        await localDatabaseService.deleteChannelMessages(sessionId);
        await localDatabaseService.deleteChannel(sessionId);

        final remaining = sessions.where((s) => s.id != sessionId).toList();
        final targetSession = remaining.first;

        _emit(DismissOverlayEvent());
        _emit(NavigateToSessionEvent(
          channelId: targetSession.id,
          agentId: agentId,
          agentName: agentName,
          agentAvatar: agentAvatar,
          embedded: embedded,
        ));
      } else {
        await localDatabaseService.deleteChannelMessages(sessionId);

        _emit(DismissOverlayEvent());
        messages.clear();
        messageIdMap.clear();
        _notify();
        _emit(ShowSnackBarEvent('chat_sessionCleared'));
      }
    } catch (e) {
      _emit(DismissOverlayEvent());
      _emit(ShowErrorSnackBarEvent('chat_clearSessionFailed:$e'));
    }
  }

  Future<void> clearAllSessionsHistory() async {
    if (agentId == null) return;

    final userId = getUserId();
    final userName = getUserName();
    final sessionId = currentChannelId
        ?? await chatService.getLatestActiveChannelId(userId, agentId!)
        ?? chatService.generateChannelId(userId, agentId!);

    _emit(ShowLoadingOverlayEvent('chat_clearingAllSessions'));

    try {
      final remoteAgent = await localDatabaseService.getRemoteAgentById(agentId!);

      if (remoteAgent != null && remoteAgent.isOnline) {
        try {
          await chatService.sendMessageToAgent(
            content: '/reset-all',
            agent: remoteAgent,
            userId: userId,
            userName: userName,
            channelId: sessionId,
          );
        } catch (_) {}
      }

      final sessions = await chatService.getAgentSessions(agentId: agentId!);
      final defaultChannelId = chatService.generateChannelId(userId, agentId!);

      for (final session in sessions) {
        await localDatabaseService.deleteChannelMessages(session.id);
        if (session.id != defaultChannelId) {
          await localDatabaseService.deleteChannel(session.id);
        }
      }

      final defaultChannel = await localDatabaseService.getChannelById(defaultChannelId);
      if (defaultChannel == null) {
        final channel = Channel.withMemberIds(
          id: defaultChannelId,
          name: 'Chat with ${agentName ?? 'Agent'}',
          type: 'dm',
          memberIds: [userId, agentId!],
          isPrivate: true,
        );
        await localDatabaseService.createChannel(channel, userId);
      }

      _emit(DismissOverlayEvent());
      final isAlreadyDefault = currentChannelId == defaultChannelId;

      if (isAlreadyDefault) {
        messages.clear();
        messageIdMap.clear();
        _notify();
        _emit(ShowSnackBarEvent('chat_allSessionsCleared'));
      } else {
        _emit(NavigateToSessionEvent(
          channelId: defaultChannelId,
          agentId: agentId,
          agentName: agentName,
          agentAvatar: agentAvatar,
          embedded: embedded,
        ));
      }
    } catch (e) {
      _emit(DismissOverlayEvent());
      _emit(ShowErrorSnackBarEvent('chat_clearAllSessionsFailed:$e'));
    }
  }

  Future<void> clearGroupSessionHistory() async {
    if (groupChannel == null || currentChannelId == null) return;

    _emit(ShowLoadingOverlayEvent('chat_clearingGroupSession'));

    try {
      final agentIds = groupAgents.map((a) => a.id).toList();
      final parentGroupId = groupChannel!.groupFamilyId;
      final sessions = await chatService.getGroupSessions(parentGroupId: parentGroupId);

      if (sessions.length > 1) {
        await chatService.clearGroupSessionHistory(
          channelId: currentChannelId!,
          agentIds: agentIds,
        );
        await localDatabaseService.deleteChannel(currentChannelId!);

        final remaining = sessions.where((s) => s.id != currentChannelId).toList();
        final targetSession = remaining.first;

        _emit(DismissOverlayEvent());
        _emit(NavigateToSessionEvent(
          channelId: targetSession.id,
          embedded: embedded,
        ));
      } else {
        await chatService.clearGroupSessionHistory(
          channelId: currentChannelId!,
          agentIds: agentIds,
        );

        _emit(DismissOverlayEvent());
        messages.clear();
        messageIdMap.clear();
        _notify();
        _emit(ShowSnackBarEvent('chat_groupSessionCleared'));
      }
    } catch (e) {
      _emit(DismissOverlayEvent());
      _emit(ShowErrorSnackBarEvent('chat_clearGroupSessionFailed:$e'));
    }
  }

  Future<void> clearAllGroupSessionsHistory() async {
    if (groupChannel == null || currentChannelId == null) return;

    _emit(ShowLoadingOverlayEvent('chat_clearingAllGroupSessions'));

    try {
      final agentIds = groupAgents.map((a) => a.id).toList();
      final parentGroupId = groupChannel!.groupFamilyId;

      await chatService.clearAllGroupSessions(
        parentGroupId: parentGroupId,
        currentChannelId: currentChannelId!,
        agentIds: agentIds,
      );

      _emit(DismissOverlayEvent());
      final isAlreadyParent = currentChannelId == parentGroupId;

      if (isAlreadyParent) {
        messages.clear();
        messageIdMap.clear();
        _notify();
        _emit(ShowSnackBarEvent('chat_allGroupSessionsCleared'));
      } else {
        _emit(NavigateToSessionEvent(
          channelId: parentGroupId,
          embedded: embedded,
        ));
      }
    } catch (e) {
      _emit(DismissOverlayEvent());
      _emit(ShowErrorSnackBarEvent('chat_clearAllGroupSessionsFailed:$e'));
    }
  }

  Future<void> batchDeleteSessions(List<String> sessionIds, {required bool isGroup}) async {
    if (sessionIds.isEmpty) return;

    _emit(ShowLoadingOverlayEvent('chat_clearingAllSessions'));

    try {
      for (final id in sessionIds) {
        await localDatabaseService.deleteChannelMessages(id);
        await localDatabaseService.deleteChannel(id);
      }

      _emit(DismissOverlayEvent());
      _emit(ShowSnackBarEvent('chat_batchDeleteSuccess:${sessionIds.length}'));
    } catch (e) {
      _emit(DismissOverlayEvent());
      _emit(ShowErrorSnackBarEvent('chat_clearSessionFailed:$e'));
    }
  }

  // ---------------------------------------------------------------------------
  // Group member management
  // ---------------------------------------------------------------------------

  Future<void> addGroupMember(RemoteAgent agent) async {
    if (currentChannelId == null) return;

    await localDatabaseService.addChannelMember(currentChannelId!, agent.id);

    final systemMsg = await chatService.notifyGroupMembershipChange(
      currentChannelId!,
      agent.id,
      agent.name,
      isJoin: true,
    );
    messages.add(systemMsg);
    messageIdMap[systemMsg.id] = systemMsg;
    _notify();
    _emit(RequestScrollToBottomEvent());

    await refreshGroupMembers();
  }

  Future<void> removeGroupMember(RemoteAgent agent) async {
    if (currentChannelId == null) return;

    await localDatabaseService.removeChannelMember(currentChannelId!, agent.id);

    final systemMsg = await chatService.notifyGroupMembershipChange(
      currentChannelId!,
      agent.id,
      agent.name,
      isJoin: false,
    );
    messages.add(systemMsg);
    messageIdMap[systemMsg.id] = systemMsg;
    _notify();
    _emit(RequestScrollToBottomEvent());

    await refreshGroupMembers();
  }

  Future<void> refreshGroupMembers() async {
    if (currentChannelId == null) return;
    final userId = getUserId();

    final channel = await localDatabaseService.getChannelById(currentChannelId!);
    final memberIds = await localDatabaseService.getChannelMemberIds(currentChannelId!);
    final agentIdsList = memberIds.where((id) => id != userId && id != 'user').toList();
    final agents = <RemoteAgent>[];
    for (final aid in agentIdsList) {
      final agent = await localDatabaseService.getRemoteAgentById(aid);
      if (agent != null) agents.add(agent);
    }

    groupAgents = agents;
    groupChannel = channel;
    groupAdminAgentId = channel?.adminAgentId;
    _notify();
  }

  Future<List<ChannelMember>> saveMemberGroupBio(RemoteAgent agent, String? newGroupBio) async {
    if (currentChannelId == null) return groupChannel?.members ?? [];

    final parentGroupId = groupChannel?.groupFamilyId ?? currentChannelId!;
    final sessions = await localDatabaseService.getGroupSessions(parentGroupId);
    for (final session in sessions) {
      await localDatabaseService.updateChannelMemberGroupBio(session.id, agent.id, newGroupBio);
    }

    await refreshGroupMembers();
    return groupChannel?.members ?? [];
  }

  List<String> parseMentionedAgentIds(String content) {
    if (content.contains('@all')) {
      return groupAgents.map((a) => a.id).toList();
    }
    final mentioned = <String>[];
    for (final agent in groupAgents) {
      if (content.contains('@${agent.name}')) {
        mentioned.add(agent.id);
      }
    }
    return mentioned;
  }

  // ---------------------------------------------------------------------------
  // Group message reconciliation
  // ---------------------------------------------------------------------------

  Future<void> reconcileGroupMessages() async {
    if (currentChannelId == null) return;

    final dbMessages = await chatService.loadChannelMessages(currentChannelId!);

    final tempMessages = <String, int>{};
    for (int i = 0; i < messages.length; i++) {
      final id = messages[i].id;
      if (id.startsWith('group_streaming_') || id.startsWith('temp_user_')) {
        tempMessages[id] = i;
      }
    }

    print('[ChatController] reconcileGroupMessages: ${tempMessages.length} temp, ${dbMessages.length} db, ${messages.length} total');

    if (tempMessages.isEmpty) {
      messages = dbMessages;
      rebuildMessageIdMap();
      _notify();
      return;
    }

    final matchedDbIds = <String>{};
    final usedTempIds = <String>{};

    // Pass 1: exact content match
    for (final dbMsg in dbMessages) {
      if (matchedDbIds.contains(dbMsg.id)) continue;
      String? matchedTempId;
      for (final entry in tempMessages.entries) {
        if (usedTempIds.contains(entry.key)) continue;
        final tempMsg = messages[entry.value];
        if (tempMsg.from.id == dbMsg.from.id &&
            tempMsg.content.trim() == dbMsg.content.trim()) {
          matchedTempId = entry.key;
          break;
        }
      }
      if (matchedTempId != null) {
        final idx = tempMessages[matchedTempId]!;
        messages[idx] = dbMsg;
        matchedDbIds.add(dbMsg.id);
        usedTempIds.add(matchedTempId);
      }
    }

    // Pass 2: for unmatched DB messages, match by sender ID alone.
    // The DB content may differ from the streaming content because the
    // service strips redundant agent-name prefixes before saving.  When
    // there is exactly one remaining temp message from the same sender,
    // treat it as a match so the streaming placeholder is replaced
    // correctly and doesn't disappear.
    for (final dbMsg in dbMessages) {
      if (matchedDbIds.contains(dbMsg.id)) continue;
      final candidates = tempMessages.entries
          .where((e) => !usedTempIds.contains(e.key) && messages[e.value].from.id == dbMsg.from.id)
          .toList();
      if (candidates.length == 1) {
        final entry = candidates.first;
        final idx = entry.value;
        messages[idx] = dbMsg;
        matchedDbIds.add(dbMsg.id);
        usedTempIds.add(entry.key);
      }
    }

    print('[ChatController] reconcileGroupMessages: pass1 matched ${matchedDbIds.length}, pass2 total matched ${usedTempIds.length}');

    // Remove unmatched temp messages, but keep streaming messages that
    // have non-empty content when no corresponding DB message exists —
    // the DB save may have failed and discarding the only copy of the
    // response would lose it permanently.
    final dbSenderIds = dbMessages.map((m) => m.from.id).toSet();
    messages.removeWhere((m) {
      if (!m.id.startsWith('group_streaming_') && !m.id.startsWith('temp_user_')) {
        return false;
      }
      if (usedTempIds.contains(m.id)) return false;
      // Keep streaming messages with content when no DB message was
      // found from this sender (i.e. the DB save likely failed).
      if (m.id.startsWith('group_streaming_') &&
          m.content.trim().isNotEmpty &&
          !dbSenderIds.contains(m.from.id)) {
        return false;
      }
      return true;
    });

    final existingIds = messages.map((m) => m.id).toSet();
    for (final dbMsg in dbMessages) {
      if (!existingIds.contains(dbMsg.id) && !matchedDbIds.contains(dbMsg.id)) {
        messages.add(dbMsg);
      }
    }

    messages.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    rebuildMessageIdMap();
    print('[ChatController] reconcileGroupMessages done: ${messages.length} messages');
    _notify();
  }

  void scheduleStreamingRebuild() {
    if (_pendingStreamingRebuild) return;
    _pendingStreamingRebuild = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingStreamingRebuild = false;
      _notify();
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void addSystemHint(String text) {
    final hint = Message(
      id: 'hint_${DateTime.now().millisecondsSinceEpoch}',
      content: text,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      from: MessageFrom(id: 'system', type: 'system', name: 'System'),
      type: MessageType.system,
    );
    messages.add(hint);
    messageIdMap[hint.id] = hint;
    _notify();
    _emit(RequestScrollToBottomEvent());
  }

  /// Update agent info (e.g. after editing in detail screen)
  void updateAgentInfo(String? name, String? avatar) {
    agentName = name;
    agentAvatar = avatar;
    _notify();
  }
}
