/// ACP Server 服务
/// 实现 WebSocket Server，接收 Agent 主动请求
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/acp_protocol.dart';
import '../models/acp_server_message.dart';
import 'permission_service.dart';
import 'local_api_service.dart';
import 'file_download_service.dart';
import 'local_database_service.dart';
import 'acp_hub_handlers.dart';

/// ACP Server 配置
class ACPServerConfig {
  final String host;
  final int port;
  final int heartbeatInterval;
  final bool enableTLS;
  final String? certPath;
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
  final String id;
  final WebSocket socket;
  String? agentId;
  String? agentName;
  final DateTime connectedAt;
  DateTime lastActivityAt;
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

  void send(Map<String, dynamic> message) {
    socket.add(jsonEncode(message));
    lastActivityAt = DateTime.now();
  }

  void sendResponse(ACPServerResponse response) {
    send(response.toJson());
  }

  Future<void> close() async {
    await socket.close();
  }
}

/// ACP Server 服务
class ACPServerService {
  final ACPServerConfig config;
  final ACPHubHandlers _hubHandlers;

  HttpServer? _server;
  final Map<String, ACPClientConnection> _connections = {};
  final StreamController<ACPServerRequest> _requestController =
      StreamController<ACPServerRequest>.broadcast();
  Timer? _heartbeatTimer;

  bool _isRunning = false;

  /// Called when an inbound agent connection disconnects.
  /// Provides the agentId (if known) so the caller can update status.
  void Function(String? agentId)? onAgentDisconnected;

  /// Called when an inbound agent sends a ui.fileMessage notification.
  /// Provides agentId, agentName, and the notification params.
  void Function(String agentId, String agentName, Map<String, dynamic> params)? onFileMessage;

  // ==================== File Transfer Callbacks ====================

  void Function(String agentId, String fileId, Uint8List chunk)? onFileChunk;
  void Function(String agentId, String fileId, int totalBytes)? onFileTransferComplete;
  void Function(String agentId, String fileId, String error)? onFileTransferError;

  /// Pending requests sent TO agents, keyed by request ID.
  final Map<String, Completer<Map<String, dynamic>>> _pendingServerRequests = {};
  int _serverRequestId = 0;

  ACPServerService({
    required this.config,
    required PermissionService permissionService,
    required LocalApiService apiService,
    FileDownloadService? fileDownloadService,
    LocalDatabaseService? databaseService,
  }) : _hubHandlers = ACPHubHandlers(
          permissionService: permissionService,
          apiService: apiService,
          fileDownloadService: fileDownloadService,
          databaseService: databaseService,
        );

  bool get isRunning => _isRunning;
  int get connectionCount => _connections.length;
  Stream<ACPServerRequest> get requestStream => _requestController.stream;

  Future<void> start() async {
    if (_isRunning) {
      throw StateError('ACP Server already running');
    }

    try {
      _server = await HttpServer.bind(config.host, config.port);
      _isRunning = true;

      print('ACP Server started on ${config.host}:${config.port}');

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

      _startHeartbeat();
    } catch (e) {
      _isRunning = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;
    _heartbeatTimer?.cancel();

    for (final conn in _connections.values) {
      await conn.close();
    }
    _connections.clear();

    await _server?.close();
    _server = null;

    print('ACP Server stopped');
  }

  Future<void> _handleWebSocketUpgrade(HttpRequest request) async {
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      final connectionId = DateTime.now().millisecondsSinceEpoch.toString();

      final connection = ACPClientConnection(
        id: connectionId,
        socket: socket,
      );

      _connections[connectionId] = connection;

      print('New ACP connection: $connectionId');

      socket.listen(
        (message) => _handleMessage(connection, message),
        onError: (error) => _handleError(connection, error),
        onDone: () => _handleDisconnect(connection),
      );
    } catch (e) {
      print('WebSocket upgrade failed: $e');
    }
  }

  Future<void> _handleMessage(
    ACPClientConnection connection,
    dynamic message,
  ) async {
    connection.lastActivityAt = DateTime.now();

    // Handle binary WebSocket frames (file transfer chunks)
    if (message is List<int>) {
      _handleBinaryFrame(connection, Uint8List.fromList(message));
      return;
    }

    try {
      final json = jsonDecode(message as String) as Map<String, dynamic>;

      // Extract agent identity from any message
      final sourceAgentId = json['source_agent_id'] as String?;
      if (connection.agentId == null && sourceAgentId != null) {
        connection.agentId = sourceAgentId;
      }

      final hasId = json.containsKey('id') && json['id'] != null;
      final hasMethod = json.containsKey('method') && json['method'] != null;

      if (hasMethod && !hasId) {
        // JSON-RPC Notification (no id) — e.g. ui.fileMessage, ui.textContent
        _handleNotification(connection, json);
      } else if (hasMethod && hasId) {
        // JSON-RPC Request (has id and method) — e.g. hub.*
        final request = ACPServerRequest.fromJson(json);
        _requestController.add(request);

        final response = await _hubHandlers.handleRequest(
          method: request.method,
          id: request.id,
          params: request.params,
          agentId: connection.agentId,
          agentName: connection.agentName,
        );

        connection.sendResponse(ACPServerResponse(
          jsonrpc: response.jsonrpc,
          id: response.id.toString(),
          result: response.result,
          error: response.error,
        ));
      } else if (hasId && !hasMethod) {
        // Response to a request we sent to the agent
        final id = json['id'].toString();
        final completer = _pendingServerRequests.remove(id);
        if (completer != null && !completer.isCompleted) {
          completer.complete(json);
        }
      }
    } catch (e) {
      print('Failed to process message: $e');
      connection.sendResponse(
        ACPServerResponse.error(
          id: '0',
          code: ACPErrorCode.parseError,
          message: 'Failed to parse message: $e',
        ),
      );
    }
  }

  /// Handle a JSON-RPC notification from an inbound Agent (ui.* methods).
  void _handleNotification(ACPClientConnection connection, Map<String, dynamic> json) {
    final method = json['method'] as String;
    final params = json['params'] as Map<String, dynamic>? ?? {};

    switch (method) {
      case ACPMethod.uiFileMessage:
        final agentId = connection.agentId;
        if (agentId != null) {
          onFileMessage?.call(agentId, connection.agentName ?? 'Agent', params);
        }
        break;
      case ACPMethod.fileTransferComplete:
        final agentId = connection.agentId;
        final fileId = params['file_id'] as String? ?? '';
        final totalBytes = params['total_bytes'] as int? ?? 0;
        if (agentId != null) {
          onFileTransferComplete?.call(agentId, fileId, totalBytes);
        }
        break;
      case ACPMethod.fileTransferError:
        final agentId = connection.agentId;
        final fileId = params['file_id'] as String? ?? '';
        final error = params['error'] as String? ?? 'Unknown error';
        if (agentId != null) {
          onFileTransferError?.call(agentId, fileId, error);
        }
        break;
      default:
        print('[ACPServerService] Unhandled notification: $method');
    }
  }

  /// Parse a binary WebSocket frame containing a file chunk.
  /// Header: [4 bytes magic "FILE"] [12 bytes file_id, null-padded UTF-8] [rest: chunk data]
  void _handleBinaryFrame(ACPClientConnection connection, Uint8List data) {
    if (data.length < 16) return;

    // Validate magic bytes: 0x46494C45 ("FILE")
    if (data[0] != 0x46 || data[1] != 0x49 || data[2] != 0x4C || data[3] != 0x45) {
      print('[ACPServerService] Binary frame with unknown magic, ignoring');
      return;
    }

    // Extract file_id from bytes 4-16 (null-padded UTF-8)
    final fileIdBytes = data.sublist(4, 16);
    int nullIdx = fileIdBytes.indexOf(0);
    if (nullIdx == -1) nullIdx = 12;
    final fileId = String.fromCharCodes(fileIdBytes.sublist(0, nullIdx));

    // Extract payload from byte 16+
    final payload = data.sublist(16);
    final agentId = connection.agentId;
    if (agentId != null) {
      onFileChunk?.call(agentId, fileId, payload);
    }
  }

  /// Send a JSON-RPC request to a specific connected agent and wait for the response.
  Future<Map<String, dynamic>> sendRequestToAgent(
    String agentId,
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    // Find a connection for the given agentId
    ACPClientConnection? targetConn;
    for (final conn in _connections.values) {
      if (conn.agentId == agentId) {
        targetConn = conn;
        break;
      }
    }
    if (targetConn == null) {
      throw Exception('No connection found for agent: $agentId');
    }

    final id = (++_serverRequestId).toString();
    final request = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'id': id,
    };
    if (params != null) {
      request['params'] = params;
    }

    final completer = Completer<Map<String, dynamic>>();
    _pendingServerRequests[id] = completer;

    targetConn.send(request);

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingServerRequests.remove(id);
        throw TimeoutException('Request timeout for $method to agent $agentId');
      },
    );
  }

  void _handleError(ACPClientConnection connection, dynamic error) {
    print('Connection error [${connection.id}]: $error');
  }

  void _handleDisconnect(ACPClientConnection connection) {
    print('Connection closed: ${connection.id} (agent: ${connection.agentId})');
    _connections.remove(connection.id);
    onAgentDisconnected?.call(connection.agentId);
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: config.heartbeatInterval),
      (_) => _checkHeartbeat(),
    );
  }

  void _checkHeartbeat() {
    final now = DateTime.now();
    final timeout = Duration(seconds: config.heartbeatInterval * 2);

    final disconnected = <String>[];
    for (final entry in _connections.entries) {
      if (now.difference(entry.value.lastActivityAt) > timeout) {
        disconnected.add(entry.key);
      }
    }

    for (final id in disconnected) {
      final conn = _connections.remove(id);
      if (conn != null) {
        onAgentDisconnected?.call(conn.agentId);
        conn.close();
      }
      print('Connection timeout: $id');
    }
  }

  void broadcastToChannel(String channelId, Map<String, dynamic> message) {
    for (final conn in _connections.values) {
      if (conn.subscribedChannels.contains(channelId)) {
        conn.send(message);
      }
    }
  }

  void sendToAgent(String agentId, Map<String, dynamic> message) {
    for (final conn in _connections.values) {
      if (conn.agentId == agentId) {
        conn.send(message);
      }
    }
  }
}
