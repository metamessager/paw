import 'package:uuid/uuid.dart';
import '../models/knot_agent.dart';
import 'local_database_service.dart';

/// 本地化 Knot Agent 服务
/// 注意：这是本地模拟版本，不会真正调用 Knot API
/// 如果需要实际调用 Knot API，可以保留原 KnotApiService 作为可选功能
class LocalKnotAgentService {
  static final LocalKnotAgentService _instance = LocalKnotAgentService._internal();
  factory LocalKnotAgentService() => _instance;
  LocalKnotAgentService._internal();

  final _db = LocalDatabaseService();
  final _uuid = const Uuid();

  // ==================== Knot Agent 管理 ====================

  /// 获取所有 Knot Agent
  Future<List<KnotAgent>> getAllKnotAgents() async {
    try {
      return await _db.getAllKnotAgents();
    } catch (e) {
      print('获取 Knot Agent 列表失败: $e');
      rethrow;
    }
  }

  /// 根据 ID 获取 Knot Agent
  Future<KnotAgent?> getKnotAgentById(String id) async {
    try {
      return await _db.getKnotAgentById(id);
    } catch (e) {
      print('获取 Knot Agent 失败: $e');
      rethrow;
    }
  }

  /// 创建 Knot Agent
  Future<KnotAgent> createKnotAgent(KnotAgent agent) async {
    try {
      final agentToCreate = agent.id.isEmpty
          ? agent.copyWith(id: _uuid.v4())
          : agent;

      await _db.createKnotAgent(agentToCreate);
      return agentToCreate;
    } catch (e) {
      print('创建 Knot Agent 失败: $e');
      rethrow;
    }
  }

  /// 更新 Knot Agent
  Future<KnotAgent> updateKnotAgent(KnotAgent agent) async {
    try {
      await _db.updateKnotAgent(agent);
      return agent;
    } catch (e) {
      print('更新 Knot Agent 失败: $e');
      rethrow;
    }
  }

  /// 删除 Knot Agent
  Future<void> deleteKnotAgent(String id) async {
    try {
      await _db.deleteKnotAgent(id);
    } catch (e) {
      print('删除 Knot Agent 失败: $e');
      rethrow;
    }
  }

  // ==================== 任务执行（本地模拟）====================

  /// 发送任务给 Knot Agent（本地模拟）
  /// 实际使用时，这里应该调用真实的 Knot API
  Future<KnotTaskResult> sendTask(String agentId, String input) async {
    try {
      final agent = await _db.getKnotAgentById(agentId);
      if (agent == null) {
        throw Exception('Knot Agent 不存在: $agentId');
      }

      // 本地模拟：生成模拟响应
      final taskId = _uuid.v4();
      final output = _generateMockResponse(agent, input);

      // 保存任务记录到数据库（可选）
      // await _db.createKnotTask(taskId, agentId, input, output);

      return KnotTaskResult(
        taskId: taskId,
        agentId: agentId,
        input: input,
        output: output,
        status: 'completed',
        createdAt: DateTime.now(),
        completedAt: DateTime.now(),
      );
    } catch (e) {
      print('发送任务失败: $e');
      rethrow;
    }
  }

  /// 生成模拟响应（仅用于本地测试）
  String _generateMockResponse(KnotAgent agent, String input) {
    return '''
[本地模拟响应]

Agent: ${agent.name}
Model: ${agent.model}
Workspace: ${agent.workspaceId}

您的输入: $input

这是一个本地模拟的响应。如需连接真实的 Knot API，请配置相应的 API Token 并使用 KnotApiService。

模拟时间: ${DateTime.now().toString()}
''';
  }

  // ==================== 初始化示例数据 ====================

  /// 初始化示例 Knot Agent
  Future<void> initializeSampleKnotAgents() async {
    try {
      final existingAgents = await getAllKnotAgents();
      if (existingAgents.isNotEmpty) {
        print('已有 Knot Agent 数据，跳过初始化');
        return;
      }

      print('初始化示例 Knot Agent...');

      final agent1 = KnotAgent(
        id: _uuid.v4(),
        name: 'Knot 代码助手',
        description: '专注于代码分析和生成的 Knot Agent',
        workspaceId: 'local_workspace_001',
        model: 'gpt-4',
        systemPrompt: '你是一个专业的代码助手',
        tools: ['code_search', 'code_analysis', 'code_generation'],
        status: 'active',
        config: {
          'temperature': 0.3,
          'max_tokens': 4000,
        },
      );

      final agent2 = KnotAgent(
        id: _uuid.v4(),
        name: 'Knot 文档助手',
        description: '专注于文档处理的 Knot Agent',
        workspaceId: 'local_workspace_001',
        model: 'claude-3',
        systemPrompt: '你是一个文档处理专家',
        tools: ['document_search', 'document_analysis'],
        status: 'active',
        config: {
          'temperature': 0.5,
          'max_tokens': 2000,
        },
      );

      await createKnotAgent(agent1);
      await createKnotAgent(agent2);

      print('示例 Knot Agent 初始化完成');
    } catch (e) {
      print('初始化示例 Knot Agent 失败: $e');
    }
  }
}

/// Knot 任务结果
class KnotTaskResult {
  final String taskId;
  final String agentId;
  final String input;
  final String output;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? error;

  KnotTaskResult({
    required this.taskId,
    required this.agentId,
    required this.input,
    required this.output,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.error,
  });
}

// KnotAgent 扩展方法
extension KnotAgentExtension on KnotAgent {
  KnotAgent copyWith({
    String? id,
    String? name,
    String? description,
    String? workspaceId,
    String? model,
    String? systemPrompt,
    List<String>? tools,
    String? status,
    Map<String, dynamic>? config,
  }) {
    return KnotAgent(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      workspaceId: workspaceId ?? this.workspaceId,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      tools: tools ?? this.tools,
      status: status ?? this.status,
      config: config ?? this.config,
    );
  }
}
