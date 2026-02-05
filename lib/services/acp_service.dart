/// ACP 服务
/// 用于管理 OpenClaw Agent 并通过 ACP 协议通信

import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/openclaw_agent.dart';
import '../models/acp_protocol.dart';
import '../models/a2a/task.dart';
import '../models/agent.dart';
import 'acp_websocket_client.dart';
/// ACP 服务
class ACPService {
  final Database _db;

  /// WebSocket 客户端映射 (agentId -> client)
  final Map<String, ACPWebSocketClient> _clients = {};

  ACPService(this._db);

  /// 添加 OpenClaw Agent
  Future<OpenClawAgent> addAgent({
    required String name,
    required String gatewayUrl,
    String? authToken,
    String? bio,
    String avatar = '🦅',
    List<String>? tools,
    String? model,
    String? systemPrompt,
    Map<String, dynamic>? config,
  }) async {
    final agent = OpenClawAgent(
      id: 'openclaw_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      avatar: avatar,
      bio: bio,
      gatewayUrl: gatewayUrl,
      authToken: authToken,
      sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
      tools: tools,
      model: model,
      systemPrompt: systemPrompt,
      config: config,
      status: AgentStatus(state: 'offline'),
    );

    // 保存到数据库
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

  /// 获取所有 OpenClaw Agent
  Future<List<OpenClawAgent>> getAgents() async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'agents',
      where: 'type = ?',
      whereArgs: ['openclaw'],
      orderBy: 'created_at DESC',
    );

    return maps.map((map) {
      final config = jsonDecode(map['config']);
      return OpenClawAgent.fromJson(config);
    }).toList();
  }

  /// 获取单个 Agent
  Future<OpenClawAgent?> getAgent(String agentId) async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'agents',
      where: 'id = ? AND type = ?',
      whereArgs: [agentId, 'openclaw'],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    final config = jsonDecode(maps.first['config']);
    return OpenClawAgent.fromJson(config);
  }

  /// 更新 Agent
  Future<void> updateAgent(OpenClawAgent agent) async {
    await _db.update(
      'agents',
      {
        'name': agent.name,
        'avatar': agent.avatar,
        'bio': agent.bio,
        'config': jsonEncode(agent.toJson()),
      },
      where: 'id = ?',
      whereArgs: [agent.id],
    );
  }

  /// 删除 Agent
  Future<void> deleteAgent(String agentId) async {
    // 先断开连接
    await disconnect(agentId);

    // 从数据库删除
    await _db.delete(
      'agents',
      where: 'id = ?',
      whereArgs: [agentId],
    );
  }

  /// 连接到 Agent
  Future<void> connect(OpenClawAgent agent) async {
    if (_clients.containsKey(agent.id)) {
      return; // 已连接
    }

    try {
      final client = ACPWebSocketClient(
        gatewayUrl: agent.gatewayUrl,
        authToken: agent.authToken,
      );

      await client.connect();
      _clients[agent.id] = client;

      // 更新状态为在线
      await _updateAgentStatus(agent.id, 'online');
    } catch (e) {
      await _updateAgentStatus(agent.id, 'error', errorMessage: e.toString());
      rethrow;
    }
  }

  /// 测试连接
  Future<bool> testConnection(OpenClawAgent agent) async {
    try {
      final client = ACPWebSocketClient(
        gatewayUrl: agent.gatewayUrl,
        authToken: agent.authToken,
        autoReconnect: false,
      );

      await client.connect();

      // 发送 ping 测试
      final request = ACPRequest(
        method: 'ping',
        id: DateTime.now().millisecondsSinceEpoch,
      );

      final response = await client.sendRequest(request);
      client.disconnect();

      return response.isSuccess;
    } catch (e) {
      return false;
    }
  }

  /// 发送消息
  Future<String> sendMessage(
    OpenClawAgent agent,
    String message, {
    Map<String, dynamic>? context,
  }) async {
    // 确保已连接
    if (!_clients.containsKey(agent.id)) {
      await connect(agent);
    }

    final client = _clients[agent.id]!;

    final request = ACPRequest(
      method: ACPMethod.chat,
      params: {
        'message': message,
        'session_id': agent.sessionId,
        if (agent.tools != null && agent.tools!.isNotEmpty)
          'tools': agent.tools,
        if (agent.model != null) 'model': agent.model,
        if (agent.systemPrompt != null) 'system': agent.systemPrompt,
        if (context != null) 'context': context,
      },
      id: DateTime.now().millisecondsSinceEpoch,
    );

    final response = await client.sendRequest(request);

    if (response.isError) {
      throw Exception('Chat failed: ${response.error!.message}');
    }

    // 提取响应文本
    if (response.result is Map) {
      return response.result['response'] ??
          response.result['content'] ??
          response.result['message'] ??
          jsonEncode(response.result);
    } else if (response.result is String) {
      return response.result;
    }

    return 'No response';
  }

  /// 流式发送消息
  Stream<String> sendMessageStream(
    OpenClawAgent agent,
    String message, {
    Map<String, dynamic>? context,
  }) async* {
    // 确保已连接
    if (!_clients.containsKey(agent.id)) {
      await connect(agent);
    }

    final client = _clients[agent.id]!;

    final request = ACPRequest(
      method: ACPMethod.streamResponse,
      params: {
        'message': message,
        'session_id': agent.sessionId,
        if (agent.tools != null && agent.tools!.isNotEmpty)
          'tools': agent.tools,
        if (agent.model != null) 'model': agent.model,
        if (agent.systemPrompt != null) 'system': agent.systemPrompt,
        if (context != null) 'context': context,
      },
      id: DateTime.now().millisecondsSinceEpoch,
    );

    await for (var response in client.sendStreamRequest(request)) {
      if (response.isError) {
        throw Exception('Stream failed: ${response.error!.message}');
      }

      if (response.result != null) {
        // 提取流式文本块
        if (response.result is Map) {
          final chunk = response.result['chunk'] ??
              response.result['delta'] ??
              response.result['content'];
          if (chunk != null) {
            yield chunk.toString();
          }
        } else if (response.result is String) {
          yield response.result;
        }
      }
    }
  }

  /// 提交任务（A2A 风格）
  Future<A2ATaskResponse> submitTask(
    OpenClawAgent agent,
    A2ATask task,
  ) async {
    // 确保已连接
    if (!_clients.containsKey(agent.id)) {
      await connect(agent);
    }

    final client = _clients[agent.id]!;

    final request = ACPRequest(
      method: ACPMethod.executeTask,
      params: {
        'instruction': task.instruction,
        'context': task.context?.map((p) => {
              'type': p.type,
              'data': p.content,
            }).toList(),
        'session_id': agent.sessionId,
        if (agent.tools != null && agent.tools!.isNotEmpty)
          'tools': agent.tools,
        if (agent.model != null) 'model': agent.model,
      },
      id: DateTime.now().millisecondsSinceEpoch,
    );

    final response = await client.sendRequest(request);

    if (response.isError) {
      return A2ATaskResponse(
        taskId: 'task_${DateTime.now().millisecondsSinceEpoch}',
        state: 'failed',
        error: '${response.error!.code}: ${response.error!.message}',
      );
    }

    // 转换为 A2A 格式
    return A2ATaskResponse(
      taskId: response.result['task_id'] ??
          'task_${DateTime.now().millisecondsSinceEpoch}',
      state: response.result['status'] ?? 'completed',
      artifacts: response.result['result'] != null
          ? [
              A2AArtifact(
                name: 'openclaw_result',
                parts: [A2APart.text(response.result['result'].toString())],
              )
            ]
          : null,
    );
  }

  /// 获取 Agent 状态
  Future<Map<String, dynamic>> getAgentStatus(OpenClawAgent agent) async {
    // 确保已连接
    if (!_clients.containsKey(agent.id)) {
      return {
        'connected': false,
        'state': 'offline',
      };
    }

    final client = _clients[agent.id]!;

    try {
      final request = ACPRequest(
        method: ACPMethod.getStatus,
        id: DateTime.now().millisecondsSinceEpoch,
      );

      final response = await client.sendRequest(request);

      if (response.isSuccess) {
        return {
          'connected': true,
          'state': 'online',
          ...response.result,
        };
      }
    } catch (e) {
      // 忽略错误
    }

    return {
      'connected': client.isConnected,
      'state': client.isConnected ? 'online' : 'offline',
    };
  }

  /// 断开连接
  Future<void> disconnect(String agentId) async {
    if (_clients.containsKey(agentId)) {
      _clients[agentId]!.disconnect();
      _clients.remove(agentId);
      await _updateAgentStatus(agentId, 'offline');
    }
  }

  /// 更新 Agent 状态
  Future<void> _updateAgentStatus(
    String agentId,
    String state, {
    String? errorMessage,
  }) async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'agents',
      where: 'id = ?',
      whereArgs: [agentId],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      final config = jsonDecode(maps.first['config']);
      config['status'] = {
        'state': state,
        if (errorMessage != null) 'error': errorMessage,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };

      await _db.update(
        'agents',
        {'config': jsonEncode(config)},
        where: 'id = ?',
        whereArgs: [agentId],
      );
    }
  }

  /// 清理所有连接
  void dispose() {
    for (var client in _clients.values) {
      client.disconnect();
    }
    _clients.clear();
  }
}
