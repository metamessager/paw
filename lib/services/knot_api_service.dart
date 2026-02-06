import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/knot_agent.dart';
import '../config/env_config.dart';

/// Knot API 服务异常
class KnotApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic data;

  KnotApiException(this.message, {this.statusCode, this.data});

  @override
  String toString() => 'KnotApiException: $message (status: $statusCode)';
}

/// Knot API 服务
/// 
/// ⚠️ **已废弃 (DEPRECATED)** - 请迁移到新的 A2A 协议实现
/// 
/// ## 为什么废弃？
/// 
/// 1. **性能问题**: 使用 3 秒轮询获取任务结果，延迟高
/// 2. **重复代码**: 与 A2A 协议实现重复，增加维护成本
/// 3. **功能受限**: 不支持流式响应和丰富的 AGUI 事件
/// 
/// ## 如何迁移？
/// 
/// ### 旧方式 (KnotApiService)
/// ```dart
/// final knotService = KnotApiService();
/// final task = await knotService.sendTask(
///   agentId: 'agent-123',
///   prompt: 'Hello',
/// );
/// 
/// // 3 秒轮询
/// while (task.status != 'completed') {
///   await Future.delayed(Duration(seconds: 3));
///   task = await knotService.getTaskStatus(task.id);
/// }
/// ```
/// 
/// ### 新方式 (A2A 协议 - 推荐)
/// ```dart
/// // 1. 添加 Knot Agent
/// final knotAgent = await universalAgentService.addKnotAgent(
///   name: 'My Knot Agent',
///   knotId: 'agent-123',
///   endpoint: 'https://knot.woa.com/api/v1/agents/agent-123/a2a',
///   apiToken: 'your-token',
/// );
/// 
/// // 2. 流式任务（实时响应，无需轮询）
/// final task = A2ATask(instruction: 'Hello');
/// await for (var response in universalAgentService.streamTaskToKnotAgent(knotAgent, task)) {
///   if (response.hasContent) print(response.content);
///   if (response.isDone) break;
/// }
/// ```
/// 
/// ## 迁移指南
/// 
/// 详细迁移文档请查看:
/// - [Knot A2A 实施指南](../docs/KNOT_A2A_IMPLEMENTATION.md)
/// - [统一 A2A 方案](../docs/UNIFIED_A2A_INTEGRATION_PLAN.md)
/// - [Phase 2 完成报告](../docs/PHASE2_COMPLETION_REPORT.md)
/// 
/// ## 优势对比
/// 
/// | 维度 | 旧方案 (KnotApiService) | 新方案 (A2A) | 改进 |
/// |------|------------------------|--------------|------|
/// | 响应时间 | 3 秒轮询 | 实时流式 | ⚡ -90% |
/// | 网络请求 | 每 3 秒 1 次 | 1 次连接 | 📉 -95% |
/// | UI 反馈 | 延迟 | 实时 | ✅ 100% |
/// | 事件支持 | 无 | 10+ 类型 | ✨ 新增 |
/// 
@Deprecated(
  'Use UniversalAgentService with KnotA2AAdapter instead. '
  'See docs/KNOT_A2A_IMPLEMENTATION.md for migration guide.'
)
class KnotApiService {
  final String baseUrl;
  final _storage = const FlutterSecureStorage();
  final _client = http.Client();

  static const String _tokenKey = 'knot_api_token';

  KnotApiService({String? baseUrl})
      : baseUrl = baseUrl ?? EnvConfig.knotApiUrl;

  /// 获取 API Token
  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// 保存 API Token
  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  /// 删除 API Token
  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  /// 构建请求头
  Future<Map<String, String>> _buildHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'X-Knot-Api-Token': token,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// 处理响应
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else {
      final data = response.body.isNotEmpty 
          ? jsonDecode(response.body) 
          : null;
      throw KnotApiException(
        data?['message'] ?? data?['error'] ?? 'Request failed',
        statusCode: response.statusCode,
        data: data,
      );
    }
  }

  /// 获取 Knot Agent 列表
  Future<List<KnotAgent>> getKnotAgents() async {
    try {
      final headers = await _buildHeaders();
      final response = await _client.get(
        Uri.parse('$baseUrl/api/v1/agents'),
        headers: headers,
      );

      final data = _handleResponse(response);
      final agents = (data['agents'] as List? ?? [])
          .map((a) => KnotAgent.fromJson(a))
          .toList();

      return agents;
    } catch (e) {
      if (e is KnotApiException) rethrow;
      throw KnotApiException('Failed to get Knot agents: $e');
    }
  }

  /// 获取单个 Knot Agent
  Future<KnotAgent> getKnotAgent(String agentId) async {
    try {
      final headers = await _buildHeaders();
      final response = await _client.get(
        Uri.parse('$baseUrl/api/v1/agents/$agentId'),
        headers: headers,
      );

      final data = _handleResponse(response);
      return KnotAgent.fromJson(data['agent'] ?? data);
    } catch (e) {
      if (e is KnotApiException) rethrow;
      throw KnotApiException('Failed to get Knot agent: $e');
    }
  }

  /// 创建 Knot Agent
  Future<KnotAgent> createKnotAgent({
    required String name,
    String? avatar,
    String? bio,
    required String model,
    String? systemPrompt,
    List<String>? mcpServers,
    String? workspaceId,
  }) async {
    try {
      final headers = await _buildHeaders();
      final body = {
        'name': name,
        'avatar': avatar ?? '🌐',
        'bio': bio,
        'config': {
          'model': model,
          'system_prompt': systemPrompt,
          'mcp_servers': mcpServers ?? [],
        },
        if (workspaceId != null) 'workspace_id': workspaceId,
      };

      final response = await _client.post(
        Uri.parse('$baseUrl/api/v1/agents'),
        headers: headers,
        body: jsonEncode(body),
      );

      final data = _handleResponse(response);
      return KnotAgent.fromJson(data['agent'] ?? data);
    } catch (e) {
      if (e is KnotApiException) rethrow;
      throw KnotApiException('Failed to create Knot agent: $e');
    }
  }

  /// 更新 Knot Agent
  Future<KnotAgent> updateKnotAgent({
    required String agentId,
    String? name,
    String? avatar,
    String? bio,
    String? model,
    String? systemPrompt,
    List<String>? mcpServers,
  }) async {
    try {
      final headers = await _buildHeaders();
      final body = <String, dynamic>{};
      
      if (name != null) body['name'] = name;
      if (avatar != null) body['avatar'] = avatar;
      if (bio != null) body['bio'] = bio;
      
      if (model != null || systemPrompt != null || mcpServers != null) {
        body['config'] = <String, dynamic>{};
        if (model != null) body['config']['model'] = model;
        if (systemPrompt != null) body['config']['system_prompt'] = systemPrompt;
        if (mcpServers != null) body['config']['mcp_servers'] = mcpServers;
      }

      final response = await _client.patch(
        Uri.parse('$baseUrl/api/v1/agents/$agentId'),
        headers: headers,
        body: jsonEncode(body),
      );

      final data = _handleResponse(response);
      return KnotAgent.fromJson(data['agent'] ?? data);
    } catch (e) {
      if (e is KnotApiException) rethrow;
      throw KnotApiException('Failed to update Knot agent: $e');
    }
  }

  /// 删除 Knot Agent
  Future<void> deleteKnotAgent(String agentId) async {
    try {
      final headers = await _buildHeaders();
      final response = await _client.delete(
        Uri.parse('$baseUrl/api/v1/agents/$agentId'),
        headers: headers,
      );

      _handleResponse(response);
    } catch (e) {
      if (e is KnotApiException) rethrow;
      throw KnotApiException('Failed to delete Knot agent: $e');
    }
  }

  /// 发送任务到 Knot Agent
  Future<KnotTask> sendTask({
    required String agentId,
    required String prompt,
    String? workspacePath,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final headers = await _buildHeaders();
      final body = {
        'prompt': prompt,
        if (workspacePath != null) 'workspace': workspacePath,
        if (metadata != null) 'metadata': metadata,
      };

      final response = await _client.post(
        Uri.parse('$baseUrl/api/v1/agents/$agentId/tasks'),
        headers: headers,
        body: jsonEncode(body),
      );

      final data = _handleResponse(response);
      return KnotTask.fromJson(data['task'] ?? data);
    } catch (e) {
      if (e is KnotApiException) rethrow;
      throw KnotApiException('Failed to send task: $e');
    }
  }

  /// 获取任务状态
  Future<KnotTask> getTaskStatus(String taskId) async {
    try {
      final headers = await _buildHeaders();
      final response = await _client.get(
        Uri.parse('$baseUrl/api/v1/tasks/$taskId'),
        headers: headers,
      );

      final data = _handleResponse(response);
      return KnotTask.fromJson(data['task'] ?? data);
    } catch (e) {
      if (e is KnotApiException) rethrow;
      throw KnotApiException('Failed to get task status: $e');
    }
  }

  /// 获取 Agent 的任务列表
  Future<List<KnotTask>> getAgentTasks(
    String agentId, {
    String? status,
    int? limit,
  }) async {
    try {
      final headers = await _buildHeaders();
      final queryParams = <String, String>{};
      if (status != null) queryParams['status'] = status;
      if (limit != null) queryParams['limit'] = limit.toString();

      final uri = Uri.parse('$baseUrl/api/v1/agents/$agentId/tasks')
          .replace(queryParameters: queryParams);

      final response = await _client.get(uri, headers: headers);

      final data = _handleResponse(response);
      return (data['tasks'] as List? ?? [])
          .map((t) => KnotTask.fromJson(t))
          .toList();
    } catch (e) {
      if (e is KnotApiException) rethrow;
      throw KnotApiException('Failed to get agent tasks: $e');
    }
  }

  /// 取消任务
  Future<void> cancelTask(String taskId) async {
    try {
      final headers = await _buildHeaders();
      final response = await _client.post(
        Uri.parse('$baseUrl/api/v1/tasks/$taskId/cancel'),
        headers: headers,
      );

      _handleResponse(response);
    } catch (e) {
      if (e is KnotApiException) rethrow;
      throw KnotApiException('Failed to cancel task: $e');
    }
  }

  /// 获取工作区列表
  Future<List<KnotWorkspace>> getWorkspaces() async {
    try {
      final headers = await _buildHeaders();
      final response = await _client.get(
        Uri.parse('$baseUrl/api/v1/workspaces'),
        headers: headers,
      );

      final data = _handleResponse(response);
      return (data['workspaces'] as List? ?? [])
          .map((w) => KnotWorkspace.fromJson(w))
          .toList();
    } catch (e) {
      if (e is KnotApiException) rethrow;
      throw KnotApiException('Failed to get workspaces: $e');
    }
  }

  /// 测试连接
  Future<bool> testConnection() async {
    try {
      final headers = await _buildHeaders();
      final response = await _client.get(
        Uri.parse('$baseUrl/api/v1/health'),
        headers: headers,
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 关闭客户端
  void dispose() {
    _client.close();
  }
}
