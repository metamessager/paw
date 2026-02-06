# Knot 接入和双向通信 - 快速总结

> 一页纸了解 AI Agent Hub 如何接入 Knot 平台

**最后更新**: 2026-02-05

---

## 📌 核心结论

AI Agent Hub 通过 **HTTP REST API + 轮询机制** 实现与 Knot 平台的双向通信。

---

## 🔄 双向通信流程

### 用户 → Knot Agent

```
1. 用户在 Channel 发送消息 
   ↓
2. 检测到桥接的 Knot Agent
   ↓
3. 转换为 Knot 任务（包含上下文）
   ↓
4. 调用 Knot API 提交任务
   ↓
5. 获得 Task ID
```

### Knot Agent → 用户

```
6. 开始轮询任务状态（每 3 秒）
   ↓
7. Knot Platform 执行任务
   ↓
8. 任务完成，获取结果
   ↓
9. 转换为 Channel 消息
   ↓
10. 显示在 UI 中
```

---

## 🏗️ 技术架构

```
用户界面 (Channel Chat)
    ↓
KnotChannelBridgeService (消息路由)
    ↓
KnotAgentAdapter (消息/任务转换)
    ↓
KnotApiService (HTTP 通信)
    ↓
Knot Platform API
```

---

## 🔑 关键技术点

### 1. 不使用 WebSocket 的原因
- ✅ HTTP REST API 更简单可靠
- ✅ Flutter 更友好
- ✅ 轮询足够满足当前需求

### 2. 轮询机制
- **间隔**: 3 秒
- **超时**: 5 分钟
- **状态**: PENDING → RUNNING → COMPLETED/FAILED

### 3. 上下文构建
```dart
String _buildTaskPrompt(Message message, Channel channel) {
  // 自动添加：
  // 1. Channel 名称
  // 2. 最近 5 条对话历史
  // 3. 当前消息
  // 4. 回复提示
}
```

---

## 📊 Knot 官方支持的接入方式

| 方式 | 通信协议 | 双向通信 | AI Agent Hub 采用 |
|------|---------|---------|------------------|
| Web SDK | HTTP + SSE | ✅ | ❌ (仅 Web) |
| A2A 协议 | HTTP + AGUI | ✅ | ❌ (过于复杂) |
| REST API | HTTP | ⚠️ | ✅ (配合轮询) |
| Knot CLI | HTTP | ❌ | ❌ (单向) |
| MCP | streamable-http | ✅ | ❌ (仅知识库) |

**AI Agent Hub 选择**: REST API + 轮询机制

---

## 💻 核心代码示例

### 发送消息到 Knot Agent

```dart
// 1. 用户发送消息
Message userMessage = Message(
  content: "帮我分析这段代码",
  sender: currentUser,
);

// 2. 转换为 Knot 任务
final taskId = await knotAgentAdapter.sendMessageToKnotAgent(
  agentId: 'knot_xxx',
  message: userMessage,
  channel: currentChannel,
);

// 3. 轮询任务状态
final agentMessage = await knotAgentAdapter.pollTaskAndConvertToMessage(
  taskId: taskId,
  agentId: 'knot_xxx',
);

// 4. 显示结果
channel.addMessage(agentMessage);
```

---

## ⚙️ 配置 Knot Token

### 1. 获取 Token
访问: https://knot.woa.com/settings/token

### 2. 保存 Token
```dart
await knotApiService.saveToken('your-token-here');
```

### 3. 验证配置
```dart
final agents = await knotApiService.getKnotAgents();
print('找到 ${agents.length} 个 Agents');
```

---

## ✅ 优点

- ✅ **简单可靠**: 标准 HTTP 协议
- ✅ **易于调试**: 无复杂流式处理
- ✅ **跨平台**: Flutter 完美支持
- ✅ **上下文感知**: 自动构建完整对话历史

## ⚠️ 局限

- ⚠️ **非实时**: 3 秒轮询延迟
- ⚠️ **无流式输出**: 必须等任务完成
- ⚠️ **资源消耗**: 频繁轮询

---

## 🎯 使用场景

### ✅ 适合
- 代码审查（需要执行工具）
- 文件操作（需要文件系统访问）
- 定时任务（后台执行）
- 复杂分析（需要长时间计算）

### ⚠️ 不适合
- 实时聊天（延迟 3 秒）
- 流式输出（无法逐字显示）
- 高频交互（轮询消耗大）

---

## 📖 完整文档

详细信息请参考: [KNOT_INTEGRATION_EXPLAINED.md](KNOT_INTEGRATION_EXPLAINED.md)

---

## 🔗 相关资源

- [Knot 官方文档](https://iwiki.woa.com/space/knot)
- [通过 HTTP API 调用智能体](https://iwiki.woa.com/p/4016457374)
- [在云工作区中运行 Knot 智能体](https://iwiki.woa.com/p/4016884620)

---

**版本**: v1.0  
**作者**: AI Assistant  
**更新**: 2026-02-05
