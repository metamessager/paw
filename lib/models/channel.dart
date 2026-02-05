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
  final bool isPrivate;
  final int? unreadCount;
  final String? lastMessage;
  final DateTime? lastMessageTime;

  Channel({
    required this.id,
    required this.name,
    required this.type,
    required this.members,
    this.createdBy = '',
    this.createdAt = 0,
    this.description,
    this.avatar,
    this.isPrivate = true,
    this.unreadCount,
    this.lastMessage,
    this.lastMessageTime,
  });

  /// Factory constructor that accepts memberIds for convenience
  factory Channel.withMemberIds({
    required String id,
    required String name,
    required String type,
    required List<String> memberIds,
    String createdBy = '',
    int createdAt = 0,
    String? description,
    String? avatar,
    bool isPrivate = true,
    int? unreadCount,
    String? lastMessage,
    DateTime? lastMessageTime,
  }) {
    return Channel(
      id: id,
      name: name,
      type: type,
      members: memberIds.map((id) => ChannelMember(
        id: id,
        type: 'user',
        role: 'member',
        joinedAt: DateTime.now().millisecondsSinceEpoch,
      )).toList(),
      createdBy: createdBy,
      createdAt: createdAt,
      description: description,
      avatar: avatar,
      isPrivate: isPrivate,
      unreadCount: unreadCount,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
    );
  }

  bool get isDM => type == 'dm';
  bool get isGroup => type == 'group';
  bool get isPublic => type == 'public';

  int get memberCount => members.length;

  List<String> get agentIds => 
      members.where((m) => m.isAgent).map((m) => m.id).toList();

  List<String> get memberIds =>
      members.map((m) => m.id).toList();

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
      isPrivate: json['is_private'] ?? true,
      unreadCount: json['unread_count'],
    );
  }

  Channel copyWith({
    String? id,
    String? name,
    String? type,
    List<ChannelMember>? members,
    String? createdBy,
    int? createdAt,
    String? description,
    String? avatar,
    bool? isPrivate,
    int? unreadCount,
    String? lastMessage,
    DateTime? lastMessageTime,
  }) {
    return Channel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      members: members ?? this.members,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      description: description ?? this.description,
      avatar: avatar ?? this.avatar,
      isPrivate: isPrivate ?? this.isPrivate,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
    );
  }
}
