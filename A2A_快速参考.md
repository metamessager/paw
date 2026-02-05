# A2A 协议 - 快速参考

## 🚀 一分钟上手

### 添加 A2A Agent (自动发现)

```dart
final agent = await agentService.discoverAndAddA2AAgent(
  'https://agent.example.com',
  apiKey: 'your-api-key',
);
```

### 发送任务 (同步)

```dart
final task = A2ATask(instruction: 'Hello, agent!');
final response = await agentService.sendTaskToA2AAgent(
  agent, task, waitForCompletion: true
);
```

### 流式任务

```dart
await for (var update in agentService.streamTaskToA2AAgent(agent, task)) {
  print('状态: ${update.state}');
}
```

---

## 📋 A2A 协议核心概念

### Agent Card (Agent 名片)

```json
{
  "name": "WeatherBot",
  "description": "提供天气预报服务",
  "endpoints": {
    "tasks": "https://api.example.com/a2a/tasks",
    "stream": "https://api.example.com/a2a/stream"
  },
  "capabilities": ["weather_forecast"],
  "authentication": {"schemes": ["bearer"]}
}
```

### Task (任务)

```dart
final task = A2ATask(
  instruction: '今天天气如何？',
  context: [A2APart.text('我在北京')],
  metadata: {'user_id': '123'},
);
```

### Task States (任务状态)

- `submitted` - 已提交
- `working` - 执行中
- `completed` - 已完成 ✅
- `failed` - 失败 ❌

---

## 🎨 UI 使用流程

### 添加 Agent

```
1. 打开"通用 Agent 管理"
2. 点击 [+] 按钮
3. 选择"A2A Agent"
4. 输入 Agent URI
5. 点击"发现并添加"
```

### 与 Agent 对话

```
1. 在列表点击 Agent
2. 切换到"对话"标签
3. 输入消息
4. 点击发送
5. 查看响应
```

---

## 🔧 常用 API

### Agent 管理

```dart
// 获取所有 Agent
final agents = await agentService.getAllAgents();

// 按类型筛选
final a2aAgents = await agentService.getAgentsByType('a2a');

// 获取单个 Agent
final agent = await agentService.getAgentById('agent-123');

// 删除 Agent
await agentService.deleteAgent('agent-123');
```

### 任务操作

```dart
// 提交任务 (同步)
final response = await agentService.sendTaskToA2AAgent(
  agent, task, waitForCompletion: true
);

// 提交任务 (异步)
final response = await a2aService.submitTask(endpoint, task);

// 查询状态
final status = await a2aService.getTaskStatus(endpoint, taskId);

// 轮询至完成
final completed = await a2aService.pollTaskUntilComplete(
  endpoint, taskId, interval: Duration(seconds: 2)
);

// 流式任务
await for (var update in a2aService.streamTask(endpoint, task)) {
  // 处理更新
}
```

### 任务历史

```dart
// 获取 Agent 的所有任务
final tasks = await agentService.getAgentTasks(agent.id);

// 过滤已完成的任务
final completed = tasks.where((t) => t.isCompleted).toList();

// 过滤失败的任务
final failed = tasks.where((t) => t.isFailed).toList();
```

---

## 🌐 支持的 Agent 类型

| 类型 | 协议 | 发现 | 状态 |
|------|------|------|------|
| A2A Agent | A2A Protocol | ✅ 自动 | ✅ |
| Knot Agent | Knot API | 手动 | ✅ |
| Custom Agent | 自定义 | 手动 | ⏳ |

---

## 📊 数据库表

### agents

```sql
CREATE TABLE agents (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT DEFAULT 'standard',  -- a2a, knot, custom
  config TEXT,                    -- JSON 配置
  ...
);
```

### agent_cards

```sql
CREATE TABLE agent_cards (
  id INTEGER PRIMARY KEY,
  agent_id TEXT UNIQUE,
  card_data TEXT,  -- JSON 格式
  cached_at INTEGER
);
```

### tasks

```sql
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY,
  task_id TEXT UNIQUE,
  agent_id TEXT,
  state TEXT,      -- submitted, working, completed, failed
  ...
);
```

---

## 🔐 安全配置

### 设置认证

```dart
// Bearer Token
a2aService.setAuthentication('bearer', 'your-token');

// API Key
a2aService.setAuthentication('apiKey', 'your-api-key');
```

### HTTPS 强制

所有 A2A Agent URI 必须使用 HTTPS：

```dart
if (!uri.startsWith('https://')) {
  throw Exception('Must use HTTPS');
}
```

---

## 🐛 错误处理

### Agent 发现失败

```dart
try {
  final agent = await agentService.discoverAndAddA2AAgent(uri);
} catch (e) {
  if (e.toString().contains('404')) {
    // Agent Card 不存在
  } else if (e.toString().contains('timeout')) {
    // 网络超时
  } else {
    // 其他错误
  }
}
```

### 任务提交失败

```dart
try {
  final response = await agentService.sendTaskToA2AAgent(agent, task);
} catch (e) {
  if (e.toString().contains('401')) {
    // 认证失败
  } else if (e.toString().contains('timeout')) {
    // 任务超时
  }
}
```

---

## 📈 性能优化

### Agent Card 缓存

Agent Card 自动缓存在本地数据库，减少网络请求。

### 任务轮询间隔

```dart
// 默认 2 秒
await a2aService.pollTaskUntilComplete(endpoint, taskId);

// 自定义间隔
await a2aService.pollTaskUntilComplete(
  endpoint, 
  taskId,
  interval: Duration(seconds: 5),  // 5 秒轮询
);
```

### 流式任务推荐

对于长时间运行的任务，推荐使用流式模式：

```dart
await for (var update in a2aService.streamTask(endpoint, task)) {
  // 实时获取更新，无需轮询
}
```

---

## 🧪 测试示例

### 测试 Agent 发现

```dart
test('discover agent', () async {
  final agent = await agentService.discoverAndAddA2AAgent(
    'https://example.com'
  );
  
  expect(agent.name, isNotEmpty);
  expect(agent.agentCard, isNotNull);
});
```

### 测试任务提交

```dart
test('submit task', () async {
  final task = A2ATask(instruction: 'test');
  final response = await agentService.sendTaskToA2AAgent(
    agent, task, waitForCompletion: true
  );
  
  expect(response.state, 'completed');
});
```

---

## 📚 相关文档

- 📖 [完整技术指南](docs/A2A_UNIVERSAL_AGENT_GUIDE.md)
- 📊 [实施完成报告](docs/A2A_IMPLEMENTATION_REPORT.md)
- 🎉 [完成总结](A2A_完成总结.md)
- 🚀 [快速开始](docs/QUICK_START.md)

---

## 🆚 A2A vs MCP vs ACP

| 特性 | A2A | MCP | ACP |
|------|-----|-----|-----|
| **用途** | Agent ↔ Agent | Agent ↔ Tool | Agent ↔ Agent |
| **标准** | Google | Anthropic | AgentUnion |
| **协议** | HTTP/JSON-RPC | Stdio/HTTP | HTTP |
| **区域** | 全球 | 全球 | 中国 |

---

## 💡 最佳实践

### 1. 使用 HTTPS
始终使用 HTTPS 连接 Agent。

### 2. 缓存 Agent Card
Agent Card 自动缓存，避免频繁请求。

### 3. 优先流式任务
长时间任务使用流式模式，避免轮询开销。

### 4. 错误重试
网络错误时实施指数退避重试。

### 5. Token 安全
API Key 加密存储，不要硬编码。

---

## 🔗 快速链接

- 🌐 [A2A 协议官网](https://a2a-protocol.org/)
- 📖 [Google A2A Hub](https://google-a2a.wiki/)
- 💬 [GitHub Issues](https://github.com/yourusername/ai-agent-hub/issues)

---

**版本**: v1.0.0  
**最后更新**: 2026-02-05  
**状态**: ✅ 生产就绪
