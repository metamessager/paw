/// ACP Server 服务
/// 实现 WebSocket Server，接收 OpenClaw 主动请求
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/acp_server_message.dart';
import '../models/agent.dart';
import 'permission_service.dart';
import 'local_api_service.dart';

/// ACP Server 配置
class ACPServerConfig {
  /// 监听地址
  final String host;
  
  /// 监听端口
  final int port;
  
  /// 心跳间隔（秒）
  final int heartbeatInterval;
  
  /// 是否启用 TLS
  final bool enableTLS;
  
  /// 证书路径
  final String? certPath;
  
  /// 私钥路径
  final String? keyPath;

  ACPServerConfig({
    this.host = '0.0.0.0',
    this.port = 18790,
    this.heartbeatInterval = 30,
    this.enableTLS = false,
    this.certPath,
    this.keyPath,
  });
}

/// ACP 客户端连接
class ACPClientConnection {
  /// 连接 ID
  final String id;
  
  /// WebSocket 连接
  final WebSocket socket;
  
  /// Agent ID
  String? agentId;
  
  /// Agent 名称
  String? agentName;
  
  /// 连接时间
  final DateTime connectedAt;
  
  /// 最后活动时间
  DateTime lastActivityAt;
  
  /// 订阅的 Channel
  final Set<String> subscribedChannels = {};

  ACPClientConnection({
    required this.id,
    required this.socket,
    this.agentId,
    this.agentName,
    DateTime? connectedAt,
    DateTime? lastActivityAt,
  })  : connectedAt = connectedAt ?? DateTime.now(),
        lastActivityAt = lastActivityAt ?? DateTime.now();

  /// 发送消息
  void send(Map<String, dynamic> message) {
    socket.add(jsonEncode(message));
    lastActivityAt = DateTime.now();
  }

  /// 发送响应
  void sendResponse(ACPServerResponse response) {
    send(response.toJson());
  }

  /// 关闭连接
  Future<void> close() async {
    await socket.close();
  }
}

/// ACP Server 服务
class ACPServerService {
  final ACPServerConfig config;
  final PermissionService _permissionService;
  final LocalApiService _apiService;
  
  HttpServer? _server;
  final Map<String, ACPClientConnection> _connections = {};
  final StreamController<ACPServerRequest> _requestController = 
      StreamController<ACPServerRequest>.broadcast();
  Timer? _heartbeatTimer;
  
  bool _isRunning = false;

  ACPServerService({
    required this.config,
    required PermissionService permissionService,
    required LocalApiService apiService,
  })  : _permissionService = permissionService,
        _apiService = apiService;

  /// 是否正在运行
  bool get isRunning => _isRunning;

  /// 当前连接数
  int get connectionCount => _connections.length;

  /// 请求流
  Stream<ACPServerRequest> get requestStream => _requestController.stream;

  /// 启动服务器
  Future<void> start() async {
    if (_isRunning) {
      throw StateError('ACP Server already running');
    }

    try {
      // 启动 HTTP Server
      _server = await HttpServer.bind(config.host, config.port);
      _isRunning = true;

      print('🚀 ACP Server started on ${config.host}:${config.port}');

      // 监听连接
      _server!.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          _handleWebSocketUpgrade(request);
        } else {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write('WebSocket upgrade required')
            ..close();
        }
      });

      // 启动心跳检查
      _startHeartbeat();
    } catch (e) {
      _isRunning = false;
      rethrow;
    }
  }

  /// 停止服务器
  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;
    _heartbeatTimer?.cancel();

    // 关闭所有连接
    for (final conn in _connections.values) {
      await conn.close();
    }
    _connections.clear();

    // 关闭服务器
    await _server?.close();
    _server = null;

    print('🛑 ACP Server stopped');
  }

  /// 处理 WebSocket 升级
  Future<void> _handleWebSocketUpgrade(HttpRequest request) async {
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      final connectionId = DateTime.now().millisecondsSinceEpoch.toString();
      
      final connection = ACPClientConnection(
        id: connectionId,
        socket: socket,
      );

      _connections[connectionId] = connection;

      print('✅ New connection: $connectionId');

      // 监听消息
      socket.listen(
        (message) => _handleMessage(connection, message),
        onError: (error) => _handleError(connection, error),
        onDone: () => _handleDisconnect(connection),
      );
    } catch (e) {
      print('❌ WebSocket upgrade failed: $e');
    }
  }

  /// 处理消息
  Future<void> _handleMessage(
    ACPClientConnection connection,
    dynamic message,
  ) async {
    connection.lastActivityAt = DateTime.now();

    try {
      final json = jsonDecode(message as String);
      final request = ACPServerRequest.fromJson(json);

      // 更新 Agent 信息
      if (connection.agentId == null && request.sourceAgentId != null) {
        connection.agentId = request.sourceAgentId;
      }

      // 分发请求
      _requestController.add(request);

      // 处理请求
      final response = await _processRequest(connection, request);
      connection.sendResponse(response);
    } catch (e) {
      print('❌ Failed to process message: $e');
      connection.sendResponse(
        ACPServerResponse.error(
          id: '0',
          code: ACPErrorCode.parseError,
          message: 'Failed to parse message: $e',
        ),
      );
    }
  }

  /// 处理请求
  Future<ACPServerResponse> _processRequest(
    ACPClientConnection connection,
    ACPServerRequest request,
  ) async {
    try {
      switch (request.requestType) {
        case ACPRequestType.initiateChat:
          return await _handleInitiateChat(connection, request);
        
        case ACPRequestType.getAgentList:
          return await _handleGetAgentList(connection, request);
        
        case ACPRequestType.getAgentCapabilities:
          return await _handleGetAgentCapabilities(connection, request);
        
        case ACPRequestType.getHubInfo:
          return await _handleGetHubInfo(connection, request);
        
        case ACPRequestType.subscribeChannel:
          return await _handleSubscribeChannel(connection, request);
        
        case ACPRequestType.unsubscribeChannel:
          return await _handleUnsubscribeChannel(connection, request);
        
        default:
          return ACPServerResponse.error(
            id: request.id,
            code: ACPErrorCode.methodNotFound,
            message: 'Method not found: ${request.method}',
          );
      }
    } catch (e) {
      return ACPServerResponse.error(
        id: request.id,
        code: ACPErrorCode.internalError,
        message: 'Internal error: $e',
      );
    }
  }

  /// 处理发起聊天请求
  Future<ACPServerResponse> _handleInitiateChat(
    ACPClientConnection connection,
    ACPServerRequest request,
  ) async {
    if (connection.agentId == null) {
      return ACPServerResponse.error(
        id: request.id,
        code: ACPErrorCode.unauthorized,
        message: 'Agent not authenticated',
      );
    }

    // 检查权限
    final hasPermission = await _permissionService.checkPermission(
      agentId: connection.agentId!,
      permissionType: PermissionType.initiateChat,
    );

    if (!hasPermission) {
      // 请求权限
      final permissionRequest = await _permissionService.requestPermission(
        agentId: connection.agentId!,
        agentName: connection.agentName ?? 'Unknown Agent',
        permissionType: PermissionType.initiateChat,
        reason: 'Agent wants to initiate a chat',
        metadata: request.params,
      );

      return ACPServerResponse.error(
        id: request.id,
        code: ACPErrorCode.pendingApproval,
        message: 'Permission request pending user approval',
        data: {'permission_request_id': permissionRequest.id},
      );
    }

    // 解析请求
    final chatRequest = InitiateChatRequest.fromParams(request.params ?? {});

    // TODO: 实现实际的聊天发起逻辑
    // 这里应该创建新消息并发送到目标 Channel

    return ACPServerResponse.success(
      id: request.id,
      result: {
        'status': 'success',
        'message_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'message': 'Chat initiated successfully',
      },
    );
  }

  /// 处理获取 Agent 列表
  Future<ACPServerResponse> _handleGetAgentList(
    ACPClientConnection connection,
    ACPServerRequest request,
  ) async {
    // 检查权限
    if (connection.agentId != null) {
      final hasPermission = await _permissionService.checkPermission(
        agentId: connection.agentId!,
        permissionType: PermissionType.getAgentList,
      );

      if (!hasPermission) {
        return ACPServerResponse.error(
          id: request.id,
          code: ACPErrorCode.permissionDenied,
          message: 'Permission denied to access agent list',
        );
      }
    }

    // 获取 Agent 列表
    final agents = await _apiService.getAgents();

    return ACPServerResponse.success(
      id: request.id,
      result: {
        'agents': agents.map((agent) => {
          'id': agent.id,
          'name': agent.name,
          'type': agent.type ?? agent.provider.type,
          'description': agent.description ?? agent.bio,
          'status': agent.status.state,
        }).toList(),
      },
    );
  }

  /// 处理获取 Agent 能力
  Future<ACPServerResponse> _handleGetAgentCapabilities(
    ACPClientConnection connection,
    ACPServerRequest request,
  ) async {
    final agentId = request.params?['agent_id'];
    if (agentId == null) {
      return ACPServerResponse.error(
        id: request.id,
        code: ACPErrorCode.invalidParams,
        message: 'Missing agent_id parameter',
      );
    }

    // TODO: 实现获取 Agent 能力逻辑
    // 这里应该查询具体 Agent 的能力信息

    return ACPServerResponse.success(
      id: request.id,
      result: {
        'agent_id': agentId,
        'capabilities': ['chat', 'task_execution', 'tool_calling'],
        'tools': ['bash', 'file_system', 'web_search'],
        'is_online': true,
      },
    );
  }

  /// 处理获取 Hub 信息
  Future<ACPServerResponse> _handleGetHubInfo(
    ACPClientConnection connection,
    ACPServerRequest request,
  ) async {
    final agents = await _apiService.getAgents();

    return ACPServerResponse.success(
      id: request.id,
      result: {
        'version': '1.0.0',
        'name': 'AI Agent Hub',
        'supported_protocols': ['ACP/1.0', 'A2A/1.0'],
        'agent_count': agents.length,
        'channel_count': 0, // TODO: 实现 Channel 计数
        'online_user_count': _connections.length,
      },
    );
  }

  /// 处理订阅 Channel
  Future<ACPServerResponse> _handleSubscribeChannel(
    ACPClientConnection connection,
    ACPServerRequest request,
  ) async {
    final channelId = request.params?['channel_id'];
    if (channelId == null) {
      return ACPServerResponse.error(
        id: request.id,
        code: ACPErrorCode.invalidParams,
        message: 'Missing channel_id parameter',
      );
    }

    connection.subscribedChannels.add(channelId);

    return ACPServerResponse.success(
      id: request.id,
      result: {
        'status': 'subscribed',
        'channel_id': channelId,
      },
    );
  }

  /// 处理取消订阅 Channel
  Future<ACPServerResponse> _handleUnsubscribeChannel(
    ACPClientConnection connection,
    ACPServerRequest request,
  ) async {
    final channelId = request.params?['channel_id'];
    if (channelId == null) {
      return ACPServerResponse.error(
        id: request.id,
        code: ACPErrorCode.invalidParams,
        message: 'Missing channel_id parameter',
      );
    }

    connection.subscribedChannels.remove(channelId);

    return ACPServerResponse.success(
      id: request.id,
      result: {
        'status': 'unsubscribed',
        'channel_id': channelId,
      },
    );
  }

  /// 处理错误
  void _handleError(ACPClientConnection connection, dynamic error) {
    print('❌ Connection error [${connection.id}]: $error');
  }

  /// 处理断开连接
  void _handleDisconnect(ACPClientConnection connection) {
    print('👋 Connection closed: ${connection.id}');
    _connections.remove(connection.id);
  }

  /// 启动心跳检查
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: config.heartbeatInterval),
      (_) => _checkHeartbeat(),
    );
  }

  /// 检查心跳
  void _checkHeartbeat() {
    final now = DateTime.now();
    final timeout = Duration(seconds: config.heartbeatInterval * 2);

    final disconnected = <String>[];
    for (final entry in _connections.entries) {
      if (now.difference(entry.value.lastActivityAt) > timeout) {
        disconnected.add(entry.key);
      }
    }

    // 断开超时连接
    for (final id in disconnected) {
      final conn = _connections.remove(id);
      conn?.close();
      print('⏱️ Connection timeout: $id');
    }
  }

  /// 广播消息到订阅的客户端
  void broadcastToChannel(String channelId, Map<String, dynamic> message) {
    for (final conn in _connections.values) {
      if (conn.subscribedChannels.contains(channelId)) {
        conn.send(message);
      }
    }
  }

  /// 发送消息到特定 Agent
  void sendToAgent(String agentId, Map<String, dynamic> message) {
    for (final conn in _connections.values) {
      if (conn.agentId == agentId) {
        conn.send(message);
      }
    }
  }
}
