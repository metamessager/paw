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
