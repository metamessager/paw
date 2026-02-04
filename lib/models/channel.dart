/// 频道成员
class ChannelMember {
  final String id;
  final String type;
  final String role;
  final int joinedAt;

  ChannelMember({
    required this.id,
    required this.type,
    required this.role,
    required this.joinedAt,
  });

  bool get isAgent => type == 'agent';
  bool get isUser => type == 'user';

  factory ChannelMember.fromJson(Map<String, dynamic> json) {
    return ChannelMember(
      id: json['id'] ?? '',
      type: json['type'] ?? 'user',
      role: json['role'] ?? 'member',
      joinedAt: json['joined_at'] ?? 0,
    );
  }
}

/// 频道 (对话/群聊)
class Channel {
  final String id;
  final String name;
  final String type;
  final List<ChannelMember> members;
  final String createdBy;
  final int createdAt;
  final String? description;
  final String? avatar;

  Channel({
    required this.id,
    required this.name,
    required this.type,
    required this.members,
    required this.createdBy,
    required this.createdAt,
    this.description,
    this.avatar,
  });

  bool get isDM => type == 'dm';
  bool get isGroup => type == 'group';
  bool get isPublic => type == 'public';

  int get memberCount => members.length;

  List<String> get agentIds => 
      members.where((m) => m.isAgent).map((m) => m.id).toList();

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? 'dm',
      members: (json['members'] as List?)
          ?.map((m) => ChannelMember.fromJson(m))
          .toList() ?? [],
      createdBy: json['created_by'] ?? '',
      createdAt: json['created_at'] ?? 0,
      description: json['metadata']?['description'],
      avatar: json['metadata']?['avatar'],
    );
  }
}
