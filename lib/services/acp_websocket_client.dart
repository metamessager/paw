/// ACP WebSocket 客户端
/// 用于与 OpenClaw Gateway 建立 WebSocket 连接并通信

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/acp_protocol.dart';

/// ACP WebSocket 客户端
class ACPWebSocketClient {
  /// OpenClaw Gateway URL (例如: ws://localhost:18789)
  final String gatewayUrl;

  /// 认证 Token（可选）
  final String? authToken;

  /// WebSocket 连接
  WebSocketChannel? _channel;

  /// 请求 ID 计数器
  int _requestId = 0;

  /// 响应流控制器
  final Map<dynamic, Completer<ACPResponse>> _responseCompleters = {};

  /// 流式响应控制器
  final Map<dynamic, StreamController<ACPResponse>> _streamControllers = {};

  /// 通知流控制器
  final StreamController<ACPNotification> _notificationController =
      StreamController.broadcast();

  /// 连接状态
  bool _isConnected = false;

  /// 是否已认证
  bool _isAuthenticated = false;

  /// 自动重连
  bool autoReconnect;

  /// 重连延迟（毫秒）
  int reconnectDelay;

  /// 心跳间隔（秒）
  int heartbeatInterval;

  /// 心跳定时器
  Timer? _heartbeatTimer;

  ACPWebSocketClient({
    required this.gatewayUrl,
    this.authToken,
    this.autoReconnect = true,
    this.reconnectDelay = 3000,
    this.heartbeatInterval = 30,
  });

  /// 是否已连接
  bool get isConnected => _isConnected;

  /// 是否已认证
  bool get isAuthenticated => _isAuthenticated;

  /// 通知流
  Stream<ACPNotification> get notifications => _notificationController.stream;

  /// 连接到 OpenClaw Gateway
  Future<void> connect() async {
    if (_isConnected) {
      return; // 已连接
    }

    try {
      final uri = Uri.parse(gatewayUrl);
      _channel = WebSocketChannel.connect(uri);

      // 监听消息
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
        cancelOnError: false,
      );

      _isConnected = true;

      // 如果有 Token，进行认证
      if (authToken != null) {
        await authenticate(authToken!);
      }

      // 启动心跳
      _startHeartbeat();
    } catch (e) {
      _isConnected = false;
      rethrow;
    }
  }

  /// 认证
  Future<void> authenticate(String token) async {
    final request = ACPRequest(
      method: ACPMethod.authenticate,
      params: {'token': token},
      id: _nextRequestId(),
    );

    final response = await sendRequest(request);

    if (response.isError) {
      throw Exception('Authentication failed: ${response.error!.message}');
    }

    _isAuthenticated = true;
  }

  /// 发送请求（等待单个响应）
  Future<ACPResponse> sendRequest(ACPRequest request) async {
    if (!_isConnected) {
      throw Exception('Not connected to OpenClaw Gateway');
    }

    // 创建响应完成器
    final completer = Completer<ACPResponse>();
    _responseCompleters[request.id] = completer;

    // 发送请求
    _channel!.sink.add(request.toJsonString());

    // 等待响应（30秒超时）
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _responseCompleters.remove(request.id);
        throw TimeoutException('Request timeout');
      },
    );
  }

  /// 发送流式请求（接收多个响应）
  Stream<ACPResponse> sendStreamRequest(ACPRequest request) {
    if (!_isConnected) {
      throw Exception('Not connected to OpenClaw Gateway');
    }

    // 创建流控制器
    final controller = StreamController<ACPResponse>();
    _streamControllers[request.id] = controller;

    // 发送请求
    _channel!.sink.add(request.toJsonString());

    return controller.stream;
  }

  /// 断开连接
  void disconnect() {
    _stopHeartbeat();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _isAuthenticated = false;

    // 清理所有待处理的请求
    for (var completer in _responseCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Connection closed'));
      }
    }
    _responseCompleters.clear();

    // 清理所有流控制器
    for (var controller in _streamControllers.values) {
      controller.close();
    }
    _streamControllers.clear();
  }

  /// 处理消息
  void _handleMessage(dynamic message) {
    try {
      final json = jsonDecode(message);

      // 判断是响应还是通知
      if (json.containsKey('id')) {
        // 响应
        final response = ACPResponse.fromJson(json);
        _handleResponse(response);
      } else if (json.containsKey('method')) {
        // 通知
        final notification = ACPNotification.fromJson(json);
        _notificationController.add(notification);
      }
    } catch (e) {
      print('Failed to parse ACP message: $e');
    }
  }

  /// 处理响应
  void _handleResponse(ACPResponse response) {
    // 检查是否是流式响应
    if (_streamControllers.containsKey(response.id)) {
      final controller = _streamControllers[response.id]!;

      // 如果响应标记为完成，关闭流
      if (response.result != null && response.result['done'] == true) {
        controller.close();
        _streamControllers.remove(response.id);
      } else {
        controller.add(response);
      }
    }
    // 检查是否是单次响应
    else if (_responseCompleters.containsKey(response.id)) {
      final completer = _responseCompleters.remove(response.id)!;
      if (!completer.isCompleted) {
        completer.complete(response);
      }
    }
  }

  /// 处理错误
  void _handleError(error) {
    print('WebSocket error: $error');
    if (autoReconnect && !_isConnected) {
      _reconnect();
    }
  }

  /// 处理断开连接
  void _handleDisconnect() {
    _isConnected = false;
    _isAuthenticated = false;
    _stopHeartbeat();

    if (autoReconnect) {
      _reconnect();
    }
  }

  /// 重新连接
  Future<void> _reconnect() async {
    await Future.delayed(Duration(milliseconds: reconnectDelay));
    try {
      await connect();
    } catch (e) {
      print('Reconnection failed: $e');
      if (autoReconnect) {
        _reconnect();
      }
    }
  }

  /// 启动心跳
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: heartbeatInterval),
      (_) => _sendHeartbeat(),
    );
  }

  /// 停止心跳
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 发送心跳
  void _sendHeartbeat() {
    if (!_isConnected) return;

    final request = ACPRequest(
      method: 'ping',
      id: _nextRequestId(),
    );

    sendRequest(request).catchError((e) {
      print('Heartbeat failed: $e');
    });
  }

  /// 生成下一个请求 ID
  int _nextRequestId() => ++_requestId;

  /// 清理资源
  void dispose() {
    disconnect();
    _notificationController.close();
  }
}
