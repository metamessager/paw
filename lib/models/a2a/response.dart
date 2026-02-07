import 'task.dart';

/// A2A 流式响应模型
/// 用于表示 A2A 协议的流式响应（包括 AGUI 事件）
class A2AResponse {
  /// 消息 ID
  final String? messageId;

  /// 任务 ID
  final String? taskId;

  /// 任务状态 (submitted, working, completed, failed)
  final String? state;

  /// 响应类型 (RUN_STARTED, TEXT_MESSAGE_CONTENT, etc.)
  final String? type;

  /// 响应内容（文本内容）
  final String? content;

  /// 思考过程内容
  final String? thinking;

  /// 是否完成
  final bool isDone;

  /// 是否出错
  final bool isError;

  /// 错误信息
  final String? error;

  /// 原始数据
  final Map<String, dynamic>? rawData;

  /// 工具调用信息
  final ToolCall? toolCall;

  /// 进度信息
  final ProgressInfo? progress;

  /// 任务输出（artifacts）
  final List<A2AArtifact>? artifacts;

  A2AResponse({
    this.messageId,
    this.taskId,
    this.state,
    this.type,
    this.content,
    this.thinking,
    this.isDone = false,
    this.isError = false,
    this.error,
    this.rawData,
    this.toolCall,
    this.progress,
    this.artifacts,
  });

  /// 从 AGUI 事件创建
  factory A2AResponse.fromAGUIEvent(Map<String, dynamic> event) {
    final type = event['type'] ?? event['event'] ?? '';
    final data = event['data'] ?? event;

    switch (type) {
      case 'RUN_STARTED':
        return A2AResponse(
          messageId: data['message_id'],
          type: 'RUN_STARTED',
        );

      case 'TEXT_MESSAGE_CONTENT':
      case 'text':
        return A2AResponse(
          messageId: data['message_id'],
          type: 'TEXT_MESSAGE_CONTENT',
          content: data['text']?.toString() ?? data['content']?.toString() ?? '',
        );

      case 'THINKING_MESSAGE_CONTENT':
        return A2AResponse(
          messageId: data['message_id'],
          type: 'THINKING_MESSAGE_CONTENT',
          thinking: data['thinking']?.toString() ?? '',
        );

      case 'TOOL_CALL_STARTED':
        return A2AResponse(
          messageId: data['message_id'],
          type: 'TOOL_CALL_STARTED',
          toolCall: ToolCall(
            id: data['tool_call_id'],
            name: data['tool_name'],
            status: 'started',
          ),
        );

      case 'TOOL_CALL_COMPLETED':
        return A2AResponse(
          messageId: data['message_id'],
          type: 'TOOL_CALL_COMPLETED',
          toolCall: ToolCall(
            id: data['tool_call_id'],
            name: data['tool_name'],
            status: 'completed',
            result: data['result'],
          ),
        );

      case 'PROGRESS':
        return A2AResponse(
          messageId: data['message_id'],
          type: 'PROGRESS',
          progress: ProgressInfo(
            current: data['current']?.toInt() ?? 0,
            total: data['total']?.toInt() ?? 100,
            message: data['message']?.toString(),
          ),
        );

      case 'RUN_COMPLETED':
        return A2AResponse(
          messageId: data['message_id'],
          type: 'RUN_COMPLETED',
          isDone: true,
        );

      case 'RUN_FAILED':
      case 'error':
        return A2AResponse(
          messageId: data['message_id'],
          type: 'RUN_FAILED',
          isDone: true,
          isError: true,
          error: data['error']?.toString() ?? data['message']?.toString() ?? 'Unknown error',
        );

      default:
        return A2AResponse(
          messageId: data['message_id'],
          type: type,
          rawData: event,
        );
    }
  }

  /// 从 JSON 创建
  factory A2AResponse.fromJson(Map<String, dynamic> json) {
    return A2AResponse(
      messageId: json['message_id'],
      taskId: json['task_id'],
      state: json['state'],
      type: json['type'],
      content: json['content'],
      thinking: json['thinking'],
      isDone: json['is_done'] ?? false,
      isError: json['is_error'] ?? false,
      error: json['error'],
      rawData: json['raw_data'],
      toolCall: json['tool_call'] != null ? ToolCall.fromJson(json['tool_call']) : null,
      progress: json['progress'] != null ? ProgressInfo.fromJson(json['progress']) : null,
      artifacts: json['artifacts'] != null
          ? (json['artifacts'] as List).map((e) => A2AArtifact.fromJson(e)).toList()
          : null,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'task_id': taskId,
      'state': state,
      'type': type,
      'content': content,
      'thinking': thinking,
      'is_done': isDone,
      'is_error': isError,
      'error': error,
      'raw_data': rawData,
      'tool_call': toolCall?.toJson(),
      'progress': progress?.toJson(),
      'artifacts': artifacts?.map((e) => e.toJson()).toList(),
    };
  }

  /// 创建副本并修改部分字段
  A2AResponse copyWith({
    String? messageId,
    String? taskId,
    String? state,
    String? type,
    String? content,
    String? thinking,
    bool? isDone,
    bool? isError,
    String? error,
    Map<String, dynamic>? rawData,
    ToolCall? toolCall,
    ProgressInfo? progress,
    List<A2AArtifact>? artifacts,
  }) {
    return A2AResponse(
      messageId: messageId ?? this.messageId,
      taskId: taskId ?? this.taskId,
      state: state ?? this.state,
      type: type ?? this.type,
      content: content ?? this.content,
      thinking: thinking ?? this.thinking,
      isDone: isDone ?? this.isDone,
      isError: isError ?? this.isError,
      error: error ?? this.error,
      rawData: rawData ?? this.rawData,
      toolCall: toolCall ?? this.toolCall,
      progress: progress ?? this.progress,
      artifacts: artifacts ?? this.artifacts,
    );
  }

  /// 是否包含内容
  bool get hasContent => content != null && content!.isNotEmpty;

  /// 是否包含思考内容
  bool get hasThinking => thinking != null && thinking!.isNotEmpty;

  /// 是否包含工具调用
  bool get hasToolCall => toolCall != null;

  /// 是否包含进度信息
  bool get hasProgress => progress != null;

  @override
  String toString() {
    if (isError) return 'A2AResponse(error: $error)';
    if (isDone) return 'A2AResponse(done)';
    if (hasContent) return 'A2AResponse(content: ${content!.length} chars)';
    if (hasThinking) return 'A2AResponse(thinking: ${thinking!.length} chars)';
    if (hasToolCall) return 'A2AResponse(toolCall: ${toolCall!.name})';
    if (hasProgress) return 'A2AResponse(progress: ${progress!.current}/${progress!.total})';
    return 'A2AResponse(type: $type)';
  }
}

/// 工具调用信息
class ToolCall {
  final String? id;
  final String? name;
  final String? status; // started, running, completed, failed
  final dynamic result;
  final String? error;

  ToolCall({
    this.id,
    this.name,
    this.status,
    this.result,
    this.error,
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      id: json['id'],
      name: json['name'],
      status: json['status'],
      result: json['result'],
      error: json['error'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'status': status,
      'result': result,
      'error': error,
    };
  }
}

/// 进度信息
class ProgressInfo {
  final int current;
  final int total;
  final String? message;

  ProgressInfo({
    required this.current,
    required this.total,
    this.message,
  });

  /// 进度百分比 (0-100)
  double get percentage => (current / total * 100).clamp(0, 100);

  factory ProgressInfo.fromJson(Map<String, dynamic> json) {
    return ProgressInfo(
      current: json['current'] ?? 0,
      total: json['total'] ?? 100,
      message: json['message'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'current': current,
      'total': total,
      'message': message,
    };
  }
}
