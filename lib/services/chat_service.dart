import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/channel.dart';
import '../models/remote_agent.dart';
import 'local_database_service.dart';
import 'a2a_protocol_service.dart';
import '../models/a2a/task.dart';

/// Chat Service
/// Handles message sending and receiving with agents
class ChatService {
  final LocalDatabaseService _databaseService;
  final A2AProtocolService _a2aService;
  final Uuid _uuid = const Uuid();

  // Stream controllers for real-time updates
  final Map<String, StreamController<List<Message>>> _messageControllers = {};

  ChatService(this._databaseService, {A2AProtocolService? a2aService})
      : _a2aService = a2aService ?? A2AProtocolService();

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
    StreamCancellationToken? cancellationToken,
  }) async {
    print('🚀 [ChatService] 开始发送消息到 Agent');
    print('   - Agent ID: ${agent.id}');
    print('   - Agent Name: ${agent.name}');
    print('   - Agent Protocol: ${agent.protocol}');
    print('   - Agent Status: ${agent.status}');
    print('   - Agent Endpoint: ${agent.endpoint}');
    print('   - Message Content: $content');

    try {
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

      // Create user message
      final userMessage = Message(
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

      // Send message to agent based on protocol
      Message? agentResponse;
      print('🔄 [ChatService] Preparing to send message via ${agent.protocol} protocol...');

      if (agent.protocol == ProtocolType.a2a) {
        print('   - Using A2A protocol');
        agentResponse = await _sendViaA2AProtocol(userMessage, agent, onStreamChunk: onStreamChunk, onActionConfirmation: onActionConfirmation, onSingleSelect: onSingleSelect, onMultiSelect: onMultiSelect, onFileUpload: onFileUpload, onForm: onForm, sessionId: channelId, cancellationToken: cancellationToken);
      } else {
        // For other protocols, use generic HTTP POST
        print('   - Using generic protocol');
        agentResponse = await _sendViaGenericProtocol(userMessage, agent);
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
      return null;
    }
  }

  /// Send message via A2A protocol
  Future<Message?> _sendViaA2AProtocol(Message userMessage, RemoteAgent agent, {
    void Function(String chunk)? onStreamChunk,
    void Function(Map<String, dynamic> actionData)? onActionConfirmation,
    void Function(Map<String, dynamic> selectData)? onSingleSelect,
    void Function(Map<String, dynamic> selectData)? onMultiSelect,
    void Function(Map<String, dynamic> uploadData)? onFileUpload,
    void Function(Map<String, dynamic> formData)? onForm,
    String? sessionId,
    StreamCancellationToken? cancellationToken,
  }) async {
    print('🔌 [A2AProtocol] 开始通过 A2A 协议发送消息');
    print('   - Agent Endpoint: ${agent.endpoint}');
    print('   - Agent Token: ${agent.token.isNotEmpty ? "✅ 有 token" : "❌ 无 token"}');
    
    try {
      // Set authentication token
      print('🔑 [A2AProtocol] 设置认证 token...');
      _a2aService.setAuthentication('bearer', agent.token);
      print('✅ [A2AProtocol] Token 设置成功');

      // Create A2A task
      print('📋 [A2AProtocol] 创建 A2A Task...');
      final task = A2ATask(
        id: _uuid.v4(),
        instruction: userMessage.content,
        context: [
          A2APart.text(userMessage.content),
        ],
        metadata: {
          'user_id': userMessage.from.id,
          'message_id': userMessage.id,
          'timestamp': userMessage.timestampMs,
          if (sessionId != null) 'session_id': sessionId,
        },
      );
      print('   - Task ID: ${task.id}');
      print('   - Task instruction: ${task.instruction}');
      print('✅ [A2AProtocol] Task 创建成功');

      // Submit task to agent
      // 注意：Mock Agent 的端点是 /a2a/task（单数），不是 /tasks（复数）
      String taskEndpoint;
      if (agent.endpoint.endsWith('/a2a/task')) {
        // 如果 endpoint 已经包含完整路径，直接使用
        taskEndpoint = agent.endpoint;
      } else if (agent.endpoint.endsWith('/a2a')) {
        // 如果 endpoint 是 /a2a，添加 /task
        taskEndpoint = '${agent.endpoint}/task';
      } else {
        // 默认情况，添加 /tasks（标准 A2A 协议）
        taskEndpoint = '${agent.endpoint}/tasks';
      }
      
      print('📤 [A2AProtocol] 提交 Task 到: $taskEndpoint');

      Map<String, dynamic>? actionConfirmationData;
      Map<String, dynamic>? singleSelectData;
      Map<String, dynamic>? multiSelectData;
      Map<String, dynamic>? fileUploadData;
      Map<String, dynamic>? formData;

      final taskResponse = await _a2aService.submitTask(
        taskEndpoint,
        task,
        onContentChunk: onStreamChunk,
        onActionConfirmation: (actionData) {
          actionConfirmationData = Map<String, dynamic>.from(actionData);
          onActionConfirmation?.call(actionData);
        },
        onSingleSelect: (selectData) {
          singleSelectData = Map<String, dynamic>.from(selectData);
          onSingleSelect?.call(selectData);
        },
        onMultiSelect: (selectData) {
          multiSelectData = Map<String, dynamic>.from(selectData);
          onMultiSelect?.call(selectData);
        },
        onFileUpload: (uploadData) {
          fileUploadData = Map<String, dynamic>.from(uploadData);
          onFileUpload?.call(uploadData);
        },
        onForm: (fData) {
          formData = Map<String, dynamic>.from(fData);
          onForm?.call(fData);
        },
        cancellationToken: cancellationToken,
      );
      
      print('✅ [A2AProtocol] Task 提交完成');
      print('   - Response Task ID: ${taskResponse.taskId}');
      print('   - Response state: ${taskResponse.state}');
      print('   - Response artifacts count: ${taskResponse.artifacts?.length ?? 0}');

      // Extract response from artifacts
      String responseContent = 'Task completed';
      
      if (taskResponse.artifacts != null && taskResponse.artifacts!.isNotEmpty) {
        print('📦 [A2AProtocol] 解析 artifacts...');
        // Get the first artifact
        final firstArtifact = taskResponse.artifacts!.first;
        print('   - Artifact parts count: ${firstArtifact.parts.length}');
        
        // Find the first text part
        final textPart = firstArtifact.parts.firstWhere(
          (part) => part.type == 'text',
          orElse: () => A2APart.text(''),
        );
        
        responseContent = textPart.content?.toString() ?? 'Task completed';
        print('   - Response content: $responseContent');
      } else {
        print('⚠️ [A2AProtocol] No artifacts in response');
      }

      // Check for error
      if (taskResponse.isFailed) {
        print('❌ [A2AProtocol] Task 失败');
        print('   - Error: ${taskResponse.error}');
        throw Exception(taskResponse.error ?? 'Task failed');
      }

      print('✅ [A2AProtocol] 消息发送成功');

      // Build metadata from interactive elements
      Map<String, dynamic>? messageMetadata;
      if (actionConfirmationData != null || singleSelectData != null || multiSelectData != null || fileUploadData != null || formData != null) {
        messageMetadata = {};
        if (actionConfirmationData != null) {
          messageMetadata['action_confirmation'] = actionConfirmationData;
        }
        if (singleSelectData != null) {
          messageMetadata['single_select'] = singleSelectData;
        }
        if (multiSelectData != null) {
          messageMetadata['multi_select'] = multiSelectData;
        }
        if (fileUploadData != null) {
          messageMetadata['file_upload'] = fileUploadData;
        }
        if (formData != null) {
          messageMetadata['form'] = formData;
        }
      }

      return Message(
        id: _uuid.v4(),
        content: responseContent,
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
      print('❌ [A2AProtocol] 发送消息失败');
      print('   - Error: $e');
      print('   - Stack trace: $stackTrace');
      throw Exception('A2A protocol error: $e');
    }
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

  /// Submit action confirmation response
  /// Updates the original message's metadata and sends a new request to the agent
  Future<Message?> submitActionConfirmationResponse({
    required Message originalMessage,
    required String confirmationId,
    required String selectedActionId,
    required String selectedActionLabel,
    required RemoteAgent agent,
    required String userId,
    required String userName,
    String? channelId,
    void Function(String chunk)? onStreamChunk,
    StreamCancellationToken? cancellationToken,
  }) async {
    print('🔘 [ChatService] Submitting action confirmation response');
    print('   - Confirmation ID: $confirmationId');
    print('   - Selected Action: $selectedActionId ($selectedActionLabel)');

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

    // Send the selection as a new message to the agent
    return await sendMessageToAgent(
      content: 'Selected action: $selectedActionLabel',
      agent: agent,
      userId: userId,
      userName: userName,
      channelId: channelId,
      onStreamChunk: onStreamChunk,
      cancellationToken: cancellationToken,
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
    StreamCancellationToken? cancellationToken,
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
      cancellationToken: cancellationToken,
    );
  }

  /// Save message to agent channel
  Future<void> _saveMessageToChannel(Message message, String agentId, {String? channelId}) async {
    // Use provided channelId or generate deterministic one
    final effectiveChannelId = channelId ?? (() {
      final otherPartyId = message.from.id == agentId ? (message.to?.id ?? message.from.id) : message.from.id;
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

    // Notify listeners
    _notifyChannelUpdate(effectiveChannelId);
  }

  /// Load message history for an agent
  Future<List<Message>> loadMessageHistory({
    required String agentId,
    required String userId,
    int limit = 100,
  }) async {
    final channelId = generateChannelId(userId, agentId);
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
      default:
        return MessageType.text;
    }
  }

  /// Notify channel update
  void _notifyChannelUpdate(String channelId) {
    _messageControllers[channelId]?.add([]);
  }

  /// Delete chat history for an agent
  Future<void> deleteChatHistory({
    required String agentId,
    required String userId,
  }) async {
    final channelId = generateChannelId(userId, agentId);
    // Delete channel (cascades to delete messages)
    await _databaseService.deleteChannel(channelId);
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
    String taskEndpoint;
    if (agent.endpoint.endsWith('/a2a/task')) {
      taskEndpoint = agent.endpoint;
    } else if (agent.endpoint.endsWith('/a2a')) {
      taskEndpoint = '${agent.endpoint}/task';
    } else {
      taskEndpoint = '${agent.endpoint}/tasks';
    }

    _a2aService.setAuthentication('bearer', agent.token);
    // Fire-and-forget: don't await or block on failure
    _a2aService.sendRollback(taskEndpoint, messageId).catchError((_) {});

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

  /// Dispose resources
  void dispose() {
    for (final controller in _messageControllers.values) {
      controller.close();
    }
    _messageControllers.clear();
    _a2aService.dispose();
  }
}
