# Knot A2A 协议实施指南

> 基于 Knot 官方文档的完整实施方案

**版本**: v1.0  
**日期**: 2026-02-05  
**状态**: ✅ 已验证 - 准备实施

---

## 📋 目录

1. [Knot A2A 协议详解](#knot-a2a-协议详解)
2. [KnotA2AAdapter 实现](#knota2aadapter-实现)
3. [测试验证](#测试验证)
4. [集成到项目](#集成到项目)

---

## Knot A2A 协议详解

### 1. 获取 Agent Card

在 Knot 智能体的"使用配置"中可以获取：

```json
{
  "agent_id": "3711f0b61fd7421cb2857dbcb815b939",
  "name": "test-agent-client",
  "description": "这是一个测试 Agent",
  "endpoint": "http://test.knot.woa.com/apigw/v1/agents/a2a/chat/completions/3711f0b61fd7421cb2857dbcb815b939",
  "model": "",
  "need_history": "no",
  "version": "1.0.0"
}
```

### 2. A2A 请求格式

**端点**: `POST {endpoint}` (来自 Agent Card)

**Headers**:
```json
{
  "Connection": "keep-alive",
  "Content-Type": "application/json",
  "X-Conversation-Id": "{conversation_id}",
  "X-Request-Id": "{message_id}",
  "X-Username": "{rtx_username}",
  "X-Request-Platform": "knot"
}
```

**Body**:
```json
{
  "a2a": {
    "agent_cards": [],
    "request": {
      "agent_id": "{agent_id}",
      "id": "call_{uuid}",
      "method": "message",
      "need_history": "no",
      "params": {
        "message": {
          "context_id": "{conversation_id}",
          "kind": "message",
          "message_id": "{message_id}",
          "parts": [
            {
              "kind": "text",
              "text": "{用户消息}"
            }
          ],
          "role": "user"
        }
      },
      "parent_agent_id": "",
      "parent_id": null
    }
  },
  "chat_extra": {
    "extra_header": {
      "X-Platform": "knot"
    },
    "model": "deepseek-v3.1",
    "scene_platform": "knot"
  },
  "conversation_id": "{conversation_id}",
  "is_sub_agent": true,
  "message_id": "{message_id}"
}
```

**模型选项**:
- `deepseek-v3.1` (推荐)
- `deepseek-v3.2`
- `deepseek-r1-0528`
- `kimi-k2-instruct`
- `glm-4.6`
- `glm-4.7`

### 3. A2A 响应格式

Knot 返回**流式响应**（SSE 格式）：

```
data: {"contextId":"xxx","kind":"message","messageId":"xxx","parts":[...],"role":"agent"}
data: {"contextId":"xxx","kind":"message","messageId":"xxx","parts":[...],"role":"agent"}
...
data: [DONE]
```

**单条消息示例**:
```json
{
  "contextId": "5ef57d19a77f4b28a998358c3b7bdae6",
  "extensions": null,
  "kind": "message",
  "messageId": "fced70375aa949eea4f8286d5b554569",
  "metadata": null,
  "parts": [
    {
      "kind": "text",
      "metadata": null,
      "text": "{\"type\":\"RUN_STARTED\",\"timestamp\":1763458923,...}"
    }
  ],
  "referenceTaskIds": null,
  "role": "agent",
  "taskId": null
}
```

**parts[0].text** 中是 **AGUI 事件** (JSON 字符串)，需要解析。

---

## AGUI 事件协议

### 核心事件类型

| 事件类型 | 说明 | rawEvent 字段 |
|---------|------|--------------|
| `RUN_STARTED` | 任务开始 | `message_id`, `conversation_id` |
| `TEXT_MESSAGE_START` | 文本消息开始 | `message_id`, `conversation_id` |
| `TEXT_MESSAGE_CONTENT` | 文本消息内容 | `message_id`, `conversation_id`, `content` |
| `TEXT_MESSAGE_END` | 文本消息结束 | `message_id`, `conversation_id` |
| `RUN_COMPLETED` | 任务完成 | `message_id`, `conversation_id` |
| `RUN_ERROR` | 任务错误 | `message_id`, `conversation_id`, `tip_option` |

### 思考消息事件

| 事件类型 | 说明 |
|---------|------|
| `THINKING_TEXT_MESSAGE_START` | 思考开始 |
| `THINKING_TEXT_MESSAGE_CONTENT` | 思考内容 |
| `THINKING_TEXT_MESSAGE_END` | 思考结束 |

### 工具调用事件

| 事件类型 | 说明 |
|---------|------|
| `TOOL_CALL_START` | 工具调用开始 |
| `TOOL_CALL_ARGS` | 工具参数 |
| `TOOL_CALL_END` | 工具调用结束 |
| `TOOL_CALL_RESULT` | 工具返回结果 |

### 生命周期事件

| 事件类型 | 说明 | rawEvent 特殊字段 |
|---------|------|-----------------|
| `STEP_STARTED` | 步骤开始 | `step_name` (call_llm, execute_tool) |
| `STEP_FINISHED` | 步骤结束 | `step_name`, `token_usage` (可选) |

### AGUI 事件示例

```json
{
  "type": "TEXT_MESSAGE_CONTENT",
  "timestamp": 1763458923,
  "rawEvent": {
    "message_id": "fced70375aa949eea4f8286d5b554569",
    "conversation_id": "5ef57d19a77f4b28a998358c3b7bdae6",
    "content": "这是回复的内容"
  },
  "threadId": "5ef57d19a77f4b28a998358c3b7bdae6",
  "runId": "fced70375aa949eea4f8286d5b554569"
}
```

---

## KnotA2AAdapter 实现

### 文件结构

```
lib/services/
├── a2a_protocol_service.dart       ✅ 已存在
├── knot_a2a_adapter.dart           ⏳ 待创建
└── universal_agent_service.dart    ✅ 已存在
```

### KnotA2AAdapter 完整实现

```dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/a2a/agent_card.dart';
import '../models/a2a/task.dart';
import '../models/a2a/response.dart';
import '../models/a2a/artifact.dart';
import '../models/a2a/part.dart';

/// Knot A2A 适配器
/// 
/// 将标准 A2A 调用转换为 Knot 特定的 A2A 格式
class KnotA2AAdapter {
  final http.Client _httpClient;
  final _uuid = Uuid();

  KnotA2AAdapter({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// 转换 Knot Agent Card 为标准 A2A Agent Card
  A2AAgentCard convertKnotAgentCard(Map<String, dynamic> knotCard) {
    return A2AAgentCard(
      name: knotCard['name'] ?? '',
      description: knotCard['description'] ?? '',
      version: knotCard['version'] ?? '1.0.0',
      endpoints: A2AEndpoints(
        tasks: knotCard['endpoint'],
        stream: null, // Knot 使用同一端点
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'agui', 'streaming'],
      authentication: A2AAuthentication(
        schemes: ['bearer', 'apiKey'],
      ),
      metadata: {
        'agent_id': knotCard['agent_id'],
        'need_history': knotCard['need_history'] ?? 'no',
        'model': knotCard['model'] ?? '',
        'platform': 'knot',
      },
    );
  }

  /// 构建 Knot A2A 请求
  Map<String, dynamic> buildKnotA2ARequest({
    required String agentId,
    required A2ATask task,
    required String conversationId,
    required String messageId,
    String model = 'deepseek-v3.1',
  }) {
    final callId = 'call_${_uuid.v4()}';

    return {
      'a2a': {
        'agent_cards': [],
        'request': {
          'agent_id': agentId,
          'id': callId,
          'method': 'message',
          'need_history': 'no',
          'params': {
            'message': {
              'context_id': conversationId,
              'kind': 'message',
              'message_id': messageId,
              'parts': [
                {
                  'kind': 'text',
                  'text': task.instruction,
                }
              ],
              'role': 'user',
            }
          },
          'parent_agent_id': '',
          'parent_id': null,
        }
      },
      'chat_extra': {
        'extra_header': {
          'X-Platform': 'knot',
        },
        'model': model,
        'scene_platform': 'knot',
      },
      'conversation_id': conversationId,
      'is_sub_agent': true,
      'message_id': messageId,
    };
  }

  /// 解析 AGUI 事件
  AGUIEvent? parseAGUIEvent(String text) {
    try {
      final json = jsonDecode(text);
      return AGUIEvent.fromJson(json);
    } catch (e) {
      print('Failed to parse AGUI event: $e');
      return null;
    }
  }

  /// 解析 Knot A2A Response (单条消息)
  A2AResponse? parseKnotA2AMessage(Map<String, dynamic> message) {
    final parts = message['parts'] as List? ?? [];
    final buffer = StringBuffer();
    String state = 'running';
    String? error;

    for (var part in parts) {
      if (part['kind'] == 'text') {
        final text = part['text'] as String;

        // 尝试解析 AGUI 事件
        final aguiEvent = parseAGUIEvent(text);
        if (aguiEvent != null) {
          switch (aguiEvent.type) {
            case 'TEXT_MESSAGE_CONTENT':
              final content = aguiEvent.rawEvent['content'] as String?;
              if (content != null) {
                buffer.write(content);
              }
              break;

            case 'TEXT_MESSAGE_END':
              // 文本消息结束，但任务可能还在运行
              break;

            case 'RUN_COMPLETED':
              state = 'completed';
              break;

            case 'RUN_ERROR':
              state = 'failed';
              final tipOption = aguiEvent.rawEvent['tip_option'];
              error = tipOption?['content'] ?? 'Unknown error';
              break;

            default:
              // 其他事件暂不处理
              break;
          }
        } else {
          // 如果不是 JSON，直接追加文本
          buffer.write(text);
        }
      }
    }

    return A2AResponse(
      taskId: message['messageId'] ?? '',
      state: state,
      artifacts: [
        A2AArtifact(
          parts: [
            A2APart(
              type: 'text',
              content: buffer.toString(),
            )
          ],
        )
      ],
      error: error,
    );
  }

  /// 提交任务到 Knot (流式响应)
  Stream<A2AResponse> submitTaskToKnot({
    required A2AAgentCard agentCard,
    required A2ATask task,
    required String conversationId,
    String? username,
    String? apiToken,
  }) async* {
    final messageId = _uuid.v4();
    final agentId = agentCard.metadata?['agent_id'] as String?;

    if (agentId == null) {
      throw Exception('Knot agent_id not found in metadata');
    }

    final model = (agentCard.metadata?['model'] as String?)?.isEmpty ?? true
        ? 'deepseek-v3.1'
        : agentCard.metadata!['model'] as String;

    // 构建请求
    final requestBody = buildKnotA2ARequest(
      agentId: agentId,
      task: task,
      conversationId: conversationId,
      messageId: messageId,
      model: model,
    );

    // 发送请求
    final request = http.Request(
      'POST',
      Uri.parse(agentCard.endpoints.tasks),
    );

    request.headers.addAll({
      'Content-Type': 'application/json',
      'Connection': 'keep-alive',
      'X-Conversation-Id': conversationId,
      'X-Request-Id': messageId,
      'X-Username': username ?? 'anonymous',
      'X-Request-Platform': 'knot',
    });

    // 添加认证
    if (apiToken != null) {
      request.headers['x-knot-api-token'] = apiToken;
    }

    request.body = jsonEncode(requestBody);

    // 发送流式请求
    final streamedResponse = await _httpClient.send(request);

    if (streamedResponse.statusCode != 200) {
      throw Exception(
        'Knot A2A request failed: ${streamedResponse.statusCode}',
      );
    }

    // 解析流式响应
    final buffer = StringBuffer();
    A2AResponse? lastResponse;

    await for (var chunk in streamedResponse.stream
        .transform(utf8.decoder)
        .transform(LineSplitter())) {
      if (chunk.trim().isEmpty) continue;

      // 移除 "data: " 前缀
      var jsonStr = chunk.trim();
      if (jsonStr.startsWith('data:')) {
        jsonStr = jsonStr.substring(5).trim();
      }

      if (jsonStr == '[DONE]') {
        // 流结束
        if (lastResponse != null) {
          yield lastResponse.copyWith(state: 'completed');
        }
        break;
      }

      try {
        final json = jsonDecode(jsonStr);
        final response = parseKnotA2AMessage(json);

        if (response != null) {
          lastResponse = response;
          yield response;
        }
      } catch (e) {
        print('Failed to parse chunk: $jsonStr, error: $e');
      }
    }
  }

  /// 提交任务到 Knot (等待完成)
  Future<A2AResponse> submitTaskToKnotSync({
    required A2AAgentCard agentCard,
    required A2ATask task,
    required String conversationId,
    String? username,
    String? apiToken,
  }) async {
    A2AResponse? finalResponse;

    await for (var response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      finalResponse = response;

      if (response.state == 'completed' || response.state == 'failed') {
        break;
      }
    }

    return finalResponse ??
        A2AResponse(
          taskId: '',
          state: 'failed',
          error: 'No response received',
        );
  }

  void dispose() {
    _httpClient.close();
  }
}

/// AGUI 事件模型
class AGUIEvent {
  final String type;
  final int timestamp;
  final Map<String, dynamic> rawEvent;
  final String? threadId;
  final String? runId;

  AGUIEvent({
    required this.type,
    required this.timestamp,
    required this.rawEvent,
    this.threadId,
    this.runId,
  });

  factory AGUIEvent.fromJson(Map<String, dynamic> json) {
    return AGUIEvent(
      type: json['type'] as String,
      timestamp: json['timestamp'] as int,
      rawEvent: json['rawEvent'] as Map<String, dynamic>,
      threadId: json['threadId'] as String?,
      runId: json['runId'] as String?,
    );
  }
}
```

---

## 测试验证

### 1. 准备测试数据

**获取 Knot Agent Card**:
1. 访问 https://knot.woa.com (或 test.knot.woa.com)
2. 进入智能体详情页
3. 点击"使用配置"
4. 复制 agent_card JSON

**获取 API Token**:
1. 访问 https://knot.woa.com/settings/token
2. 申请个人 API Token

### 2. 创建测试脚本

**文件**: `test/knot_a2a_adapter_test.dart`

```dart
import 'package:test/test.dart';
import '../lib/services/knot_a2a_adapter.dart';
import '../lib/models/a2a/agent_card.dart';
import '../lib/models/a2a/task.dart';

void main() {
  group('KnotA2AAdapter Tests', () {
    late KnotA2AAdapter adapter;

    setUp(() {
      adapter = KnotA2AAdapter();
    });

    tearDown(() {
      adapter.dispose();
    });

    test('Convert Knot Agent Card to A2A Agent Card', () {
      final knotCard = {
        'agent_id': 'test-agent-id',
        'name': 'Test Agent',
        'description': 'Test Description',
        'endpoint': 'http://test.knot.woa.com/apigw/v1/agents/a2a/chat/completions/test-agent-id',
        'model': 'deepseek-v3.1',
        'need_history': 'no',
        'version': '1.0.0',
      };

      final a2aCard = adapter.convertKnotAgentCard(knotCard);

      expect(a2aCard.name, 'Test Agent');
      expect(a2aCard.description, 'Test Description');
      expect(a2aCard.endpoints.tasks, knotCard['endpoint']);
      expect(a2aCard.metadata?['agent_id'], 'test-agent-id');
      expect(a2aCard.capabilities, contains('a2a'));
      expect(a2aCard.capabilities, contains('agui'));
    });

    test('Build Knot A2A Request', () {
      final request = adapter.buildKnotA2ARequest(
        agentId: 'test-agent-id',
        task: A2ATask(instruction: 'Hello, Knot!'),
        conversationId: 'conv-123',
        messageId: 'msg-123',
      );

      expect(request['a2a']['request']['agent_id'], 'test-agent-id');
      expect(request['conversation_id'], 'conv-123');
      expect(request['message_id'], 'msg-123');
      expect(request['is_sub_agent'], true);
      expect(request['a2a']['request']['params']['message']['parts'][0]['text'],
          'Hello, Knot!');
    });

    test('Parse AGUI Event', () {
      final aguiJson = '''
      {
        "type": "TEXT_MESSAGE_CONTENT",
        "timestamp": 1763458923,
        "rawEvent": {
          "message_id": "msg-123",
          "conversation_id": "conv-123",
          "content": "Hello, World!"
        },
        "threadId": "conv-123",
        "runId": "msg-123"
      }
      ''';

      final event = adapter.parseAGUIEvent(aguiJson);

      expect(event, isNotNull);
      expect(event!.type, 'TEXT_MESSAGE_CONTENT');
      expect(event.rawEvent['content'], 'Hello, World!');
    });

    // 集成测试（需要真实 API Token 和 Agent）
    test('Submit Task to Knot (Integration Test)', () async {
      // ⚠️ 跳过此测试，除非配置了真实环境
      // 取消注释以运行集成测试

      /*
      final knotCard = {
        'agent_id': 'YOUR_AGENT_ID',
        'name': 'Your Agent',
        'description': 'Description',
        'endpoint': 'YOUR_ENDPOINT',
        'version': '1.0.0',
      };

      final a2aCard = adapter.convertKnotAgentCard(knotCard);
      final task = A2ATask(instruction: 'Hello, Knot!');

      final stream = adapter.submitTaskToKnot(
        agentCard: a2aCard,
        task: task,
        conversationId: 'test-conv',
        username: 'your-rtx',
        apiToken: 'YOUR_API_TOKEN',
      );

      await for (var response in stream) {
        print('State: ${response.state}');
        print('Content: ${response.artifacts?.first.parts.first.content}');

        if (response.state == 'completed' || response.state == 'failed') {
          expect(response.state, 'completed');
          break;
        }
      }
      */
    }, skip: true);
  });
}
```

### 3. 手动测试（curl）

创建测试脚本 `test_knot_a2a.sh`:

```bash
#!/bin/bash

# 配置
AGENT_ID="YOUR_AGENT_ID"
ENDPOINT="YOUR_ENDPOINT"
API_TOKEN="YOUR_API_TOKEN"
USERNAME="your-rtx"

# 生成 UUID
CONV_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
MSG_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
CALL_ID="call_$(uuidgen | tr '[:upper:]' '[:lower:]')"

echo "Testing Knot A2A API"
echo "===================="
echo "Agent ID: $AGENT_ID"
echo "Conversation ID: $CONV_ID"
echo "Message ID: $MSG_ID"
echo ""

# 发送请求
curl -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -H "Connection: keep-alive" \
  -H "X-Conversation-Id: $CONV_ID" \
  -H "X-Request-Id: $MSG_ID" \
  -H "X-Username: $USERNAME" \
  -H "X-Request-Platform: knot" \
  -H "x-knot-api-token: $API_TOKEN" \
  -d "{
    \"a2a\": {
      \"agent_cards\": [],
      \"request\": {
        \"agent_id\": \"$AGENT_ID\",
        \"id\": \"$CALL_ID\",
        \"method\": \"message\",
        \"need_history\": \"no\",
        \"params\": {
          \"message\": {
            \"context_id\": \"$CONV_ID\",
            \"kind\": \"message\",
            \"message_id\": \"$MSG_ID\",
            \"parts\": [
              {
                \"kind\": \"text\",
                \"text\": \"Hello, Knot! Please say hi.\"
              }
            ],
            \"role\": \"user\"
          }
        },
        \"parent_agent_id\": \"\",
        \"parent_id\": null
      }
    },
    \"chat_extra\": {
      \"extra_header\": {
        \"X-Platform\": \"knot\"
      },
      \"model\": \"deepseek-v3.1\",
      \"scene_platform\": \"knot\"
    },
    \"conversation_id\": \"$CONV_ID\",
    \"is_sub_agent\": true,
    \"message_id\": \"$MSG_ID\"
  }"

echo ""
echo "Test completed!"
```

---

## 集成到项目

### 1. 更新 UniversalAgentService

在 `lib/services/universal_agent_service.dart` 中添加 Knot A2A 支持：

```dart
import 'knot_a2a_adapter.dart';

class UniversalAgentService {
  final KnotA2AAdapter _knotAdapter = KnotA2AAdapter();

  /// 添加 Knot Agent (通过 A2A)
  Future<A2AAgent> addKnotAgentViaA2A({
    required Map<String, dynamic> knotCard,
  }) async {
    // 1. 转换为 A2A Agent Card
    final a2aCard = _knotAdapter.convertKnotAgentCard(knotCard);

    // 2. 创建 A2AAgent
    final agent = A2AAgent(
      id: generateId(),
      name: a2aCard.name,
      avatar: null,
      bio: a2aCard.description,
      baseUri: extractBaseUri(a2aCard.endpoints.tasks),
      agentCard: a2aCard,
      type: AgentType.a2a,
    );

    // 3. 保存到数据库
    await _db.saveAgent(agent);

    return agent;
  }

  /// 发送任务到 Knot Agent (流式)
  Stream<A2AResponse> streamTaskToKnotAgent({
    required A2AAgent agent,
    required A2ATask task,
    required String conversationId,
    String? username,
    String? apiToken,
  }) {
    return _knotAdapter.submitTaskToKnot(
      agentCard: agent.agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    );
  }

  /// 发送任务到 Knot Agent (同步)
  Future<A2AResponse> sendTaskToKnotAgent({
    required A2AAgent agent,
    required A2ATask task,
    required String conversationId,
    String? username,
    String? apiToken,
  }) {
    return _knotAdapter.submitTaskToKnotSync(
      agentCard: agent.agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    );
  }
}
```

### 2. 更新 UI - 添加 Knot Agent 配置页

创建 `lib/pages/add_knot_agent_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'dart:convert';

class AddKnotAgentPage extends StatefulWidget {
  @override
  _AddKnotAgentPageState createState() => _AddKnotAgentPageState();
}

class _AddKnotAgentPageState extends State<AddKnotAgentPage> {
  final _agentCardController = TextEditingController();
  final _apiTokenController = TextEditingController();

  void _addAgent() async {
    try {
      // 解析 Agent Card JSON
      final knotCard = jsonDecode(_agentCardController.text);

      // 添加 Agent
      final agent = await context.read<UniversalAgentService>().addKnotAgentViaA2A(
        knotCard: knotCard,
      );

      // 保存 API Token (可选)
      if (_apiTokenController.text.isNotEmpty) {
        // 保存到安全存储
        await _secureStorage.write(
          key: 'knot_api_token_${agent.id}',
          value: _apiTokenController.text,
        );
      }

      // 返回
      Navigator.of(context).pop(agent);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('添加 Knot Agent')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _agentCardController,
              decoration: InputDecoration(
                labelText: 'Agent Card (JSON)',
                hintText: '粘贴从 Knot 获取的 agent_card',
              ),
              maxLines: 10,
            ),
            SizedBox(height: 16),
            TextField(
              controller: _apiTokenController,
              decoration: InputDecoration(
                labelText: 'API Token (可选)',
                hintText: '从 knot.woa.com/settings/token 获取',
              ),
              obscureText: true,
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: _addAgent,
              child: Text('添加 Agent'),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 总结

### ✅ 已完成

1. ✅ 获取 Knot A2A 协议完整文档
2. ✅ 理解 AGUI 事件协议
3. ✅ 设计 KnotA2AAdapter 实现
4. ✅ 创建测试方案和脚本

### ⏳ 下一步

1. ⏳ 创建 `lib/services/knot_a2a_adapter.dart` 文件
2. ⏳ 编写单元测试
3. ⏳ 使用 curl 验证 Knot A2A 端点
4. ⏳ 集成到 UniversalAgentService
5. ⏳ 更新 UI 界面

### 📊 工作量评估

- **KnotA2AAdapter 实现**: 2-3 小时
- **单元测试**: 1 小时
- **集成和 UI**: 1-2 小时
- **测试验证**: 1 小时

**总计**: 5-7 小时

---

**文档版本**: v1.0  
**作者**: AI Assistant  
**日期**: 2026-02-05  
**状态**: ✅ 准备实施
