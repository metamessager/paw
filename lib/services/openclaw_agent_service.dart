import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../models/openclaw_agent.dart';
import '../models/a2a/task.dart';

/// OpenClaw Agent 服务
/// 专门用于管理和操作 OpenClaw (Knot) 平台的智能体
class OpenClawAgentService {
  final Database _db;
  final http.Client _client;

  OpenClawAgentService(this._db, {http.Client? client})
      : _client = client ?? http.Client();

  /// 添加 OpenClaw Agent
  Future<OpenClawAgent> addAgent({
    required String name,
    required String knotBaseUrl,
    required String knotToken,
    required String knotWorkspaceId,
    String? knotModel,
    String? bio,
    String avatar = '🦅',
    Map<String, dynamic>? systemPrompt,
    List<String>? tools,
    Map<String, dynamic>? rules,
    List<String>? knowledgeBases,
  }) async {
    final agent = OpenClawAgent(
      id: 'openclaw_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      avatar: avatar,
      bio: bio,
      knotBaseUrl: knotBaseUrl,
      knotToken: knotToken,
      knotWorkspaceId: knotWorkspaceId,
      knotModel: knotModel,
      systemPrompt: systemPrompt,
      tools: tools,
      rules: rules,
      knowledgeBases: knowledgeBases,
      status: const AgentStatus(state: 'online'),
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
  Future<List<OpenClawAgent>> getAllAgents() async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'agents',
      where: 'type = ?',
      whereArgs: ['openclaw'],
    );

    return maps.map((map) {
      final config = jsonDecode(map['config']);
      return OpenClawAgent.fromJson(config);
    }).toList();
  }

  /// 根据 ID 获取 Agent
  Future<OpenClawAgent?> getAgentById(String id) async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'agents',
      where: 'id = ? AND type = ?',
      whereArgs: [id, 'openclaw'],
    );

    if (maps.isEmpty) return null;

    final config = jsonDecode(maps.first['config']);
    return OpenClawAgent.fromJson(config);
  }

  /// 向 OpenClaw Agent 发送消息
  Future<String> sendMessage(OpenClawAgent agent, String message) async {
    try {
      final uri = Uri.parse('${agent.knotBaseUrl}/api/agents/${agent.id}/chat');
      
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${agent.knotToken}',
        },
        body: jsonEncode({
          'message': message,
          'workspace_id': agent.knotWorkspaceId,
          'model': agent.knotModel,
          'system_prompt': agent.systemPrompt,
          'tools': agent.tools,
          'rules': agent.rules,
          'knowledge_bases': agent.knowledgeBases,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['response'] ?? data['message'] ?? 'No response';
      }

      throw Exception('Failed to send message: ${response.statusCode}');
    } catch (e) {
      throw Exception('Send message error: $e');
    }
  }

  /// 提交任务到 OpenClaw Agent (A2A 风格)
  Future<A2ATaskResponse> submitTask(
    OpenClawAgent agent,
    A2ATask task,
  ) async {
    try {
      final uri = Uri.parse('${agent.knotBaseUrl}/api/agents/${agent.id}/tasks');
      
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${agent.knotToken}',
        },
        body: jsonEncode({
          'instruction': task.instruction,
          'context': task.context?.map((p) => p.toJson()).toList(),
          'workspace_id': agent.knotWorkspaceId,
          'model': agent.knotModel,
          'tools': agent.tools,
          'rules': agent.rules,
          'knowledge_bases': agent.knowledgeBases,
          'metadata': task.metadata,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        
        // 转换为 A2A 格式
        return A2ATaskResponse(
          taskId: data['task_id'] ?? 'task_${DateTime.now().millisecondsSinceEpoch}',
          state: _convertKnotStateToA2A(data['state'] ?? 'completed'),
          createdAt: data['created_at'],
          updatedAt: data['updated_at'],
          artifacts: data['response'] != null
              ? [
                  A2AArtifact(
                    name: 'knot_response',
                    parts: [A2APart.text(data['response'])],
                  )
                ]
              : null,
        );
      }

      throw Exception('Failed to submit task: ${response.statusCode}');
    } catch (e) {
      throw Exception('Submit task error: $e');
    }
  }

  /// 流式任务 (模拟 SSE)
  Stream<A2ATaskResponse> streamTask(
    OpenClawAgent agent,
    A2ATask task,
  ) async* {
    try {
      final uri = Uri.parse('${agent.knotBaseUrl}/api/agents/${agent.id}/stream');
      
      final request = http.Request('POST', uri);
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${agent.knotToken}',
        'Accept': 'text/event-stream',
      });
      request.body = jsonEncode({
        'instruction': task.instruction,
        'context': task.context?.map((p) => p.toJson()).toList(),
        'workspace_id': agent.knotWorkspaceId,
        'model': agent.knotModel,
        'tools': agent.tools,
        'rules': agent.rules,
        'knowledge_bases': agent.knowledgeBases,
      });

      final streamedResponse = await _client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Stream failed: ${streamedResponse.statusCode}');
      }

      await for (var chunk in streamedResponse.stream.transform(utf8.decoder)) {
        // 解析 SSE 格式
        final lines = chunk.split('\n');
        for (var line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data.isNotEmpty && data != '[DONE]') {
              try {
                final json = jsonDecode(data);
                yield A2ATaskResponse(
                  taskId: json['task_id'] ?? 'stream_task',
                  state: _convertKnotStateToA2A(json['state'] ?? 'working'),
                  artifacts: json['chunk'] != null
                      ? [
                          A2AArtifact(
                            name: 'stream_chunk',
                            parts: [A2APart.text(json['chunk'])],
                          )
                        ]
                      : null,
                );
              } catch (e) {
                // 忽略解析错误
              }
            }
          }
        }
      }
    } catch (e) {
      throw Exception('Stream task error: $e');
    }
  }

  /// 使用知识库查询
  Future<String> queryWithKnowledge(
    OpenClawAgent agent,
    String query,
    List<String> knowledgeBaseIds,
  ) async {
    try {
      final uri = Uri.parse('${agent.knotBaseUrl}/api/knowledge/search');
      
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${agent.knotToken}',
        },
        body: jsonEncode({
          'query': query,
          'knowledge_uuid': knowledgeBaseIds.join(';'),
          'workspace_id': agent.knotWorkspaceId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['result'] ?? 'No results';
      }

      throw Exception('Knowledge query failed: ${response.statusCode}');
    } catch (e) {
      throw Exception('Knowledge query error: $e');
    }
  }

  /// 测试 Agent 连接
  Future<bool> testConnection(OpenClawAgent agent) async {
    try {
      final uri = Uri.parse('${agent.knotBaseUrl}/api/health');
      
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer ${agent.knotToken}'},
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 删除 Agent
  Future<void> deleteAgent(String agentId) async {
    await _db.delete('agents', where: 'id = ?', whereArgs: [agentId]);
    await _db.delete('tasks', where: 'agent_id = ?', whereArgs: [agentId]);
  }

  /// 更新 Agent 配置
  Future<void> updateAgent(OpenClawAgent agent) async {
    await _db.update(
      'agents',
      {
        'name': agent.name,
        'avatar': agent.avatar,
        'bio': agent.bio,
        'config': jsonEncode(agent.toJson()),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [agent.id],
    );
  }

  /// 获取 Agent 工具列表
  Future<List<String>> getAgentTools(OpenClawAgent agent) async {
    try {
      final uri = Uri.parse('${agent.knotBaseUrl}/api/agents/${agent.id}/tools');
      
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer ${agent.knotToken}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<String>.from(data['tools'] ?? []);
      }

      return agent.tools ?? [];
    } catch (e) {
      return agent.tools ?? [];
    }
  }

  /// 获取知识库列表
  Future<List<Map<String, dynamic>>> getKnowledgeBases(OpenClawAgent agent) async {
    try {
      final uri = Uri.parse('${agent.knotBaseUrl}/api/knowledge/list');
      
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer ${agent.knotToken}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['knowledge_bases'] ?? []);
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  // 私有方法：转换 Knot 状态到 A2A 状态
  String _convertKnotStateToA2A(String knotState) {
    switch (knotState.toLowerCase()) {
      case 'pending':
      case 'submitted':
        return 'submitted';
      case 'running':
      case 'processing':
        return 'working';
      case 'completed':
      case 'success':
        return 'completed';
      case 'failed':
      case 'error':
        return 'failed';
      default:
        return 'working';
    }
  }

  /// 清理资源
  void dispose() {
    _client.close();
  }
}
