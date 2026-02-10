import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/a2a/agent_card.dart';
import '../models/a2a/task.dart';

/// 流式请求取消令牌
/// 用于取消正在进行的流式 SSE 请求
class StreamCancellationToken {
  bool _isCancelled = false;
  http.Client? _client;

  bool get isCancelled => _isCancelled;

  /// 绑定一个独立的 http.Client，取消时关闭它以中断流
  void bindClient(http.Client client) {
    _client = client;
  }

  /// 取消流式请求
  void cancel() {
    _isCancelled = true;
    _client?.close();
  }
}

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

  /// 提交任务 (同步模式，支持流式回调)
  Future<A2ATaskResponse> submitTask(
    String taskEndpoint,
    A2ATask task, {
    void Function(String chunk)? onContentChunk,
    void Function(String thought)? onThought,
    void Function(Map<String, dynamic> actionData)? onActionConfirmation,
    void Function(Map<String, dynamic> selectData)? onSingleSelect,
    void Function(Map<String, dynamic> selectData)? onMultiSelect,
    void Function(Map<String, dynamic> uploadData)? onFileUpload,
    void Function(Map<String, dynamic> formData)? onForm,
    void Function(Map<String, dynamic> fileData)? onFileMessage,
    void Function(Map<String, dynamic> metadata)? onMessageMetadata,
    void Function(Map<String, dynamic> historyRequestData)? onRequestHistory,
    StreamCancellationToken? cancellationToken,
  }) async {
    print('🌐 [A2AProtocolService] 提交任务 (同步模式)');
    print('   - Task Endpoint: $taskEndpoint');
    print('   - Task ID: ${task.id}');
    print('   - Task Instruction: ${task.instruction}');
    print('   - Auth Headers: $_authHeaders');

    // 为流式请求创建独立的 http.Client，以便通过 cancellationToken 取消
    final requestClient = http.Client();
    cancellationToken?.bindClient(requestClient);

    try {
      final uri = Uri.parse(taskEndpoint);
      print('   - Parsed URI: $uri');

      final requestBody = jsonEncode(task.toJson());
      print('   - Request Body: $requestBody');

      // 使用流式请求以支持 SSE 响应
      final request = http.Request('POST', uri);
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        ..._authHeaders,
      });
      request.body = requestBody;

      final streamedResponse = await requestClient.send(request);

      print('   - Response Status Code: ${streamedResponse.statusCode}');

      if (streamedResponse.statusCode != 200) {
        print('❌ [A2AProtocolService] 任务提交失败');
        print('   - Expected status 200, got ${streamedResponse.statusCode}');

        // 尝试读取错误响应
        final responseBody = await streamedResponse.stream.bytesToString();
        print('   - Response Body: $responseBody');
        throw Exception('Task submission failed: ${streamedResponse.statusCode}');
      }

      print('✅ [A2AProtocolService] 接收到流式响应');

      // 解析 SSE 流
      print('📡 [A2AProtocolService] 开始解析 SSE 流...');
      final responseBuilder = StringBuffer();
      bool isCompleted = false;
      String? errorMessage;

      await for (var chunk in streamedResponse.stream.transform(utf8.decoder)) {
        // 检查是否已被取消
        if (cancellationToken?.isCancelled == true) {
          print('🛑 [A2AProtocolService] 流式请求被取消');
          break;
        }

        print('   - Received chunk: ${chunk.length} bytes');

        // 解析 SSE 格式
        final lines = chunk.split('\n');
        for (var line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data.isNotEmpty && data != '[DONE]') {
              try {
                final json = jsonDecode(data);
                print('   - SSE Event: $json');

                final eventType = json['event_type'] as String?;

                if (eventType == 'RUN_COMPLETED') {
                  print('✅ [A2AProtocolService] Task 完成');
                  isCompleted = true;
                } else if (eventType == 'THOUGHT_MESSAGE') {
                  final thought = json['data']?['thought'] as String?;
                  if (thought != null) {
                    print('   💭 [A2AProtocolService] Thought: $thought');
                    onThought?.call(thought);
                  }
                } else if (eventType == 'TEXT_MESSAGE_CONTENT') {
                  final content = json['data']?['content'] as String?;
                  if (content != null) {
                    responseBuilder.write(content);
                    print('   📝 [A2AProtocolService] Content: $content');
                    onContentChunk?.call(content);
                  }
                } else if (eventType == 'RUN_STARTED') {
                  print('🚀 [A2AProtocolService] Task 开始执行');
                } else if (eventType == 'TOOL_CALL_STARTED') {
                  final toolName = json['data']?['tool_name'] as String?;
                  print('   🔧 [A2AProtocolService] Tool call started: $toolName');
                } else if (eventType == 'TOOL_CALL_COMPLETED') {
                  final toolOutput = json['data']?['tool_output'];
                  print('   ✅ [A2AProtocolService] Tool call completed: $toolOutput');
                } else if (eventType == 'ACTION_CONFIRMATION') {
                  final actionData = json['data'] as Map<String, dynamic>?;
                  if (actionData != null) {
                    print('   🔘 [A2AProtocolService] Action confirmation received');
                    onActionConfirmation?.call(actionData);
                  }
                } else if (eventType == 'SINGLE_SELECT') {
                  final selectData = json['data'] as Map<String, dynamic>?;
                  if (selectData != null) {
                    print('   📻 [A2AProtocolService] Single select received');
                    onSingleSelect?.call(selectData);
                  }
                } else if (eventType == 'MULTI_SELECT') {
                  final selectData = json['data'] as Map<String, dynamic>?;
                  if (selectData != null) {
                    print('   ☑️ [A2AProtocolService] Multi select received');
                    onMultiSelect?.call(selectData);
                  }
                } else if (eventType == 'FILE_UPLOAD') {
                  final uploadData = json['data'] as Map<String, dynamic>?;
                  if (uploadData != null) {
                    print('   📁 [A2AProtocolService] File upload received');
                    onFileUpload?.call(uploadData);
                  }
                } else if (eventType == 'FORM') {
                  final formData = json['data'] as Map<String, dynamic>?;
                  if (formData != null) {
                    print('   📋 [A2AProtocolService] Form received');
                    onForm?.call(formData);
                  }
                } else if (eventType == 'FILE_MESSAGE') {
                  final fileData = json['data'] as Map<String, dynamic>?;
                  if (fileData != null) {
                    print('   📥 [A2AProtocolService] File message received');
                    onFileMessage?.call(fileData);
                  }
                } else if (eventType == 'MESSAGE_METADATA') {
                  final metadataPayload = json['data']?['metadata'] as Map<String, dynamic>?;
                  if (metadataPayload != null) {
                    print('   🏷️ [A2AProtocolService] Message metadata received: $metadataPayload');
                    onMessageMetadata?.call(metadataPayload);
                  }
                } else if (eventType == 'REQUEST_HISTORY') {
                  final historyData = json['data'] as Map<String, dynamic>?;
                  if (historyData != null) {
                    print('   📚 [A2AProtocolService] History request received');
                    onRequestHistory?.call(historyData);
                  }
                }
              } catch (e) {
                print('   ⚠️ [A2AProtocolService] Failed to parse SSE data: $e');
              }
            }
          }
        }
      }

      // 根据取消状态决定最终 state
      final bool wasCancelled = cancellationToken?.isCancelled == true;
      final String finalState;
      if (wasCancelled) {
        finalState = 'cancelled';
        print('🛑 [A2AProtocolService] SSE 流被取消，已累积内容长度: ${responseBuilder.length}');
      } else {
        finalState = isCompleted ? 'completed' : 'running';
        print('✅ [A2AProtocolService] SSE 流解析完成');
        print('   - Total response length: ${responseBuilder.length}');
        print('   - Is completed: $isCompleted');
      }

      // 构造 A2ATaskResponse
      final responseContent = responseBuilder.toString();

      final taskResponse = A2ATaskResponse(
        taskId: task.id ?? '',
        state: finalState,
        artifacts: responseContent.isNotEmpty ? [
          A2AArtifact(
            name: 'response',
            parts: [A2APart.text(responseContent)],
          )
        ] : null,
        error: errorMessage,
      );

      print('✅ [A2AProtocolService] 任务提交成功');
      return taskResponse;
    } on http.ClientException catch (e) {
      // 当 cancellationToken.cancel() 关闭 client 时会抛出 ClientException
      if (cancellationToken?.isCancelled == true) {
        print('🛑 [A2AProtocolService] 请求被取消 (ClientException): $e');
        // 返回已累积的部分内容
        return A2ATaskResponse(
          taskId: task.id ?? '',
          state: 'cancelled',
          artifacts: null,
          error: null,
        );
      }
      rethrow;
    } catch (e, stackTrace) {
      // 当 cancellationToken.cancel() 关闭 client 时也可能抛出其他异常
      if (cancellationToken?.isCancelled == true) {
        print('🛑 [A2AProtocolService] 请求被取消: $e');
        return A2ATaskResponse(
          taskId: task.id ?? '',
          state: 'cancelled',
          artifacts: null,
          error: null,
        );
      }
      print('❌ [A2AProtocolService] 提交任务时发生错误');
      print('   - Error: $e');
      print('   - Stack trace: $stackTrace');
      throw Exception('Task submission error: $e');
    } finally {
      // 清理独立的 client（如果尚未被 cancel 关闭）
      try {
        requestClient.close();
      } catch (_) {}
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

  /// 发送 rollback 通知到远端 Agent（fire-and-forget）
  Future<void> sendRollback(String taskEndpoint, String messageId) async {
    try {
      // 将 task endpoint 中的 /task 或 /tasks 替换为 /rollback
      String rollbackEndpoint;
      if (taskEndpoint.endsWith('/task')) {
        rollbackEndpoint = '${taskEndpoint.substring(0, taskEndpoint.length - 5)}/rollback';
      } else if (taskEndpoint.endsWith('/tasks')) {
        rollbackEndpoint = '${taskEndpoint.substring(0, taskEndpoint.length - 6)}/rollback';
      } else {
        rollbackEndpoint = '$taskEndpoint/rollback';
      }

      final uri = Uri.parse(rollbackEndpoint);
      await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          ..._authHeaders,
        },
        body: jsonEncode({'message_id': messageId}),
      );
      print('✅ [A2AProtocolService] Rollback 通知已发送: $rollbackEndpoint');
    } catch (e) {
      // Fire-and-forget: 不阻塞，仅记录错误
      print('⚠️ [A2AProtocolService] Rollback 通知发送失败: $e');
    }
  }

  /// 清理资源
  void dispose() {
    _client.close();
  }
}
