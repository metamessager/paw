import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/message.dart';
import '../models/channel.dart';
import '../models/agent.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';

class WebSocketService {
  final String wsUrl;
  WebSocketChannel? _channel;
  final _messageController = StreamController<Message>.broadcast();
  final _channelController = StreamController<Channel>.broadcast();
  final _agentController = StreamController<Agent>.broadcast();

  Stream<Message> get messageStream => _messageController.stream;
  Stream<Channel> get channelStream => _channelController.stream;
  Stream<Agent> get agentStream => _agentController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;

  WebSocketService({String? wsUrl}) 
      : wsUrl = wsUrl ?? AppConfig.current.wsBaseUrl;

  /// 连接 WebSocket
  Future<void> connect() async {
    if (_isConnected) return;
    
    _manualDisconnect = false;

    try {
      AppLogger.info('正在连接 WebSocket: $wsUrl');
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      _reconnectAttempts = 0;

      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          AppLogger.error('WebSocket error', error);
          _isConnected = false;
          _scheduleReconnect();
        },
        onDone: () {
          AppLogger.warning('WebSocket连接已关闭');
          _isConnected = false;
          _scheduleReconnect();
        },
      );

      AppLogger.info('✓ WebSocket连接成功');
    } catch (e) {
      AppLogger.error('✗ WebSocket连接失败', e);
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  /// 安排重连（指数退避）
  void _scheduleReconnect() {
    if (_manualDisconnect || _reconnectAttempts >= _maxReconnectAttempts) {
      if (_reconnectAttempts >= _maxReconnectAttempts) {
        AppLogger.error('WebSocket重连失败，已达到最大重试次数');
      }
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: (2 * _reconnectAttempts).clamp(1, 30));
    
    AppLogger.info('将在 ${delay.inSeconds} 秒后重连 (尝试 $_reconnectAttempts/$_maxReconnectAttempts)');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_isConnected && !_manualDisconnect) {
        connect();
      }
    });
  }

  /// 处理收到的消息
  void _handleMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String);
      final type = json['type'];

      switch (type) {
        case 'message':
          final message = Message.fromJson(json['data']);
          _messageController.add(message);
          AppLogger.debug('收到消息: ${message.id}');
          break;

        case 'channel_created':
          final channel = Channel.fromJson(json['data']);
          _channelController.add(channel);
          AppLogger.debug('频道已创建: ${channel.id}');
          break;

        case 'agent_registered':
          final agent = Agent.fromJson(json['data']);
          _agentController.add(agent);
          AppLogger.debug('Agent已注册: ${agent.id}');
          break;

        case 'login_success':
          AppLogger.info('✓ WebSocket登录成功');
          break;

        default:
          AppLogger.warning('未知的WebSocket消息类型: $type');
      }
    } catch (e, stackTrace) {
      AppLogger.error('解析WebSocket消息失败', e, stackTrace);
    }
  }

  /// 发送登录消息
  void login(String username, String avatar) {
    if (!_isConnected) {
      AppLogger.warning('WebSocket未连接，无法发送登录消息');
      return;
    }

    final message = jsonEncode({
      'type': 'login',
      'username': username,
      'avatar': avatar,
    });

    _channel?.sink.add(message);
    AppLogger.debug('发送登录消息: $username');
  }

  /// 断开连接
  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    AppLogger.info('WebSocket手动断开连接');
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _channelController.close();
    _agentController.close();
  }
}
