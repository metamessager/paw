# 统一 A2A 协议接入方案

> 统一使用 A2A 协议接入所有外部 Agent，避免为每个平台单独适配

**版本**: v1.0  
**日期**: 2026-02-05  
**状态**: 🎯 方案设计

---

## 📋 目录

1. [背景和问题](#背景和问题)
2. [核心决策](#核心决策)
3. [技术方案](#技术方案)
4. [Knot 的 A2A 接入](#knot-的-a2a-接入)
5. [实施计划](#实施计划)
6. [对比分析](#对比分析)
7. [风险和应对](#风险和应对)

---

## 背景和问题

### 当前架构的问题

```
❌ 当前设计（多协议适配）:

AI Agent Hub
├── KnotApiService         → Knot REST API + 轮询
├── OpenClawACPService     → ACP 协议 (WebSocket)
├── A2AProtocolService     → A2A 协议 (HTTP/SSE)
└── CustomAgentService     → 自定义协议

问题：
1. 每个 Agent 平台需要单独适配
2. 代码重复，维护成本高
3. 新增平台需要大量开发工作
4. 协议不统一，难以互操作
```

### 理想架构

```
✅ 统一设计（A2A 协议）:

AI Agent Hub
├── A2AProtocolService     → 统一 A2A 协议
│   ├── Knot Agent         → 通过 A2A 接入
│   ├── OpenClaw Agent     → 通过 A2A 接入
│   ├── Custom Agent       → 通过 A2A 接入
│   └── 其他任何 Agent     → 通过 A2A 接入

优点：
1. 统一协议标准
2. 无需单独适配
3. 易于扩展新平台
4. 完全互操作
```

---

## 核心决策

### ✅ 决策：统一使用 A2A 协议

**理由**:
1. **Knot 平台完整支持 A2A** - 官方文档确认 (见 [通过A2A多智能体协议调用智能体](https://iwiki.woa.com/p/4016604641))
2. **A2A 是开放标准** - Google 开源的 Agent-to-Agent 协议
3. **AI Agent Hub 已实现 A2A** - 代码已存在 (`lib/services/a2a_protocol_service.dart`)
4. **避免重复适配** - 统一协议，一次实现，处处可用

---

## 技术方案

### 架构总览

```
┌─────────────────────────────────────────────────────┐
│         AI Agent Hub (Flutter App)                  │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │  用户界面 (Channel / Agent List)             │ │
│  └───────────────────────────────────────────────┘ │
│                        ↓                            │
│  ┌───────────────────────────────────────────────┐ │
│  │  UniversalAgentService                        │ │
│  │  - 统一 Agent 管理                            │ │
│  │  - Agent 类型透明                             │ │
│  └───────────────────────────────────────────────┘ │
│                        ↓                            │
│  ┌───────────────────────────────────────────────┐ │
│  │  A2AProtocolService (统一协议层)              │ │
│  │  ✅ discoverAgent()    - 发现 Agent           │ │
│  │  ✅ submitTask()       - 提交任务             │ │
│  │  ✅ getTaskStatus()    - 查询状态             │ │
│  │  ✅ streamTask()       - 流式输出             │ │
│  └───────────────────────────────────────────────┘ │
│                        ↓                            │
│         HTTP/HTTPS (A2A Protocol)                   │
└─────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────┐
│         外部 Agent 提供商                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐│
│  │ Knot Agent  │  │OpenClaw Agt │  │ Custom Agt  ││
│  │ (A2A端点)   │  │ (A2A桥接)   │  │ (A2A实现)   ││
│  └─────────────┘  └─────────────┘  └─────────────┘│
└─────────────────────────────────────────────────────┘
```

### 核心组件

#### 1. A2AProtocolService (已存在)

**文件**: `lib/services/a2a_protocol_service.dart`

**功能**:
```dart
class A2AProtocolService {
  // ✅ 已实现 - 发现 Agent
  Future<A2AAgentCard> discoverAgent(String baseUri);
  
  // ✅ 已实现 - 提交任务 (同步)
  Future<A2AResponse> submitTask(String endpoint, A2ATask task);
  
  // ✅ 已实现 - 查询状态 (异步)
  Future<A2AResponse> getTaskStatus(String statusEndpoint, String taskId);
  
  // ✅ 已实现 - 轮询至完成
  Future<A2AResponse> pollTaskUntilComplete(
    String statusEndpoint, 
    String taskId,
  );
  
  // ✅ 已实现 - 流式任务 (SSE)
  Stream<A2AResponse> streamTask(String streamEndpoint, A2ATask task);
  
  // ✅ 已实现 - 取消任务
  Future<void> cancelTask(String endpoint, String taskId);
}
```

**状态**: ✅ **已完整实现，无需修改**

---

#### 2. UniversalAgentService (已存在)

**文件**: `lib/services/universal_agent_service.dart`

**功能**:
```dart
class UniversalAgentService {
  final A2AProtocolService _a2aService;
  
  // ✅ 已实现 - 发现并添加 A2A Agent
  Future<A2AAgent> discoverAndAddA2AAgent(String baseUri);
  
  // ✅ 已实现 - 发送任务到 A2A Agent
  Future<A2AResponse> sendTaskToA2AAgent(
    A2AAgent agent,
    A2ATask task, {
    bool waitForCompletion = true,
  });
  
  // ✅ 已实现 - 流式任务
  Stream<A2AResponse> streamTaskToA2AAgent(
    A2AAgent agent,
    A2ATask task,
  );
}
```

**状态**: ✅ **已完整实现，无需修改**

---

#### 3. 数据模型 (已存在)

**A2A Agent Card** (`lib/models/a2a/agent_card.dart`):
```dart
class A2AAgentCard {
  final String name;
  final String description;
  final String version;
  final A2AEndpoints endpoints;  // tasks, stream, status
  final List<String> capabilities;
  final A2AAuthentication? authentication;
}
```

**A2A Task** (`lib/models/a2a/task.dart`):
```dart
class A2ATask {
  final String instruction;
  final List<A2APart>? context;
  final Map<String, dynamic>? metadata;
}

class A2AResponse {
  final String taskId;
  final String state;  // pending, running, completed, failed
  final List<A2AArtifact>? artifacts;
  final String? error;
}
```

**状态**: ✅ **已完整实现，无需修改**

---

## Knot 的 A2A 接入

### Knot 官方 A2A 支持

根据 Knot 官方文档 ([通过A2A多智能体协议调用智能体](https://iwiki.woa.com/p/4016604641))，Knot 完整支持 A2A 协议。

### Knot Agent Card 获取

#### 方式 1: 通过 Knot UI 获取

```
1. 访问 https://knot.woa.com
2. 进入智能体详情页
3. 点击"使用配置"
4. 复制 agent_card JSON
```

**Agent Card 示例**:
```json
{
  "agent_id": "3711f0b61fd7421cb2857dbcb815b939",
  "name": "test-agent-client",
  "description": "这是一个测试 Agent",
  "endpoint": "http://test.knot.woa.com/apigw/v1/agents/a2a/chat/completions/xxx",
  "model": "",
  "need_history": "no",
  "version": "1.0.0"
}
```

#### 方式 2: 标准 A2A 发现机制

如果 Knot 提供标准 Agent Card 端点：
```
https://knot.woa.com/.well-known/agent.json
或
https://knot.woa.com/agents/{agent_id}/agent.json
```

我们的 `A2AProtocolService.discoverAgent()` 可以自动发现。

---

### Knot A2A 调用流程

#### 1. Agent Card 转换

**Knot Agent Card → A2A Agent Card**

```dart
// Knot 格式
{
  "agent_id": "xxx",
  "endpoint": "http://knot.woa.com/apigw/v1/agents/a2a/chat/completions/xxx",
  "name": "Knot Agent",
  "description": "...",
}

// 转换为 A2A 标准格式
A2AAgentCard(
  name: "Knot Agent",
  description: "...",
  version: "1.0.0",
  endpoints: A2AEndpoints(
    tasks: "http://knot.woa.com/apigw/v1/agents/a2a/chat/completions/xxx",
    stream: null,  // Knot 返回流式响应，但端点相同
    status: null,  // Knot 不提供单独的状态端点
  ),
  capabilities: ["chat", "a2a"],
  authentication: A2AAuthentication(
    schemes: ["apiKey", "bearer"],
  ),
)
```

---

#### 2. 任务提交

**用户消息 → A2A Task**

```dart
// 用户输入
String userMessage = "帮我分析这段代码";

// 转换为 A2A Task
A2ATask task = A2ATask(
  instruction: userMessage,
  metadata: {
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'conversation_id': conversationId,
  },
);
```

**A2A Task → Knot A2A Request**

根据 Knot 文档，需要发送以下格式：

```dart
// AI Agent Hub 发送的请求
POST http://knot.woa.com/apigw/v1/agents/a2a/chat/completions/{agent_id}

Headers:
  X-Username: {username}
  X-Conversation-Id: {conversation_id}
  X-Request-Id: {request_id}
  X-Request-Platform: knot
  Content-Type: application/json

Body:
{
  "a2a": {
    "agent_cards": [],  // Knot 会自动注入 sub_agent
    "request": {
      "agent_id": "{agent_id}",
      "id": "{call_id}",
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
      }
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

---

#### 3. 响应处理

**Knot A2A Response → A2A Response**

Knot 返回的是 A2A 流式响应，格式如下：

```json
{
  "contextId": "xxx",
  "kind": "message",
  "messageId": "xxx",
  "parts": [
    {
      "kind": "text",
      "text": "{\"type\":\"TEXT_MESSAGE_CONTENT\",\"rawEvent\":{...}}"
    }
  ],
  "role": "agent"
}
```

**parts[0].text** 中包含 AGUI 事件（JSON 字符串），需要解析：

```dart
// 解析 AGUI 事件
final aguiEvent = jsonDecode(part.text);

switch (aguiEvent['type']) {
  case 'TEXT_MESSAGE_CONTENT':
    // 提取文本内容
    final content = aguiEvent['rawEvent']['content'];
    // 追加到响应中
    break;
    
  case 'TEXT_MESSAGE_END':
    // 消息结束
    break;
    
  case 'RUN_COMPLETED':
    // 任务完成
    break;
}
```

---

### 实现 KnotA2AAdapter

为了适配 Knot 的特殊 A2A 格式，需要创建一个适配器：

**文件**: `lib/services/knot_a2a_adapter.dart`

```dart
/// Knot A2A 适配器
/// 将标准 A2A 调用转换为 Knot 特定格式
class KnotA2AAdapter {
  final A2AProtocolService _a2aService;
  
  KnotA2AAdapter(this._a2aService);
  
  /// 转换 Knot Agent Card 为标准 A2A Agent Card
  A2AAgentCard convertKnotAgentCard(Map<String, dynamic> knotCard) {
    return A2AAgentCard(
      name: knotCard['name'] ?? '',
      description: knotCard['description'] ?? '',
      version: knotCard['version'] ?? '1.0.0',
      endpoints: A2AEndpoints(
        tasks: knotCard['endpoint'],
        stream: null,  // Knot 使用同一端点
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'agui'],
      authentication: A2AAuthentication(
        schemes: ['bearer'],
      ),
      metadata: {
        'agent_id': knotCard['agent_id'],
        'need_history': knotCard['need_history'] ?? 'no',
        'platform': 'knot',
      },
    );
  }
  
  /// 转换 A2A Task 为 Knot A2A Request
  Map<String, dynamic> buildKnotA2ARequest({
    required String agentId,
    required A2ATask task,
    required String conversationId,
    required String messageId,
    String model = 'deepseek-v3.1',
  }) {
    return {
      'a2a': {
        'agent_cards': [],
        'request': {
          'agent_id': agentId,
          'id': 'call_${generateUuid()}',
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
  
  /// 解析 Knot A2A Response
  A2AResponse parseKnotA2AResponse(Map<String, dynamic> response) {
    final parts = response['parts'] as List? ?? [];
    final buffer = StringBuffer();
    String state = 'running';
    
    for (var part in parts) {
      if (part['kind'] == 'text') {
        try {
          // 解析 AGUI 事件
          final aguiEvent = jsonDecode(part['text']);
          
          switch (aguiEvent['type']) {
            case 'TEXT_MESSAGE_CONTENT':
              buffer.write(aguiEvent['rawEvent']['content']);
              break;
              
            case 'RUN_COMPLETED':
              state = 'completed';
              break;
              
            case 'RUN_ERROR':
              state = 'failed';
              break;
          }
        } catch (e) {
          // 如果不是 JSON，直接追加文本
          buffer.write(part['text']);
        }
      }
    }
    
    return A2AResponse(
      taskId: response['messageId'] ?? '',
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
    );
  }
  
  /// 提交任务到 Knot Agent (使用 A2A)
  Future<A2AResponse> submitTaskToKnot({
    required A2AAgentCard agentCard,
    required A2ATask task,
    required String conversationId,
    String? username,
  }) async {
    final messageId = generateUuid();
    final agentId = agentCard.metadata?['agent_id'] as String?;
    
    if (agentId == null) {
      throw Exception('Knot agent_id not found in metadata');
    }
    
    // 构建 Knot A2A 请求
    final requestBody = buildKnotA2ARequest(
      agentId: agentId,
      task: task,
      conversationId: conversationId,
      messageId: messageId,
    );
    
    // 发送请求
    final response = await http.post(
      Uri.parse(agentCard.endpoints.tasks),
      headers: {
        'Content-Type': 'application/json',
        'X-Username': username ?? 'anonymous',
        'X-Conversation-Id': conversationId,
        'X-Request-Id': messageId,
        'X-Request-Platform': 'knot',
      },
      body: jsonEncode(requestBody),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Knot A2A request failed: ${response.statusCode}');
    }
    
    // 解析响应（流式）
    // Knot 返回的是流式数据，需要逐行解析
    final lines = response.body.split('\n');
    A2AResponse? finalResponse;
    
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      
      try {
        // 移除 "data: " 前缀
        final jsonStr = line.startsWith('data:') 
            ? line.substring(5).trim() 
            : line.trim();
            
        if (jsonStr == '[DONE]') break;
        
        final json = jsonDecode(jsonStr);
        finalResponse = parseKnotA2AResponse(json);
      } catch (e) {
        print('Failed to parse line: $line, error: $e');
      }
    }
    
    return finalResponse ?? A2AResponse(
      taskId: messageId,
      state: 'failed',
      error: 'No response received',
    );
  }
  
  /// 流式任务（SSE）
  Stream<A2AResponse> streamTaskToKnot({
    required A2AAgentCard agentCard,
    required A2ATask task,
    required String conversationId,
    String? username,
  }) async* {
    // 实现流式响应
    // 与 submitTaskToKnot 类似，但逐步 yield 结果
  }
}
```

---

## 实施计划

### Phase 1: 验证 Knot A2A 支持 (1-2 小时)

**任务**:
1. ✅ 确认 Knot 支持 A2A 协议（已通过文档确认）
2. ⏳ 获取测试 Knot Agent 的 Agent Card
3. ⏳ 使用 Postman/curl 测试 Knot A2A 端点
4. ⏳ 验证请求/响应格式

**验证命令**:
```bash
# 测试 Knot A2A 端点
curl -X POST \
  'http://test.knot.woa.com/apigw/v1/agents/a2a/chat/completions/{agent_id}' \
  -H 'Content-Type: application/json' \
  -H 'X-Username: your-username' \
  -H 'X-Conversation-Id: test-123' \
  -H 'X-Request-Id: req-123' \
  -H 'X-Request-Platform: knot' \
  -d '{
    "a2a": {
      "agent_cards": [],
      "request": {
        "agent_id": "{agent_id}",
        "id": "call-123",
        "method": "message",
        "need_history": "no",
        "params": {
          "message": {
            "context_id": "test-123",
            "kind": "message",
            "message_id": "msg-123",
            "parts": [{"kind": "text", "text": "Hello"}],
            "role": "user"
          }
        }
      }
    },
    "chat_extra": {
      "extra_header": {"X-Platform": "knot"},
      "model": "deepseek-v3.1",
      "scene_platform": "knot"
    },
    "conversation_id": "test-123",
    "is_sub_agent": true,
    "message_id": "msg-123"
  }'
```

---

### Phase 2: 实现 KnotA2AAdapter (2-3 小时)

**任务**:
1. ⏳ 创建 `lib/services/knot_a2a_adapter.dart`
2. ⏳ 实现 Agent Card 转换
3. ⏳ 实现请求格式转换
4. ⏳ 实现响应解析（AGUI 事件）
5. ⏳ 添加单元测试

**关键代码**:
```dart
// 示例：添加到 UniversalAgentService
Future<A2AAgent> addKnotAgentViaA2A(String agentId) async {
  // 1. 获取 Knot Agent Card (手动配置或 API 获取)
  final knotCard = await fetchKnotAgentCard(agentId);
  
  // 2. 转换为 A2A Agent Card
  final a2aCard = _knotAdapter.convertKnotAgentCard(knotCard);
  
  // 3. 创建 A2AAgent
  final agent = A2AAgent(
    id: generateId(),
    name: a2aCard.name,
    avatar: null,
    bio: a2aCard.description,
    baseUri: extractBaseUri(a2aCard.endpoints.tasks),
    agentCard: a2aCard,
  );
  
  // 4. 保存到数据库
  await _db.saveAgent(agent);
  
  return agent;
}
```

---

### Phase 3: 废弃旧的 Knot 实现 (1-2 小时)

**任务**:
1. ⏳ 标记 `KnotApiService` 为 `@deprecated`
2. ⏳ 标记 `KnotAgentAdapter` 为 `@deprecated`
3. ⏳ 标记 `KnotChannelBridgeService` 为 `@deprecated`
4. ⏳ 更新文档，说明迁移路径
5. ⏳ 保留代码（向后兼容），但不推荐使用

**迁移说明**:
```dart
/// ⚠️ 已废弃：请使用 A2A 协议接入 Knot Agent
/// 
/// 迁移示例：
/// ```dart
/// // ❌ 旧方式
/// final knotAgent = await knotApiService.getKnotAgent(agentId);
/// final result = await knotAdapter.sendMessageToKnotAgent(...);
/// 
/// // ✅ 新方式
/// final a2aAgent = await universalAgentService.addKnotAgentViaA2A(agentId);
/// final response = await universalAgentService.sendTaskToA2AAgent(a2aAgent, task);
/// ```
@deprecated
class KnotApiService {
  // ... 保留原有代码
}
```

---

### Phase 4: 更新文档 (1 小时)

**任务**:
1. ⏳ 更新 `README.md` - 说明统一 A2A 架构
2. ⏳ 更新 `KNOT_INTEGRATION_EXPLAINED.md` - 添加 A2A 接入方式
3. ⏳ 创建 `MIGRATION_GUIDE.md` - 从旧 Knot API 迁移到 A2A
4. ⏳ 更新 `DOCUMENT_INDEX.md` - 索引新文档

---

### Phase 5: 测试和验证 (2-3 小时)

**任务**:
1. ⏳ 单元测试 - KnotA2AAdapter
2. ⏳ 集成测试 - 完整 Knot A2A 流程
3. ⏳ UI 测试 - 添加/使用 Knot Agent
4. ⏳ 性能测试 - 对比旧实现
5. ⏳ 兼容性测试 - 确保向后兼容

---

## 对比分析

### 旧实现 vs 新实现

| 维度 | 旧实现 (Knot REST API) | 新实现 (Knot A2A) |
|------|----------------------|------------------|
| **协议** | Knot 私有 REST API + 轮询 | 标准 A2A 协议 |
| **接入复杂度** | 高（需专门适配） | 低（标准协议） |
| **代码量** | ~800 行（3 个服务） | ~300 行（1 个适配器） |
| **维护成本** | 高（Knot API 变化需跟进） | 低（A2A 标准稳定） |
| **互操作性** | 仅 Knot | 所有 A2A Agent |
| **实时性** | 3 秒轮询延迟 | 流式响应（SSE） |
| **流式输出** | ❌ 不支持 | ✅ 支持 |
| **状态可见** | ❌ 仅最终结果 | ✅ AGUI 事件流 |
| **扩展性** | 低（单一平台） | 高（通用协议） |

**结论**: 新实现在所有维度上都优于旧实现。

---

### 其他 Agent 平台接入

使用统一 A2A 协议后，接入新平台变得极其简单：

#### 接入 OpenClaw

```dart
// 如果 OpenClaw 提供 A2A 端点
final openclawAgent = await universalAgentService.discoverAndAddA2AAgent(
  'https://openclaw.example.com',
);

// 如果 OpenClaw 没有 A2A 端点，需要桥接服务
// 创建 OpenClawA2ABridge (类似 KnotA2AAdapter)
```

#### 接入任何自定义 Agent

```dart
// 只要提供符合 A2A 规范的端点
final customAgent = await universalAgentService.discoverAndAddA2AAgent(
  'https://my-agent.example.com',
  apiKey: 'optional-api-key',
);
```

---

## 风险和应对

### 风险 1: Knot A2A 端点与标准 A2A 有差异

**描述**: Knot 的 A2A 实现可能不完全符合标准

**影响**: 需要额外适配

**应对**:
- ✅ 创建 `KnotA2AAdapter` 处理差异
- ✅ 保留旧实现作为备选方案
- ✅ 与 Knot 团队沟通，推动标准化

---

### 风险 2: AGUI 事件解析复杂

**描述**: Knot 返回的 AGUI 事件需要逐个解析

**影响**: 实现复杂度增加

**应对**:
- ✅ 创建 `AGUIParser` 统一处理
- ✅ 只解析关键事件（TEXT_MESSAGE_CONTENT, RUN_COMPLETED）
- ✅ 其他事件可选处理

---

### 风险 3: 性能问题

**描述**: A2A 协议可能比直接 API 调用慢

**影响**: 用户体验下降

**应对**:
- ✅ 使用流式响应（SSE）提升实时性
- ✅ 本地缓存 Agent Card
- ✅ 性能测试对比

---

### 风险 4: 向后兼容性

**描述**: 现有使用 Knot API 的代码可能受影响

**影响**: 升级困难

**应对**:
- ✅ 保留旧代码，标记为 `@deprecated`
- ✅ 提供迁移指南
- ✅ 逐步迁移，不强制升级

---

## 总结

### 核心优势

1. **统一架构** - 所有 Agent 都通过 A2A 接入，无需单独适配
2. **代码简化** - 减少 60% 的适配代码
3. **易于扩展** - 新增平台只需提供 A2A 端点
4. **标准协议** - 基于 Google 开源标准，互操作性强
5. **向后兼容** - 保留旧实现，平滑迁移

### 下一步行动

1. ✅ **立即行动**: 验证 Knot A2A 端点（Phase 1）
2. ⏳ **本周完成**: 实现 KnotA2AAdapter（Phase 2）
3. ⏳ **下周完成**: 废弃旧实现 + 更新文档（Phase 3-4）
4. ⏳ **测试验证**: 完整测试流程（Phase 5）

**预计总时间**: 7-11 小时

---

## 参考资料

- [Knot 官方文档 - A2A 协议](https://iwiki.woa.com/p/4016604641)
- [AI Agent Hub - A2A 实现](docs/A2A_UNIVERSAL_AGENT_GUIDE.md)
- [Google A2A 协议规范](https://github.com/google/agent-protocol)
- [现有 A2AProtocolService 实现](lib/services/a2a_protocol_service.dart)

---

**文档版本**: v1.0  
**作者**: AI Assistant  
**日期**: 2026-02-05  
**状态**: 🎯 待实施
