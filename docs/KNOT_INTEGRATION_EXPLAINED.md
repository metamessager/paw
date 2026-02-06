# Knot 平台接入和双向通信说明

> 本文档详细说明 AI Agent Hub 如何接入 Knot 平台，以及如何实现双向通信

**文档版本**: v1.0  
**更新时间**: 2026-02-05  
**适用版本**: AI Agent Hub v2.2.0+

---

## 📋 目录

1. [接入方式概述](#接入方式概述)
2. [Knot 平台通信协议](#knot-平台通信协议)
3. [AI Agent Hub 的实现方式](#ai-agent-hub-的实现方式)
4. [双向通信实现](#双向通信实现)
5. [技术架构详解](#技术架构详解)
6. [使用场景示例](#使用场景示例)
7. [常见问题](#常见问题)

---

## 接入方式概述

Knot 平台提供了**多种接入方式**，根据不同的使用场景选择：

### Knot 官方提供的接入方式

| 接入方式 | 适用场景 | 通信方式 | 双向通信 |
|---------|---------|---------|---------|
| **SDK 引入** | Web 页面嵌入聊天组件 | HTTP REST API + SSE 流式 | ✅ 支持（事件监听） |
| **npm 包** | 前端工程化项目 | HTTP REST API + SSE 流式 | ✅ 支持（事件监听） |
| **iframe** | 最简单嵌入 | HTTP REST API | ⚠️ 有限支持 |
| **A2A 协议** | Agent 间通信 | HTTP POST + AGUI 流式 | ✅ 完整支持 |
| **Knot CLI** | 本地命令行/自动化脚本 | HTTP REST API | ❌ 单向（任务提交） |
| **MCP 协议** | 知识库检索 | streamable-http 协议 | ✅ 支持 |

### AI Agent Hub 的接入方式

**AI Agent Hub 采用**: **HTTP REST API + 轮询机制**

- **协议**: HTTP/HTTPS REST API
- **通信模式**: 请求-响应 + 轮询
- **双向通信**: ✅ 通过适配器和桥接服务实现
- **主要用途**: 将 Knot Agent 作为智能体接入到 Hub 中，参与 Channel 对话

---

## Knot 平台通信协议

### 1. HTTP REST API（基础协议）

Knot 平台的核心 API 端点：

```
基础 URL: https://knot.woa.com
或测试环境: http://test.knot.woa.com

核心端点:
├─ /api/v1/agents                # Agent 管理
├─ /api/v1/agents/{id}           # 单个 Agent 操作
├─ /api/v1/tasks                 # 任务管理
├─ /api/v1/workspaces            # 工作区管理
└─ /apigw/api/v1/agents/agui/{id} # AGUI 协议端点
```

#### 认证方式

```http
Headers:
  X-Knot-Api-Token: <用户个人 Token>
  或
  X-Knot-Token: <智能体 API 密钥>
  X-Username: <用户名>
```

**Token 获取**: https://knot.woa.com/settings/token

---

### 2. AGUI 协议（流式响应）

**AGUI** (Agent UI Protocol) 是 Knot 平台的流式事件协议，用于实时推送智能体的执行状态。

#### 请求格式

```python
# Python 示例
import requests
import json

api_url = "http://knot.woa.com/apigw/api/v1/agents/agui/{agent_id}"

chat_body = {
    "input": {
        "message": "这是你的提问",
        "conversation_id": "",  # 空表示新会话
        "model": "deepseek-v3.1",
        "stream": True,  # 流式响应
        "enable_web_search": False,
        "chat_extra": {
            "attached_images": [],
            "extra_headers": {}
        },
        "temperature": 0.5
    }
}

headers = {
    "x-knot-api-token": "用户的个人 token"
}

response = requests.post(api_url, json=chat_body, headers=headers, stream=True)

# 流式读取
for chunk in response.iter_lines():
    if not chunk:
        continue
    chunk_str = chunk.decode("utf-8").lstrip("data:").strip()
    if chunk_str == "[DONE]":
        break
    msg = json.loads(chunk_str)
    
    if msg["type"] == "TEXT_MESSAGE_CONTENT":
        print(msg["rawEvent"]["content"], end="")
```

#### AGUI 事件类型

| 事件类型 | 说明 | rawEvent 字段 |
|---------|------|--------------|
| `RUN_STARTED` | 任务开始执行 | `message_id`, `conversation_id` |
| `TEXT_MESSAGE_START` | 文本消息开始 | `message_id`, `conversation_id` |
| `TEXT_MESSAGE_CONTENT` | 文本内容流式输出 | `message_id`, `content` |
| `TEXT_MESSAGE_END` | 文本消息结束 | `message_id` |
| `THINKING_TEXT_MESSAGE_*` | 思考过程消息 | 同上 |
| `TOOL_CALL_START` | 工具调用开始 | `tool_name`, `tool_args` |
| `TOOL_CALL_END` | 工具调用结束 | `tool_result` |
| `STEP_STARTED` | 步骤开始 | `step_name` (`call_llm`/`execute_tool`) |
| `STEP_FINISHED` | 步骤结束 | `step_name`, `token_usage` |
| `RUN_ERROR` | 执行错误 | `tip_option` (错误信息) |
| `RUN_COMPLETED` | 任务完成 | `message_id` |

**优点**:
- ✅ 实时推送执行状态
- ✅ 可以看到思考过程和工具调用
- ✅ Token 使用统计

**缺点**:
- ⚠️ 需要维持长连接
- ⚠️ 需要解析复杂的事件流

---

### 3. A2A 协议（Agent-to-Agent）

A2A 是标准的智能体间通信协议，Knot 完整支持。

#### Agent Card（智能体卡片）

```json
{
  "agent_id": "3711f0b61fd7421cb2857dbcb815b939",
  "description": "test-agent-client",
  "endpoint": "http://test.knot.woa.com/apigw/v1/agents/a2a/chat/completions/xxx",
  "model": "",
  "name": "test-agent-client",
  "need_history": "no",
  "version": "1.0.0"
}
```

#### A2A 调用请求

```json
{
  "a2a": {
    "agent_cards": [],
    "request": {
      "agent_id": "68cec608ff124d9795d7ab903610c942",
      "id": "call_2587cf42-829d-4f61-b525-62ccf63f4354",
      "method": "message",
      "need_history": "no",
      "params": {
        "message": {
          "context_id": "123",
          "kind": "message",
          "message_id": "123",
          "parts": [
            {
              "kind": "text",
              "text": "这是你的提问"
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
  "conversation_id": "123",
  "is_sub_agent": true,
  "message_id": "123"
}
```

**特点**:
- ✅ 标准化协议，易于集成
- ✅ 支持 Agent 间协作
- ✅ 返回 AGUI 流式响应

---

### 4. Web SDK 事件监听（前端专用）

Knot 的 Web SDK 提供了事件监听机制，实现**客户端双向通信**：

```javascript
// SDK 方式
const { init, ChatEventKey } = window.ChatSDK;

const chat = await init({
  service: {
    agentId: 'your-agent-id',
    baseURL: 'https://knot.woa.com',
  },
  streamingTimeout: 1800,
});

// 监听事件 - 这是双向通信的关键！
chat.on(ChatEventKey.READY, () => {
  console.log('组件就绪');
});

chat.on(ChatEventKey.STREAMING_START, ({ messages }) => {
  console.log('开始输出', messages);
});

chat.on(ChatEventKey.STREAMING_STOP, ({ message }) => {
  console.log('输出完成', message);
});

// 发送消息
await chat.sendUserPrompt('你好，请介绍一下自己');
```

**双向通信机制**:
1. **用户 → Knot**: 通过 `sendUserPrompt()` 发送消息
2. **Knot → 用户**: 通过事件监听 (`on()`) 接收响应

---

## AI Agent Hub 的实现方式

### 选择的接入方式

AI Agent Hub **没有使用** Web SDK 或 A2A 协议，而是采用：

**HTTP REST API + 任务轮询机制**

### 为什么不使用其他方式？

| 方式 | 不适用的原因 |
|------|------------|
| **Web SDK** | 仅适用于前端 Web 页面，不适合 Flutter 应用 |
| **A2A 协议** | 过于复杂，AI Agent Hub 不是标准 A2A Agent |
| **AGUI 流式** | 需要维持长连接，Flutter HTTP 客户端处理复杂 |
| **Knot CLI** | 仅单向通信，无法接收响应 |

### AI Agent Hub 的实现策略

**核心思路**: 将 Knot Agent 视为"外部任务执行器"

```
用户消息 → 转换为 Knot 任务 → 提交到 Knot API → 轮询任务状态 → 获取结果 → 返回为消息
```

---

## 双向通信实现

### 通信架构

```
┌──────────────────────────────────────────────────┐
│         AI Agent Hub (Flutter App)               │
│  ┌────────────────────────────────────────────┐  │
│  │  用户界面 (Channel Chat)                  │  │
│  │  • 用户发送消息                            │  │
│  │  • 显示 Agent 回复                         │  │
│  └────────────────────────────────────────────┘  │
│                    ↓  ↑                          │
│  ┌────────────────────────────────────────────┐  │
│  │  KnotChannelBridgeService                  │  │
│  │  • 检测 Knot Agent                         │  │
│  │  • 消息路由                                 │  │
│  │  • 状态管理                                 │  │
│  └────────────────────────────────────────────┘  │
│                    ↓  ↑                          │
│  ┌────────────────────────────────────────────┐  │
│  │  KnotAgentAdapter                          │  │
│  │  • 消息 → 任务转换                         │  │
│  │  • 任务结果 → 消息转换                     │  │
│  └────────────────────────────────────────────┘  │
│                    ↓  ↑                          │
│  ┌────────────────────────────────────────────┐  │
│  │  KnotApiService                            │  │
│  │  • Token 管理                              │  │
│  │  • HTTP 请求                               │  │
│  │  • 任务轮询                                 │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
                    ↓  ↑
          HTTP REST API (轮询)
                    ↓  ↑
┌──────────────────────────────────────────────────┐
│         Knot Platform                            │
│  • 接收任务请求                                  │
│  • 执行智能体任务                                │
│  • 返回任务状态和结果                            │
└──────────────────────────────────────────────────┘
```

### 双向通信流程详解

#### 方向 1: 用户 → Knot Agent

**步骤**:

1. **用户在 Channel 发送消息**
   ```dart
   // 用户输入: "帮我分析这段代码"
   Message userMessage = Message(
     content: "帮我分析这段代码",
     sender: currentUser,
   );
   ```

2. **KnotChannelBridgeService 检测到消息**
   ```dart
   // 检查 Channel 中是否有桥接的 Knot Agent
   final bridgedAgents = await getBridgedAgentsForChannel(channelId);
   
   if (bridgedAgents.isNotEmpty) {
     // 有桥接的 Knot Agent，需要转发消息
     await handleChannelMessage(message, channel);
   }
   ```

3. **KnotAgentAdapter 转换消息为任务**
   ```dart
   // 构建任务提示词（包含上下文）
   String taskPrompt = _buildTaskPrompt(message, channel);
   
   // taskPrompt 示例:
   // """
   // 你正在 Channel "技术讨论" 中与用户对话。
   // 
   // 最近的对话历史:
   // [Alice]: 我在处理一个 bug
   // [Bob]: 可以分享代码吗？
   // 
   // 当前消息:
   // [Alice]: 帮我分析这段代码
   // 
   // 请回复这条消息。
   // """
   ```

4. **KnotApiService 发送任务**
   ```dart
   // 调用 Knot API
   final response = await http.post(
     Uri.parse('$baseUrl/api/v1/tasks'),
     headers: {
       'X-Knot-Api-Token': token,
       'Content-Type': 'application/json',
     },
     body: jsonEncode({
       'agent_id': knotAgentId,
       'prompt': taskPrompt,
       'workspace_id': workspaceId,
     }),
   );
   
   final taskId = response['task_id']; // 获得任务 ID
   ```

5. **开始轮询任务状态**
   ```dart
   // 每 3 秒查询一次
   while (true) {
     await Future.delayed(Duration(seconds: 3));
     
     final status = await getTaskStatus(taskId);
     
     if (status == 'COMPLETED') {
       final result = await getTaskResult(taskId);
       break;
     } else if (status == 'FAILED') {
       throw Exception('Task failed');
     }
     // 状态: PENDING, RUNNING, COMPLETED, FAILED
   }
   ```

#### 方向 2: Knot Agent → 用户

**步骤**:

6. **Knot Platform 执行任务**
   - Knot Agent 在云工作区或本地环境执行任务
   - 可能调用工具（bash、文件系统、网页搜索等）
   - 生成执行结果

7. **AI Agent Hub 获取任务结果**
   ```dart
   // 轮询到任务完成
   final taskResult = await knotApiService.getTaskResult(taskId);
   
   // taskResult 示例:
   // {
   //   "task_id": "xxx",
   //   "status": "COMPLETED",
   //   "result": "这段代码存在内存泄漏问题...",
   //   "execution_time": 5.2,
   // }
   ```

8. **KnotAgentAdapter 转换结果为消息**
   ```dart
   Message agentMessage = Message(
     id: generateId(),
     content: taskResult['result'],
     sender: knotAgent,
     timestamp: DateTime.now(),
     metadata: {
       'task_id': taskId,
       'execution_time': taskResult['execution_time'],
     },
   );
   ```

9. **触发消息回调，更新 UI**
   ```dart
   // 通过回调函数将消息添加到 Channel
   onMessageReceived?.call(agentMessage);
   
   // UI 自动更新，用户看到 Agent 的回复
   ```

### 双向通信的关键点

#### ✅ 优点

1. **简单可靠**
   - 使用标准 HTTP REST API
   - 无需维持 WebSocket 长连接
   - 易于调试和错误处理

2. **适配 Flutter**
   - Flutter 的 `http` 包完美支持
   - 无需复杂的流式处理
   - 跨平台兼容性好

3. **上下文感知**
   - 自动构建包含历史消息的上下文
   - Knot Agent 能理解完整对话

#### ⚠️ 局限性

1. **非实时推送**
   - 依赖轮询，有 3 秒延迟
   - 无法看到任务的中间状态
   - 不能实时显示"正在思考..."

2. **资源消耗**
   - 频繁轮询消耗网络资源
   - 长时间任务会持续占用连接

3. **不支持流式输出**
   - 无法像 ChatGPT 那样逐字显示
   - 必须等任务完成才能看到结果

---

## 技术架构详解

### 核心组件

#### 1. KnotApiService

**职责**: 底层 HTTP 通信

```dart
class KnotApiService {
  final String baseUrl;
  final _storage = FlutterSecureStorage();
  
  // Token 管理
  Future<String?> getToken();
  Future<void> saveToken(String token);
  
  // Agent 管理
  Future<List<KnotAgent>> getKnotAgents();
  Future<KnotAgent> getKnotAgent(String agentId);
  
  // 任务管理
  Future<String> sendTask({
    required String agentId,
    required String prompt,
    String? workspaceId,
  });
  
  Future<Map<String, dynamic>> getTaskStatus(String taskId);
  Future<String> getTaskResult(String taskId);
  
  // 工作区管理
  Future<List<KnotWorkspace>> getWorkspaces();
}
```

**实现细节**:
- 使用 `flutter_secure_storage` 安全存储 Token
- 自动添加认证头 (`X-Knot-Api-Token`)
- 统一错误处理（`KnotApiException`）

---

#### 2. KnotAgentAdapter

**职责**: 消息和任务的双向转换

```dart
class KnotAgentAdapter {
  final KnotApiService _knotApiService;
  
  // 转换为标准 Agent
  Agent toStandardAgent(KnotAgent knotAgent) {
    return Agent(
      id: 'knot_${knotAgent.knotAgentId}', // 添加前缀避免冲突
      name: '${knotAgent.name} (Knot)',
      provider: AgentProvider(
        name: 'Knot',
        platform: 'knot',
        type: 'openclaw-adapter',
      ),
    );
  }
  
  // Channel 消息 → Knot 任务
  Future<String> sendMessageToKnotAgent({
    required String agentId,
    required Message message,
    required Channel channel,
  }) async {
    // 1. 构建包含上下文的任务提示词
    final taskPrompt = _buildTaskPrompt(message, channel);
    
    // 2. 发送任务到 Knot API
    final taskId = await _knotApiService.sendTask(
      agentId: getKnotAgentId(agentId),
      prompt: taskPrompt,
      workspaceId: knotAgent.workspaceId,
    );
    
    // 3. 记录任务-频道映射
    _taskChannelMapping[taskId] = channel.id;
    
    return taskId;
  }
  
  // Knot 任务结果 → Channel 消息
  Future<Message?> pollTaskAndConvertToMessage({
    required String taskId,
    required String agentId,
  }) async {
    // 轮询任务状态
    while (true) {
      await Future.delayed(Duration(seconds: pollInterval));
      
      final status = await _knotApiService.getTaskStatus(taskId);
      
      if (status['status'] == 'COMPLETED') {
        final result = await _knotApiService.getTaskResult(taskId);
        
        // 转换为消息
        return Message(
          id: generateId(),
          content: result,
          sender: Agent(id: agentId, name: 'Knot Agent'),
          timestamp: DateTime.now(),
        );
      } else if (status['status'] == 'FAILED') {
        // 返回错误消息
        return _createErrorMessage(agentId, status['error']);
      }
    }
  }
  
  // 构建任务提示词（包含上下文）
  String _buildTaskPrompt(Message message, Channel channel) {
    final buffer = StringBuffer();
    
    buffer.writeln('你正在 Channel "${channel.name}" 中与用户对话。');
    buffer.writeln();
    
    // 添加最近的对话历史
    if (channel.messages.length > 1) {
      buffer.writeln('最近的对话历史:');
      for (var msg in channel.messages.reversed.take(5)) {
        buffer.writeln('[${msg.sender.name}]: ${msg.content}');
      }
      buffer.writeln();
    }
    
    buffer.writeln('当前消息:');
    buffer.writeln('[${message.sender.name}]: ${message.content}');
    buffer.writeln();
    buffer.writeln('请回复这条消息。');
    
    return buffer.toString();
  }
}
```

**关键特性**:
- ✅ ID 前缀管理 (`knot_`)
- ✅ 智能上下文构建
- ✅ 任务-频道映射
- ✅ 错误处理

---

#### 3. KnotChannelBridgeService

**职责**: 桥接管理和消息路由

```dart
class KnotChannelBridgeService {
  final KnotAgentAdapter _adapter;
  final _bridges = <String, List<String>>{}; // channelId -> [agentIds]
  
  // 创建桥接
  Future<void> createBridge({
    required String channelId,
    required String knotAgentId,
  }) async {
    if (!_bridges.containsKey(channelId)) {
      _bridges[channelId] = [];
    }
    
    if (!_bridges[channelId]!.contains(knotAgentId)) {
      _bridges[channelId]!.add(knotAgentId);
    }
  }
  
  // 删除桥接
  Future<void> removeBridge({
    required String channelId,
    required String knotAgentId,
  }) async {
    _bridges[channelId]?.remove(knotAgentId);
  }
  
  // 处理 Channel 消息
  Future<void> handleChannelMessage({
    required Message message,
    required Channel channel,
    Function(Message)? onMessageReceived,
  }) async {
    // 获取桥接的 Knot Agents
    final bridgedAgents = _bridges[channel.id] ?? [];
    
    if (bridgedAgents.isEmpty) {
      return; // 没有桥接的 Agent
    }
    
    // 为每个桥接的 Agent 发送消息
    for (var agentId in bridgedAgents) {
      try {
        // 1. 发送任务
        final taskId = await _adapter.sendMessageToKnotAgent(
          agentId: agentId,
          message: message,
          channel: channel,
        );
        
        // 2. 轮询并获取结果
        final agentMessage = await _adapter.pollTaskAndConvertToMessage(
          taskId: taskId,
          agentId: agentId,
        );
        
        // 3. 触发回调
        if (agentMessage != null) {
          onMessageReceived?.call(agentMessage);
        }
      } catch (e) {
        print('Error handling message for $agentId: $e');
      }
    }
  }
  
  // 获取桥接的 Agents
  List<String> getBridgedAgents(String channelId) {
    return _bridges[channelId] ?? [];
  }
}
```

**工作流程**:
1. 用户发送消息到 Channel
2. 检查是否有桥接的 Knot Agent
3. 如果有，通过 Adapter 转发消息
4. 等待任务完成
5. 将结果作为 Agent 消息添加到 Channel

---

### 数据模型

#### KnotAgent

```dart
class KnotAgent extends Agent {
  final String knotAgentId;        // Knot 平台的 Agent ID
  final String? workspaceId;       // 云工作区 ID
  final String? workspacePath;     // 工作区路径
  final KnotAgentConfig config;    // 配置（模型、MCP 等）
  final List<String>? tools;       // 可用工具列表
  
  // 继承自 Agent:
  // - id: AI Agent Hub 内部 ID
  // - name: 显示名称
  // - avatar: 头像
  // - bio: 简介
  // - provider: 提供商信息
  // - status: 在线状态
}
```

#### KnotAgentConfig

```dart
class KnotAgentConfig {
  final String model;                   // 模型名称 (deepseek-v3.1 等)
  final String? systemPrompt;           // 系统提示词
  final List<String> mcpServers;        // MCP 服务器列表
  final Map<String, dynamic> capabilities; // 能力配置
}
```

---

## 使用场景示例

### 场景 1: 代码审查

**需求**: 用户希望 Knot Agent 审查 Pull Request

**流程**:

1. **用户在 Channel 发送消息**:
   ```
   @KnotAgent 请审查 PR #123 的代码
   ```

2. **AI Agent Hub 处理**:
   ```dart
   // 1. 检测到 Knot Agent 桥接
   final bridgedAgents = bridgeService.getBridgedAgents(channelId);
   
   // 2. 转换为 Knot 任务
   final taskPrompt = """
   你正在 Channel "代码审查" 中与用户对话。
   
   当前消息:
   [Alice]: @KnotAgent 请审查 PR #123 的代码
   
   请执行代码审查任务。
   """;
   
   // 3. 发送到 Knot API
   final taskId = await knotApiService.sendTask(
     agentId: knotAgentId,
     prompt: taskPrompt,
     workspaceId: 'code-review-workspace',
   );
   ```

3. **Knot Agent 执行**:
   - 在云工作区克隆代码库
   - 调用 `bash` 工具执行 `git diff`
   - 使用 `file_system` 工具读取文件
   - 调用 LLM 分析代码
   - 生成审查报告

4. **返回结果**:
   ```dart
   // 轮询到任务完成
   final result = await knotApiService.getTaskResult(taskId);
   
   // 转换为消息
   Message agentMessage = Message(
     content: """
     代码审查完成！
     
     发现 3 个问题:
     1. 内存泄漏风险 (line 42)
     2. SQL 注入漏洞 (line 58)
     3. 未处理的异常 (line 76)
     
     详细报告已生成。
     """,
     sender: knotAgent,
   );
   
   // 添加到 Channel
   channel.addMessage(agentMessage);
   ```

---

### 场景 2: 定时任务执行

**需求**: 每天早上 9 点自动生成日报

**实现**:

```dart
// 1. 设置定时任务
Timer.periodic(Duration(hours: 24), (timer) async {
  if (DateTime.now().hour == 9) {
    // 2. 发送任务到 Knot Agent
    final taskId = await knotApiService.sendTask(
      agentId: dailyReportAgentId,
      prompt: "生成今日的工作日报",
      workspaceId: reportWorkspaceId,
    );
    
    // 3. 轮询结果
    final result = await pollTaskResult(taskId);
    
    // 4. 发送到指定 Channel
    await sendMessageToChannel(
      channelId: 'daily-reports',
      message: result,
    );
  }
});
```

---

### 场景 3: 多 Agent 协作

**需求**: Knot Agent 与 A2A Agent 一起讨论方案

**流程**:

```
Channel "架构设计"
├─ Alice (用户): 我们需要设计一个高并发系统
├─ A2A Agent: 建议使用微服务架构
├─ Knot Agent: 我可以分析现有代码库的结构
└─ Alice: @KnotAgent 请分析 repo/backend
    └─ Knot Agent: [执行分析] 当前是单体架构，建议拆分为...
```

**实现**:

```dart
// 1. 添加 Knot Agent 到 Channel
await channelService.addAgentToChannel(
  channelId: 'architecture-design',
  agentId: 'knot_code-analyzer',
);

// 2. 创建桥接
await bridgeService.createBridge(
  channelId: 'architecture-design',
  knotAgentId: 'knot_code-analyzer',
);

// 3. 用户发送消息时，Knot Agent 自动参与讨论
```

---

## 常见问题

### Q1: 为什么不使用 WebSocket？

**答**: 
- Flutter 的 WebSocket 支持相对简单
- Knot 平台的 WebSocket 端点需要更多配置
- HTTP 轮询更简单、稳定，足够满足当前需求
- 未来如果需要实时性，可以升级为 WebSocket

---

### Q2: 轮询间隔为什么是 3 秒？

**答**:
- 平衡实时性和资源消耗
- Knot Agent 任务通常需要 5-30 秒
- 3 秒是合理的轮询频率
- 可以通过 `KnotAgentAdapter.pollInterval` 调整

---

### Q3: 如何处理长时间任务？

**答**:
- 设置超时时间（默认 5 分钟）
- 超时后返回错误消息
- 用户可以手动查询任务状态
- 未来可以添加后台任务通知

```dart
// 示例: 超时处理
Future<Message?> pollTaskWithTimeout({
  required String taskId,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final startTime = DateTime.now();
  
  while (true) {
    if (DateTime.now().difference(startTime) > timeout) {
      return Message(
        content: '任务执行超时，请稍后查询结果',
        sender: knotAgent,
      );
    }
    
    // 正常轮询逻辑...
  }
}
```

---

### Q4: Knot Agent 可以主动发起对话吗？

**答**:
**当前不支持**，因为：
- AI Agent Hub 采用轮询机制，不是事件驱动
- Knot Platform 也不支持 Agent 主动推送

**未来可能的实现**:
1. 在 AI Agent Hub 添加 WebSocket Server
2. Knot Platform 推送事件到 AI Agent Hub
3. 需要修改 Knot Platform（或使用 Knot 提供的 Webhook）

---

### Q5: 如何配置 Knot Token？

**答**:

1. **获取 Token**:
   - 访问 https://knot.woa.com/settings/token
   - 点击"生成新 Token"
   - 复制 Token

2. **在 AI Agent Hub 中配置**:
   ```dart
   // 方式 1: 通过 UI 设置
   Settings -> Knot Integration -> API Token
   
   // 方式 2: 代码设置
   await knotApiService.saveToken('your-token-here');
   ```

3. **验证配置**:
   ```dart
   final agents = await knotApiService.getKnotAgents();
   if (agents.isNotEmpty) {
     print('Token 配置成功！');
   }
   ```

---

### Q6: 支持哪些 Knot 功能？

**当前支持**:
- ✅ Agent 列表获取
- ✅ 任务提交和查询
- ✅ 工作区管理
- ✅ Channel 桥接
- ✅ 上下文对话

**暂不支持**:
- ❌ 流式输出
- ❌ 实时工具调用显示
- ❌ 思考过程显示
- ❌ MCP 工具直接调用
- ❌ Rules 规则引擎配置

---

### Q7: 如何调试 Knot 集成？

**答**:

1. **检查 Token**:
   ```dart
   final token = await knotApiService.getToken();
   print('Token: ${token != null ? "已配置" : "未配置"}');
   ```

2. **测试 API 连接**:
   ```dart
   try {
     final agents = await knotApiService.getKnotAgents();
     print('API 连接成功，找到 ${agents.length} 个 Agents');
   } catch (e) {
     print('API 连接失败: $e');
   }
   ```

3. **查看任务状态**:
   ```dart
   final status = await knotApiService.getTaskStatus(taskId);
   print('任务状态: ${status['status']}');
   print('任务详情: ${status}');
   ```

4. **启用日志**:
   ```dart
   // 在 KnotApiService 中添加日志
   print('Request: POST $url');
   print('Headers: $headers');
   print('Body: $body');
   print('Response: ${response.body}');
   ```

---

## 总结

### AI Agent Hub 的 Knot 接入特点

| 特性 | 实现方式 | 优点 | 局限 |
|------|---------|------|------|
| **接入协议** | HTTP REST API | 简单可靠 | 非实时 |
| **双向通信** | 轮询机制 | 易于实现 | 有延迟 |
| **上下文支持** | 自动构建 | 智能对话 | - |
| **错误处理** | 统一处理 | 用户友好 | - |
| **多 Agent 协作** | Channel 桥接 | 灵活强大 | 需配置 |

### 关键设计决策

1. **为什么用轮询而不是 WebSocket？**
   - Flutter 更友好
   - 更简单可靠
   - 足够满足当前需求

2. **为什么不直接使用 A2A 协议？**
   - AI Agent Hub 不是标准 A2A Agent
   - 轮询机制更适合 UI 交互
   - A2A 协议过于复杂

3. **为什么需要适配器和桥接服务？**
   - 解耦 Knot 逻辑和 Channel 逻辑
   - 便于未来扩展其他 Agent 类型
   - 提供统一的 Agent 接口

### 未来优化方向

1. **支持流式输出**
   - 使用 SSE (Server-Sent Events)
   - 显示"正在思考..."状态
   - 实时显示工具调用

2. **WebSocket 支持**
   - 减少轮询开销
   - 支持 Agent 主动推送
   - 更好的实时性

3. **任务管理优化**
   - 后台任务队列
   - 任务历史记录
   - 任务取消功能

4. **更多 Knot 功能**
   - MCP 工具直接调用
   - Rules 规则配置
   - 知识库集成

---

## 参考资料

- [Knot 官方文档](https://iwiki.woa.com/space/knot)
- [将 knot 智能体嵌入到 web 页面](https://iwiki.woa.com/p/4016321338)
- [通过 HTTP API 调用智能体](https://iwiki.woa.com/p/4016457374)
- [通过 A2A 多智能体协议调用智能体](https://iwiki.woa.com/p/4016604641)
- [在云工作区中运行 Knot 智能体](https://iwiki.woa.com/p/4016884620)

---

**文档编写**: AI Assistant  
**最后更新**: 2026-02-05  
**版本**: v1.0
