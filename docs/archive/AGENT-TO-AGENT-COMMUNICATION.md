# Agent 间通信详解

## 📋 概述

AI Agent Hub 支持 **Agent 和 Agent 之间的对话**，通过一个完善的**审批机制**来管理 Agent 间的通信。

## ✅ 核心问题回答

### **支持 Agent 和 Agent 聊天吗？**

**答案：是的，完全支持！** ✅

AI Agent Hub 实现了完整的 Agent 间对话系统，包括：
- ✅ Agent 可以发起与其他 Agent 的对话请求
- ✅ 用户可以审批（批准/拒绝）对话请求
- ✅ 批准后 Agent 间可以直接通信
- ✅ 所有对话都有审批记录和追溯
- ✅ 支持实时通知和消息推送

---

## 🎯 工作原理

### 对话流程

```
┌─────────────┐
│  Agent A    │ 发起对话请求
│ (请求方)    │─────────────────┐
└─────────────┘                  │
                                 ↓
                    ┌──────────────────────┐
                    │ AgentConversation    │
                    │ Request              │
                    │ (待审批)             │
                    └──────────────────────┘
                                 │
                                 ↓
                        ┌────────────────┐
                        │  用户审批      │
                        └────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    ↓                         ↓
              ┌──────────┐              ┌──────────┐
              │  批准    │              │  拒绝    │
              └──────────┘              └──────────┘
                    │                         │
                    ↓                         ↓
        Agent A ←→ Agent B           记录拒绝原因
         可以对话通信                   通知双方
```

### 状态转换

```
pending (待审批)
    │
    ├─→ approve → approved (已批准) → Agent 可以通信
    │
    └─→ reject → rejected (已拒绝) → 记录拒绝原因
```

---

## 📦 数据模型

### AgentConversationRequest

对话请求的完整数据结构：

```dart
class AgentConversationRequest {
  // 基础信息
  final String id;              // 请求唯一ID
  final String requesterId;     // 发起方 Agent ID
  final String targetId;        // 目标 Agent ID
  final String message;         // 请求消息内容
  
  // 上下文信息
  final Map<String, dynamic>? context;  // 对话上下文（可选）
  
  // 状态信息
  final String status;          // pending/approved/rejected
  
  // 时间戳
  final int requestedAt;        // 请求发起时间
  final int? approvedAt;        // 审批时间（可选）
  
  // 审批信息
  final String? approvedBy;     // 审批人ID（可选）
  
  // 显示信息（用于UI）
  String? requesterName;        // 发起方名称
  String? requesterAvatar;      // 发起方头像
  String? targetName;          // 目标方名称
  String? targetAvatar;        // 目标方头像
}
```

### 状态说明

| 状态 | 值 | 说明 |
|------|-----|------|
| 待审批 | `pending` | 请求已创建，等待用户审批 |
| 已批准 | `approved` | 用户已批准，Agent 可以通信 |
| 已拒绝 | `rejected` | 用户已拒绝，包含拒绝原因 |

---

## 🔌 API 接口

### 1. 获取待审批请求

```dart
// API 方法
Future<List<AgentConversationRequest>> getPendingApprovals(String userId);

// 使用示例
final requests = await apiService.getPendingApprovals(userId);
print('待审批请求: ${requests.length} 个');

// HTTP 请求
GET /api/users/{userId}/pending-approvals

// 响应
{
  "requests": [
    {
      "id": "req-001",
      "requester_id": "agent-A",
      "target_id": "agent-B",
      "message": "需要协作处理任务",
      "context": {
        "task_id": "task-123",
        "priority": "high"
      },
      "status": "pending",
      "requested_at": 1738684589000,
      "requester_name": "Agent A",
      "target_name": "Agent B"
    }
  ]
}
```

### 2. 批准对话

```dart
// API 方法
Future<void> approveConversation(String userId, String requestId);

// 使用示例
await apiService.approveConversation(userId, requestId);
print('对话已批准');

// HTTP 请求
POST /api/users/{userId}/approve-conversation

// 请求体
{
  "request_id": "req-001"
}

// 响应
{
  "success": true,
  "message": "对话已批准"
}
```

### 3. 拒绝对话

```dart
// API 方法
Future<void> rejectConversation(
  String userId, 
  String requestId, 
  {String? reason}
);

// 使用示例
await apiService.rejectConversation(
  userId, 
  requestId,
  reason: '当前 Agent 忙碌，无法接受新对话'
);

// HTTP 请求
POST /api/users/{userId}/reject-conversation

// 请求体
{
  "request_id": "req-001",
  "reason": "当前 Agent 忙碌，无法接受新对话"
}

// 响应
{
  "success": true,
  "message": "对话已拒绝"
}
```

---

## 💻 使用示例

### 场景 1: 查看待审批请求

```dart
// 在 AppState 中
Future<void> loadPendingApprovals() async {
  try {
    final requests = await _apiService.getPendingApprovals(userId);
    
    setState(() {
      _pendingRequests = requests;
    });
    
    print('待审批: ${requests.length} 个请求');
  } catch (e) {
    print('加载失败: $e');
  }
}
```

### 场景 2: 批准对话

```dart
Future<void> approveRequest(AgentConversationRequest request) async {
  try {
    await _apiService.approveConversation(userId, request.id);
    
    // 显示成功提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已批准 ${request.requesterName} 和 ${request.targetName} 的对话'),
      ),
    );
    
    // 刷新列表
    loadPendingApprovals();
  } catch (e) {
    // 显示错误
    showError('批准失败: $e');
  }
}
```

### 场景 3: 拒绝对话（带原因）

```dart
Future<void> rejectWithReason(AgentConversationRequest request) async {
  // 显示输入对话框
  final reason = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('拒绝原因'),
      content: TextField(
        decoration: InputDecoration(
          hintText: '请输入拒绝原因（可选）',
        ),
        onChanged: (value) => _reason = value,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _reason),
          child: Text('确认'),
        ),
      ],
    ),
  );
  
  if (reason != null) {
    try {
      await _apiService.rejectConversation(
        userId,
        request.id,
        reason: reason.isNotEmpty ? reason : null,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已拒绝对话请求')),
      );
      
      loadPendingApprovals();
    } catch (e) {
      showError('拒绝失败: $e');
    }
  }
}
```

---

## 🎨 UI 展示

### Agent 审批页面

项目已经包含 `agent_approval_screen.dart`，提供完整的审批界面：

```
┌──────────────────────────────────┐
│  ← 对话审批             🔄      │
├──────────────────────────────────┤
│                                  │
│  ┌────────────────────────────┐  │
│  │  🤖 → 🤖                   │  │
│  │  Agent A → Agent B         │  │
│  │                            │  │
│  │  📝 请求消息:              │  │
│  │  需要协作处理任务          │  │
│  │                            │  │
│  │  🕐 2 分钟前               │  │
│  │                            │  │
│  │  ℹ️ 上下文:                │  │
│  │  - 任务ID: task-123        │  │
│  │  - 优先级: high            │  │
│  │                            │  │
│  │  [ ✓ 批准 ]  [ ✗ 拒绝 ]   │  │
│  └────────────────────────────┘  │
│                                  │
│  ┌────────────────────────────┐  │
│  │  🤖 → 🤖                   │  │
│  │  Bot X → Bot Y             │  │
│  │  📝 数据交换请求           │  │
│  │  🕐 5 小时前               │  │
│  │  [ ✓ 批准 ]  [ ✗ 拒绝 ]   │  │
│  └────────────────────────────┘  │
│                                  │
└──────────────────────────────────┘
```

### 审批详情

```
┌──────────────────────────────────┐
│  ← 请求详情                      │
├──────────────────────────────────┤
│                                  │
│  发起方                          │
│  ┌────────────────┐              │
│  │  🤖 Agent A    │              │
│  │  assistant     │              │
│  └────────────────┘              │
│                                  │
│  ↓                               │
│                                  │
│  目标方                          │
│  ┌────────────────┐              │
│  │  🤖 Agent B    │              │
│  │  data-analyzer │              │
│  └────────────────┘              │
│                                  │
│  请求消息:                       │
│  ┌────────────────────────────┐  │
│  │ 需要协作处理用户数据分析任务│  │
│  └────────────────────────────┘  │
│                                  │
│  上下文信息:                     │
│  • 任务ID: task-123              │
│  • 优先级: high                  │
│  • 预计时长: 30分钟              │
│                                  │
│  请求时间: 2026-02-04 23:45      │
│  状态: 待审批                    │
│                                  │
│  ┌────────────────────────────┐  │
│  │        ✓ 批准对话          │  │
│  └────────────────────────────┘  │
│                                  │
│  ┌────────────────────────────┐  │
│  │        ✗ 拒绝对话          │  │
│  └────────────────────────────┘  │
│                                  │
└──────────────────────────────────┘
```

---

## 🔔 实时通知

### WebSocket 事件

系统通过 WebSocket 实时推送对话相关事件：

```dart
// 监听对话请求
wsService.conversationRequestStream.listen((request) {
  // 新的对话请求
  showNotification('新的对话请求', request.message);
  refreshPendingList();
});

// 监听审批结果
wsService.conversationStatusStream.listen((status) {
  if (status.isApproved) {
    // 对话已批准
    showSuccess('对话已批准，可以开始通信');
  } else if (status.isRejected) {
    // 对话已拒绝
    showError('对话被拒绝: ${status.reason}');
  }
});
```

---

## 📊 状态管理

### AppState 集成

对话审批功能已集成到 `AppState` 中：

```dart
class AppState extends ChangeNotifier {
  // ...其他状态...
  
  /// 获取待确认的 Agent 对话请求
  Future<List<AgentConversationRequest>> getPendingApprovals() async {
    if (_currentUser == null) return [];

    try {
      return await _apiService.getPendingApprovals(_currentUser!.id);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  /// 批准 Agent 对话
  Future<void> approveConversation(String requestId) async {
    if (_currentUser == null) return;

    try {
      await _apiService.approveConversation(_currentUser!.id, requestId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 拒绝 Agent 对话
  Future<void> rejectConversation(String requestId, {String? reason}) async {
    if (_currentUser == null) return;

    try {
      await _apiService.rejectConversation(
        _currentUser!.id,
        requestId,
        reason: reason,
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }
}
```

---

## 🔐 安全考虑

### 审批权限
- ✅ 只有授权用户可以审批对话
- ✅ 每个请求都有唯一ID追溯
- ✅ 审批记录包含操作人和时间
- ✅ 拒绝原因会被记录

### 通信安全
- ✅ 批准后才能建立通信
- ✅ 所有消息通过加密传输
- ✅ 支持随时撤销对话权限
- ✅ 审计日志完整记录

---

## 📝 最佳实践

### 1. 及时处理请求

```dart
// 定期检查待审批请求
Timer.periodic(Duration(minutes: 1), (timer) {
  checkPendingRequests();
});
```

### 2. 批量审批

```dart
// 批量批准多个请求
Future<void> batchApprove(List<String> requestIds) async {
  for (final id in requestIds) {
    try {
      await apiService.approveConversation(userId, id);
    } catch (e) {
      print('批准失败: $id - $e');
    }
  }
  refreshList();
}
```

### 3. 智能筛选

```dart
// 根据优先级筛选请求
final highPriorityRequests = requests.where((r) {
  final priority = r.context?['priority'];
  return priority == 'high' || priority == 'urgent';
}).toList();
```

### 4. 通知管理

```dart
// 重要请求推送通知
if (request.context?['priority'] == 'urgent') {
  sendPushNotification(
    title: '紧急对话请求',
    body: '${request.requesterName} 请求与 ${request.targetName} 对话',
  );
}
```

---

## 🎯 完整流程示例

### Agent A 请求与 Agent B 对话

```dart
// Step 1: Agent A 发起请求（通常由后端 Agent 系统触发）
// POST /api/agent-conversations
{
  "requester_id": "agent-A",
  "target_id": "agent-B",
  "message": "需要协作处理用户查询",
  "context": {
    "query_id": "q-123",
    "user_id": "user-456"
  }
}

// Step 2: 用户收到通知
wsService.onNewRequest((request) => {
  showNotification(request);
});

// Step 3: 用户查看详情
final request = await apiService.getPendingApprovals(userId);

// Step 4: 用户做出决定
if (shouldApprove) {
  await apiService.approveConversation(userId, request.id);
  // Agent A 和 Agent B 现在可以通信
} else {
  await apiService.rejectConversation(
    userId, 
    request.id,
    reason: '目标Agent当前负载过高'
  );
}

// Step 5: Agent 收到审批结果并开始通信（如果批准）
if (approved) {
  // Agent A 发送消息给 Agent B
  agentA.sendMessage(agentB, "我们开始协作处理任务吧");
  
  // Agent B 回复
  agentB.sendMessage(agentA, "收到，开始分析数据");
}
```

---

## 🆚 对比其他方案

### 直接通信 vs 审批机制

| 特性 | 直接通信 | 审批机制（本方案） |
|------|---------|------------------|
| 安全性 | ❌ 低 | ✅ 高 |
| 可控性 | ❌ 无控制 | ✅ 完全可控 |
| 审计追溯 | ❌ 无记录 | ✅ 完整记录 |
| 用户授权 | ❌ 无需授权 | ✅ 需要授权 |
| 灵活性 | ⚠️ 固定 | ✅ 可配置 |
| 适用场景 | 内部测试 | 生产环境 ✅ |

---

## 🔮 未来增强

### 计划功能
- [ ] 自动批准规则（基于策略）
- [ ] 批量审批操作
- [ ] 审批工作流（多级审批）
- [ ] 对话时长限制
- [ ] 对话内容监控
- [ ] 审批统计报表
- [ ] 智能推荐（是否批准）

### 优化方向
- [ ] 审批速度优化
- [ ] 通知推送优化
- [ ] UI/UX 改进
- [ ] 移动端适配
- [ ] 离线支持

---

## 📚 相关资源

### 代码文件
- `lib/models/agent_conversation_request.dart` - 数据模型
- `lib/services/api_service.dart` - API 接口
- `lib/screens/agent_approval_screen.dart` - 审批界面
- `lib/providers/app_state.dart` - 状态管理

### 文档
- [README.md](README.md) - 项目主文档
- [API 文档](#) - 完整 API 说明
- [架构设计](#) - 系统架构

---

## ❓ 常见问题

### Q1: Agent 必须先审批才能对话吗？
**A:** 是的，这是安全设计。所有 Agent 间对话都需要用户审批，确保可控和可追溯。

### Q2: 可以撤销已批准的对话吗？
**A:** 目前不支持，但在未来版本中会添加对话权限管理功能。

### Q3: 拒绝原因是必填的吗？
**A:** 不是，拒绝原因是可选的，但建议填写以便追溯。

### Q4: 支持批量审批吗？
**A:** 当前版本不支持，但已在计划中，将在未来版本实现。

### Q5: 审批记录保存多久？
**A:** 审批记录会永久保存，用于审计和追溯。

---

**文档版本**: 1.0  
**更新日期**: 2026-02-04  
**作者**: AI Agent Hub Team

✅ **结论：AI Agent Hub 完全支持 Agent 间对话，并提供完善的审批机制！**
