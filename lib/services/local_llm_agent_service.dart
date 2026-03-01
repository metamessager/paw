import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/remote_agent.dart';
import '../models/llm_stream_event.dart';
import 'ui_component_registry.dart';

/// Local LLM Agent Service
///
/// Directly calls LLM HTTP APIs (OpenAI-compatible / Claude / GLM) and
/// returns streaming responses. No WebSocket or remote endpoint needed.
class LocalLLMAgentService {
  static final LocalLLMAgentService instance = LocalLLMAgentService._();
  LocalLLMAgentService._();

  /// Whether [agent] is a local LLM agent (has `llm_provider` in metadata).
  bool isLocalAgent(RemoteAgent agent) {
    return agent.metadata.containsKey('llm_provider') &&
        agent.metadata['llm_provider'] != null;
  }

  /// Abort all currently running streaming requests.
  ///
  /// The caller should invoke this when the user taps "Stop". It force-closes
  /// all underlying [HttpClient]s, which causes the SSE `await for` loops to
  /// terminate with an error that is caught and silenced.
  void abort() {
    final clients = Set<HttpClient>.from(_activeClients);
    _activeClients.clear();
    for (final c in clients) {
      c.close(force: true);
    }
  }

  /// The [HttpClient]s for in-flight SSE requests.
  final Set<HttpClient> _activeClients = {};

  /// Send a message and get a streaming response from the configured LLM.
  ///
  /// Returns a stream of [LLMStreamEvent]s: [LLMTextEvent] for text tokens
  /// and [LLMToolCallEvent] when the LLM invokes an interactive UI tool.
  ///
  /// When [enableUITools] is true (the default), UI tool definitions are
  /// injected into the request and the system prompt is augmented.
  ///
  /// Reads provider config from [agent.metadata]:
  /// - `llm_provider`: `openai` | `claude` | `glm`
  /// - `llm_model`: model name
  /// - `llm_api_base`: base URL
  /// - `llm_api_key`: API key (optional for some providers)
  /// - `system_prompt`: system prompt (optional)
  Stream<LLMStreamEvent> chat({
    required RemoteAgent agent,
    required String message,
    List<Map<String, String>>? history,
    bool enableUITools = true,
    String? systemPromptOverride,
  }) {
    final providerType = agent.metadata['llm_provider'] as String? ?? 'openai';
    final model = agent.metadata['llm_model'] as String? ?? '';
    final apiBase = agent.metadata['llm_api_base'] as String? ?? '';
    final apiKey = agent.metadata['llm_api_key'] as String? ?? '';
    final systemPrompt = systemPromptOverride ?? (agent.metadata['system_prompt'] as String? ?? '');

    if (apiBase.isEmpty) {
      return Stream.error(Exception('LLM API Base URL is not configured'));
    }
    if (model.isEmpty) {
      return Stream.error(Exception('LLM model is not configured'));
    }

    switch (providerType) {
      case 'claude':
        return _chatClaude(
          apiBase: apiBase,
          apiKey: apiKey,
          model: model,
          message: message,
          systemPrompt: systemPrompt,
          history: history,
          enableUITools: enableUITools,
        );
      case 'glm':
      case 'openai':
      default:
        // GLM is OpenAI-compatible
        return _chatOpenAI(
          apiBase: apiBase,
          apiKey: apiKey,
          model: model,
          message: message,
          systemPrompt: systemPrompt,
          history: history,
          enableUITools: enableUITools,
        );
    }
  }

  // =========================================================================
  // chatRound — multi-round tool calling support
  // =========================================================================

  /// Execute a single LLM round with a pre-built message list and tool
  /// definitions. Unlike [chat], the caller constructs the full messages array
  /// (including tool results from prior rounds) and supplies the combined tool
  /// list (UI + OS tools).
  ///
  /// Yields [LLMTextEvent], [LLMToolCallEvent], and a final [LLMDoneEvent]
  /// carrying the stop reason and raw assistant content for building the next
  /// round's message history.
  Stream<LLMStreamEvent> chatRound({
    required RemoteAgent agent,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String? systemPrompt,
  }) {
    final providerType = agent.metadata['llm_provider'] as String? ?? 'openai';
    final model = agent.metadata['llm_model'] as String? ?? '';
    final apiBase = agent.metadata['llm_api_base'] as String? ?? '';
    final apiKey = agent.metadata['llm_api_key'] as String? ?? '';

    if (apiBase.isEmpty) {
      return Stream.error(Exception('LLM API Base URL is not configured'));
    }
    if (model.isEmpty) {
      return Stream.error(Exception('LLM model is not configured'));
    }

    switch (providerType) {
      case 'claude':
        return _chatRoundClaude(
          apiBase: apiBase,
          apiKey: apiKey,
          model: model,
          messages: messages,
          tools: tools,
          systemPrompt: systemPrompt,
        );
      case 'glm':
      case 'openai':
      default:
        return _chatRoundOpenAI(
          apiBase: apiBase,
          apiKey: apiKey,
          model: model,
          messages: messages,
          tools: tools,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // chatRound — OpenAI-compatible
  // ---------------------------------------------------------------------------

  Stream<LLMStreamEvent> _chatRoundOpenAI({
    required String apiBase,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) async* {
    final url = apiBase.endsWith('/')
        ? '${apiBase}chat/completions'
        : '$apiBase/chat/completions';

    final requestBody = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': true,
    };
    if (tools.isNotEmpty) {
      requestBody['tools'] = tools;
    }

    yield* _streamSSEOpenAI(
      url: url,
      headers: {
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(requestBody),
    );
  }

  // ---------------------------------------------------------------------------
  // chatRound — Claude
  // ---------------------------------------------------------------------------

  Stream<LLMStreamEvent> _chatRoundClaude({
    required String apiBase,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String? systemPrompt,
  }) async* {
    final url = apiBase.endsWith('/')
        ? '${apiBase}messages'
        : '$apiBase/messages';

    final requestBody = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': true,
      'max_tokens': 4096,
    };
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      requestBody['system'] = systemPrompt;
    }
    if (tools.isNotEmpty) {
      requestBody['tools'] = tools;
    }

    yield* _streamSSEClaude(
      url: url,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(requestBody),
    );
  }

  // =========================================================================
  // Legacy single-message helpers (used by chat())
  // =========================================================================

  /// OpenAI-compatible streaming chat (covers OpenAI, DeepSeek, Qwen, Kimi,
  /// HunYuan, Ollama, GLM).
  Stream<LLMStreamEvent> _chatOpenAI({
    required String apiBase,
    required String apiKey,
    required String model,
    required String message,
    required String systemPrompt,
    List<Map<String, String>>? history,
    bool enableUITools = true,
  }) async* {
    final effectiveSystemPrompt = enableUITools
        ? '$systemPrompt${UIComponentRegistry.instance.systemPromptSuffix}'
        : systemPrompt;

    final messages = <Map<String, String>>[];
    if (effectiveSystemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': effectiveSystemPrompt});
    }
    if (history != null) {
      messages.addAll(history);
    }
    messages.add({'role': 'user', 'content': message});

    final url = apiBase.endsWith('/')
        ? '${apiBase}chat/completions'
        : '$apiBase/chat/completions';

    final requestBody = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': true,
    };
    if (enableUITools) {
      requestBody['tools'] = UIComponentRegistry.instance.openAITools();
    }

    final body = jsonEncode(requestBody);

    yield* _streamSSEOpenAI(
      url: url,
      headers: {
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      },
      body: body,
    );
  }

  /// Claude (Anthropic) streaming chat.
  Stream<LLMStreamEvent> _chatClaude({
    required String apiBase,
    required String apiKey,
    required String model,
    required String message,
    required String systemPrompt,
    List<Map<String, String>>? history,
    bool enableUITools = true,
  }) async* {
    final effectiveSystemPrompt = enableUITools
        ? '$systemPrompt${UIComponentRegistry.instance.systemPromptSuffix}'
        : systemPrompt;

    final messages = <Map<String, String>>[];
    if (history != null) {
      messages.addAll(history);
    }
    messages.add({'role': 'user', 'content': message});

    final url = apiBase.endsWith('/')
        ? '${apiBase}messages'
        : '$apiBase/messages';

    final requestBody = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': true,
      'max_tokens': 4096,
    };
    if (effectiveSystemPrompt.isNotEmpty) {
      requestBody['system'] = effectiveSystemPrompt;
    }
    if (enableUITools) {
      requestBody['tools'] = UIComponentRegistry.instance.claudeTools();
    }

    final body = jsonEncode(requestBody);

    yield* _streamSSEClaude(
      url: url,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: body,
    );
  }

  // ---------------------------------------------------------------------------
  // SSE helpers
  // ---------------------------------------------------------------------------

  /// Open an SSE POST connection and return the [HttpClientResponse].
  Future<(HttpClient, HttpClientResponse)> _openSSE({
    required String url,
    required Map<String, String> headers,
    required String body,
  }) async {
    final uri = Uri.parse(url);
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;

    try {
      final request = await client.postUrl(uri);
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      request.add(utf8.encode(body));
      final response = await request.close();

      if (response.statusCode != 200) {
        final errorBody = await response.transform(utf8.decoder).join();
        client.close();
        throw Exception(
            'LLM API error (${response.statusCode}): $errorBody');
      }

      return (client, response);
    } catch (e) {
      client.close();
      if (e is Exception &&
          e.toString().contains('LLM API error')) {
        rethrow;
      }
      throw Exception('Failed to connect to LLM API: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // OpenAI SSE parser
  // ---------------------------------------------------------------------------

  /// Parse an OpenAI-compatible SSE stream, yielding [LLMStreamEvent]s.
  ///
  /// Text tokens arrive in `choices[0].delta.content`.
  /// Tool calls arrive in `choices[0].delta.tool_calls` and are accumulated
  /// across multiple chunks until `finish_reason == "tool_calls"`.
  ///
  /// A final [LLMDoneEvent] is yielded with the stop reason and accumulated
  /// assistant content (text + tool_calls) for multi-round history.
  Stream<LLMStreamEvent> _streamSSEOpenAI({
    required String url,
    required Map<String, String> headers,
    required String body,
  }) async* {
    final (client, response) = await _openSSE(
      url: url,
      headers: headers,
      body: body,
    );
    _activeClients.add(client);

    try {
      // Accumulators for streaming tool_calls:
      // index -> {id, name, argumentsBuffer}
      final Map<int, _OpenAIToolCallAccumulator> toolAccumulators = {};

      // Accumulate text content for the raw assistant message
      final textBuffer = StringBuffer();
      String? lastFinishReason;

      String buffer = '';
      await for (final chunk in response.transform(utf8.decoder)) {
        buffer += chunk;
        while (buffer.contains('\n')) {
          final newlineIndex = buffer.indexOf('\n');
          final line = buffer.substring(0, newlineIndex).trim();
          buffer = buffer.substring(newlineIndex + 1);

          if (line.isEmpty) continue;
          if (!line.startsWith('data:')) continue;

          final data = line.substring(5).trim();
          if (data == '[DONE]') break;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices == null || choices.isEmpty) continue;

            final choice = choices[0] as Map<String, dynamic>;
            final delta = choice['delta'] as Map<String, dynamic>?;
            final finishReason = choice['finish_reason'] as String?;

            if (finishReason != null) {
              lastFinishReason = finishReason;
            }

            if (delta != null) {
              // Text content
              final content = delta['content'] as String?;
              if (content != null && content.isNotEmpty) {
                textBuffer.write(content);
                yield LLMTextEvent(content);
              }

              // Tool calls (accumulated across chunks)
              final toolCalls = delta['tool_calls'] as List<dynamic>?;
              if (toolCalls != null) {
                for (final tc in toolCalls) {
                  final tcMap = tc as Map<String, dynamic>;
                  final index = tcMap['index'] as int? ?? 0;
                  final acc = toolAccumulators.putIfAbsent(
                    index,
                    () => _OpenAIToolCallAccumulator(),
                  );

                  if (tcMap.containsKey('id')) {
                    acc.id = tcMap['id'] as String? ?? '';
                  }
                  final fn = tcMap['function'] as Map<String, dynamic>?;
                  if (fn != null) {
                    if (fn.containsKey('name')) {
                      acc.name = fn['name'] as String? ?? '';
                    }
                    if (fn.containsKey('arguments')) {
                      acc.argumentsBuffer.write(fn['arguments'] as String? ?? '');
                    }
                  }
                }
              }
            }

            // When finish_reason is "tool_calls", emit accumulated tool calls
            if (finishReason == 'tool_calls') {
              for (final acc in toolAccumulators.values) {
                if (acc.name.isNotEmpty) {
                  Map<String, dynamic> args;
                  try {
                    args = jsonDecode(acc.argumentsBuffer.toString())
                        as Map<String, dynamic>;
                  } catch (_) {
                    args = {};
                  }
                  yield LLMToolCallEvent(
                    id: acc.id,
                    name: acc.name,
                    arguments: args,
                  );
                }
              }
              // Don't clear — we need them for the raw assistant message
            }
          } catch (_) {
            // Skip malformed JSON lines
          }
        }
      }

      // If there are un-emitted tool calls (e.g. some providers don't set
      // finish_reason to "tool_calls"), emit them now.
      if (lastFinishReason != 'tool_calls') {
        for (final acc in toolAccumulators.values) {
          if (acc.name.isNotEmpty) {
            Map<String, dynamic> args;
            try {
              args = jsonDecode(acc.argumentsBuffer.toString())
                  as Map<String, dynamic>;
            } catch (_) {
              args = {};
            }
            yield LLMToolCallEvent(
              id: acc.id,
              name: acc.name,
              arguments: args,
            );
          }
        }
      }

      // Build the raw assistant message for multi-round history
      final rawAssistant = <String, dynamic>{
        'role': 'assistant',
      };
      final textStr = textBuffer.toString();
      if (textStr.isNotEmpty) {
        rawAssistant['content'] = textStr;
      }
      if (toolAccumulators.isNotEmpty) {
        rawAssistant['tool_calls'] = toolAccumulators.entries.map((e) {
          final acc = e.value;
          return <String, dynamic>{
            'id': acc.id,
            'type': 'function',
            'function': {
              'name': acc.name,
              'arguments': acc.argumentsBuffer.toString(),
            },
          };
        }).toList();
      }

      yield LLMDoneEvent(
        stopReason: lastFinishReason ?? 'stop',
        rawAssistantMessage: rawAssistant,
      );
    } on HttpException catch (_) {
      // Force-closed by abort() — silently stop yielding.
    } on SocketException catch (_) {
      // Force-closed by abort() — silently stop yielding.
    } finally {
      _activeClients.remove(client);
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Claude SSE parser
  // ---------------------------------------------------------------------------

  /// Parse a Claude (Anthropic) SSE stream, yielding [LLMStreamEvent]s.
  ///
  /// Text tokens: `content_block_delta` with `delta.type == "text_delta"`.
  /// Tool use:
  ///   - `content_block_start` with `content_block.type == "tool_use"` → capture id/name
  ///   - `content_block_delta` with `delta.type == "input_json_delta"` → accumulate JSON
  ///   - `content_block_stop` → parse & emit [LLMToolCallEvent]
  ///
  /// A final [LLMDoneEvent] is yielded with the stop reason and accumulated
  /// assistant content blocks for multi-round history.
  Stream<LLMStreamEvent> _streamSSEClaude({
    required String url,
    required Map<String, String> headers,
    required String body,
  }) async* {
    final (client, response) = await _openSSE(
      url: url,
      headers: headers,
      body: body,
    );
    _activeClients.add(client);

    try {
      // Current tool_use block being accumulated
      String? currentToolId;
      String? currentToolName;
      final currentToolArgs = StringBuffer();

      // Accumulated content blocks for the raw assistant message
      final contentBlocks = <Map<String, dynamic>>[];
      final textBuffer = StringBuffer();
      String? stopReason;

      String buffer = '';
      String? currentEventType;

      await for (final chunk in response.transform(utf8.decoder)) {
        buffer += chunk;
        while (buffer.contains('\n')) {
          final newlineIndex = buffer.indexOf('\n');
          final line = buffer.substring(0, newlineIndex).trim();
          buffer = buffer.substring(newlineIndex + 1);

          if (line.isEmpty) continue;

          // Track SSE event type
          if (line.startsWith('event:')) {
            currentEventType = line.substring(6).trim();
            continue;
          }

          if (!line.startsWith('data:')) continue;

          final data = line.substring(5).trim();
          if (data == '[DONE]') break;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final type = json['type'] as String? ?? currentEventType ?? '';

            switch (type) {
              case 'message_start':
                // Capture stop_reason if present at message level
                final message = json['message'] as Map<String, dynamic>?;
                if (message != null) {
                  stopReason = message['stop_reason'] as String?;
                }
                break;

              case 'content_block_start':
                final contentBlock =
                    json['content_block'] as Map<String, dynamic>?;
                if (contentBlock != null &&
                    contentBlock['type'] == 'tool_use') {
                  currentToolId = contentBlock['id'] as String? ?? '';
                  currentToolName = contentBlock['name'] as String? ?? '';
                  currentToolArgs.clear();
                }
                break;

              case 'content_block_delta':
                final delta = json['delta'] as Map<String, dynamic>?;
                if (delta == null) break;
                final deltaType = delta['type'] as String?;

                if (deltaType == 'text_delta') {
                  final text = delta['text'] as String?;
                  if (text != null && text.isNotEmpty) {
                    textBuffer.write(text);
                    yield LLMTextEvent(text);
                  }
                } else if (deltaType == 'input_json_delta') {
                  final partial = delta['partial_json'] as String?;
                  if (partial != null) {
                    currentToolArgs.write(partial);
                  }
                }
                break;

              case 'content_block_stop':
                if (currentToolName != null && currentToolName.isNotEmpty) {
                  Map<String, dynamic> args;
                  try {
                    args = jsonDecode(currentToolArgs.toString())
                        as Map<String, dynamic>;
                  } catch (_) {
                    args = {};
                  }
                  yield LLMToolCallEvent(
                    id: currentToolId ?? '',
                    name: currentToolName,
                    arguments: args,
                  );
                  // Save to content blocks for raw assistant message
                  contentBlocks.add({
                    'type': 'tool_use',
                    'id': currentToolId ?? '',
                    'name': currentToolName,
                    'input': args,
                  });
                  currentToolId = null;
                  currentToolName = null;
                  currentToolArgs.clear();
                } else if (textBuffer.isNotEmpty) {
                  // Finalize text block
                  contentBlocks.add({
                    'type': 'text',
                    'text': textBuffer.toString(),
                  });
                }
                break;

              case 'message_delta':
                final delta = json['delta'] as Map<String, dynamic>?;
                if (delta != null) {
                  stopReason = delta['stop_reason'] as String? ?? stopReason;
                }
                break;
            }
          } catch (_) {
            // Skip malformed JSON lines
          }
        }
      }

      // Ensure text content is in content blocks even if no content_block_stop
      if (contentBlocks.isEmpty && textBuffer.isNotEmpty) {
        contentBlocks.add({
          'type': 'text',
          'text': textBuffer.toString(),
        });
      }

      yield LLMDoneEvent(
        stopReason: stopReason ?? 'end_turn',
        rawAssistantMessage: {
          'role': 'assistant',
          'content': contentBlocks,
        },
      );
    } on HttpException catch (_) {
      // Force-closed by abort() — silently stop yielding.
    } on SocketException catch (_) {
      // Force-closed by abort() — silently stop yielding.
    } finally {
      _activeClients.remove(client);
      client.close();
    }
  }
}

/// Accumulator for an in-progress OpenAI tool call being streamed.
class _OpenAIToolCallAccumulator {
  String id = '';
  String name = '';
  final StringBuffer argumentsBuffer = StringBuffer();
}
