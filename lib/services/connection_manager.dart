import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import '../models/remote_agent.dart';
import '../models/message.dart';
import 'remote_agent_service.dart';

/// 连接管理器
/// 负责管理远端助手的连接生命周期
class ConnectionManager {
  final RemoteAgentService _agentService;

  // 连接池
  final Map<String, WebSocketChannel> _wsConnections = {};
  final Map<String, http.Client> _httpClients = {};

  // 消息流控制器
  final Map<String, StreamController<Message>> _messageControllers = {};

  // 心跳监控
  Timer? _heartbeatTimer;
  Duration heartbeatInterval = const Duration(seconds: 30);
  Duration heartbeatTimeout = const Duration(seconds: 90);

  // 重连配置
  final Map<String, int> _reconnectAttempts = {};
  final int maxReconnectAttempts = 5;
  final Duration reconnectDelay = const Duration(seconds: 5);

  ConnectionManager(this._agentService);

  // ==================== 连接管理 ====================

  /// 连接远端助手
  ///
  /// [agent] 要连接的助手
  ///
  /// 根据连接类型自动选择 WebSocket 或 HTTP
  Future<void> connectAgent(RemoteAgent agent) async {
    if (agent.endpoint.isEmpty) {
      throw Exception('Agent endpoint is empty');
    }

    try {
      if (agent.connectionType == ConnectionType.websocket) {
        await _connectWebSocket(agent);
      } else {
        await _connectHttp(agent);
      }

      // 更新助手状态为在线
      await _agentService.registerAgentConnection(
        agent.token,
        endpoint: agent.endpoint,
      );

      // 重置重连计数
      _reconnectAttempts[agent.id] = 0;
    } catch (e) {
      await _agentService.markAgentError(agent.id);
      rethrow;
    }
  }

  /// 建立 WebSocket 连接
  Future<void> _connectWebSocket(RemoteAgent agent) async {
    try {
      final uri = Uri.parse(agent.endpoint);
      final channel = WebSocketChannel.connect(uri);

      // 等待连接建立
      await channel.ready;

      // 保存连接
      _wsConnections[agent.id] = channel;

      // 创建消息流控制器
      _messageControllers[agent.id] = StreamController<Message>.broadcast();

      // 监听消息
      channel.stream.listen(
        (data) {
          _handleWebSocketMessage(agent.id, data);
        },
        onError: (error) {
          _handleConnectionError(agent.id, error);
        },
        onDone: () {
          _handleConnectionClosed(agent.id);
        },
      );
    } catch (e) {
      throw Exception('WebSocket connection failed: $e');
    }
  }

  /// 建立 HTTP 连接
  Future<void> _connectHttp(RemoteAgent agent) async {
    try {
      final client = http.Client();

      // 测试连接（发送 ping 请求）
      final uri = Uri.parse('${agent.endpoint}/health');
      final response = await client.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP connection test failed: ${response.statusCode}');
      }

      // 保存客户端
      _httpClients[agent.id] = client;

      // 创建消息流控制器
      _messageControllers[agent.id] = StreamController<Message>.broadcast();
    } catch (e) {
      throw Exception('HTTP connection failed: $e');
    }
  }

  /// 断开助手连接
  Future<void> disconnectAgent(String agentId) async {
    // 关闭 WebSocket 连接
    if (_wsConnections.containsKey(agentId)) {
      await _wsConnections[agentId]?.sink.close();
      _wsConnections.remove(agentId);
    }

    // 关闭 HTTP 客户端
    if (_httpClients.containsKey(agentId)) {
      _httpClients[agentId]?.close();
      _httpClients.remove(agentId);
    }

    // 关闭消息流
    if (_messageControllers.containsKey(agentId)) {
      await _messageControllers[agentId]?.close();
      _messageControllers.remove(agentId);
    }

    // 更新助手状态
    await _agentService.disconnectAgent(agentId);

    // 清除重连计数
    _reconnectAttempts.remove(agentId);
  }

  /// 重连助手
  Future<void> reconnectAgent(String agentId) async {
    final agent = await _agentService.getAgentById(agentId);
    if (agent == null) {
      throw Exception('Agent not found: $agentId');
    }

    // 检查重连次数
    final attempts = _reconnectAttempts[agentId] ?? 0;
    if (attempts >= maxReconnectAttempts) {
      await _agentService.markAgentError(agentId);
      throw Exception('Max reconnect attempts reached for agent: $agentId');
    }

    // 增加重连计数
    _reconnectAttempts[agentId] = attempts + 1;

    // 先断开现有连接
    await disconnectAgent(agentId);

    // 等待一段时间后重连
    await Future.delayed(reconnectDelay);

    // 尝试重新连接
    await connectAgent(agent);
  }

  // ==================== 消息收发 ====================

  /// 发送消息给助手
  ///
  /// [agentId] 助手 ID
  /// [message] 要发送的消息
  Future<void> sendMessage(String agentId, Message message) async {
    final agent = await _agentService.getAgentById(agentId);
    if (agent == null) {
      throw Exception('Agent not found: $agentId');
    }

    if (!agent.isOnline) {
      throw Exception('Agent is not online: $agentId');
    }

    try {
      if (agent.connectionType == ConnectionType.websocket) {
        await _sendWebSocketMessage(agentId, message);
      } else {
        await _sendHttpMessage(agent, message);
      }
    } catch (e) {
      await _agentService.markAgentError(agentId);
      rethrow;
    }
  }

  /// 通过 WebSocket 发送消息
  Future<void> _sendWebSocketMessage(String agentId, Message message) async {
    final channel = _wsConnections[agentId];
    if (channel == null) {
      throw Exception('WebSocket connection not found for agent: $agentId');
    }

    channel.sink.add(message.toJson());
  }

  /// 通过 HTTP 发送消息
  Future<void> _sendHttpMessage(RemoteAgent agent, Message message) async {
    final client = _httpClients[agent.id];
    if (client == null) {
      throw Exception('HTTP client not found for agent: ${agent.id}');
    }

    final uri = Uri.parse('${agent.endpoint}/messages');
    final response = await client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${agent.token}',
      },
      body: message.toJson(),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('HTTP message send failed: ${response.statusCode}');
    }
  }

  /// 接收来自助手的消息流
  ///
  /// [agentId] 助手 ID
  ///
  /// 返回消息流
  Stream<Message> receiveMessages(String agentId) {
    final controller = _messageControllers[agentId];
    if (controller == null) {
      throw Exception('Message stream not found for agent: $agentId');
    }

    return controller.stream;
  }

  // ==================== 消息处理 ====================

  /// 处理 WebSocket 消息
  void _handleWebSocketMessage(String agentId, dynamic data) {
    try {
      // 解析消息
      final message = Message.fromJson(data);

      // 发送到消息流
      _messageControllers[agentId]?.add(message);

      // 更新心跳
      _agentService.updateHeartbeat(agentId);
    } catch (e) {
      // 忽略解析错误，但记录日志
    }
  }

  /// 处理连接错误
  void _handleConnectionError(String agentId, dynamic error) {
    // 标记助手为错误状态
    _agentService.markAgentError(agentId);

    // 尝试重连
    reconnectAgent(agentId).catchError((e) {
      // 重连失败，忽略错误
    });
  }

  /// 处理连接关闭
  void _handleConnectionClosed(String agentId) {
    // 断开连接
    disconnectAgent(agentId).catchError((e) {
      // 断开失败，忽略错误
    });

    // 尝试重连
    reconnectAgent(agentId).catchError((e) {
      // 重连失败，忽略错误
    });
  }

  // ==================== 心跳监控 ====================

  /// 启动心跳监控
  void startHeartbeatMonitor() {
    stopHeartbeatMonitor();

    _heartbeatTimer = Timer.periodic(heartbeatInterval, (timer) {
      checkAgentHeartbeats();
    });
  }

  /// 停止心跳监控
  void stopHeartbeatMonitor() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 检查所有助手的心跳
  void checkAgentHeartbeats() {
    _agentService.handleHeartbeatTimeouts(
      timeoutDuration: heartbeatTimeout,
    ).then((value) {
      // 心跳检查完成
    }).catchError((e) {
      // 心跳检查失败，忽略错误
    });
  }

  // ==================== 连接状态查询 ====================

  /// 检查助手是否已连接
  bool isConnected(String agentId) {
    return _wsConnections.containsKey(agentId) ||
           _httpClients.containsKey(agentId);
  }

  /// 获取所有已连接的助手 ID
  List<String> getConnectedAgentIds() {
    final wsIds = _wsConnections.keys.toList();
    final httpIds = _httpClients.keys.toList();
    return [...wsIds, ...httpIds];
  }

  /// 获取连接统计信息
  Map<String, dynamic> getConnectionStatistics() {
    return {
      'websocket_connections': _wsConnections.length,
      'http_connections': _httpClients.length,
      'total_connections': _wsConnections.length + _httpClients.length,
      'message_streams': _messageControllers.length,
    };
  }

  // ==================== 清理 ====================

  /// 断开所有连接
  Future<void> disconnectAll() async {
    final agentIds = getConnectedAgentIds();
    for (final agentId in agentIds) {
      await disconnectAgent(agentId);
    }
  }

  /// 销毁连接管理器
  Future<void> dispose() async {
    stopHeartbeatMonitor();
    await disconnectAll();
    _reconnectAttempts.clear();
  }
}
