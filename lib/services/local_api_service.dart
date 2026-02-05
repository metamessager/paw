import 'package:uuid/uuid.dart';
import '../models/agent.dart';
import '../models/channel.dart';
import '../models/message.dart';
import '../models/agent_conversation_request.dart';
import 'local_database_service.dart';
import 'local_file_storage_service.dart';

/// 本地化 API 服务 - 替代网络请求，使用本地数据库
class LocalApiService {
  static final LocalApiService _instance = LocalApiService._internal();
  factory LocalApiService() => _instance;
  LocalApiService._internal();

  final _db = LocalDatabaseService();
  final _storage = LocalFileStorageService();
  final _uuid = const Uuid();

  // 当前登录用户ID（简化版，实际应该从 AuthService 获取）
  String _currentUserId = 'local_user_001';

  String get currentUserId => _currentUserId;
  set currentUserId(String id) => _currentUserId = id;

  // ==================== Agent 管理 ====================

  /// 获取所有 Agent
  Future<List<Agent>> getAgents() async {
    try {
      return await _db.getAllAgents();
    } catch (e) {
      print('获取 Agent 列表失败: $e');
      rethrow;
    }
  }

  /// 根据 ID 获取 Agent
  Future<Agent?> getAgentById(String id) async {
    try {
      return await _db.getAgentById(id);
    } catch (e) {
      print('获取 Agent 失败: $e');
      rethrow;
    }
  }

  /// 创建 Agent
  Future<Agent> createAgent(Agent agent) async {
    try {
      // 如果没有 ID，生成一个
      final agentToCreate = agent.id.isEmpty
          ? agent.copyWith(id: _uuid.v4())
          : agent;

      await _db.createAgent(agentToCreate, _currentUserId);
      return agentToCreate;
    } catch (e) {
      print('创建 Agent 失败: $e');
      rethrow;
    }
  }

  /// 更新 Agent
  Future<Agent> updateAgent(Agent agent) async {
    try {
      await _db.updateAgent(agent);
      return agent;
    } catch (e) {
      print('更新 Agent 失败: $e');
      rethrow;
    }
  }

  /// 删除 Agent
  Future<void> deleteAgent(String id) async {
    try {
      // 删除 Agent 相关的资源文件
      final agent = await _db.getAgentById(id);
      if (agent != null && agent.avatar != null) {
        await _storage.deleteImage(agent.avatar!);
      }

      await _db.deleteAgent(id);
    } catch (e) {
      print('删除 Agent 失败: $e');
      rethrow;
    }
  }

  // ==================== Channel 管理 ====================

  /// 获取所有 Channel
  Future<List<Channel>> getChannels() async {
    try {
      final channels = await _db.getAllChannels();
      
      // 填充最后一条消息信息
      for (int i = 0; i < channels.length; i++) {
        final messages = await _db.getChannelMessages(channels[i].id, limit: 1);
        if (messages.isNotEmpty) {
          final lastMsg = messages.first;
          channels[i] = channels[i].copyWith(
            lastMessage: lastMsg['content'] as String,
            lastMessageTime: DateTime.parse(lastMsg['created_at'] as String),
            unreadCount: await _getUnreadCount(channels[i].id),
          );
        }
      }
      
      return channels;
    } catch (e) {
      print('获取 Channel 列表失败: $e');
      rethrow;
    }
  }

  /// 根据 ID 获取 Channel
  Future<Channel?> getChannelById(String id) async {
    try {
      return await _db.getChannelById(id);
    } catch (e) {
      print('获取 Channel 失败: $e');
      rethrow;
    }
  }

  /// 创建 Channel
  Future<Channel> createChannel(Channel channel) async {
    try {
      final channelToCreate = channel.id.isEmpty
          ? channel.copyWith(id: _uuid.v4())
          : channel;

      await _db.createChannel(channelToCreate, _currentUserId);
      return channelToCreate;
    } catch (e) {
      print('创建 Channel 失败: $e');
      rethrow;
    }
  }

  /// 更新 Channel
  Future<Channel> updateChannel(Channel channel) async {
    try {
      await _db.updateChannel(channel);
      return channel;
    } catch (e) {
      print('更新 Channel 失败: $e');
      rethrow;
    }
  }

  /// 删除 Channel
  Future<void> deleteChannel(String id) async {
    try {
      // 删除 Channel 相关的资源文件
      final channel = await _db.getChannelById(id);
      if (channel != null && channel.avatar != null) {
        await _storage.deleteImage(channel.avatar!);
      }

      await _db.deleteChannel(id);
    } catch (e) {
      print('删除 Channel 失败: $e');
      rethrow;
    }
  }

  /// 添加 Channel 成员
  Future<void> addChannelMember(String channelId, String agentId) async {
    try {
      await _db.addChannelMember(channelId, agentId);
    } catch (e) {
      print('添加 Channel 成员失败: $e');
      rethrow;
    }
  }

  /// 移除 Channel 成员
  Future<void> removeChannelMember(String channelId, String agentId) async {
    try {
      await _db.removeChannelMember(channelId, agentId);
    } catch (e) {
      print('移除 Channel 成员失败: $e');
      rethrow;
    }
  }

  // ==================== 消息管理 ====================

  /// 发送消息
  Future<Message> sendMessage({
    required String channelId,
    required String content,
    String? replyToId,
  }) async {
    try {
      final messageId = _uuid.v4();
      final now = DateTime.now();

      await _db.createMessage(
        id: messageId,
        channelId: channelId,
        senderId: _currentUserId,
        senderType: 'user',
        content: content,
        replyToId: replyToId,
      );

      return Message(
        id: messageId,
        channelId: channelId,
        senderId: _currentUserId,
        senderName: 'Me',
        content: content,
        timestamp: now,
        type: MessageType.text,
      );
    } catch (e) {
      print('发送消息失败: $e');
      rethrow;
    }
  }

  /// 获取 Channel 消息
  Future<List<Message>> getChannelMessages(String channelId, {int limit = 100}) async {
    try {
      final messages = await _db.getChannelMessages(channelId, limit: limit);
      
      List<Message> result = [];
      for (final msg in messages.reversed) {
        // 获取发送者名称
        String senderName = 'Unknown';
        if (msg['sender_type'] == 'user') {
          senderName = 'Me';
        } else if (msg['sender_type'] == 'agent') {
          final agent = await _db.getAgentById(msg['sender_id'] as String);
          senderName = agent?.name ?? 'Agent';
        }

        result.add(Message(
          id: msg['id'] as String,
          channelId: msg['channel_id'] as String,
          senderId: msg['sender_id'] as String,
          senderName: senderName,
          content: msg['content'] as String,
          timestamp: DateTime.parse(msg['created_at'] as String),
          type: _parseMessageType(msg['message_type'] as String),
        ));
      }
      
      return result;
    } catch (e) {
      print('获取消息列表失败: $e');
      rethrow;
    }
  }

  MessageType _parseMessageType(String type) {
    switch (type) {
      case 'text':
        return MessageType.text;
      case 'image':
        return MessageType.image;
      case 'file':
        return MessageType.file;
      default:
        return MessageType.text;
    }
  }

  /// 获取未读消息数
  Future<int> _getUnreadCount(String channelId) async {
    // 简化版：返回 0，实际可以基于 is_read 字段统计
    return 0;
  }

  // ==================== Agent 对话请求管理 ====================

  /// 获取待处理的对话请求
  Future<List<AgentConversationRequest>> getPendingConversationRequests() async {
    // 本地化版本：返回空列表（或可以实现完整功能）
    return [];
  }

  /// 批准对话请求
  Future<void> approveConversationRequest(String requestId) async {
    // 本地化版本：可以实现
    print('批准对话请求: $requestId');
  }

  /// 拒绝对话请求
  Future<void> rejectConversationRequest(String requestId, String reason) async {
    // 本地化版本：可以实现
    print('拒绝对话请求: $requestId, 原因: $reason');
  }

  // ==================== 初始化示例数据 ====================

  /// 初始化示例数据（首次启动时）
  Future<void> initializeSampleData() async {
    try {
      // 检查是否已有数据
      final existingAgents = await getAgents();
      if (existingAgents.isNotEmpty) {
        print('数据库已有数据，跳过初始化');
        return;
      }

      print('初始化示例数据...');

      // 创建示例 Agent
      final agent1 = Agent(
        id: _uuid.v4(),
        name: 'GPT-4 助手',
        description: '基于 GPT-4 的通用助手',
        model: 'gpt-4',
        systemPrompt: '你是一个有帮助的AI助手',
        capabilities: ['对话', '分析', '创作'],
      );

      final agent2 = Agent(
        id: _uuid.v4(),
        name: 'Claude 助手',
        description: '基于 Claude 的专业助手',
        model: 'claude-3',
        systemPrompt: '你是一个专业的AI助手',
        capabilities: ['对话', '编程', '翻译'],
      );

      await createAgent(agent1);
      await createAgent(agent2);

      // 创建示例 Channel
      final channel1 = Channel(
        id: _uuid.v4(),
        name: '团队讨论',
        description: '团队协作频道',
        type: 'group',
        memberIds: [agent1.id, agent2.id],
        isPrivate: false,
      );

      await createChannel(channel1);

      // 添加示例消息
      await _db.createMessage(
        id: _uuid.v4(),
        channelId: channel1.id,
        senderId: agent1.id,
        senderType: 'agent',
        content: '大家好！我是 GPT-4 助手。',
      );

      await _db.createMessage(
        id: _uuid.v4(),
        channelId: channel1.id,
        senderId: agent2.id,
        senderType: 'agent',
        content: '你好！我是 Claude 助手，很高兴加入这个频道。',
      );

      print('示例数据初始化完成');
    } catch (e) {
      print('初始化示例数据失败: $e');
    }
  }

  // ==================== 数据统计 ====================

  /// 获取数据统计信息
  Future<Map<String, dynamic>> getStats() async {
    try {
      final agents = await getAgents();
      final channels = await getChannels();
      final storageStats = await _storage.getStorageStats();

      return {
        'agentCount': agents.length,
        'channelCount': channels.length,
        'storageSize': storageStats.readableSize,
        'fileCount': storageStats.fileCount,
      };
    } catch (e) {
      print('获取统计信息失败: $e');
      return {};
    }
  }
}

// Agent 的扩展方法
extension AgentExtension on Agent {
  Agent copyWith({
    String? id,
    String? name,
    String? description,
    String? avatar,
    String? model,
    String? systemPrompt,
    double? temperature,
    int? maxTokens,
    String? status,
    List<String>? capabilities,
    Map<String, dynamic>? metadata,
  }) {
    return Agent(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatar: avatar ?? this.avatar,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      status: status ?? this.status,
      capabilities: capabilities ?? this.capabilities,
      metadata: metadata ?? this.metadata,
    );
  }
}

// Channel 的扩展方法
extension ChannelExtension on Channel {
  Channel copyWith({
    String? id,
    String? name,
    String? description,
    String? type,
    String? avatar,
    List<String>? memberIds,
    bool? isPrivate,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
  }) {
    return Channel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      avatar: avatar ?? this.avatar,
      memberIds: memberIds ?? this.memberIds,
      isPrivate: isPrivate ?? this.isPrivate,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
