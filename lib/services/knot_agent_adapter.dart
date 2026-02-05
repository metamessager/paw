import '../models/agent.dart';
import '../models/knot_agent.dart';
import '../models/message.dart';
import '../models/channel.dart';
import 'knot_api_service.dart';

/// Knot Agent 适配器
/// 将 Knot Agent 适配为标准 Agent，使其能够参与 Channel 对话
class KnotAgentAdapter {
  final KnotApiService _knotApiService;
  
  // 消息轮询间隔（秒）
  static const int pollInterval = 3;
  
  // 任务上下文缓存 (taskId -> channelId)
  final Map<String, String> _taskChannelMapping = {};

  KnotAgentAdapter(this._knotApiService);

  /// 将 KnotAgent 转换为标准 Agent
  Agent toStandardAgent(KnotAgent knotAgent) {
    return Agent(
      id: 'knot_${knotAgent.knotAgentId}', // 添加前缀避免 ID 冲突
      name: '${knotAgent.name} (Knot)',
      avatar: knotAgent.avatar,
      bio: knotAgent.bio ?? 'Knot Agent - ${knotAgent.config.model}',
      provider: AgentProvider(
        name: 'Knot',
        platform: 'knot',
        type: 'openclaw-adapter',
      ),
      status: AgentStatus(
        state: knotAgent.status.isOnline ? 'online' : 'offline',
        connectedAt: knotAgent.status.connectedAt,
        lastHeartbeat: knotAgent.status.lastHeartbeat,
      ),
    );
  }

  /// 从标准 Agent ID 获取 Knot Agent ID
  String getKnotAgentId(String agentId) {
    if (agentId.startsWith('knot_')) {
      return agentId.substring(5);
    }
    return agentId;
  }

  /// 检查是否为 Knot Agent
  bool isKnotAgent(String agentId) {
    return agentId.startsWith('knot_');
  }

  /// 将 Channel 消息发送到 Knot Agent
  /// 返回任务 ID
  Future<String> sendMessageToKnotAgent({
    required String agentId,
    required Message message,
    required Channel channel,
  }) async {
    final knotAgentId = getKnotAgentId(agentId);
    
    // 构建任务提示词
    final prompt = _buildPromptFromMessage(message, channel);
    
    // 发送任务
    final task = await _knotApiService.sendTask(
      agentId: knotAgentId,
      prompt: prompt,
      metadata: {
        'source': 'channel',
        'channel_id': channel.id,
        'message_id': message.id,
        'from': message.from.id,
      },
    );

    // 记录任务和频道的映射
    _taskChannelMapping[task.id] = channel.id;

    return task.id;
  }

  /// 构建 Knot 任务提示词
  String _buildPromptFromMessage(Message message, Channel channel) {
    final buffer = StringBuffer();
    
    // 添加上下文信息
    buffer.writeln('# 频道信息');
    buffer.writeln('频道名称: ${channel.name}');
    buffer.writeln('频道类型: ${channel.type}');
    buffer.writeln('成员数量: ${channel.memberCount}');
    buffer.writeln();
    
    // 添加发送者信息
    buffer.writeln('# 消息信息');
    buffer.writeln('发送者: ${message.from.name} (${message.from.type})');
    buffer.writeln('时间: ${message.dateTime}');
    buffer.writeln();
    
    // 添加消息内容
    buffer.writeln('# 消息内容');
    buffer.writeln(message.content);
    buffer.writeln();
    
    // 添加指示
    buffer.writeln('# 请求');
    buffer.writeln('请根据上述消息内容做出回应。');
    
    return buffer.toString();
  }

  /// 轮询 Knot 任务状态并转换为 Channel 消息
  Future<Message?> pollTaskAndConvertToMessage({
    required String taskId,
    required String agentId,
  }) async {
    try {
      final task = await _knotApiService.getTaskStatus(taskId);
      
      // 如果任务未完成，返回 null
      if (!task.isFinished) {
        return null;
      }

      // 获取频道 ID
      final channelId = _taskChannelMapping[taskId];
      if (channelId == null) {
        throw Exception('Task channel mapping not found');
      }

      // 如果任务失败，返回错误消息
      if (task.isFailed) {
        return _createErrorMessage(
          agentId: agentId,
          channelId: channelId,
          error: task.error ?? '任务执行失败',
          taskId: taskId,
        );
      }

      // 创建成功消息
      return _createSuccessMessage(
        agentId: agentId,
        channelId: channelId,
        result: task.result ?? '任务已完成',
        taskId: taskId,
      );
    } catch (e) {
      // 清理映射
      _taskChannelMapping.remove(taskId);
      rethrow;
    }
  }

  /// 创建成功消息
  Message _createSuccessMessage({
    required String agentId,
    required String channelId,
    required String result,
    required String taskId,
  }) {
    return Message(
      id: 'knot_task_$taskId',
      from: MessageFrom(
        id: agentId,
        type: 'agent',
        name: 'Knot Agent',
      ),
      channelId: channelId,
      type: MessageType.text,
      content: result,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 创建错误消息
  Message _createErrorMessage({
    required String agentId,
    required String channelId,
    required String error,
    required String taskId,
  }) {
    return Message(
      id: 'knot_task_error_$taskId',
      from: MessageFrom(
        id: agentId,
        type: 'agent',
        name: 'Knot Agent',
      ),
      channelId: channelId,
      type: MessageType.system,
      content: '⚠️ 任务执行失败: $error',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 清理任务映射
  void clearTaskMapping(String taskId) {
    _taskChannelMapping.remove(taskId);
  }

  /// 获取所有待处理的任务
  List<String> getPendingTasks() {
    return _taskChannelMapping.keys.toList();
  }

  /// 批量获取 Knot Agents 并转换为标准 Agents
  Future<List<Agent>> getKnotAgentsAsStandardAgents() async {
    try {
      final knotAgents = await _knotApiService.getKnotAgents();
      return knotAgents.map((ka) => toStandardAgent(ka)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 释放资源
  void dispose() {
    _taskChannelMapping.clear();
  }
}
