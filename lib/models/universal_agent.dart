import '../models/agent.dart';
import '../models/a2a/agent_card.dart';
import '../models/a2a/task.dart';

/// 通用 Agent 接口
/// 所有 Agent 类型都需要实现此接口
abstract class IUniversalAgent {
  /// Agent 唯一标识
  String get id;

  /// Agent 名称
  String get name;

  /// Agent 头像
  String get avatar;

  /// Agent 简介
  String? get bio;

  /// Agent 类型 (a2a, knot, custom)
  String get type;

  /// Agent 提供商信息
  AgentProvider get provider;

  /// Agent 状态
  AgentStatus get status;

  /// 发送消息
  Future<String> sendMessage(String message);

  /// 提交任务
  Future<A2ATaskResponse> submitTask(A2ATask task);

  /// 获取 Agent Card (A2A 协议)
  Future<A2AAgentCard?> getAgentCard();

  /// 转换为标准 Agent 模型
  Agent toAgent();
}

/// 通用 Agent 基类实现
abstract class UniversalAgent implements IUniversalAgent {
  @override
  final String id;

  @override
  final String name;

  @override
  final String avatar;

  @override
  final String? bio;

  @override
  final String type;

  @override
  final AgentProvider provider;

  @override
  final AgentStatus status;

  UniversalAgent({
    required this.id,
    required this.name,
    required this.avatar,
    this.bio,
    required this.type,
    required this.provider,
    required this.status,
  });

  @override
  Agent toAgent() {
    return Agent(
      id: id,
      name: name,
      avatar: avatar,
      bio: bio,
      provider: provider,
      status: status,
    );
  }

  /// 工厂方法：从 JSON 创建
  factory UniversalAgent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] ?? json['provider']?['type'] ?? 'unknown';

    // 根据类型创建不同的 Agent 实现
    switch (type) {
      case 'a2a':
        return A2AAgent.fromJson(json);
      case 'knot':
        return KnotUniversalAgent.fromJson(json);
      case 'openclaw':
        // OpenClawAgent 需要单独导入
        throw UnimplementedError('Use OpenClawAgent.fromJson() directly');
      default:
        return CustomAgent.fromJson(json);
    }
  }
}

/// A2A 标准 Agent 实现
class A2AAgent extends UniversalAgent {
  final String baseUri;
  final A2AAgentCard? agentCard;
  final String? apiKey;

  A2AAgent({
    required super.id,
    required super.name,
    required super.avatar,
    super.bio,
    required this.baseUri,
    this.agentCard,
    this.apiKey,
    super.status = const AgentStatus(state: 'offline'),
  }) : super(
          type: 'a2a',
          provider: AgentProvider(
            name: 'A2A Agent',
            platform: 'A2A Protocol',
            type: 'a2a',
          ),
        );

  @override
  Future<String> sendMessage(String message) async {
    final task = A2ATask(
      instruction: message,
      metadata: {'timestamp': DateTime.now().millisecondsSinceEpoch},
    );

    final response = await submitTask(task);
    
    // 提取文本响应
    if (response.artifacts != null && response.artifacts!.isNotEmpty) {
      final textParts = response.artifacts!.first.parts
          .where((p) => p.type == 'text')
          .toList();
      if (textParts.isNotEmpty) {
        return textParts.first.content.toString();
      }
    }

    return response.error ?? 'No response';
  }

  @override
  Future<A2ATaskResponse> submitTask(A2ATask task) async {
    // 实现由 A2AProtocolService 提供
    throw UnimplementedError('Use A2AProtocolService.submitTask()');
  }

  @override
  Future<A2AAgentCard?> getAgentCard() async {
    return agentCard;
  }

  factory A2AAgent.fromJson(Map<String, dynamic> json) {
    return A2AAgent(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      avatar: json['avatar'] ?? '🤖',
      bio: json['bio'],
      baseUri: json['base_uri'] ?? '',
      agentCard: json['agent_card'] != null
          ? A2AAgentCard.fromJson(json['agent_card'])
          : null,
      apiKey: json['api_key'],
      status: json['status'] != null
          ? AgentStatus.fromJson(json['status'])
          : const AgentStatus(state: 'offline'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'bio': bio,
      'type': type,
      'base_uri': baseUri,
      'agent_card': agentCard?.toJson(),
      'api_key': apiKey,
      'provider': provider.toJson(),
      'status': {'state': status.state},
    };
  }
}

/// Knot Agent 通用实现 (通过 A2A 协议)
class KnotUniversalAgent extends UniversalAgent {
  final String knotId;
  final String? endpoint; // Knot A2A 端点
  final String? apiToken; // Knot API Token
  final A2AAgentCard? agentCard; // Agent Card (从 Knot 获取)
  final Map<String, dynamic>? config;

  KnotUniversalAgent({
    required super.id,
    required super.name,
    required super.avatar,
    super.bio,
    required this.knotId,
    this.endpoint,
    this.apiToken,
    this.agentCard,
    this.config,
    super.status = const AgentStatus(state: 'offline'),
  }) : super(
          type: 'knot',
          provider: AgentProvider(
            name: 'Knot Agent',
            platform: 'Knot Platform',
            type: 'knot',
          ),
        );

  @override
  Future<String> sendMessage(String message) async {
    // 通过 KnotA2AAdapter 实现
    throw UnimplementedError('Use KnotA2AAdapter through UniversalAgentService');
  }

  @override
  Future<A2ATaskResponse> submitTask(A2ATask task) async {
    // 通过 KnotA2AAdapter 实现
    throw UnimplementedError('Use KnotA2AAdapter through UniversalAgentService');
  }

  @override
  Future<A2AAgentCard?> getAgentCard() async {
    return agentCard;
  }

  factory KnotUniversalAgent.fromJson(Map<String, dynamic> json) {
    return KnotUniversalAgent(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      avatar: json['avatar'] ?? '🤖',
      bio: json['bio'],
      knotId: json['knot_id'] ?? json['id'] ?? '',
      endpoint: json['endpoint'],
      apiToken: json['api_token'],
      agentCard: json['agent_card'] != null
          ? A2AAgentCard.fromJson(json['agent_card'])
          : null,
      config: json['config'],
      status: json['status'] != null
          ? AgentStatus.fromJson(json['status'])
          : const AgentStatus(state: 'offline'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'bio': bio,
      'type': type,
      'knot_id': knotId,
      'endpoint': endpoint,
      'api_token': apiToken,
      'agent_card': agentCard?.toJson(),
      'config': config,
      'provider': provider.toJson(),
      'status': {'state': status.state},
    };
  }
}

/// 自定义 Agent 实现
class CustomAgent extends UniversalAgent {
  final String endpoint;
  final Map<String, String>? headers;

  CustomAgent({
    required super.id,
    required super.name,
    required super.avatar,
    super.bio,
    required this.endpoint,
    this.headers,
    super.status = const AgentStatus(state: 'offline'),
  }) : super(
          type: 'custom',
          provider: AgentProvider(
            name: 'Custom Agent',
            platform: 'Custom',
            type: 'custom',
          ),
        );

  @override
  Future<String> sendMessage(String message) async {
    // 自定义实现
    throw UnimplementedError('Custom implementation required');
  }

  @override
  Future<A2ATaskResponse> submitTask(A2ATask task) async {
    throw UnimplementedError('Custom implementation required');
  }

  @override
  Future<A2AAgentCard?> getAgentCard() async {
    return null;
  }

  factory CustomAgent.fromJson(Map<String, dynamic> json) {
    return CustomAgent(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      avatar: json['avatar'] ?? '🤖',
      bio: json['bio'],
      endpoint: json['endpoint'] ?? '',
      headers: json['headers'] != null
          ? Map<String, String>.from(json['headers'])
          : null,
      status: json['status'] != null
          ? AgentStatus.fromJson(json['status'])
          : const AgentStatus(state: 'offline'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'bio': bio,
      'type': type,
      'endpoint': endpoint,
      'headers': headers,
      'provider': provider.toJson(),
      'status': {'state': status.state},
    };
  }
}