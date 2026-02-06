import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/universal_agent.dart';
import '../models/a2a/agent_card.dart';
import '../models/a2a/task.dart';
import '../models/a2a/response.dart';
import 'a2a_protocol_service.dart';
import 'knot_a2a_adapter.dart';

/// 通用 Agent 管理服务
/// 支持 A2A、Knot 和自定义 Agent
class UniversalAgentService {
  final Database _db;
  final A2AProtocolService _a2aService;
  final KnotA2AAdapter _knotAdapter;

  UniversalAgentService(this._db, this._a2aService, this._knotAdapter);

  /// 添加 A2A Agent (通过 URI 发现)
  Future<A2AAgent> discoverAndAddA2AAgent(
    String baseUri, {
    String? apiKey,
    String? customName,
  }) async {
    try {
      // 1. 发现 Agent Card
      if (apiKey != null) {
        _a2aService.setAuthentication('bearer', apiKey);
      }

      final agentCard = await _a2aService.discoverAgent(baseUri);

      // 2. 创建 Agent 实例
      final agent = A2AAgent(
        id: 'a2a_${DateTime.now().millisecondsSinceEpoch}',
        name: customName ?? agentCard.name,
        avatar: '🌐',
        bio: agentCard.description,
        baseUri: baseUri,
        agentCard: agentCard,
        apiKey: apiKey,
        status: const AgentStatus(state: 'online'),
      );

      // 3. 保存到数据库
      await _db.insert(
        'agents',
        {
          'id': agent.id,
          'name': agent.name,
          'avatar': agent.avatar,
          'bio': agent.bio,
          'type': agent.type,
          'config': jsonEncode(agent.toJson()),
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 4. 缓存 Agent Card
      await _db.insert(
        'agent_cards',
        {
          'agent_id': agent.id,
          'card_data': jsonEncode(agentCard.toJson()),
          'cached_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return agent;
    } catch (e) {
      throw Exception('Failed to discover A2A agent: $e');
    }
  }

  /// 手动添加 A2A Agent (不发现)
  Future<A2AAgent> addA2AAgentManually({
    required String name,
    required String baseUri,
    String? apiKey,
    String? bio,
    String avatar = '🌐',
  }) async {
    final agent = A2AAgent(
      id: 'a2a_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      avatar: avatar,
      bio: bio,
      baseUri: baseUri,
      apiKey: apiKey,
      status: const AgentStatus(state: 'offline'),
    );

    await _db.insert(
      'agents',
      {
        'id': agent.id,
        'name': agent.name,
        'avatar': agent.avatar,
        'bio': agent.bio,
        'type': agent.type,
        'config': jsonEncode(agent.toJson()),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return agent;
  }

  /// 添加 Knot Agent (通过 A2A 协议)
  Future<KnotUniversalAgent> addKnotAgent({
    required String name,
    required String knotId,
    required String endpoint,
    required String apiToken,
    String? bio,
    String avatar = '🤖',
  }) async {
    try {
      // 1. 从 Knot 获取 Agent Card (可选)
      A2AAgentCard? agentCard;
      try {
        // 构建临时 KnotUniversalAgent 以获取 AgentCard
        final tempAgent = KnotUniversalAgent(
          id: 'temp',
          name: name,
          avatar: avatar,
          knotId: knotId,
          endpoint: endpoint,
          apiToken: apiToken,
        );
        agentCard = await _knotAdapter.getKnotAgentCard(tempAgent);
      } catch (e) {
        // 如果无法获取 AgentCard，继续使用手动配置
        print('Warning: Could not fetch Knot AgentCard: $e');
      }

      // 2. 创建 KnotUniversalAgent
      final agent = KnotUniversalAgent(
        id: 'knot_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        avatar: avatar,
        bio: bio ?? agentCard?.description,
        knotId: knotId,
        endpoint: endpoint,
        apiToken: apiToken,
        agentCard: agentCard,
        status: const AgentStatus(state: 'online'),
      );

      // 3. 保存到数据库
      await _db.insert(
        'agents',
        {
          'id': agent.id,
          'name': agent.name,
          'avatar': agent.avatar,
          'bio': agent.bio,
          'type': agent.type,
          'config': jsonEncode(agent.toJson()),
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 4. 缓存 Agent Card (如果有)
      if (agentCard != null) {
        await _db.insert(
          'agent_cards',
          {
            'agent_id': agent.id,
            'card_data': jsonEncode(agentCard.toJson()),
            'cached_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      return agent;
    } catch (e) {
      throw Exception('Failed to add Knot agent: $e');
    }
  }

  /// 获取所有通用 Agent
  Future<List<UniversalAgent>> getAllAgents() async {
    final List<Map<String, dynamic>> maps = await _db.query('agents');
    return maps.map((map) {
      final config = jsonDecode(map['config']);
      return UniversalAgent.fromJson(config);
    }).toList();
  }

  /// 根据 ID 获取 Agent
  Future<UniversalAgent?> getAgentById(String id) async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'agents',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;

    final config = jsonDecode(maps.first['config']);
    return UniversalAgent.fromJson(config);
  }

  /// 根据类型获取 Agent
  Future<List<UniversalAgent>> getAgentsByType(String type) async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'agents',
      where: 'type = ?',
      whereArgs: [type],
    );

    return maps.map((map) {
      final config = jsonDecode(map['config']);
      return UniversalAgent.fromJson(config);
    }).toList();
  }

  /// 向 A2A Agent 发送任务
  Future<A2ATaskResponse> sendTaskToA2AAgent(
    A2AAgent agent,
    A2ATask task, {
    bool waitForCompletion = true,
  }) async {
    try {
      // 设置认证
      if (agent.apiKey != null) {
        _a2aService.setAuthentication('bearer', agent.apiKey!);
      }

      final agentCard = agent.agentCard;
      if (agentCard == null) {
        throw Exception('Agent card not found');
      }

      // 提交任务
      final response = await _a2aService.submitTask(
        agentCard.endpoints.tasks,
        task,
      );

      // 保存任务记录
      await _saveTaskRecord(agent.id, task, response);

      // 如果需要等待完成
      if (waitForCompletion && response.isRunning) {
        final statusEndpoint = agentCard.endpoints.status ??
            '${agentCard.endpoints.tasks}';

        final completedResponse = await _a2aService.pollTaskUntilComplete(
          statusEndpoint,
          response.taskId,
        );

        // 更新任务记录
        await _updateTaskRecord(response.taskId, completedResponse);

        return completedResponse;
      }

      return response;
    } catch (e) {
      throw Exception('Failed to send task: $e');
    }
  }

  /// 向 Knot Agent 发送任务 (通过 A2A 协议)
  Future<A2ATaskResponse> sendTaskToKnotAgent(
    KnotUniversalAgent agent,
    A2ATask task, {
    bool waitForCompletion = true,
  }) async {
    try {
      // 使用 KnotA2AAdapter 构建 Knot A2A 请求
      final knotRequest = _knotAdapter.buildKnotA2ARequest(agent, task);

      // 提交任务到 Knot
      final response = await _a2aService.submitTask(
        agent.endpoint ?? '',
        task,
        headers: knotRequest.headers,
      );

      // 保存任务记录
      await _saveTaskRecord(agent.id, task, response);

      return response;
    } catch (e) {
      throw Exception('Failed to send task to Knot agent: $e');
    }
  }

  /// 流式任务
  Stream<A2ATaskResponse> streamTaskToA2AAgent(
    A2AAgent agent,
    A2ATask task,
  ) async* {
    try {
      if (agent.apiKey != null) {
        _a2aService.setAuthentication('bearer', agent.apiKey!);
      }

      final agentCard = agent.agentCard;
      if (agentCard == null || agentCard.endpoints.stream == null) {
        throw Exception('Stream endpoint not available');
      }

      await for (var response in _a2aService.streamTask(
        agentCard.endpoints.stream!,
        task,
      )) {
        // 保存/更新任务记录
        await _saveTaskRecord(agent.id, task, response);
        yield response;
      }
    } catch (e) {
      throw Exception('Stream task failed: $e');
    }
  }

  /// 流式任务到 Knot Agent (通过 A2A 协议)
  Stream<A2AResponse> streamTaskToKnotAgent(
    KnotUniversalAgent agent,
    A2ATask task,
  ) async* {
    try {
      // 使用 KnotA2AAdapter 流式请求
      await for (var response in _knotAdapter.streamKnotTask(agent, task)) {
        yield response;

        // 保存最终结果
        if (response.isDone || response.isError) {
          final taskResponse = _convertResponseToTaskResponse(response);
          await _saveTaskRecord(agent.id, task, taskResponse);
        }
      }
    } catch (e) {
      throw Exception('Stream task to Knot agent failed: $e');
    }
  }

  /// 辅助方法：将 A2AResponse 转换为 A2ATaskResponse
  A2ATaskResponse _convertResponseToTaskResponse(A2AResponse response) {
    return A2ATaskResponse(
      taskId: response.messageId ?? 'unknown',
      state: response.isDone ? 'completed' : (response.isError ? 'failed' : 'running'),
      artifacts: response.content != null
          ? [
              A2AArtifact(
                type: 'text',
                parts: [
                  A2AArtifactPart(
                    type: 'text',
                    content: response.content,
                  ),
                ],
              ),
            ]
          : null,
      error: response.error,
    );
  }

  /// 删除 Agent
  Future<void> deleteAgent(String agentId) async {
    await _db.delete('agents', where: 'id = ?', whereArgs: [agentId]);
    await _db.delete('agent_cards', where: 'agent_id = ?', whereArgs: [agentId]);
    await _db.delete('tasks', where: 'agent_id = ?', whereArgs: [agentId]);
  }

  /// 更新 Agent
  Future<void> updateAgent(UniversalAgent agent) async {
    await _db.update(
      'agents',
      {
        'name': agent.name,
        'avatar': agent.avatar,
        'bio': agent.bio,
        'config': jsonEncode(
          agent is A2AAgent
              ? agent.toJson()
              : agent is KnotUniversalAgent
                  ? agent.toJson()
                  : (agent as CustomAgent).toJson(),
        ),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [agent.id],
    );
  }

  /// 获取 Agent 的任务历史
  Future<List<A2ATaskResponse>> getAgentTasks(String agentId) async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'tasks',
      where: 'agent_id = ?',
      whereArgs: [agentId],
      orderBy: 'created_at DESC',
    );

    return maps.map((map) {
      final responseData = jsonDecode(map['response_data']);
      return A2ATaskResponse.fromJson(responseData);
    }).toList();
  }

  // 私有方法：保存任务记录
  Future<void> _saveTaskRecord(
    String agentId,
    A2ATask task,
    A2ATaskResponse response,
  ) async {
    await _db.insert(
      'tasks',
      {
        'task_id': response.taskId,
        'agent_id': agentId,
        'instruction': task.instruction,
        'state': response.state,
        'request_data': jsonEncode(task.toJson()),
        'response_data': jsonEncode(response.toJson()),
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 私有方法：更新任务记录
  Future<void> _updateTaskRecord(
    String taskId,
    A2ATaskResponse response,
  ) async {
    await _db.update(
      'tasks',
      {
        'state': response.state,
        'response_data': jsonEncode(response.toJson()),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
  }
}