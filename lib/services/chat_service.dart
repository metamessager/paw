import 'dart:async';
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
  }) async {
    try {
      // Check if agent is online
      if (agent.status != AgentStatus.online) {
        throw Exception('Agent ${agent.name} is not online');
      }

      // Check if agent has valid endpoint
      if (agent.endpoint.isEmpty) {
        throw Exception('Agent ${agent.name} has no valid endpoint');
      }

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
      );

      // Save user message to database
      await _saveMessageToChannel(userMessage, agent.id);

      // Send message to agent based on protocol
      Message? agentResponse;
      if (agent.protocol == ProtocolType.a2a) {
        agentResponse = await _sendViaA2AProtocol(userMessage, agent);
      } else {
        // For other protocols, use generic HTTP POST
        agentResponse = await _sendViaGenericProtocol(userMessage, agent);
      }

      // Save agent response if received
      if (agentResponse != null) {
        await _saveMessageToChannel(agentResponse, agent.id);
      }

      return agentResponse;
    } catch (e) {
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
      await _saveMessageToChannel(errorMessage, agent.id);
      return null;
    }
  }

  /// Send message via A2A protocol
  Future<Message?> _sendViaA2AProtocol(Message userMessage, RemoteAgent agent) async {
    try {
      // Set authentication token
      _a2aService.setAuthentication('bearer', agent.token);

      // Create A2A task
      final task = A2ATask(
        id: _uuid.v4(),
        instruction: userMessage.content,
        metadata: {
          'user_id': userMessage.from.id,
          'message_id': userMessage.id,
          'timestamp': userMessage.timestampMs,
        },
      );

      // Submit task to agent
      final taskResponse = await _a2aService.submitTask(
        '${agent.endpoint}/tasks',
        task,
      );

      // Extract response from artifacts
      String responseContent = 'Task completed';
      
      if (taskResponse.artifacts != null && taskResponse.artifacts!.isNotEmpty) {
        // Get the first artifact
        final firstArtifact = taskResponse.artifacts!.first;
        
        // Find the first text part
        final textPart = firstArtifact.parts.firstWhere(
          (part) => part.type == 'text',
          orElse: () => A2APart.text(''),
        );
        
        responseContent = textPart.content?.toString() ?? 'Task completed';
      }

      // Check for error
      if (taskResponse.isFailed) {
        throw Exception(taskResponse.error ?? 'Task failed');
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
      );
    } catch (e) {
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

  /// Save message to agent channel
  Future<void> _saveMessageToChannel(Message message, String agentId) async {
    // Generate channel ID (user-agent conversation)
    final channelId = _generateChannelId(message.from.id, agentId);

    // Check if channel exists
    final existingChannel = await _databaseService.getChannelById(channelId);
    
    if (existingChannel == null) {
      // Create channel if it doesn't exist
      final channel = Channel.withMemberIds(
        id: channelId,
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
      channelId: channelId,
      senderId: message.from.id,
      senderType: message.from.type,
      content: message.content,
      messageType: message.type.toString().split('.').last,
      replyToId: message.replyTo,
    );

    // Notify listeners
    _notifyChannelUpdate(channelId);
  }

  /// Load message history for an agent
  Future<List<Message>> loadMessageHistory({
    required String agentId,
    required String userId,
    int limit = 100,
  }) async {
    final channelId = _generateChannelId(userId, agentId);
    return await loadChannelMessages(channelId, limit: limit);
  }

  /// Load messages from a channel
  Future<List<Message>> loadChannelMessages(String channelId, {int limit = 100}) async {
    final messageMaps = await _databaseService.getChannelMessages(channelId, limit: limit);
    
    return messageMaps.map((map) {
      return Message(
        id: map['id'] as String,
        from: MessageFrom(
          id: map['sender_id'] as String,
          type: map['sender_type'] as String,
          name: map['sender_id'] as String,
        ),
        channelId: channelId,
        type: _parseMessageType(map['message_type'] as String),
        content: map['content'] as String,
        timestampMs: DateTime.parse(map['created_at'] as String).millisecondsSinceEpoch,
        replyTo: map['reply_to_id'] as String?,
      );
    }).toList()
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
  }

  /// Get channel ID for user-agent conversation
  String _generateChannelId(String userId, String agentId) {
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
    final channelId = _generateChannelId(userId, agentId);
    // Delete channel (cascades to delete messages)
    await _databaseService.deleteChannel(channelId);
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

  /// Dispose resources
    for (final controller in _messageControllers.values) {
      controller.close();
    }
    _messageControllers.clear();
    _a2aService.dispose();
  }
}
