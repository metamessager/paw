/// ACP (Agent Client Protocol) 协议实现
/// 基于 JSON-RPC 2.0，用于与 OpenClaw Gateway 通信

import 'dart:convert';

/// ACP 请求
class ACPRequest {
  /// JSON-RPC 版本（固定为 2.0）
  final String jsonrpc = '2.0';

  /// 方法名称
  /// 常用方法:
  /// - chat: 对话
  /// - executeTask: 执行任务
  /// - streamResponse: 流式响应
  /// - authenticate: 认证
  final String method;

  /// 请求参数
  final Map<String, dynamic>? params;

  /// 请求 ID（用于匹配响应）
  final dynamic id;

  ACPRequest({
    required this.method,
    this.params,
    required this.id,
  });

  Map<String, dynamic> toJson() {
    return {
      'jsonrpc': jsonrpc,
      'method': method,
      if (params != null) 'params': params,
      'id': id,
    };
  }

  String toJsonString() => jsonEncode(toJson());
}

/// ACP 响应
class ACPResponse {
  /// JSON-RPC 版本
  final String jsonrpc;

  /// 响应结果（成功时）
  final dynamic result;

  /// 错误信息（失败时）
  final ACPError? error;

  /// 请求 ID（与请求匹配）
  final dynamic id;

  ACPResponse({
    required this.jsonrpc,
    this.result,
    this.error,
    required this.id,
  });

  factory ACPResponse.fromJson(Map<String, dynamic> json) {
    return ACPResponse(
      jsonrpc: json['jsonrpc'] ?? '2.0',
      result: json['result'],
      error: json['error'] != null ? ACPError.fromJson(json['error']) : null,
      id: json['id'],
    );
  }

  factory ACPResponse.fromJsonString(String jsonString) {
    return ACPResponse.fromJson(jsonDecode(jsonString));
  }

  /// 是否成功
  bool get isSuccess => error == null;

  /// 是否失败
  bool get isError => error != null;
}

/// ACP 错误
class ACPError {
  /// 错误代码
  final int code;

  /// 错误消息
  final String message;

  /// 额外数据
  final dynamic data;

  ACPError({
    required this.code,
    required this.message,
    this.data,
  });

  factory ACPError.fromJson(Map<String, dynamic> json) {
    return ACPError(
      code: json['code'] ?? -1,
      message: json['message'] ?? 'Unknown error',
      data: json['data'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      if (data != null) 'data': data,
    };
  }

  @override
  String toString() => 'ACPError($code): $message';
}

/// ACP 通知（服务器主动推送，无 id）
class ACPNotification {
  /// JSON-RPC 版本
  final String jsonrpc = '2.0';

  /// 方法名称
  final String method;

  /// 参数
  final Map<String, dynamic>? params;

  ACPNotification({
    required this.method,
    this.params,
  });

  factory ACPNotification.fromJson(Map<String, dynamic> json) {
    return ACPNotification(
      method: json['method'] ?? '',
      params: json['params'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'jsonrpc': jsonrpc,
      'method': method,
      if (params != null) 'params': params,
    };
  }
}

/// ACP 方法枚举
class ACPMethod {
  /// 对话
  static const String chat = 'chat';

  /// 执行任务
  static const String executeTask = 'executeTask';

  /// 流式响应
  static const String streamResponse = 'streamResponse';

  /// 认证
  static const String authenticate = 'authenticate';

  /// 获取状态
  static const String getStatus = 'getStatus';

  /// 获取工具列表
  static const String getTools = 'getTools';

  /// 取消任务
  static const String cancelTask = 'cancelTask';
}

/// ACP 错误代码
class ACPErrorCode {
  /// 解析错误
  static const int parseError = -32700;

  /// 无效请求
  static const int invalidRequest = -32600;

  /// 方法不存在
  static const int methodNotFound = -32601;

  /// 无效参数
  static const int invalidParams = -32602;

  /// 内部错误
  static const int internalError = -32603;

  /// 认证失败
  static const int authenticationFailed = -32000;

  /// 会话不存在
  static const int sessionNotFound = -32001;

  /// 任务失败
  static const int taskFailed = -32002;

  /// 超时
  static const int timeout = -32003;
}
