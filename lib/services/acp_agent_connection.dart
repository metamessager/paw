/// ACP Agent Connection
/// Manages a single WebSocket connection to a remote Agent,
/// implementing bidirectional JSON-RPC 2.0 communication.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/acp_protocol.dart';
import 'acp_hub_handlers.dart';
import 'ui_component_registry.dart';

/// Cancellation token for ACP protocol operations.
/// Sends `agent.cancelTask` to the remote Agent when cancelled,
/// and invokes a local [onCancelled] callback so the waiting
/// `taskCompleter` can be resolved immediately without relying
/// on the remote Agent to respond.
class ACPCancellationToken {
  bool _isCancelled = false;
  ACPAgentConnection? _connection;
  String? _taskId;

  /// Callback invoked synchronously when [cancel] is called.
  /// Used by the chat service to complete the task completer locally.
  void Function()? onCancelled;

  bool get isCancelled => _isCancelled;

  void bind(ACPAgentConnection connection, String taskId) {
    _connection = connection;
    _taskId = taskId;
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    // Notify local listeners first so the UI unblocks immediately.
    onCancelled?.call();
    // Then best-effort tell the remote Agent to stop.
    if (_connection != null && _taskId != null) {
      _connection!.cancelTask(_taskId!).catchError((_) => ACPResponse(jsonrpc: '2.0', id: 0));
    }
  }
}

/// Manages a single WebSocket connection to a remote Agent.
///
/// Implements the full ACP bidirectional JSON-RPC 2.0 protocol:
/// - App -> Agent: requests (agent.chat, agent.cancelTask, etc.)
/// - Agent -> App: notifications (ui.textContent, task.*, etc.)
/// - Agent -> App: requests (hub.*) delegated to [ACPHubHandlers]
class ACPAgentConnection {
  final String agentId;
  final ACPHubHandlers? _hubHandlers;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  int _requestId = 0;
  bool _isConnected = false;
  bool _isAuthenticated = false;
  String? _wsUrl;
  String? _token;

  /// Pending request completers (keyed by request ID)
  final Map<dynamic, Completer<ACPResponse>> _pendingRequests = {};

  /// Heartbeat timer
  Timer? _heartbeatTimer;
  final int heartbeatIntervalSeconds;
  int _consecutiveHeartbeatFailures = 0;
  final int maxHeartbeatFailures;

  /// Auto-reconnect
  final bool autoReconnect;
  final int reconnectDelayMs;
  int _reconnectAttempts = 0;
  final int maxReconnectAttempts;

  // ==================== UI Event Callbacks ====================

  void Function(Map<String, dynamic> data)? onTextContent;
  void Function(Map<String, dynamic> data)? onActionConfirmation;
  void Function(Map<String, dynamic> data)? onSingleSelect;
  void Function(Map<String, dynamic> data)? onMultiSelect;
  void Function(Map<String, dynamic> data)? onFileUpload;
  void Function(Map<String, dynamic> data)? onForm;
  void Function(Map<String, dynamic> data)? onFileMessage;
  void Function(Map<String, dynamic> data)? onMessageMetadata;
  void Function(Map<String, dynamic> data)? onRequestHistory;
  void Function(Map<String, dynamic> data)? onTaskStarted;
  void Function(Map<String, dynamic> data)? onTaskCompleted;
  void Function(Map<String, dynamic> data)? onTaskError;

  // ==================== File Transfer Callbacks ====================

  void Function(String fileId, Uint8List chunk)? onFileChunk;
  void Function(String fileId, int totalBytes)? onFileTransferComplete;
  void Function(String fileId, String error)? onFileTransferError;

  /// Called when connection state changes
  void Function(bool isConnected)? onConnectionStateChanged;

  ACPAgentConnection({
    required this.agentId,
    ACPHubHandlers? hubHandlers,
    this.heartbeatIntervalSeconds = 30,
    this.autoReconnect = true,
    this.reconnectDelayMs = 3000,
    this.maxReconnectAttempts = 5,
    this.maxHeartbeatFailures = 3,
  }) : _hubHandlers = hubHandlers;

  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated;

  /// Connect to the Agent's WebSocket endpoint and authenticate.
  Future<void> connect(String wsUrl, String token) async {
    if (_isConnected) return;

    _wsUrl = wsUrl;
    _token = token;

    try {
      final uri = Uri.parse(wsUrl);
      _channel = WebSocketChannel.connect(uri);

      // Wait for connection to be ready
      await _channel!.ready;

      _isConnected = true;
      _reconnectAttempts = 0;
      _consecutiveHeartbeatFailures = 0;
      onConnectionStateChanged?.call(true);

      // Listen for messages
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
        cancelOnError: false,
      );

      // Authenticate
      await authenticate(token);

      // Start heartbeat
      _startHeartbeat();

      print('[ACPAgentConnection] Connected to $wsUrl');
    } catch (e) {
      _isConnected = false;
      onConnectionStateChanged?.call(false);
      rethrow;
    }
  }

  /// Disconnect from the Agent.
  Future<void> disconnect() async {
    _stopHeartbeat();
    _subscription?.cancel();
    _subscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}

    _channel = null;
    _isConnected = false;
    _isAuthenticated = false;
    onConnectionStateChanged?.call(false);

    // Fail all pending requests
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Connection closed'));
      }
    }
    _pendingRequests.clear();
  }

  /// Authenticate with the Agent.
  Future<ACPResponse> authenticate(String token) async {
    final response = await sendRequest(
      ACPMethod.authAuthenticate,
      params: {'token': token},
    );

    if (response.isSuccess) {
      _isAuthenticated = true;
    } else {
      throw Exception('Authentication failed: ${response.error?.message}');
    }

    return response;
  }

  /// Send a chat message to the Agent.
  Future<ACPResponse> sendChatMessage({
    required String taskId,
    required String sessionId,
    required String message,
    required String userId,
    required String messageId,
    List<Map<String, String>>? history,
    bool historySupplement = false,
    List<Map<String, String>>? additionalHistory,
    String? originalQuestion,
    int? totalMessageCount,
    String? systemPrompt,
    Map<String, dynamic>? groupContext,
    List<Map<String, dynamic>>? attachments,
  }) async {
    final params = <String, dynamic>{
      'task_id': taskId,
      'session_id': sessionId,
      'message': message,
      'user_id': userId,
      'message_id': messageId,
    };

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      params['system_prompt'] = systemPrompt;
    }

    if (history != null && history.isNotEmpty) {
      params['history'] = history;
    }

    if (totalMessageCount != null) {
      params['total_message_count'] = totalMessageCount;
    }

    params['ui_component_version'] = UIComponentRegistry.version;

    if (historySupplement) {
      params['history_supplement'] = true;
      if (additionalHistory != null) {
        params['additional_history'] = additionalHistory;
      }
      if (originalQuestion != null) {
        params['original_question'] = originalQuestion;
      }
    }

    if (groupContext != null && groupContext.isNotEmpty) {
      params['group_context'] = groupContext;
    }

    if (attachments != null && attachments.isNotEmpty) {
      params['attachments'] = attachments;
    }

    return await sendRequest(ACPMethod.agentChat, params: params);
  }

  /// Cancel a running task.
  Future<ACPResponse> cancelTask(String taskId) async {
    return await sendRequest(
      ACPMethod.agentCancelTask,
      params: {'task_id': taskId},
    );
  }

  /// Submit an interactive response (action confirmation, select, form, etc.)
  Future<ACPResponse> submitResponse({
    required String taskId,
    required String responseType,
    required Map<String, dynamic> responseData,
  }) async {
    return await sendRequest(
      ACPMethod.agentSubmitResponse,
      params: {
        'task_id': taskId,
        'response_type': responseType,
        'response_data': responseData,
      },
    );
  }

  /// Rollback a message.
  Future<ACPResponse> rollback({
    required String sessionId,
    required String messageId,
  }) async {
    return await sendRequest(
      ACPMethod.agentRollback,
      params: {
        'session_id': sessionId,
        'message_id': messageId,
      },
    );
  }

  /// Get the Agent card.
  Future<ACPResponse> getAgentCard() async {
    return await sendRequest(ACPMethod.agentGetCard);
  }

  /// Send a ping.
  Future<ACPResponse> ping() async {
    return await sendRequest(ACPMethod.ping);
  }

  // ==================== Low-level send/receive ====================

  /// Send a JSON-RPC request and wait for response.
  Future<ACPResponse> sendRequest(String method, {Map<String, dynamic>? params}) async {
    if (!_isConnected) {
      throw Exception('Not connected to Agent');
    }

    final id = _nextRequestId();
    final request = ACPRequest(method: method, params: params, id: id);

    final completer = Completer<ACPResponse>();
    _pendingRequests[id] = completer;

    _channel!.sink.add(request.toJsonString());

    return completer.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('Request timeout for $method');
      },
    );
  }

  /// Send a JSON-RPC notification (no response expected).
  void sendNotification(String method, {Map<String, dynamic>? params}) {
    if (!_isConnected) return;

    final notification = ACPNotification(method: method, params: params);
    _channel!.sink.add(notification.toJsonString());
  }

  // ==================== Message handling ====================

  void _handleMessage(dynamic rawMessage) {
    try {
      // Handle binary WebSocket frames (file transfer chunks)
      if (rawMessage is List<int>) {
        _handleBinaryFrame(Uint8List.fromList(rawMessage));
        return;
      }

      final json = jsonDecode(rawMessage as String) as Map<String, dynamic>;

      final hasId = json.containsKey('id') && json['id'] != null;
      final hasMethod = json.containsKey('method') && json['method'] != null;

      if (hasId && hasMethod) {
        // Agent -> App Request (has both id and method, e.g. hub.*)
        _handleIncomingRequest(json);
      } else if (hasId && !hasMethod) {
        // Response to our request (has id, no method)
        _handleResponse(json);
      } else if (hasMethod && !hasId) {
        // Notification from Agent (has method, no id, e.g. ui.*, task.*)
        _handleNotification(json);
      }
    } catch (e) {
      print('[ACPAgentConnection] Failed to parse message: $e');
    }
  }

  /// Handle a response to one of our pending requests.
  void _handleResponse(Map<String, dynamic> json) {
    final response = ACPResponse.fromJson(json);
    final completer = _pendingRequests.remove(response.id);

    if (completer != null && !completer.isCompleted) {
      completer.complete(response);
    }
  }

  /// Handle an incoming request from the Agent (hub.* methods).
  Future<void> _handleIncomingRequest(Map<String, dynamic> json) async {
    final request = ACPRequest.fromJson(json);

    if (_hubHandlers != null) {
      final response = await _hubHandlers!.handleRequest(
        method: request.method,
        id: request.id,
        params: request.params,
        agentId: agentId,
      );
      _channel?.sink.add(response.toJsonString());
    } else {
      // No full hub handlers — handle lightweight requests directly
      final response = _handleRequestWithoutHubHandlers(request);
      _channel?.sink.add(response.toJsonString());
    }
  }

  /// Handle select hub requests that don't require full ACPHubHandlers.
  ACPResponse _handleRequestWithoutHubHandlers(ACPRequest request) {
    if (request.method == ACPMethod.hubGetUIComponentTemplates) {
      return ACPResponse.success(
        id: request.id,
        result: UIComponentRegistry.instance.toTemplatePayload(),
      );
    }
    return ACPResponse.error(
      id: request.id,
      code: ACPErrorCode.methodNotFound,
      message: 'Hub handlers not available for: ${request.method}',
    );
  }

  /// Handle a notification from the Agent (ui.* and task.* methods).
  void _handleNotification(Map<String, dynamic> json) {
    final method = json['method'] as String;
    final params = json['params'] as Map<String, dynamic>? ?? {};

    switch (method) {
      case ACPMethod.uiTextContent:
        onTextContent?.call(params);
        break;
      case ACPMethod.uiActionConfirmation:
        onActionConfirmation?.call(params);
        break;
      case ACPMethod.uiSingleSelect:
        onSingleSelect?.call(params);
        break;
      case ACPMethod.uiMultiSelect:
        onMultiSelect?.call(params);
        break;
      case ACPMethod.uiFileUpload:
        onFileUpload?.call(params);
        break;
      case ACPMethod.uiForm:
        onForm?.call(params);
        break;
      case ACPMethod.uiFileMessage:
        onFileMessage?.call(params);
        break;
      case ACPMethod.uiMessageMetadata:
        onMessageMetadata?.call(params);
        break;
      case ACPMethod.uiRequestHistory:
        onRequestHistory?.call(params);
        break;
      case ACPMethod.taskStarted:
        onTaskStarted?.call(params);
        break;
      case ACPMethod.taskCompleted:
        onTaskCompleted?.call(params);
        break;
      case ACPMethod.taskError:
        onTaskError?.call(params);
        break;
      case ACPMethod.fileTransferComplete:
        final fileId = params['file_id'] as String? ?? '';
        final totalBytes = params['total_bytes'] as int? ?? 0;
        onFileTransferComplete?.call(fileId, totalBytes);
        break;
      case ACPMethod.fileTransferError:
        final fileId = params['file_id'] as String? ?? '';
        final error = params['error'] as String? ?? 'Unknown error';
        onFileTransferError?.call(fileId, error);
        break;
      default:
        print('[ACPAgentConnection] Unknown notification: $method');
    }
  }

  // ==================== Binary frame handling ====================

  /// Parse a binary WebSocket frame containing a file chunk.
  /// Header: [4 bytes magic "FILE"] [12 bytes file_id, null-padded UTF-8] [rest: chunk data]
  void _handleBinaryFrame(Uint8List data) {
    if (data.length < 16) return; // Too short to contain header

    // Validate magic bytes: 0x46494C45 ("FILE")
    if (data[0] != 0x46 || data[1] != 0x49 || data[2] != 0x4C || data[3] != 0x45) {
      print('[ACPAgentConnection] Binary frame with unknown magic, ignoring');
      return;
    }

    // Extract file_id from bytes 4-16 (null-padded UTF-8)
    final fileIdBytes = data.sublist(4, 16);
    int nullIdx = fileIdBytes.indexOf(0);
    if (nullIdx == -1) nullIdx = 12;
    final fileId = String.fromCharCodes(fileIdBytes.sublist(0, nullIdx));

    // Extract payload from byte 16+
    final payload = data.sublist(16);

    onFileChunk?.call(fileId, payload);
  }

  // ==================== Connection lifecycle ====================

  void _handleError(dynamic error) {
    print('[ACPAgentConnection] WebSocket error: $error');
    if (autoReconnect) {
      _tryReconnect();
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isAuthenticated = false;
    _stopHeartbeat();
    onConnectionStateChanged?.call(false);

    if (autoReconnect) {
      _tryReconnect();
    }
  }

  Future<void> _tryReconnect() async {
    if (_wsUrl == null || _token == null) return;
    if (_reconnectAttempts >= maxReconnectAttempts) {
      print('[ACPAgentConnection] Max reconnect attempts reached');
      return;
    }

    _reconnectAttempts++;
    await Future.delayed(Duration(milliseconds: reconnectDelayMs));

    try {
      await connect(_wsUrl!, _token!);
    } catch (e) {
      print('[ACPAgentConnection] Reconnect failed: $e');
      if (autoReconnect && _reconnectAttempts < maxReconnectAttempts) {
        _tryReconnect();
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: heartbeatIntervalSeconds),
      (_) => _sendHeartbeat(),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendHeartbeat() {
    if (!_isConnected) return;
    ping().then((_) {
      _consecutiveHeartbeatFailures = 0;
    }).catchError((e) {
      _consecutiveHeartbeatFailures++;
      print('[ACPAgentConnection] Heartbeat failed ($_consecutiveHeartbeatFailures/$maxHeartbeatFailures): $e');
      if (_consecutiveHeartbeatFailures >= maxHeartbeatFailures) {
        print('[ACPAgentConnection] Max heartbeat failures reached, disconnecting');
        disconnect();
      }
    });
  }

  int _nextRequestId() => ++_requestId;

  /// Clean up resources.
  void dispose() {
    disconnect();
  }
}
