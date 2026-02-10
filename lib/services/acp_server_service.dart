/// ACP Server 服务
/// 实现 WebSocket Server，接收 OpenClaw 主动请求
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/acp_server_message.dart';
import '../models/agent.dart';
import '../models/channel.dart';
import 'permission_service.dart';
import 'local_api_service.dart';
import 'file_download_service.dart';
import 'local_database_service.dart';
import 'package:uuid/uuid.dart';

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
  final FileDownloadService _fileDownloadService;
  final LocalDatabaseService _databaseService;
  final Uuid _uuid = const Uuid();

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
    FileDownloadService? fileDownloadService,
    LocalDatabaseService? databaseService,
  })  : _permissionService = permissionService,
        _apiService = apiService,
        _fileDownloadService = fileDownloadService ?? FileDownloadService(),
        _databaseService = databaseService ?? LocalDatabaseService();

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

        case ACPRequestType.sendFile:
          return await _handleSendFile(connection, request);

        case ACPRequestType.getSessions:
          return await _handleGetSessions(connection, request);

        case ACPRequestType.getSessionMessages:
          return await _handleGetSessionMessages(connection, request);

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

  /// 处理发送文件请求
  Future<ACPServerResponse> _handleSendFile(
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
      permissionType: PermissionType.sendFile,
    );

    if (!hasPermission) {
      final permissionRequest = await _permissionService.requestPermission(
        agentId: connection.agentId!,
        agentName: connection.agentName ?? 'Unknown Agent',
        permissionType: PermissionType.sendFile,
        reason: 'Agent wants to send a file',
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
    final sendFileReq = SendFileRequest.fromParams(request.params ?? {});

    if (sendFileReq.url.isEmpty) {
      return ACPServerResponse.error(
        id: request.id,
        code: ACPErrorCode.invalidParams,
        message: 'Missing url parameter',
      );
    }

    try {
      // Download file
      final result = await _fileDownloadService.downloadAndSave(
        sendFileReq.url,
        fileName: sendFileReq.filename.isNotEmpty ? sendFileReq.filename : null,
        mimeType: sendFileReq.mimeType,
        expectedSize: sendFileReq.size,
      );

      // Determine channel ID
      final channelId = sendFileReq.targetChannelId ?? '';

      // Build metadata matching existing format
      final metadata = <String, dynamic>{
        'path': result.relativePath,
        'name': result.fileName,
        'type': result.mimeType,
        'size': result.fileSize,
        'source_url': sendFileReq.url,
      };

      final msgType = result.isImage ? 'image' : 'file';
      final messageId = _uuid.v4();

      // Save message to DB
      await _databaseService.createMessage(
        id: messageId,
        channelId: channelId,
        senderId: connection.agentId!,
        senderType: 'agent',
        senderName: connection.agentName ?? 'Agent',
        content: result.isImage
            ? '[Image: ${result.fileName}]'
            : '[File: ${result.fileName}]',
        messageType: msgType,
        metadata: metadata,
      );

      // Broadcast to channel subscribers
      if (channelId.isNotEmpty) {
        broadcastToChannel(channelId, {
          'type': 'file_message',
          'message_id': messageId,
          'file': metadata,
        });
      }

      return ACPServerResponse.success(
        id: request.id,
        result: {
          'status': 'success',
          'message_id': messageId,
          'file': {
            'path': result.relativePath,
            'name': result.fileName,
            'size': result.fileSize,
            'mime_type': result.mimeType,
          },
        },
      );
    } catch (e) {
      return ACPServerResponse.error(
        id: request.id,
        code: ACPErrorCode.internalError,
        message: 'Failed to download file: $e',
      );
    }
  }

  /// 处理获取会话列表请求
  Future<ACPServerResponse> _handleGetSessions(
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

    // 强制审核
    final result = await _permissionService.requestFreshPermissionAndWait(
      agentId: connection.agentId!,
      agentName: connection.agentName ?? 'Unknown Agent',
      permissionType: PermissionType.getSessions,
      reason: 'Agent wants to access your session list',
    );

    // 记录审核消息
    await _recordAuditMessage(
      agentId: connection.agentId!,
      agentName: connection.agentName ?? 'Unknown Agent',
      action: 'getSessions',
      approved: result.approved,
    );

    if (!result.approved) {
      return ACPServerResponse.error(
        id: request.id,
        code: ACPErrorCode.permissionDenied,
        message: 'User denied access to session list',
      );
    }

    // 获取所有 Channel
    final channels = await _databaseService.getAllChannels();

    return ACPServerResponse.success(
      id: request.id,
      result: {
        'sessions': channels.map((ch) => {
          'id': ch.id,
          'name': ch.name,
          'type': ch.type,
          'member_ids': ch.memberIds,
          'is_private': ch.isPrivate,
        }).toList(),
      },
    );
  }

  /// 处理获取会话消息请求
  Future<ACPServerResponse> _handleGetSessionMessages(
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

    // 校验参数
    final sessionId = request.params?['session_id'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      return ACPServerResponse.error(
        id: request.id,
        code: ACPErrorCode.invalidParams,
        message: 'Missing required parameter: session_id',
      );
    }

    final limit = request.params?['limit'] as int? ?? 50;

    // 强制审核
    final result = await _permissionService.requestFreshPermissionAndWait(
      agentId: connection.agentId!,
      agentName: connection.agentName ?? 'Unknown Agent',
      permissionType: PermissionType.getSessionMessages,
      reason: 'Agent wants to read messages from session $sessionId',
      metadata: {'session_id': sessionId, 'limit': limit},
    );

    // 记录审核消息
    await _recordAuditMessage(
      agentId: connection.agentId!,
      agentName: connection.agentName ?? 'Unknown Agent',
      action: 'getSessionMessages',
      approved: result.approved,
      extra: {'session_id': sessionId, 'limit': limit},
    );

    if (!result.approved) {
      return ACPServerResponse.error(
        id: request.id,
        code: ACPErrorCode.permissionDenied,
        message: 'User denied access to session messages',
      );
    }

    // 获取消息
    final messageMaps = await _databaseService.getChannelMessages(
      sessionId,
      limit: limit,
    );

    final messages = messageMaps.map((m) => {
      'id': m['id'],
      'sender_id': m['sender_id'],
      'sender_name': m['sender_name'],
      'content': m['content'],
      'message_type': m['message_type'],
      'created_at': m['created_at'],
    }).toList();

    return ACPServerResponse.success(
      id: request.id,
      result: {
        'session_id': sessionId,
        'messages': messages,
        'count': messages.length,
      },
    );
  }

  /// 记录审核消息到聊天记录
  Future<void> _recordAuditMessage({
    required String agentId,
    required String agentName,
    required String action,
    required bool approved,
    Map<String, dynamic>? extra,
  }) async {
    try {
      // 找到 Agent 最近的 channel，或创建一个审核专用 channel
      final channels = await _databaseService.getChannelsForAgent(agentId);
      String channelId;

      if (channels.isNotEmpty) {
        channelId = channels.first.id;
      } else {
        channelId = 'system_audit_$agentId';
        // 创建审核 channel
        final channel = Channel.withMemberIds(
          id: channelId,
          name: 'Audit: $agentName',
          type: 'dm',
          memberIds: ['system', agentId],
          isPrivate: true,
        );
        await _databaseService.createChannel(channel, 'system');
      }

      final messageId = _uuid.v4();
      final now = DateTime.now();
      final metadata = {
        'permission_audit': {
          'agent_id': agentId,
          'agent_name': agentName,
          'action': action,
          'approved': approved,
          'timestamp': now.toIso8601String(),
          if (extra != null) ...extra,
        },
      };

      await _databaseService.createMessage(
        id: messageId,
        channelId: channelId,
        senderId: 'system',
        senderType: 'system',
        senderName: 'System',
        content: approved
            ? 'Permission granted: $agentName requested $action'
            : 'Permission denied: $agentName requested $action',
        messageType: 'permission_audit',
        metadata: metadata,
      );
    } catch (e) {
      print('❌ Failed to record audit message: $e');
    }
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
