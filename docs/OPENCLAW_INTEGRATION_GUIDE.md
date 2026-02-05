# OpenClaw Agent 集成指南

## 🦅 OpenClaw 简介

**OpenClaw** 是基于 **Knot Platform** 构建的智能体系统，提供强大的 AI Agent 能力。

### 核心特性

✅ **MCP 工具集成** - 支持多种 Model Context Protocol 工具  
✅ **Rules 规则引擎** - 灵活的规则配置  
✅ **知识库检索** - 集成企业知识库  
✅ **多模型支持** - GPT-4, Claude, 等主流模型  
✅ **工作区管理** - 多租户隔离  

---

## 🏗️ 技术架构

```
┌──────────────────────────────────────────┐
│     AI Agent Hub (Flutter)               │
│  ┌────────────────────────────────────┐  │
│  │  OpenClawAgent (专用实现)          │  │
│  │  - MCP Tools                       │  │
│  │  - Rules Engine                    │  │
│  │  - Knowledge Base                  │  │
│  └────────────────────────────────────┘  │
│              ↓                            │
│  ┌────────────────────────────────────┐  │
│  │  OpenClawAgentService              │  │
│  │  - sendMessage()                   │  │
│  │  - submitTask()                    │  │
│  │  - queryWithKnowledge()            │  │
│  └────────────────────────────────────┘  │
│              ↓                            │
│  ┌────────────────────────────────────┐  │
│  │  LocalDatabaseService (SQLite)     │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
              ↓ HTTPS
┌──────────────────────────────────────────┐
│     Knot Platform (OpenClaw)             │
│  ┌────────────────────────────────────┐  │
│  │  Agent Runtime                     │  │
│  │  ├─ MCP Tools                      │  │
│  │  ├─ Rules Engine                   │  │
│  │  ├─ Knowledge Base                 │  │
│  │  └─ Multi-Model Support            │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

---

## 📦 核心组件

### 1. OpenClawAgent 模型

```dart
class OpenClawAgent extends UniversalAgent {
  final String knotBaseUrl;      // Knot 平台 URL
  final String knotToken;         // API Token
  final String knotWorkspaceId;   // 工作区 ID
  final String? knotModel;        // 模型名称
  
  // 高级配置
  final List<String>? tools;            // MCP 工具列表
  final Map<String, dynamic>? rules;    // Rules 配置
  final List<String>? knowledgeBases;   // 知识库 UUID
}
```

### 2. OpenClawAgentService 服务

**核心方法**:
- `addAgent()` - 添加 OpenClaw Agent
- `sendMessage()` - 发送消息
- `submitTask()` - 提交任务 (A2A 风格)
- `streamTask()` - 流式任务
- `queryWithKnowledge()` - 知识库查询
- `testConnection()` - 测试连接
- `getAgentTools()` - 获取工具列表
- `getKnowledgeBases()` - 获取知识库列表

---

## 🚀 快速开始

### 步骤 1: 添加 OpenClaw Agent

```dart
final agent = await openClawService.addAgent(
  name: 'My OpenClaw Assistant',
  knotBaseUrl: 'https://knot.example.com',
  knotToken: 'your-knot-token',
  knotWorkspaceId: 'workspace-123',
  knotModel: 'gpt-4',
  tools: ['weather', 'web_search'],
  knowledgeBases: ['bed6837500624aa6b2d3f3551f8590be'],
);
```

### 步骤 2: 发送消息

```dart
final response = await openClawService.sendMessage(
  agent,
  '今天天气如何？',
);

print('Agent 响应: $response');
```

### 步骤 3: 使用知识库

```dart
final result = await openClawService.queryWithKnowledge(
  agent,
  '什么是 A2A 协议？',
  ['bed6837500624aa6b2d3f3551f8590be'], // Knot 知识库
);

print('知识库结果: $result');
```

---

## 🎨 UI 使用流程

### 添加 Agent

```
1. 打开"通用 Agent 管理"
2. 点击 [+] → "OpenClaw Agent"
3. 填写基本信息:
   - Agent 名称
   - Knot Base URL
   - Knot Token
   - Workspace ID
   - 模型 (可选)
4. (可选) 展开"高级配置":
   - 选择 MCP 工具
   - 添加知识库 UUID
5. 点击"测试连接"
6. 点击"添加 OpenClaw Agent"
```

### 与 Agent 对话

```
1. 在列表点击 OpenClaw Agent
2. 切换到"对话"标签
3. 输入消息
4. Agent 自动调用 MCP 工具
5. 查看带知识库增强的响应
```

---

## 🔧 API 详解

### 基本对话

```dart
// 简单对话
final response = await openClawService.sendMessage(
  agent,
  'Hello, OpenClaw!',
);
```

### A2A 风格任务

```dart
// 创建任务
final task = A2ATask(
  instruction: '帮我查一下北京的天气',
  context: [
    A2APart.text('我明天要出门'),
  ],
);

// 提交任务
final response = await openClawService.submitTask(agent, task);

// 查看结果
if (response.isCompleted) {
  print('任务完成: ${response.artifacts}');
}
```

### 流式任务

```dart
await for (var update in openClawService.streamTask(agent, task)) {
  print('进度: ${update.state}');
  
  if (update.artifacts != null) {
    for (var artifact in update.artifacts!) {
      for (var part in artifact.parts) {
        print('内容片段: ${part.content}');
      }
    }
  }
}
```

### 知识库查询

```dart
// 查询知识库
final result = await openClawService.queryWithKnowledge(
  agent,
  'Knot 平台有哪些功能？',
  ['bed6837500624aa6b2d3f3551f8590be'], // Knot 知识库 UUID
);

print('检索结果: $result');
```

### 获取工具列表

```dart
final tools = await openClawService.getAgentTools(agent);
print('可用工具: $tools');
// 输出: ['weather', 'web_search', 'file_system', ...]
```

### 获取知识库列表

```dart
final kbs = await openClawService.getKnowledgeBases(agent);
for (var kb in kbs) {
  print('知识库: ${kb['name']} (${kb['uuid']})');
}
```

---

## 🌟 高级功能

### 1. MCP 工具集成

OpenClaw Agent 支持多种 MCP 工具：

```dart
final agent = await openClawService.addAgent(
  name: 'Tool-Enhanced Agent',
  // ... 基本配置
  tools: [
    'weather',        // 天气查询
    'web_search',     // 网络搜索
    'file_system',    // 文件操作
    'database',       // 数据库查询
    'calculator',     // 计算器
    'translator',     // 翻译
  ],
);
```

**自动工具调用**:
```dart
// Agent 自动判断需要调用哪些工具
final response = await openClawService.sendMessage(
  agent,
  '查一下明天北京的天气，然后帮我翻译成英文',
);
// Agent 会自动调用 weather 和 translator 工具
```

### 2. Rules 规则引擎

```dart
final agent = await openClawService.addAgent(
  name: 'Rule-Based Agent',
  // ... 基本配置
  rules: {
    'max_tokens': 2000,
    'temperature': 0.7,
    'response_format': 'markdown',
    'safety_level': 'strict',
    'custom_rules': [
      'Always respond in Chinese',
      'Include sources for factual claims',
    ],
  },
);
```

### 3. 多知识库集成

```dart
final agent = await openClawService.addAgent(
  name: 'Knowledge Agent',
  // ... 基本配置
  knowledgeBases: [
    'bed6837500624aa6b2d3f3551f8590be', // Knot 知识库
    'b9e8CgF0-11g9f7B529G0E0636D588ecc', // 公司文档库
    'c0f9DhG1-22h0g8C630H1F1747E699fdd', // 技术手册库
  ],
);

// 跨知识库查询
final result = await openClawService.queryWithKnowledge(
  agent,
  '什么是 Knot 平台的 A2A 协议？',
  agent.knowledgeBases!, // 查询所有知识库
);
```

### 4. 多模型支持

```dart
// GPT-4
final gpt4Agent = await openClawService.addAgent(
  name: 'GPT-4 Agent',
  knotModel: 'gpt-4',
  // ...
);

// Claude 3
final claudeAgent = await openClawService.addAgent(
  name: 'Claude Agent',
  knotModel: 'claude-3-opus',
  // ...
);

// 通义千问
final qwenAgent = await openClawService.addAgent(
  name: 'Qwen Agent',
  knotModel: 'qwen-max',
  // ...
);
```

---

## 🔐 安全配置

### Token 安全

```dart
// Token 自动加密存储
final agent = await openClawService.addAgent(
  name: 'Secure Agent',
  knotToken: 'your-secret-token', // 自动加密
  // ...
);

// Token 不会明文存储在数据库
// 使用时自动解密
```

### HTTPS 强制

```dart
// 所有请求强制使用 HTTPS
if (!knotBaseUrl.startsWith('https://')) {
  throw Exception('Must use HTTPS for security');
}
```

### 工作区隔离

```dart
// 每个 Agent 绑定到特定工作区
final agent = await openClawService.addAgent(
  knotWorkspaceId: 'workspace-123',  // 工作区隔离
  // ...
);

// 不同工作区的数据完全隔离
```

---

## 📊 与其他 Agent 类型对比

| 特性 | A2A Agent | OpenClaw Agent | Knot Agent |
|------|-----------|----------------|------------|
| **协议** | A2A Protocol | Knot API | Knot API |
| **发现** | ✅ 自动发现 | 手动配置 | 手动配置 |
| **MCP 工具** | ❌ | ✅ 完整支持 | ⚠️ 部分支持 |
| **Rules 引擎** | ❌ | ✅ | ❌ |
| **知识库** | ❌ | ✅ 多库支持 | ✅ 单库 |
| **流式任务** | ✅ SSE | ✅ SSE | ⚠️ 轮询 |
| **多模型** | ✅ | ✅ | ✅ |
| **互操作性** | ✅ 标准化 | ⚠️ Knot 专用 | ⚠️ Knot 专用 |

**结论**: 
- **A2A Agent** - 标准化、跨平台
- **OpenClaw Agent** - 功能最强大（MCP + Rules + 知识库）
- **Knot Agent** - 简化版，基本功能

---

## 🧪 测试示例

### 测试基本对话

```dart
test('OpenClaw basic chat', () async {
  final agent = await openClawService.addAgent(
    name: 'Test Agent',
    knotBaseUrl: 'https://test.knot.com',
    knotToken: 'test-token',
    knotWorkspaceId: 'test-workspace',
  );

  final response = await openClawService.sendMessage(
    agent,
    'Hello!',
  );

  expect(response, isNotEmpty);
});
```

### 测试知识库查询

```dart
test('OpenClaw knowledge query', () async {
  final result = await openClawService.queryWithKnowledge(
    agent,
    '什么是 Knot？',
    ['bed6837500624aa6b2d3f3551f8590be'],
  );

  expect(result, contains('Knot'));
});
```

### 测试工具调用

```dart
test('OpenClaw tool usage', () async {
  final agent = await openClawService.addAgent(
    // ...
    tools: ['weather'],
  );

  final response = await openClawService.sendMessage(
    agent,
    '今天天气如何？',
  );

  expect(response, contains('天气'));
});
```

---

## 📈 性能优化

### 连接复用

```dart
// 服务单例，自动复用 HTTP 连接
final openClawService = OpenClawAgentService(db);

// 多次调用共享连接池
await openClawService.sendMessage(agent1, 'msg1');
await openClawService.sendMessage(agent2, 'msg2');
```

### 知识库缓存

```dart
// Agent 配置中的知识库自动缓存
final agent = await openClawService.addAgent(
  knowledgeBases: [...],  // 缓存在 Agent 配置中
);

// 查询时直接使用，无需重复配置
```

### 流式响应

```dart
// 使用流式任务减少延迟
await for (var update in openClawService.streamTask(agent, task)) {
  // 实时显示内容
  print(update.artifacts);
}
```

---

## 🐛 常见问题

### Q1: 连接失败怎么办？

**检查清单**:
1. ✅ Base URL 是否正确？
2. ✅ Token 是否有效？
3. ✅ Workspace ID 是否正确？
4. ✅ 网络是否可达？

```dart
// 测试连接
final success = await openClawService.testConnection(agent);
if (!success) {
  print('连接失败，请检查配置');
}
```

### Q2: 知识库查询无结果？

**可能原因**:
1. 知识库 UUID 错误
2. 查询关键词不匹配
3. 知识库未授权

```dart
// 检查知识库列表
final kbs = await openClawService.getKnowledgeBases(agent);
print('可用知识库: $kbs');
```

### Q3: MCP 工具未生效？

**解决方法**:
```dart
// 检查工具列表
final tools = await openClawService.getAgentTools(agent);
print('Agent 工具: $tools');

// 重新配置
await openClawService.updateAgent(
  agent.copyWith(tools: ['weather', 'web_search']),
);
```

---

## 🛣️ 未来计划

### v1.1 (近期)
- ⏳ Rules 可视化编辑器
- ⏳ MCP 工具市场
- ⏳ 知识库批量导入
- ⏳ Agent 性能监控

### v2.0 (长期)
- 📋 Agent 间协作
- 📋 工作流编排
- 📋 自定义 MCP 工具
- 📋 知识图谱集成

---

## 📚 相关资源

### 官方文档
- [Knot Platform 文档](https://iwiki.woa.com/space/knot)
- [MCP 协议规范](https://modelcontextprotocol.io/)
- [OpenClaw GitHub](https://github.com/your-org/openclaw)

### 知识库
- **Knot 知识库**: `bed6837500624aa6b2d3f3551f8590be`
  - 地址: https://iwiki.woa.com/space/knot
  - 内容: FAQ, 功能介绍, 更新日志

---

## 📝 完整示例

```dart
import 'package:ai_agent_hub/models/openclaw_agent.dart';
import 'package:ai_agent_hub/services/openclaw_agent_service.dart';

void main() async {
  // 1. 初始化服务
  final db = await openDatabase('ai_agent_hub.db');
  final openClawService = OpenClawAgentService(db);

  // 2. 添加 OpenClaw Agent
  final agent = await openClawService.addAgent(
    name: 'My OpenClaw Assistant',
    knotBaseUrl: 'https://knot.example.com',
    knotToken: 'your-token',
    knotWorkspaceId: 'workspace-123',
    knotModel: 'gpt-4',
    bio: '一个强大的 OpenClaw 智能助手',
    tools: ['weather', 'web_search'],
    knowledgeBases: ['bed6837500624aa6b2d3f3551f8590be'],
  );

  // 3. 测试连接
  final connected = await openClawService.testConnection(agent);
  print('连接状态: ${connected ? "成功" : "失败"}');

  // 4. 基本对话
  final response = await openClawService.sendMessage(
    agent,
    '你好，介绍一下 Knot 平台的功能',
  );
  print('Agent 响应: $response');

  // 5. 知识库查询
  final kbResult = await openClawService.queryWithKnowledge(
    agent,
    '什么是 A2A 协议？',
    ['bed6837500624aa6b2d3f3551f8590be'],
  );
  print('知识库结果: $kbResult');

  // 6. 流式任务
  final task = A2ATask(instruction: '帮我写一首关于 AI 的诗');
  await for (var update in openClawService.streamTask(agent, task)) {
    print('状态: ${update.state}');
    if (update.artifacts != null) {
      print('内容: ${update.artifacts!.first.parts.first.content}');
    }
  }

  // 7. 清理
  openClawService.dispose();
}
```

---

## ✅ 完成检查清单

### 核心功能
- [x] OpenClawAgent 模型
- [x] OpenClawAgentService 服务
- [x] 基本对话
- [x] A2A 风格任务
- [x] 流式任务
- [x] 知识库查询
- [x] MCP 工具集成
- [x] Rules 引擎支持

### UI 界面
- [x] 添加 Agent 页面
- [x] 高级配置 (工具/知识库)
- [x] 连接测试
- [x] Agent 列表集成

### 文档
- [x] 集成指南
- [x] API 参考
- [x] 使用示例
- [x] 故障排除

---

## 🎉 **OpenClaw Agent 集成完成！**

**状态**: ✅ 生产就绪  
**版本**: v1.0.0  
**文档**: 完整  
**测试**: 通过  

---

**文档版本**: v1.0.0  
**最后更新**: 2026-02-05  
**作者**: AI Agent Hub Team
