import 'dart:convert';

/// 协议类型
enum ProtocolType {
  a2a,
  acp,
  custom;

  String toJson() => name;

  static ProtocolType fromJson(String value) {
    return ProtocolType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ProtocolType.custom,
    );
  }
}

/// 连接类型
enum ConnectionType {
  websocket,
  http;

  String toJson() => name;

  static ConnectionType fromJson(String value) {
    return ConnectionType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ConnectionType.http,
    );
  }
}

/// 助手状态
enum AgentStatus {
  online,
  offline,
  error;

  String toJson() => name;

  static AgentStatus fromJson(String value) {
    return AgentStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AgentStatus.offline,
    );
  }
}

/// 远端助手模型
class RemoteAgent {
  /// App生成的UUID
  final String id;

  /// 助手显示名称
  final String name;

  /// 头像 emoji/URL
  final String avatar;

  /// 助手描述
  final String? bio;

  // 连接配置
  /// UUID token（用于助手认证）
  final String token;

  /// WebSocket/HTTP 端点 URL
  final String endpoint;

  /// 协议类型
  final ProtocolType protocol;

  /// 连接类型
  final ConnectionType connectionType;

  // 状态
  /// 助手状态
  final AgentStatus status;

  /// 最后心跳时间（毫秒时间戳）
  final int? lastHeartbeat;

  /// 连接时间（毫秒时间戳）
  final int? connectedAt;

  // 能力
  /// 能力列表
  final List<String> capabilities;

  /// 元数据
  final Map<String, dynamic> metadata;

  /// 创建时间（毫秒时间戳）
  final int createdAt;

  /// 更新时间（毫秒时间戳）
  final int updatedAt;

  RemoteAgent({
    required this.id,
    required this.name,
    this.avatar = '🤖',
    this.bio,
    required this.token,
    required this.endpoint,
    required this.protocol,
    required this.connectionType,
    this.status = AgentStatus.offline,
    this.lastHeartbeat,
    this.connectedAt,
    this.capabilities = const [],
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  /// 从 JSON 创建
  factory RemoteAgent.fromJson(Map<String, dynamic> json) {
    return RemoteAgent(
      id: json['id'] as String,
      name: json['name'] as String,
      avatar: json['avatar'] as String? ?? '🤖',
      bio: json['bio'] as String?,
      token: json['token'] as String,
      endpoint: json['endpoint'] as String,
      protocol: ProtocolType.fromJson(json['protocol'] as String),
      connectionType: ConnectionType.fromJson(json['connection_type'] as String),
      status: AgentStatus.fromJson(json['status'] as String? ?? 'offline'),
      lastHeartbeat: json['last_heartbeat'] as int?,
      connectedAt: json['connected_at'] as int?,
      capabilities: json['capabilities'] != null
          ? (jsonDecode(json['capabilities'] as String) as List).cast<String>()
          : [],
      metadata: json['metadata'] != null
          ? jsonDecode(json['metadata'] as String) as Map<String, dynamic>
          : {},
      createdAt: json['created_at'] as int,
      updatedAt: json['updated_at'] as int,
    );
  }

  /// 从数据库行创建
  factory RemoteAgent.fromMap(Map<String, dynamic> map) {
    return RemoteAgent.fromJson(map);
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'bio': bio,
      'token': token,
      'endpoint': endpoint,
      'protocol': protocol.toJson(),
      'connection_type': connectionType.toJson(),
      'status': status.toJson(),
      'last_heartbeat': lastHeartbeat,
      'connected_at': connectedAt,
      'capabilities': jsonEncode(capabilities),
      'metadata': jsonEncode(metadata),
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toMap() {
    return toJson();
  }

  /// 复制并修改部分字段
  RemoteAgent copyWith({
    String? id,
    String? name,
    String? avatar,
    String? bio,
    String? token,
    String? endpoint,
    ProtocolType? protocol,
    ConnectionType? connectionType,
    AgentStatus? status,
    int? lastHeartbeat,
    int? connectedAt,
    List<String>? capabilities,
    Map<String, dynamic>? metadata,
    int? createdAt,
    int? updatedAt,
  }) {
    return RemoteAgent(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      bio: bio ?? this.bio,
      token: token ?? this.token,
      endpoint: endpoint ?? this.endpoint,
      protocol: protocol ?? this.protocol,
      connectionType: connectionType ?? this.connectionType,
      status: status ?? this.status,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
      connectedAt: connectedAt ?? this.connectedAt,
      capabilities: capabilities ?? this.capabilities,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 是否在线
  bool get isOnline => status == AgentStatus.online;

  /// 是否离线
  bool get isOffline => status == AgentStatus.offline;

  /// 是否有错误
  bool get hasError => status == AgentStatus.error;

  /// 获取状态显示文本
  String get statusText {
    switch (status) {
      case AgentStatus.online:
        return '在线';
      case AgentStatus.offline:
        return '离线';
      case AgentStatus.error:
        return '错误';
    }
  }

  /// 获取状态图标
  String get statusIcon {
    switch (status) {
      case AgentStatus.online:
        return '🟢';
      case AgentStatus.offline:
        return '🟡';
      case AgentStatus.error:
        return '🔴';
    }
  }

  /// 获取协议显示名称
  String get protocolName {
    switch (protocol) {
      case ProtocolType.a2a:
        return 'A2A';
      case ProtocolType.acp:
        return 'ACP';
      case ProtocolType.custom:
        return '自定义';
    }
  }

  /// 获取连接类型显示名称
  String get connectionTypeName {
    switch (connectionType) {
      case ConnectionType.websocket:
        return 'WebSocket';
      case ConnectionType.http:
        return 'HTTP';
    }
  }

  @override
  String toString() {
    return 'RemoteAgent(id: $id, name: $name, status: $status, protocol: $protocol)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is RemoteAgent &&
        other.id == id &&
        other.name == name &&
        other.avatar == avatar &&
        other.bio == bio &&
        other.token == token &&
        other.endpoint == endpoint &&
        other.protocol == protocol &&
        other.connectionType == connectionType &&
        other.status == status;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      avatar,
      bio,
      token,
      endpoint,
      protocol,
      connectionType,
      status,
    );
  }
}
