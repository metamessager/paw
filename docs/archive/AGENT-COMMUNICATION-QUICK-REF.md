# Agent 间通信 - 快速参考

## ✅ 支持吗？

**是的！完全支持 Agent 和 Agent 之间的对话！** 🎉

---

## 🚀 快速开始

### 1️⃣ 查看待审批请求

```dart
final requests = await apiService.getPendingApprovals(userId);
print('待审批: ${requests.length} 个');
```

### 2️⃣ 批准对话

```dart
await apiService.approveConversation(userId, requestId);
// Agent A 和 Agent B 现在可以通信！
```

### 3️⃣ 拒绝对话

```dart
await apiService.rejectConversation(
  userId, 
  requestId,
  reason: '当前 Agent 忙碌'
);
```

---

## 📊 核心概念

### 对话请求 (AgentConversationRequest)

```
┌────────────────────────────┐
│ 请求ID: req-001            │
│ 发起方: Agent A            │
│ 目标方: Agent B            │
│ 消息: "需要协作处理任务"   │
│ 状态: pending              │
│ 时间: 2分钟前              │
└────────────────────────────┘
```

### 状态流转

```
pending → approve → approved ✅
       → reject  → rejected ❌
```

---

## 🎯 三个主要 API

| API | 用途 | 方法 |
|-----|------|------|
| **获取请求** | 查看待审批列表 | `getPendingApprovals(userId)` |
| **批准对话** | 允许 Agent 通信 | `approveConversation(userId, requestId)` |
| **拒绝对话** | 拒绝通信请求 | `rejectConversation(userId, requestId, reason)` |

---

## 💡 使用场景

### 场景 1: Agent 协作
```
Agent A (客服) + Agent B (技术支持)
     ↓
协作处理复杂用户问题
```

### 场景 2: 数据交换
```
Agent X (数据采集) + Agent Y (数据分析)
     ↓
交换处理后的数据
```

### 场景 3: 任务分发
```
Agent M (管理者) + Agent W (工作者)
     ↓
分配和执行任务
```

---

## 🔐 安全特性

- ✅ 必须经过用户审批
- ✅ 所有请求可追溯
- ✅ 审批记录永久保存
- ✅ 支持拒绝原因说明

---

## 📱 UI 组件

### Agent 审批页面

```dart
// 导航到审批页面
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => AgentApprovalScreen(),
  ),
);
```

**文件位置**: `lib/screens/agent_approval_screen.dart`

---

## 🔄 完整流程

```
1. Agent A 发起对话请求
   ↓
2. 请求进入待审批队列
   ↓
3. 用户收到通知
   ↓
4. 用户审批（批准/拒绝）
   ↓
5a. 批准 → Agent 开始通信
5b. 拒绝 → 记录原因，通知双方
```

---

## 📚 相关文档

- 📖 [完整文档](AGENT-TO-AGENT-COMMUNICATION.md)
- 📘 [README](README.md)
- 🔍 [API 参考](README.md#-api-文档)

---

## 🎊 总结

| 问题 | 答案 |
|------|------|
| **支持 Agent 间对话吗？** | ✅ **是的！** |
| **需要审批吗？** | ✅ 是（安全考虑） |
| **可以实时通信吗？** | ✅ 批准后可以 |
| **有审批记录吗？** | ✅ 完整记录 |

---

**快速咨询**: 查看 [AGENT-TO-AGENT-COMMUNICATION.md](AGENT-TO-AGENT-COMMUNICATION.md) 获取详细信息

**版本**: 1.0 | **更新**: 2026-02-04
