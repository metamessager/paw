import 'dart:async';
import '../models/message.dart';
import '../models/channel.dart';
import '../models/knot_agent.dart';
import 'knot_agent_adapter.dart';

/// Knot Agent 桥接配置
class KnotBridgeConfig {
  final String knotAgentId;
  final String channelId;
  final bool enabled;
  final DateTime createdAt;

  KnotBridgeConfig({
    required this.knotAgentId,
    required this.channelId,
    required this.enabled,
    required this.createdAt,
  });

  factory KnotBridgeConfig.fromJson(Map<String, dynamic> json) {
    return KnotBridgeConfig(
      knotAgentId: json['knot_agent_id'] ?? '',
      channelId: json['channel_id'] ?? '',
      enabled: json['enabled'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'knot_agent_id': knotAgentId,
      'channel_id': channelId,
      'enabled': enabled,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Knot Channel 桥接服务
/// 管理 Knot Agent 与 Channel 之间的消息桥接
class KnotChannelBridgeService {
  final dynamic _knotApiService;  // Accepts KnotApiService or LocalKnotAgentService
  final KnotAgentAdapter _adapter;

  // 桥接配置 (channelId_agentId -> config)
  final Map<String, KnotBridgeConfig> _bridgeConfigs = {};
  // 活跃的任务轮询 (taskId -> Timer)
  final Map<String, Timer> _activePolls = {};

  // 消息回调
  final List<Function(Message)> _messageCallbacks = [];

  KnotChannelBridgeService(this._knotApiService)
      : _adapter = KnotAgentAdapter(_knotApiService);

  /// 添加消息回调
  void addMessageCallback(Function(Message) callback) {
    _messageCallbacks.add(callback);
  }

  /// 移除消息回调
  void removeMessageCallback(Function(Message) callback) {
    _messageCallbacks.remove(callback);
  }

  /// 触发消息回调
  void _triggerMessageCallbacks(Message message) {
    for (var callback in _messageCallbacks) {
      try {
        callback(message);
      } catch (e) {
        print('Error in message callback: $e');
      }
    }
  }

  /// 创建桥接配置
  Future<void> createBridge({
    required String knotAgentId,
    required String channelId,
  }) async {
    final key = '${channelId}_knot_$knotAgentId';
    
    if (_bridgeConfigs.containsKey(key)) {
      throw Exception('Bridge already exists');
    }

    final config = KnotBridgeConfig(
      knotAgentId: knotAgentId,
      channelId: channelId,
      enabled: true,
      createdAt: DateTime.now(),
    );

    _bridgeConfigs[key] = config;
  }

  /// 删除桥接配置
  Future<void> deleteBridge({
    required String knotAgentId,
    required String channelId,
  }) async {
    final key = '${channelId}_knot_$knotAgentId';
    _bridgeConfigs.remove(key);
  }

  /// 启用/禁用桥接
  Future<void> toggleBridge({
    required String knotAgentId,
    required String channelId,
    required bool enabled,
  }) async {
    final key = '${channelId}_knot_$knotAgentId';
    final config = _bridgeConfigs[key];
    
    if (config != null) {
      _bridgeConfigs[key] = KnotBridgeConfig(
        knotAgentId: config.knotAgentId,
        channelId: config.channelId,
        enabled: enabled,
        createdAt: config.createdAt,
      );
    }
  }

  /// 检查是否已桥接
  bool isBridged({
    required String knotAgentId,
    required String channelId,
  }) {
    final key = '${channelId}_knot_$knotAgentId';
    final config = _bridgeConfigs[key];
    return config != null && config.enabled;
  }

  /// 获取频道的所有桥接 Agent
  List<String> getBridgedAgentsForChannel(String channelId) {
    return _bridgeConfigs.values
        .where((c) => c.channelId == channelId && c.enabled)
        .map((c) => 'knot_${c.knotAgentId}')
        .toList();
  }

  /// 处理 Channel 消息（发送到 Knot Agent）
  Future<void> handleChannelMessage({
    required Message message,
    required Channel channel,
  }) async {
    // 获取频道中桥接的 Knot Agents
    final bridgedAgents = getBridgedAgentsForChannel(channel.id);
    
    if (bridgedAgents.isEmpty) {
      return;
    }

    // 对每个桥接的 Agent 发送消息
    for (var agentId in bridgedAgents) {
      // 跳过消息发送者自己
      if (message.from.id == agentId) {
        continue;
      }

      try {
        // 发送到 Knot Agent
        final taskId = await _adapter.sendMessageToKnotAgent(
          agentId: agentId,
          message: message,
          channel: channel,
        );

        // 开始轮询任务状态
        _startTaskPolling(taskId, agentId);
      } catch (e) {
        print('Failed to send message to Knot Agent $agentId: $e');
        
        // 发送错误通知消息
        final errorMessage = Message(
          id: 'error_${DateTime.now().millisecondsSinceEpoch}',
          from: MessageFrom(
            id: 'system',
            type: 'system',
            name: 'System',
          ),
          channelId: channel.id,
          type: MessageType.system,
          content: '⚠️ 发送消息到 Knot Agent 失败: $e',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        );
        _triggerMessageCallbacks(errorMessage);
      }
    }
  }

  /// 开始轮询任务状态
  void _startTaskPolling(String taskId, String agentId) {
    if (_activePolls.containsKey(taskId)) {
      return; // 已经在轮询
    }

    final timer = Timer.periodic(
      Duration(seconds: KnotAgentAdapter.pollInterval),
      (timer) async {
        try {
          final message = await _adapter.pollTaskAndConvertToMessage(
            taskId: taskId,
            agentId: agentId,
          );

          if (message != null) {
            // 任务完成，触发回调
            _triggerMessageCallbacks(message);
            
            // 停止轮询
            timer.cancel();
            _activePolls.remove(taskId);
            _adapter.clearTaskMapping(taskId);
          }
        } catch (e) {
          print('Error polling task $taskId: $e');
          
          // 发生错误，停止轮询
          timer.cancel();
          _activePolls.remove(taskId);
          _adapter.clearTaskMapping(taskId);
        }
      },
    );

    _activePolls[taskId] = timer;
  }

  /// 停止所有轮询
  void stopAllPolling() {
    for (var timer in _activePolls.values) {
      timer.cancel();
    }
    _activePolls.clear();
  }

  /// 获取 Knot Agents 作为标准 Agents
  Future<List<dynamic>> getKnotAgentsAsStandardAgents() async {
    return await _adapter.getKnotAgentsAsStandardAgents();
  }

  /// 获取适配器
  KnotAgentAdapter get adapter => _adapter;

  /// 获取所有桥接配置
  List<KnotBridgeConfig> getAllBridges() {
    return _bridgeConfigs.values.toList();
  }

  /// 获取频道的桥接配置
  List<KnotBridgeConfig> getBridgesForChannel(String channelId) {
    return _bridgeConfigs.values
        .where((c) => c.channelId == channelId)
        .toList();
  }

  /// 导出桥接配置
  List<Map<String, dynamic>> exportBridges() {
    return _bridgeConfigs.values.map((c) => c.toJson()).toList();
  }

  /// 导入桥接配置
  void importBridges(List<Map<String, dynamic>> configs) {
    for (var json in configs) {
      final config = KnotBridgeConfig.fromJson(json);
      final key = '${config.channelId}_knot_${config.knotAgentId}';
      _bridgeConfigs[key] = config;
    }
  }

  /// 释放资源
  void dispose() {
    stopAllPolling();
    _adapter.dispose();
    _bridgeConfigs.clear();
    _messageCallbacks.clear();
  }
}
