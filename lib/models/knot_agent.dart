import 'agent.dart';

/// Knot Agent 配置
class KnotAgentConfig {
  final String model;
  final String? systemPrompt;
  final List<String> mcpServers;
  final Map<String, dynamic> capabilities;

  KnotAgentConfig({
    required this.model,
    this.systemPrompt,
    this.mcpServers = const [],
    this.capabilities = const {},
  });

  factory KnotAgentConfig.fromJson(Map<String, dynamic> json) {
    return KnotAgentConfig(
      model: json['model'] ?? 'deepseek-v3.1-Terminus',
      systemPrompt: json['system_prompt'],
      mcpServers: (json['mcp_servers'] as List?)
          ?.map((e) => e.toString())
          .toList() ?? [],
      capabilities: json['capabilities'] ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'model': model,
      'system_prompt': systemPrompt,
      'mcp_servers': mcpServers,
      'capabilities': capabilities,
    };
  }
}

/// Knot Agent（OpenClaw 风格）
class KnotAgent extends Agent {
  final String knotAgentId;
  final String? workspaceId;
  final String? workspacePath;
  final KnotAgentConfig config;

  KnotAgent({
    required String id,
    required String name,
    String? avatar,
    String? bio,
    required this.knotAgentId,
    this.workspaceId,
    this.workspacePath,
    required this.config,
    AgentStatus? status,
  }) : super(
    id: id,
    name: name,
    avatar: avatar ?? '🌐',
    bio: bio,
    provider: AgentProvider(
      name: 'Knot',
      platform: 'knot',
      type: 'openclaw-style',
    ),
    status: status ?? AgentStatus(state: 'offline'),
  );

  factory KnotAgent.fromJson(Map<String, dynamic> json) {
    return KnotAgent(
      id: json['id'] ?? json['agent_id'] ?? '',
      name: json['name'] ?? '',
      avatar: json['avatar'],
      bio: json['bio'],
      knotAgentId: json['knot_agent_id'] ?? json['id'] ?? '',
      workspaceId: json['workspace_id'],
      workspacePath: json['workspace_path'],
      config: KnotAgentConfig.fromJson(json['config'] ?? {}),
      status: json['status'] != null 
          ? AgentStatus.fromJson(json['status'])
          : null,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'knot_agent_id': knotAgentId,
      'workspace_id': workspaceId,
      'workspace_path': workspacePath,
      'config': config.toJson(),
    });
    return json;
  }
}

/// Knot 工作区
class KnotWorkspace {
  final String id;
  final String name;
  final String path;
  final String type; // anydev, local, remote
  final String? description;

  KnotWorkspace({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    this.description,
  });

  factory KnotWorkspace.fromJson(Map<String, dynamic> json) {
    return KnotWorkspace(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      type: json['type'] ?? 'anydev',
      description: json['description'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'type': type,
      'description': description,
    };
  }
}

/// Knot 任务
class KnotTask {
  final String id;
  final String agentId;
  final String prompt;
  final String status; // pending, running, completed, failed
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? result;
  final String? error;
  final Map<String, dynamic>? metadata;

  KnotTask({
    required this.id,
    required this.agentId,
    required this.prompt,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.result,
    this.error,
    this.metadata,
  });

  bool get isPending => status == 'pending';
  bool get isRunning => status == 'running';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isFinished => isCompleted || isFailed;

  factory KnotTask.fromJson(Map<String, dynamic> json) {
    return KnotTask(
      id: json['id'] ?? json['task_id'] ?? '',
      agentId: json['agent_id'] ?? '',
      prompt: json['prompt'] ?? '',
      status: json['status'] ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'])
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
      result: json['result'],
      error: json['error'],
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'agent_id': agentId,
      'prompt': prompt,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'result': result,
      'error': error,
      'metadata': metadata,
    };
  }
}
