import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/agent.dart';
import '../models/channel.dart';
import '../models/remote_agent.dart' as remote_agent;
/// 本地数据库服务 - 使用 SQLite 存储所有数据
class LocalDatabaseService {
  static final LocalDatabaseService _instance = LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  Database? _database;
  final _uuid = const Uuid();

  /// 生成UUID
  String _generateUuid() => _uuid.v4();

  /// 获取数据库实例
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    String path;
    
    if (kIsWeb) {
      // Web平台使用sqflite_common_ffi
      return await openDatabase(
        'ai_agent_hub',
        version: 3,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } else {
      // 移动平台使用sqflite
      final databasePath = await getDatabasesPath();
      path = join(databasePath, 'ai_agent_hub.db');

      return await openDatabase(
        path,
        version: 3,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
  }

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    // 用户表
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        email TEXT,
        avatar_path TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Agent 表（远端助手）
    await db.execute('''
      CREATE TABLE agents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        avatar TEXT DEFAULT '🤖',
        bio TEXT,

        -- Connection
        token TEXT UNIQUE NOT NULL,
        endpoint TEXT NOT NULL,
        protocol TEXT NOT NULL,
        connection_type TEXT NOT NULL,

        -- Status
        status TEXT DEFAULT 'offline',
        last_heartbeat INTEGER,
        connected_at INTEGER,

        -- Config
        capabilities TEXT,
        metadata TEXT,

        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // A2A Agent Card 缓存表
    await db.execute('''
      CREATE TABLE agent_cards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        agent_id TEXT UNIQUE NOT NULL,
        card_data TEXT NOT NULL,
        cached_at INTEGER NOT NULL,
        FOREIGN KEY (agent_id) REFERENCES agents (id) ON DELETE CASCADE
      )
    ''');

    // 通用任务表 (支持 A2A 和其他协议)
    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id TEXT UNIQUE NOT NULL,
        agent_id TEXT NOT NULL,
        instruction TEXT NOT NULL,
        state TEXT NOT NULL,
        request_data TEXT NOT NULL,
        response_data TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (agent_id) REFERENCES agents (id) ON DELETE CASCADE
      )
    ''');

    // Channel 表
    await db.execute('''
      CREATE TABLE channels (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        type TEXT NOT NULL,
        avatar_path TEXT,
        is_private INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        created_by TEXT NOT NULL
      )
    ''');

    // Channel 成员表
    await db.execute('''
      CREATE TABLE channel_members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT NOT NULL,
        agent_id TEXT NOT NULL,
        role TEXT DEFAULT 'member',
        joined_at TEXT NOT NULL,
        UNIQUE(channel_id, agent_id),
        FOREIGN KEY (channel_id) REFERENCES channels (id) ON DELETE CASCADE,
        FOREIGN KEY (agent_id) REFERENCES agents (id) ON DELETE CASCADE
      )
    ''');

    // 消息表
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        channel_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        sender_type TEXT NOT NULL,
        content TEXT NOT NULL,
        message_type TEXT DEFAULT 'text',
        metadata TEXT,
        reply_to_id TEXT,
        created_at TEXT NOT NULL,
        is_read INTEGER DEFAULT 0,
        FOREIGN KEY (channel_id) REFERENCES channels (id) ON DELETE CASCADE
      )
    ''');

    // Agent 对话请求表
    await db.execute('''
      CREATE TABLE conversation_requests (
        id TEXT PRIMARY KEY,
        requester_id TEXT NOT NULL,
        target_id TEXT NOT NULL,
        purpose TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        metadata TEXT,
        requested_at TEXT NOT NULL,
        responded_at TEXT,
        response_reason TEXT,
        FOREIGN KEY (requester_id) REFERENCES agents (id) ON DELETE CASCADE,
        FOREIGN KEY (target_id) REFERENCES agents (id) ON DELETE CASCADE
      )
    ''');

    // 文件/资源表
    await db.execute('''
      CREATE TABLE resources (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        file_type TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        mime_type TEXT,
        thumbnail_path TEXT,
        owner_id TEXT NOT NULL,
        owner_type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        metadata TEXT
      )
    ''');

    // 创建索引 (P0: 性能优化)
    await db.execute('CREATE INDEX idx_agents_token ON agents(token)');
    await db.execute('CREATE INDEX idx_agents_status ON agents(status)');
    await db.execute('CREATE INDEX idx_agents_last_heartbeat ON agents(last_heartbeat)');
    await db.execute('CREATE INDEX idx_tasks_agent ON tasks(agent_id)');
    await db.execute('CREATE INDEX idx_tasks_state ON tasks(state)');
    await db.execute('CREATE INDEX idx_tasks_created ON tasks(created_at)');
    await db.execute('CREATE INDEX idx_messages_channel ON messages(channel_id)');
    await db.execute('CREATE INDEX idx_messages_created ON messages(created_at DESC)');
    await db.execute('CREATE INDEX idx_messages_sender ON messages(sender_id)');
    await db.execute('CREATE INDEX idx_messages_read ON messages(is_read)');
    await db.execute('CREATE INDEX idx_channels_created_by ON channels(created_by)');
    await db.execute('CREATE INDEX idx_channels_type ON channels(type)');
    await db.execute('CREATE INDEX idx_channel_members_agent ON channel_members(agent_id)');
    await db.execute('CREATE INDEX idx_conversation_requests_status ON conversation_requests(status)');
    await db.execute('CREATE INDEX idx_conversation_requests_target ON conversation_requests(target_id)');
    await db.execute('CREATE INDEX idx_resources_owner ON resources(owner_id, owner_type)');

    // 复合索引用于常见查询
    await db.execute('CREATE INDEX idx_messages_channel_created ON messages(channel_id, created_at DESC)');
    await db.execute('CREATE INDEX idx_tasks_agent_state ON tasks(agent_id, state)');

    // Phase 2 优化: 未读消息查询
    await db.execute('CREATE INDEX idx_messages_channel_read ON messages(channel_id, is_read, created_at DESC)');

    // Phase 2 优化: Agent Card 缓存管理
    await db.execute('CREATE INDEX idx_agent_cards_cached ON agent_cards(cached_at)');

    // Phase 2 优化: 对话请求查询
    await db.execute('CREATE INDEX idx_conversation_requests_target_status ON conversation_requests(target_id, status)');
    await db.execute('CREATE INDEX idx_conversation_requests_requester ON conversation_requests(requester_id, requested_at DESC)');

    // Phase 2 优化: 发送者在 Channel 中的消息
    await db.execute('CREATE INDEX idx_messages_sender_channel ON messages(sender_id, channel_id, created_at DESC)');
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 版本 1 -> 2: 添加 knot_agents 表的缺失字段
      await db.execute('ALTER TABLE knot_agents ADD COLUMN knot_agent_id TEXT DEFAULT ""');
      await db.execute('ALTER TABLE knot_agents ADD COLUMN workspace_path TEXT');

      // 更新现有记录，将 knot_agent_id 设置为与 id 相同（如果为空）
      await db.execute('UPDATE knot_agents SET knot_agent_id = id WHERE knot_agent_id = ""');
    }

    if (oldVersion < 3) {
      // 版本 2 -> 3: 重构为远端助手管理系统

      // Step 1: 创建备份表
      await db.execute('ALTER TABLE agents RENAME TO agents_backup');

      // Step 2: 创建新的 agents 表（远端助手模型）
      await db.execute('''
        CREATE TABLE agents (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          avatar TEXT DEFAULT '🤖',
          bio TEXT,

          -- Connection
          token TEXT UNIQUE NOT NULL,
          endpoint TEXT NOT NULL,
          protocol TEXT NOT NULL,
          connection_type TEXT NOT NULL,

          -- Status
          status TEXT DEFAULT 'offline',
          last_heartbeat INTEGER,
          connected_at INTEGER,

          -- Config
          capabilities TEXT,
          metadata TEXT,

          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');

      // Step 3: 创建索引
      await db.execute('CREATE INDEX idx_agents_token ON agents(token)');
      await db.execute('CREATE INDEX idx_agents_status ON agents(status)');
      await db.execute('CREATE INDEX idx_agents_last_heartbeat ON agents(last_heartbeat)');

      // Step 4: 迁移兼容的 A2A agents（如果有的话）
      // 注意：这只会迁移有完整信息的 agents
      await db.execute('''
        INSERT OR IGNORE INTO agents (
          id, name, avatar, bio, token, endpoint, protocol,
          connection_type, status, capabilities, metadata,
          created_at, updated_at
        )
        SELECT
          id,
          name,
          COALESCE(avatar_path, '🤖'),
          description,
          COALESCE(
            json_extract(metadata, '\$.token'),
            lower(hex(randomblob(16))) || '-' ||
            lower(hex(randomblob(2))) || '-4' ||
            substr(lower(hex(randomblob(2))), 2) || '-' ||
            lower(hex(randomblob(2))) || '-' ||
            lower(hex(randomblob(6)))
          ),
          COALESCE(json_extract(metadata, '\$.endpoint'), ''),
          'a2a',
          'http',
          COALESCE(status, 'offline'),
          capabilities,
          metadata,
          CAST(strftime('%s', created_at) AS INTEGER) * 1000,
          CAST(strftime('%s', updated_at) AS INTEGER) * 1000
        FROM agents_backup
        WHERE type = 'a2a' OR type IS NULL
      ''');

      // Step 5: 删除 Knot 相关表
      await db.execute('DROP TABLE IF EXISTS knot_agents');
      await db.execute('DROP TABLE IF EXISTS knot_tasks');
      await db.execute('DROP TABLE IF EXISTS channel_knot_bridges');

      // Step 6: 删除备份表
      await db.execute('DROP TABLE agents_backup');

      // Step 7: 清理 tasks 表，只保留与现存 agents 关联的记录
      await db.execute('''
        DELETE FROM tasks
        WHERE agent_id NOT IN (SELECT id FROM agents)
      ''');
    }
  }

  // ==================== 用户操作 ====================

  /// 创建用户
  Future<void> createUser({
    required String id,
    required String username,
    required String passwordHash,
    required String salt,
    String? email,
    String? avatarPath,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'users',
      {
        'id': id,
        'username': username,
        'password_hash': passwordHash,
        'salt': salt,
        'email': email,
        'avatar_path': avatarPath,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 根据用户名获取用户
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final db = await database;
    final results = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
    );
    return results.isEmpty ? null : results.first;
  }

  /// 更新用户密码
  Future<void> updateUserPassword(String userId, String newPasswordHash, String newSalt) async {
    final db = await database;
    await db.update(
      'users',
      {
        'password_hash': newPasswordHash,
        'salt': newSalt,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  // ==================== Agent 操作 ====================

  /// 创建 Agent
  Future<void> createAgent(Agent agent, String ownerId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'agents',
      {
        'id': agent.id,
        'name': agent.name,
        'avatar': agent.avatar,
        'bio': agent.description,
        'token': agent.metadata?['token'] ?? _generateUuid(),
        'endpoint': agent.metadata?['endpoint'] ?? '',
        'protocol': agent.metadata?['protocol'] ?? 'a2a',
        'connection_type': agent.metadata?['connection_type'] ?? 'http',
        'status': agent.status.state,
        'capabilities': jsonEncode(agent.capabilities),
        'metadata': jsonEncode(agent.metadata ?? {}),
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取所有 Agent
  Future<List<Agent>> getAllAgents() async {
    final db = await database;
    final results = await db.query('agents', orderBy: 'created_at DESC');
    return results.map((map) => _agentFromMap(map)).toList();
  }

  /// 根据 ID 获取 Agent
  Future<Agent?> getAgentById(String id) async {
    final db = await database;
    final results = await db.query('agents', where: 'id = ?', whereArgs: [id]);
    return results.isEmpty ? null : _agentFromMap(results.first);
  }

  /// 更新 Agent
  Future<void> updateAgent(Agent agent) async {
    final db = await database;
    await db.update(
      'agents',
      {
        'name': agent.name,
        'avatar': agent.avatar,
        'bio': agent.description,
        'status': agent.status.state,
        'capabilities': jsonEncode(agent.capabilities ?? []),
        'metadata': jsonEncode(agent.metadata ?? {}),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [agent.id],
    );
  }

  /// 删除 Agent
  Future<void> deleteAgent(String id) async {
    final db = await database;
    await db.delete('agents', where: 'id = ?', whereArgs: [id]);
  }

  Agent _agentFromMap(Map<String, dynamic> map) {
    final metadata = map['metadata'] != null
        ? Map<String, dynamic>.from(jsonDecode(map['metadata']))
        : <String, dynamic>{};

    return Agent(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Unknown Agent',
      avatar: map['avatar'] ?? '🤖',
      description: map['bio'],
      model: metadata['model'],
      systemPrompt: metadata['system_prompt'],
      temperature: metadata['temperature']?.toDouble(),
      maxTokens: metadata['max_tokens'],
      type: map['protocol'] ?? 'a2a',
      provider: AgentProvider(
        name: metadata['provider_name'] ?? 'Unknown',
        platform: map['protocol'] ?? 'unknown',
        type: metadata['provider_type'] ?? 'llm',
      ),
      status: AgentStatus(
        state: map['status'] ?? 'offline',
        connectedAt: map['connected_at'],
        lastHeartbeat: map['last_heartbeat'],
      ),
      capabilities: map['capabilities'] != null
          ? List<String>.from(jsonDecode(map['capabilities']))
          : [],
      metadata: metadata,
    );
  }

  // ==================== Channel 操作 ====================

  /// 创建 Channel
  Future<void> createChannel(Channel channel, String createdBy) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'channels',
      {
        'id': channel.id,
        'name': channel.name,
        'description': channel.description,
        'type': channel.type,
        'avatar_path': channel.avatar,
        'is_private': channel.isPrivate ? 1 : 0,
        'created_at': now,
        'updated_at': now,
        'created_by': createdBy,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 添加成员
    for (final memberId in channel.memberIds) {
      await addChannelMember(channel.id, memberId);
    }
  }

  /// 获取所有 Channel
  Future<List<Channel>> getAllChannels() async {
    final db = await database;
    final results = await db.query('channels', orderBy: 'created_at DESC');
    
    List<Channel> channels = [];
    for (final map in results) {
      final memberIds = await getChannelMemberIds(map['id'] as String);
      channels.add(_channelFromMap(map, memberIds));
    }
    return channels;
  }

  /// 根据 ID 获取 Channel
  Future<Channel?> getChannelById(String id) async {
    final db = await database;
    final results = await db.query('channels', where: 'id = ?', whereArgs: [id]);
    if (results.isEmpty) return null;
    
    final memberIds = await getChannelMemberIds(id);
    return _channelFromMap(results.first, memberIds);
  }

  /// 更新 Channel
  Future<void> updateChannel(Channel channel) async {
    final db = await database;
    await db.update(
      'channels',
      {
        'name': channel.name,
        'description': channel.description,
        'type': channel.type,
        'avatar_path': channel.avatar,
        'is_private': channel.isPrivate ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [channel.id],
    );
  }

  /// 删除 Channel
  Future<void> deleteChannel(String id) async {
    final db = await database;
    await db.delete('channels', where: 'id = ?', whereArgs: [id]);
  }

  /// 添加 Channel 成员
  Future<void> addChannelMember(String channelId, String agentId, {String role = 'member'}) async {
    final db = await database;
    await db.insert(
      'channel_members',
      {
        'channel_id': channelId,
        'agent_id': agentId,
        'role': role,
        'joined_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 移除 Channel 成员
  Future<void> removeChannelMember(String channelId, String agentId) async {
    final db = await database;
    await db.delete(
      'channel_members',
      where: 'channel_id = ? AND agent_id = ?',
      whereArgs: [channelId, agentId],
    );
  }

  /// 获取 Channel 成员 ID 列表
  Future<List<String>> getChannelMemberIds(String channelId) async {
    final db = await database;
    final results = await db.query(
      'channel_members',
      columns: ['agent_id'],
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
    return results.map((r) => r['agent_id'] as String).toList();
  }

  Channel _channelFromMap(Map<String, dynamic> map, List<String> memberIds) {
    return Channel.withMemberIds(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      type: map['type'],
      avatar: map['avatar_path'],
      memberIds: memberIds,
      isPrivate: map['is_private'] == 1,
      lastMessage: null,
      lastMessageTime: null,
      unreadCount: 0,
    );
  }

  // ==================== 消息操作 ====================

  /// 创建消息
  Future<void> createMessage({
    required String id,
    required String channelId,
    required String senderId,
    required String senderType,
    required String content,
    String messageType = 'text',
    Map<String, dynamic>? metadata,
    String? replyToId,
  }) async {
    final db = await database;
    await db.insert(
      'messages',
      {
        'id': id,
        'channel_id': channelId,
        'sender_id': senderId,
        'sender_type': senderType,
        'content': content,
        'message_type': messageType,
        'metadata': metadata != null ? jsonEncode(metadata) : null,
        'reply_to_id': replyToId,
        'created_at': DateTime.now().toIso8601String(),
        'is_read': 0,
      },
    );
  }

  /// 获取 Channel 的消息
  Future<List<Map<String, dynamic>>> getChannelMessages(String channelId, {int limit = 100}) async {
    final db = await database;
    return await db.query(
      'messages',
      where: 'channel_id = ?',
      whereArgs: [channelId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// 标记消息为已读
  Future<void> markMessageAsRead(String messageId) async {
    final db = await database;
    await db.update(
      'messages',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// 删除消息
  Future<void> deleteMessage(String messageId) async {
    final db = await database;
    await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// 删除 Channel 的所有消息
  Future<void> deleteChannelMessages(String channelId) async {
    final db = await database;
    await db.delete(
      'messages',
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
  }

  /// 更新消息内容
  Future<void> updateMessage({
    required String messageId,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    final db = await database;
    final updateData = <String, dynamic>{
      'content': content,
    };

    if (metadata != null) {
      updateData['metadata'] = jsonEncode(metadata);
    }

    await db.update(
      'messages',
      updateData,
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  // ==================== RemoteAgent 操作 ====================

  /// 创建远端助手
  Future<void> createRemoteAgent(remote_agent.RemoteAgent agent) async {
    final db = await database;
    await db.insert(
      'agents',
      agent.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取所有远端助手
  Future<List<remote_agent.RemoteAgent>> getAllRemoteAgents() async {
    final db = await database;
    final results = await db.query('agents', orderBy: 'created_at DESC');
    return results.map((map) => remote_agent.RemoteAgent.fromMap(map)).toList();
  }

  /// 根据 ID 获取远端助手
  Future<remote_agent.RemoteAgent?> getRemoteAgentById(String id) async {
    final db = await database;
    final results = await db.query('agents', where: 'id = ?', whereArgs: [id]);
    return results.isEmpty ? null : remote_agent.RemoteAgent.fromMap(results.first);
  }

  /// 根据 Token 获取远端助手
  Future<remote_agent.RemoteAgent?> getRemoteAgentByToken(String token) async {
    final db = await database;
    final results = await db.query('agents', where: 'token = ?', whereArgs: [token]);
    return results.isEmpty ? null : remote_agent.RemoteAgent.fromMap(results.first);
  }

  /// 获取所有在线的远端助手
  Future<List<remote_agent.RemoteAgent>> getOnlineRemoteAgents() async {
    final db = await database;
    final results = await db.query(
      'agents',
      where: 'status = ?',
      whereArgs: ['online'],
      orderBy: 'connected_at DESC',
    );
    return results.map((map) => remote_agent.RemoteAgent.fromMap(map)).toList();
  }

  /// 更新远端助手
  Future<void> updateRemoteAgent(remote_agent.RemoteAgent agent) async {
    final db = await database;
    await db.update(
      'agents',
      agent.toMap(),
      where: 'id = ?',
      whereArgs: [agent.id],
    );
  }

  /// 更新远端助手状态
  Future<void> updateRemoteAgentStatus(String agentId, String status, {int? connectedAt}) async {
    final db = await database;
    final updateData = {
      'status': status,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };

    if (connectedAt != null) {
      updateData['connected_at'] = connectedAt;
    }

    await db.update(
      'agents',
      updateData,
      where: 'id = ?',
      whereArgs: [agentId],
    );
  }

  /// 更新远端助手心跳
  Future<void> updateRemoteAgentHeartbeat(String agentId) async {
    final db = await database;
    await db.update(
      'agents',
      {
        'last_heartbeat': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [agentId],
    );
  }

  /// 删除远端助手
  Future<void> deleteRemoteAgent(String id) async {
    final db = await database;
    await db.delete('agents', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== 资源文件操作 ====================

  /// 创建资源记录
  Future<void> createResource({
    required String id,
    required String name,
    required String filePath,
    required String fileType,
    required int fileSize,
    String? mimeType,
    String? thumbnailPath,
    required String ownerId,
    required String ownerType,
    Map<String, dynamic>? metadata,
  }) async {
    final db = await database;
    await db.insert(
      'resources',
      {
        'id': id,
        'name': name,
        'file_path': filePath,
        'file_type': fileType,
        'file_size': fileSize,
        'mime_type': mimeType,
        'thumbnail_path': thumbnailPath,
        'owner_id': ownerId,
        'owner_type': ownerType,
        'created_at': DateTime.now().toIso8601String(),
        'metadata': metadata != null ? jsonEncode(metadata) : null,
      },
    );
  }

  /// 根据 Owner 获取资源
  Future<List<Map<String, dynamic>>> getResourcesByOwner(String ownerId, String ownerType) async {
    final db = await database;
    return await db.query(
      'resources',
      where: 'owner_id = ? AND owner_type = ?',
      whereArgs: [ownerId, ownerType],
      orderBy: 'created_at DESC',
    );
  }

  /// 删除资源记录
  Future<void> deleteResource(String id) async {
    final db = await database;
    await db.delete('resources', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== 数据库维护 ====================

  /// 清空所有数据（用于测试或重置）
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('users');
    await db.delete('agents');
    await db.delete('channels');
    await db.delete('channel_members');
    await db.delete('messages');
    await db.delete('conversation_requests');
    await db.delete('resources');
  }

  /// 关闭数据库
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
