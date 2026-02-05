import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import '../models/agent.dart';
import '../models/channel.dart';
import '../models/agent_conversation_request.dart';
import '../models/knot_agent.dart';

/// 本地数据库服务 - 使用 SQLite 存储所有数据
class LocalDatabaseService {
  static final LocalDatabaseService _instance = LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  Database? _database;

  /// 获取数据库实例
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'ai_agent_hub.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
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

    // Agent 表
    await db.execute('''
      CREATE TABLE agents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        avatar_path TEXT,
        model TEXT,
        system_prompt TEXT,
        temperature REAL DEFAULT 0.7,
        max_tokens INTEGER DEFAULT 2000,
        status TEXT DEFAULT 'active',
        type TEXT DEFAULT 'standard',
        config TEXT,
        capabilities TEXT,
        metadata TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        owner_id TEXT
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

    // Knot Agent 表
    await db.execute('''
      CREATE TABLE knot_agents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        workspace_id TEXT NOT NULL,
        model TEXT NOT NULL,
        system_prompt TEXT,
        tools TEXT,
        status TEXT DEFAULT 'active',
        config TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Knot Task 表
    await db.execute('''
      CREATE TABLE knot_tasks (
        id TEXT PRIMARY KEY,
        agent_id TEXT NOT NULL,
        input TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        output TEXT,
        error TEXT,
        created_at TEXT NOT NULL,
        completed_at TEXT,
        FOREIGN KEY (agent_id) REFERENCES knot_agents (id) ON DELETE CASCADE
      )
    ''');

    // Channel-Knot Agent 桥接表
    await db.execute('''
      CREATE TABLE channel_knot_bridges (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT NOT NULL,
        knot_agent_id TEXT NOT NULL,
        is_enabled INTEGER DEFAULT 1,
        config TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(channel_id, knot_agent_id),
        FOREIGN KEY (channel_id) REFERENCES channels (id) ON DELETE CASCADE,
        FOREIGN KEY (knot_agent_id) REFERENCES knot_agents (id) ON DELETE CASCADE
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
    await db.execute('CREATE INDEX idx_agents_type ON agents(type)');
    await db.execute('CREATE INDEX idx_agents_owner ON agents(owner_id)');
    await db.execute('CREATE INDEX idx_agents_status ON agents(status)');
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
    await db.execute('CREATE INDEX idx_knot_tasks_agent ON knot_tasks(agent_id)');
    await db.execute('CREATE INDEX idx_knot_tasks_status ON knot_tasks(status)');
    await db.execute('CREATE INDEX idx_resources_owner ON resources(owner_id, owner_type)');
    
    // 复合索引用于常见查询
    await db.execute('CREATE INDEX idx_messages_channel_created ON messages(channel_id, created_at DESC)');
    await db.execute('CREATE INDEX idx_tasks_agent_state ON tasks(agent_id, state)');
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 未来版本升级逻辑
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
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'agents',
      {
        'id': agent.id,
        'name': agent.name,
        'description': agent.description,
        'avatar_path': agent.avatar,
        'model': agent.model,
        'system_prompt': agent.systemPrompt,
        'temperature': agent.temperature,
        'max_tokens': agent.maxTokens,
        'status': agent.status,
        'capabilities': jsonEncode(agent.capabilities),
        'metadata': jsonEncode(agent.metadata),
        'created_at': now,
        'updated_at': now,
        'owner_id': ownerId,
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
        'description': agent.description,
        'avatar_path': agent.avatar,
        'model': agent.model,
        'system_prompt': agent.systemPrompt,
        'temperature': agent.temperature,
        'max_tokens': agent.maxTokens,
        'status': agent.status,
        'capabilities': jsonEncode(agent.capabilities),
        'metadata': jsonEncode(agent.metadata),
        'updated_at': DateTime.now().toIso8601String(),
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
    return Agent(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      avatar: map['avatar_path'] ?? '🤖',
      model: map['model'],
      systemPrompt: map['system_prompt'],
      temperature: map['temperature']?.toDouble(),
      maxTokens: map['max_tokens'],
      type: map['type'],
      provider: AgentProvider(
        name: map['provider_name'] ?? 'Unknown',
        platform: map['provider_platform'] ?? 'unknown',
        type: map['provider_type'] ?? 'llm',
      ),
      status: AgentStatus(state: map['status'] ?? 'offline'),
      capabilities: map['capabilities'] != null 
          ? List<String>.from(jsonDecode(map['capabilities']))
          : [],
      metadata: map['metadata'] != null 
          ? Map<String, dynamic>.from(jsonDecode(map['metadata']))
          : {},
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

  // ==================== Knot Agent 操作 ====================

  /// 创建 Knot Agent
  Future<void> createKnotAgent(KnotAgent agent) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'knot_agents',
      {
        'id': agent.id,
        'knot_agent_id': agent.knotAgentId,
        'name': agent.name,
        'description': agent.description,
        'workspace_id': agent.workspaceId,
        'workspace_path': agent.workspacePath,
        'model': agent.config.model,
        'system_prompt': agent.config.systemPrompt,
        'tools': jsonEncode(agent.tools ?? []),
        'status': agent.status.state,
        'config': jsonEncode(agent.config.capabilities),
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取所有 Knot Agent
  Future<List<KnotAgent>> getAllKnotAgents() async {
    final db = await database;
    final results = await db.query('knot_agents', orderBy: 'created_at DESC');
    return results.map((map) => _knotAgentFromMap(map)).toList();
  }

  /// 根据 ID 获取 Knot Agent
  Future<KnotAgent?> getKnotAgentById(String id) async {
    final db = await database;
    final results = await db.query('knot_agents', where: 'id = ?', whereArgs: [id]);
    return results.isEmpty ? null : _knotAgentFromMap(results.first);
  }

  /// 更新 Knot Agent
  Future<void> updateKnotAgent(KnotAgent agent) async {
    final db = await database;
    await db.update(
      'knot_agents',
      {
        'name': agent.name,
        'description': agent.description,
        'workspace_id': agent.workspaceId,
        'workspace_path': agent.workspacePath,
        'model': agent.config.model,
        'system_prompt': agent.config.systemPrompt,
        'tools': jsonEncode(agent.tools ?? []),
        'status': agent.status.state,
        'config': jsonEncode(agent.config.capabilities),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [agent.id],
    );
  }

  /// 删除 Knot Agent
  Future<void> deleteKnotAgent(String id) async {
    final db = await database;
    await db.delete('knot_agents', where: 'id = ?', whereArgs: [id]);
  }

  KnotAgent _knotAgentFromMap(Map<String, dynamic> map) {
    return KnotAgent(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      knotAgentId: map['knot_agent_id'] ?? map['id'],
      workspaceId: map['workspace_id'],
      workspacePath: map['workspace_path'],
      config: KnotAgentConfig(
        model: map['model'] ?? 'default',
        systemPrompt: map['system_prompt'],
        mcpServers: [],
        capabilities: map['config'] != null ? Map<String, dynamic>.from(jsonDecode(map['config'])) : {},
      ),
      tools: map['tools'] != null ? List<String>.from(jsonDecode(map['tools'])) : [],
      status: map['status'] != null 
          ? AgentStatus(state: map['status'])
          : AgentStatus(state: 'offline'),
    );
  }

  // ==================== Workspace 操作 ====================

  /// 获取所有工作区
  Future<List<KnotWorkspace>> getAllWorkspaces() async {
    return [
      KnotWorkspace(
        id: 'local_workspace_001',
        name: '本地工作区',
        path: '/Users/local/workspace',
        type: 'local',
        description: '本地开发工作区',
      ),
    ];
  }

  // ==================== Knot Task 操作 ====================

  /// 创建 Knot Task
  Future<void> createKnotTask(KnotTask task) async {
    final db = await database;
    await db.insert('knot_tasks', {
      'id': task.id,
      'agent_id': task.agentId,
      'prompt': task.prompt,
      'status': task.status,
      'created_at': task.createdAt.toIso8601String(),
      'started_at': task.startedAt?.toIso8601String(),
      'completed_at': task.completedAt?.toIso8601String(),
      'result': task.result,
      'error': task.error,
      'metadata': task.metadata != null ? jsonEncode(task.metadata) : null,
    });
  }

  /// 根据 ID 获取 Knot Task
  Future<KnotTask?> getKnotTaskById(String taskId) async {
    final db = await database;
    final results = await db.query(
      'knot_tasks',
      where: 'id = ?',
      whereArgs: [taskId],
    );
    if (results.isEmpty) return null;
    return _knotTaskFromMap(results.first);
  }

  /// 根据 Agent ID 获取所有 Knot Tasks
  Future<List<KnotTask>> getKnotTasksByAgentId(String agentId) async {
    final db = await database;
    final results = await db.query(
      'knot_tasks',
      where: 'agent_id = ?',
      whereArgs: [agentId],
      orderBy: 'created_at DESC',
    );
    return results.map((m) => _knotTaskFromMap(m)).toList();
  }

  /// 更新 Knot Task 状态
  Future<void> updateKnotTaskStatus(String taskId, String status) async {
    final db = await database;
    await db.update(
      'knot_tasks',
      {'status': status},
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  KnotTask _knotTaskFromMap(Map<String, dynamic> map) {
    return KnotTask(
      id: map['id'],
      agentId: map['agent_id'],
      prompt: map['prompt'],
      status: map['status'],
      createdAt: DateTime.parse(map['created_at']),
      startedAt: map['started_at'] != null ? DateTime.parse(map['started_at']) : null,
      completedAt: map['completed_at'] != null ? DateTime.parse(map['completed_at']) : null,
      result: map['result'],
      error: map['error'],
      metadata: map['metadata'] != null ? jsonDecode(map['metadata']) : null,
    );
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
    await db.delete('knot_agents');
    await db.delete('knot_tasks');
    await db.delete('channel_knot_bridges');
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
