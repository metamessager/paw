import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/a2a/agent_card.dart';
import '../models/a2a/task.dart';

/// A2A 协议服务
/// 实现 Google A2A Protocol 标准
class A2AProtocolService {
  final http.Client _client;
  final Map<String, String> _authHeaders = {};

  A2AProtocolService({http.Client? client})
      : _client = client ?? http.Client();

  /// 设置认证信息
  void setAuthentication(String scheme, String credentials) {
    if (scheme == 'apiKey') {
      _authHeaders['Authorization'] = 'Bearer $credentials';
    } else if (scheme == 'bearer') {
      _authHeaders['Authorization'] = 'Bearer $credentials';
    }
  }

  /// 发现 Agent - 通过 URI 获取 Agent Card
  /// 标准路径: https://example.com/.well-known/agent.json
  Future<A2AAgentCard> discoverAgent(String baseUri) async {
    try {
      // 尝试标准路径
      final wellKnownUri = Uri.parse('$baseUri/.well-known/agent.json');
      final response = await _client.get(wellKnownUri);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return A2AAgentCard.fromJson(json);
      }

      // 回退：尝试直接 /agent.json
      final fallbackUri = Uri.parse('$baseUri/agent.json');
      final fallbackResponse = await _client.get(fallbackUri);

      if (fallbackResponse.statusCode == 200) {
        final json = jsonDecode(fallbackResponse.body);
        return A2AAgentCard.fromJson(json);
      }

      throw Exception('Failed to discover agent: ${response.statusCode}');
    } catch (e) {
      throw Exception('Agent discovery failed: $e');
    }
  }

  /// 提交任务 (同步模式)
  Future<A2ATaskResponse> submitTask(
    String taskEndpoint,
    A2ATask task,
  ) async {
    try {
      final uri = Uri.parse(taskEndpoint);
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          ..._authHeaders,
        },
        body: jsonEncode(task.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        return A2ATaskResponse.fromJson(json);
      }

      throw Exception('Task submission failed: ${response.statusCode}');
    } catch (e) {
      throw Exception('Task submission error: $e');
    }
  }

  /// 获取任务状态 (异步模式)
  Future<A2ATaskResponse> getTaskStatus(
    String statusEndpoint,
    String taskId,
  ) async {
    try {
      final uri = Uri.parse('$statusEndpoint/$taskId');
      final response = await _client.get(
        uri,
        headers: _authHeaders,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return A2ATaskResponse.fromJson(json);
      }

      throw Exception('Get task status failed: ${response.statusCode}');
    } catch (e) {
      throw Exception('Get task status error: $e');
    }
  }

  /// 轮询任务直到完成
  Future<A2ATaskResponse> pollTaskUntilComplete(
    String statusEndpoint,
    String taskId, {
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final startTime = DateTime.now();

    while (true) {
      final response = await getTaskStatus(statusEndpoint, taskId);

      if (response.isCompleted || response.isFailed) {
        return response;
      }

      // 超时检查
      if (DateTime.now().difference(startTime) > timeout) {
        throw Exception('Task polling timeout');
      }

      // 等待后重试
      await Future.delayed(interval);
    }
  }

  /// 流式任务 (SSE 模式)
  Stream<A2ATaskResponse> streamTask(
    String streamEndpoint,
    A2ATask task,
  ) async* {
    try {
      final uri = Uri.parse(streamEndpoint);
      final request = http.Request('POST', uri);
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        ..._authHeaders,
      });
      request.body = jsonEncode(task.toJson());

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
              final json = jsonDecode(data);
              yield A2ATaskResponse.fromJson(json);
            }
          }
        }
      }
    } catch (e) {
      throw Exception('Stream task error: $e');
    }
  }

  /// 取消任务
  Future<void> cancelTask(String taskEndpoint, String taskId) async {
    try {
      final uri = Uri.parse('$taskEndpoint/$taskId/cancel');
      final response = await _client.post(
        uri,
        headers: _authHeaders,
      );

      if (response.statusCode != 200) {
        throw Exception('Cancel task failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Cancel task error: $e');
    }
  }

  /// 清理资源
  void dispose() {
    _client.close();
  }
}
