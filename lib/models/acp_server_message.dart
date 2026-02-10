/// ACP Server 消息模型
/// 定义 OpenClaw → Hub 的消息格式
library;

/// ACP 请求类型
enum ACPRequestType {
  /// 发起聊天（需要用户同意）
  initiateChat,
  
  /// 获取 Agent 列表
  getAgentList,
  
  /// 获取 Agent 能力
  getAgentCapabilities,
  
  /// 获取 Hub 信息
  getHubInfo,
  
  /// 订阅 Channel 消息
  subscribeChannel,
  
  /// 取消订阅 Channel 消息
  unsubscribeChannel,

  /// 发送文件到 Hub
  sendFile,

  /// 获取会话列表
  getSessions,

  /// 获取会话消息
  getSessionMessages,

  /// 未知类型
  unknown,
}

/// ACP Server 请求
class ACPServerRequest {
  /// JSON-RPC 版本
  final String jsonrpc;
  
  /// 请求 ID
  final String id;
  
  /// 方法名
  final String method;
  
  /// 参数
  final Map<String, dynamic>? params;
  
  /// 请求时间戳
  final DateTime timestamp;
  
  /// 来源 Agent ID
  final String? sourceAgentId;

  ACPServerRequest({
    required this.jsonrpc,
    required this.id,
    required this.method,
    this.params,
    DateTime? timestamp,
    this.sourceAgentId,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 从 JSON 创建
  factory ACPServerRequest.fromJson(Map<String, dynamic> json) {
    return ACPServerRequest(
      jsonrpc: json['jsonrpc'] ?? '2.0',
      id: json['id'].toString(),
      method: json['method'] ?? '',
      params: json['params'] as Map<String, dynamic>?,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      sourceAgentId: json['source_agent_id'],
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'jsonrpc': jsonrpc,
      'id': id,
      'method': method,
      if (params != null) 'params': params,
      'timestamp': timestamp.toIso8601String(),
      if (sourceAgentId != null) 'source_agent_id': sourceAgentId,
    };
  }

  /// 获取请求类型
  ACPRequestType get requestType {
    switch (method) {
      case 'hub.initiateChat':
        return ACPRequestType.initiateChat;
      case 'hub.getAgentList':
        return ACPRequestType.getAgentList;
      case 'hub.getAgentCapabilities':
        return ACPRequestType.getAgentCapabilities;
      case 'hub.getHubInfo':
        return ACPRequestType.getHubInfo;
      case 'hub.subscribeChannel':
        return ACPRequestType.subscribeChannel;
      case 'hub.unsubscribeChannel':
        return ACPRequestType.unsubscribeChannel;
      case 'hub.sendFile':
        return ACPRequestType.sendFile;
      case 'hub.getSessions':
        return ACPRequestType.getSessions;
      case 'hub.getSessionMessages':
        return ACPRequestType.getSessionMessages;
      default:
        return ACPRequestType.unknown;
    }
  }
}

/// ACP Server 响应
class ACPServerResponse {
  /// JSON-RPC 版本
  final String jsonrpc;
  
  /// 请求 ID
  final String id;
  
  /// 结果数据
  final dynamic result;
  
  /// 错误信息
  final ACPError? error;
  
  /// 响应时间戳
  final DateTime timestamp;

  ACPServerResponse({
    required this.jsonrpc,
    required this.id,
    this.result,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 成功响应
  factory ACPServerResponse.success({
    required String id,
    required dynamic result,
  }) {
    return ACPServerResponse(
      jsonrpc: '2.0',
      id: id,
      result: result,
    );
  }

  /// 错误响应
  factory ACPServerResponse.error({
    required String id,
    required int code,
    required String message,
    dynamic data,
  }) {
    return ACPServerResponse(
      jsonrpc: '2.0',
      id: id,
      error: ACPError(code: code, message: message, data: data),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'jsonrpc': jsonrpc,
      'id': id,
      if (result != null) 'result': result,
      if (error != null) 'error': error!.toJson(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// 从 JSON 创建
  factory ACPServerResponse.fromJson(Map<String, dynamic> json) {
    return ACPServerResponse(
      jsonrpc: json['jsonrpc'] ?? '2.0',
      id: json['id'].toString(),
      result: json['result'],
      error: json['error'] != null 
          ? ACPError.fromJson(json['error']) 
          : null,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }
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

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      if (data != null) 'data': data,
    };
  }

  /// 从 JSON 创建
  factory ACPError.fromJson(Map<String, dynamic> json) {
    return ACPError(
      code: json['code'],
      message: json['message'],
      data: json['data'],
    );
  }
}

/// ACP 错误代码
class ACPErrorCode {
  /// 解析错误
  static const int parseError = -32700;
  
  /// 无效请求
  static const int invalidRequest = -32600;
  
  /// 方法未找到
  static const int methodNotFound = -32601;
  
  /// 无效参数
  static const int invalidParams = -32602;
  
  /// 内部错误
  static const int internalError = -32603;
  
  /// 未授权
  static const int unauthorized = -32001;
  
  /// 权限被拒绝
  static const int permissionDenied = -32002;
  
  /// 资源未找到
  static const int notFound = -32003;
  
  /// 等待用户同意
  static const int pendingApproval = -32004;
}

/// 聊天发起请求
class InitiateChatRequest {
  /// 消息内容
  final String message;
  
  /// 目标用户 ID（可选）
  final String? targetUserId;
  
  /// 目标 Channel ID（可选）
  final String? targetChannelId;
  
  /// 优先级
  final String priority;
  
  /// 是否需要响应
  final bool requiresResponse;

  InitiateChatRequest({
    required this.message,
    this.targetUserId,
    this.targetChannelId,
    this.priority = 'normal',
    this.requiresResponse = false,
  });

  /// 从参数创建
  factory InitiateChatRequest.fromParams(Map<String, dynamic> params) {
    return InitiateChatRequest(
      message: params['message'] ?? '',
      targetUserId: params['target_user_id'],
      targetChannelId: params['target_channel_id'],
      priority: params['priority'] ?? 'normal',
      requiresResponse: params['requires_response'] ?? false,
    );
  }
}

/// Agent 能力信息
class AgentCapabilities {
  /// Agent ID
  final String agentId;
  
  /// Agent 名称
  final String name;
  
  /// 描述
  final String description;
  
  /// 支持的功能
  final List<String> capabilities;
  
  /// 支持的工具
  final List<String> tools;
  
  /// 是否在线
  final bool isOnline;

  AgentCapabilities({
    required this.agentId,
    required this.name,
    required this.description,
    required this.capabilities,
    required this.tools,
    required this.isOnline,
  });

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'agent_id': agentId,
      'name': name,
      'description': description,
      'capabilities': capabilities,
      'tools': tools,
      'is_online': isOnline,
    };
  }
}

/// Hub 信息
class HubInfo {
  /// Hub 版本
  final String version;
  
  /// Hub 名称
  final String name;
  
  /// 支持的协议版本
  final List<String> supportedProtocols;
  
  /// Agent 数量
  final int agentCount;
  
  /// Channel 数量
  final int channelCount;
  
  /// 在线用户数量
  final int onlineUserCount;

  HubInfo({
    required this.version,
    required this.name,
    required this.supportedProtocols,
    required this.agentCount,
    required this.channelCount,
    required this.onlineUserCount,
  });

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'name': name,
      'supported_protocols': supportedProtocols,
      'agent_count': agentCount,
      'channel_count': channelCount,
      'online_user_count': onlineUserCount,
    };
  }
}

/// 发送文件请求
class SendFileRequest {
  /// 文件下载 URL
  final String url;

  /// 文件名
  final String filename;

  /// MIME 类型
  final String mimeType;

  /// 文件大小（字节）
  final int? size;

  /// 目标 Channel ID（可选）
  final String? targetChannelId;

  /// 目标用户 ID（可选）
  final String? targetUserId;

  SendFileRequest({
    required this.url,
    required this.filename,
    required this.mimeType,
    this.size,
    this.targetChannelId,
    this.targetUserId,
  });

  /// 从参数创建
  factory SendFileRequest.fromParams(Map<String, dynamic> params) {
    return SendFileRequest(
      url: params['url'] ?? '',
      filename: params['filename'] ?? '',
      mimeType: params['mime_type'] ?? 'application/octet-stream',
      size: params['size'] as int?,
      targetChannelId: params['target_channel_id'],
      targetUserId: params['target_user_id'],
    );
  }
}

/// 获取会话消息请求
class GetSessionMessagesRequest {
  /// 会话 ID
  final String sessionId;

  /// 消息数量限制
  final int limit;

  GetSessionMessagesRequest({
    required this.sessionId,
    this.limit = 50,
  });

  /// 从参数创建
  factory GetSessionMessagesRequest.fromParams(Map<String, dynamic> params) {
    return GetSessionMessagesRequest(
      sessionId: params['session_id'] ?? '',
      limit: params['limit'] ?? 50,
    );
  }
}
