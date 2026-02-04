/// Agent 提供商信息
class AgentProvider {
  final String name;
  final String platform;
  final String type;

  AgentProvider({
    required this.name,
    required this.platform,
    required this.type,
  });

  factory AgentProvider.fromJson(Map<String, dynamic> json) {
    return AgentProvider(
      name: json['name'] ?? '',
      platform: json['platform'] ?? '',
      type: json['type'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'platform': platform,
      'type': type,
    };
  }
}

/// Agent 状态
class AgentStatus {
  final String state;
  final int? connectedAt;
  final int? lastHeartbeat;

  AgentStatus({
    required this.state,
    this.connectedAt,
    this.lastHeartbeat,
  });

  bool get isOnline => state == 'online';

  factory AgentStatus.fromJson(Map<String, dynamic> json) {
    return AgentStatus(
      state: json['state'] ?? 'offline',
      connectedAt: json['connected_at'],
      lastHeartbeat: json['last_heartbeat'],
    );
  }
}

/// Agent 信息
class Agent {
  final String id;
  final String name;
  final String avatar;
  final String? bio;
  final AgentProvider provider;
  final AgentStatus status;

  Agent({
    required this.id,
    required this.name,
    required this.avatar,
    this.bio,
    required this.provider,
    required this.status,
  });

  factory Agent.fromJson(Map<String, dynamic> json) {
    final registration = json['registration'] ?? json;
    final status = json['status'] ?? {'state': 'offline'};

    return Agent(
      id: registration['agent_id'] ?? '',
      name: registration['name'] ?? '',
      avatar: registration['avatar'] ?? '🤖',
      bio: registration['bio'],
      provider: AgentProvider.fromJson(registration['provider'] ?? {}),
      status: AgentStatus.fromJson(status),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'agent_id': id,
      'name': name,
      'avatar': avatar,
      'bio': bio,
      'provider': provider.toJson(),
    };
  }
}
