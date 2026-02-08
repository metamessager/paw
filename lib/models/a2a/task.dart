/// A2A Task - 任务请求
/// 符合 Google A2A 协议规范
class A2ATask {
  final String? id;
  final String instruction;
  final List<A2APart>? context;
  final Map<String, dynamic>? userExperience;
  final Map<String, dynamic>? metadata;

  A2ATask({
    this.id,
    required this.instruction,
    this.context,
    this.userExperience,
    this.metadata,
  });

  factory A2ATask.fromJson(Map<String, dynamic> json) {
    return A2ATask(
      id: json['id'],
      instruction: json['instruction'] ?? '',
      context: json['context'] != null
          ? (json['context'] as List)
              .map((e) => A2APart.fromJson(e))
              .toList()
          : null,
      userExperience: json['user_experience'],
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    // Support both standard A2A format and Knot-specific format
    // For Mock servers, we need task_id and a2a.input fields
    final standardFormat = {
      if (id != null) 'id': id,
      if (id != null) 'task_id': id, // Knot format expects task_id
      'instruction': instruction,
      'a2a': {
        'input': instruction, // Knot format expects a2a.input
      },
      if (context != null)
        'context': context!.map((e) => e.toJson()).toList(),
      if (userExperience != null) 'user_experience': userExperience,
      if (metadata != null) 'metadata': metadata,
    };
    return standardFormat;
  }
}

/// A2A Task Response - 任务响应
class A2ATaskResponse {
  final String taskId;
  final String state;
  final int? createdAt;
  final int? updatedAt;
  final List<A2AArtifact>? artifacts;
  final String? error;

  A2ATaskResponse({
    required this.taskId,
    required this.state,
    this.createdAt,
    this.updatedAt,
    this.artifacts,
    this.error,
  });

  bool get isCompleted => state == 'completed';
  bool get isFailed => state == 'failed';
  bool get isRunning => state == 'working' || state == 'submitted';

  factory A2ATaskResponse.fromJson(Map<String, dynamic> json) {
    return A2ATaskResponse(
      taskId: json['task_id'] ?? json['id'] ?? '',
      state: json['state'] ?? 'submitted',
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      artifacts: json['artifacts'] != null
          ? (json['artifacts'] as List)
              .map((e) => A2AArtifact.fromJson(e))
              .toList()
          : null,
      error: json['error'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'task_id': taskId,
      'state': state,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (artifacts != null)
        'artifacts': artifacts!.map((e) => e.toJson()).toList(),
      if (error != null) 'error': error,
    };
  }
}

/// A2A Artifact - 任务输出
class A2AArtifact {
  final String name;
  final List<A2APart> parts;
  final Map<String, dynamic>? metadata;

  A2AArtifact({
    required this.name,
    required this.parts,
    this.metadata,
  });

  factory A2AArtifact.fromJson(Map<String, dynamic> json) {
    return A2AArtifact(
      name: json['name'] ?? '',
      parts: (json['parts'] as List)
          .map((e) => A2APart.fromJson(e))
          .toList(),
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'parts': parts.map((e) => e.toJson()).toList(),
      if (metadata != null) 'metadata': metadata,
    };
  }
}

/// A2A Part - 多模态内容片段
class A2APart {
  final String type; // text, json, image, audio, video, binary
  final dynamic content;
  final Map<String, dynamic>? metadata;

  A2APart({
    required this.type,
    required this.content,
    this.metadata,
  });

  factory A2APart.fromJson(Map<String, dynamic> json) {
    return A2APart(
      type: json['type'] ?? 'text',
      content: json['content'],
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'content': content,
      if (metadata != null) 'metadata': metadata,
    };
  }

  // 便捷构造函数
  factory A2APart.text(String text) {
    return A2APart(type: 'text', content: text);
  }

  factory A2APart.json(Map<String, dynamic> json) {
    return A2APart(type: 'json', content: json);
  }

  factory A2APart.image(String url) {
    return A2APart(type: 'image', content: url);
  }
}
