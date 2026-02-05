/// A2A Agent Card - Agent 的数字名片
/// 符合 Google A2A 协议规范
class A2AAgentCard {
  final String name;
  final String description;
  final String version;
  final A2AEndpoints endpoints;
  final List<String> capabilities;
  final A2AAuthentication? authentication;
  final Map<String, dynamic>? metadata;

  A2AAgentCard({
    required this.name,
    required this.description,
    required this.version,
    required this.endpoints,
    required this.capabilities,
    this.authentication,
    this.metadata,
  });

  factory A2AAgentCard.fromJson(Map<String, dynamic> json) {
    return A2AAgentCard(
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      version: json['version'] ?? '1.0.0',
      endpoints: A2AEndpoints.fromJson(json['endpoints'] ?? {}),
      capabilities: List<String>.from(json['capabilities'] ?? []),
      authentication: json['authentication'] != null
          ? A2AAuthentication.fromJson(json['authentication'])
          : null,
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'version': version,
      'endpoints': endpoints.toJson(),
      'capabilities': capabilities,
      if (authentication != null) 'authentication': authentication!.toJson(),
      if (metadata != null) 'metadata': metadata,
    };
  }
}

/// A2A 端点定义
class A2AEndpoints {
  final String tasks;
  final String? stream;
  final String? status;

  A2AEndpoints({
    required this.tasks,
    this.stream,
    this.status,
  });

  factory A2AEndpoints.fromJson(Map<String, dynamic> json) {
    return A2AEndpoints(
      tasks: json['tasks'] ?? '',
      stream: json['stream'],
      status: json['status'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tasks': tasks,
      if (stream != null) 'stream': stream,
      if (status != null) 'status': status,
    };
  }
}

/// A2A 认证配置
class A2AAuthentication {
  final List<String> schemes;
  final Map<String, dynamic>? config;

  A2AAuthentication({
    required this.schemes,
    this.config,
  });

  factory A2AAuthentication.fromJson(Map<String, dynamic> json) {
    return A2AAuthentication(
      schemes: List<String>.from(json['schemes'] ?? []),
      config: json['config'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemes': schemes,
      if (config != null) 'config': config,
    };
  }
}
