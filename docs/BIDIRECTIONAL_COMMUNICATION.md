# OpenClaw 双向通信集成文档

## 📋 概述

本文档描述了如何实现 AI Agent Hub 与 OpenClaw 之间的**双向通信**，使得：
1. **AI Agent Hub → OpenClaw**: 用户可以在 Hub 中操作 OpenClaw
2. **OpenClaw → AI Agent Hub**: OpenClaw 可以主动向 Hub 发起请求（需用户同意）

---

## 🏗️ 架构设计

### 通信架构

```
┌─────────────────────────────────────────────────────────────┐
│              AI Agent Hub (Flutter)                         │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  ACP Server (WebSocket Server)  ⭐ 核心新增         │   │
│  │  - 监听端口: 18790                                   │   │
│  │  - 接收 OpenClaw 主动请求                           │   │
│  │  - 提供 Hub API (Agent 列表、能力查询)              │   │
│  │  - 权限管理（用户同意机制）                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                         ↕                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  ACP Client (WebSocket Client)                      │   │
│  │  - 连接到 OpenClaw Gateway: 18789                   │   │
│  │  - 发送用户消息                                      │   │
│  │  - 接收 OpenClaw 响应                               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                         ↕
                 WebSocket (双向)
                         ↕
┌─────────────────────────────────────────────────────────────┐
│           OpenClaw Gateway (Moltbot)                        │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  ACP Server                                          │   │
│  │  - 端口: 18789                                       │   │
│  │  - 接收 Hub 的消息                                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                         ↕                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  ACP Client  ⭐ 需要配置                            │   │
│  │  - 连接到 Hub ACP Server: 18790                     │   │
│  │  - 主动发起聊天请求                                  │   │
│  │  - 查询 Hub 能力                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 核心功能实现

### 1. ACP Server (核心新增)

**文件**: `lib/services/acp_server_service.dart`

**功能**:
- ✅ WebSocket Server（监听 18790）
- ✅ 接收 OpenClaw 主动连接
- ✅ 处理 6 种请求类型
- ✅ 权限验证
- ✅ 心跳保活
- ✅ 自动重连

**支持的 API 端点**:

```dart
// 1. 发起聊天（需要用户同意）
hub.initiateChat
{
  "message": "你好，我需要帮助",
  "target_user_id": "user_123",  // 可选
  "target_channel_id": "ch_456",  // 可选
  "priority": "normal",
  "requires_response": true
}

// 2. 获取 Agent 列表
hub.getAgentList
{
  // 无参数
}

// 3. 获取 Agent 能力
hub.getAgentCapabilities
{
  "agent_id": "agent_123"
}

// 4. 获取 Hub 信息
hub.getHubInfo
{
  // 无参数
}

// 5. 订阅 Channel 消息
hub.subscribeChannel
{
  "channel_id": "ch_123"
}

// 6. 取消订阅 Channel
hub.unsubscribeChannel
{
  "channel_id": "ch_123"
}
```

---

### 2. 权限管理系统

**文件**: `lib/services/permission_service.dart`

**功能**:
- ✅ 权限请求管理
- ✅ 用户同意机制
- ✅ 权限有效期管理
- ✅ 白名单管理
- ✅ 权限撤销

**权限类型**:

| 权限类型 | 说明 | 默认状态 |
|---------|------|---------|
| `initiateChat` | 发起聊天 | 需要审批 |
| `getAgentList` | 获取 Agent 列表 | 需要审批 |
| `getAgentCapabilities` | 获取 Agent 能力 | 需要审批 |
| `subscribeChannel` | 订阅 Channel | 需要审批 |

**数据库表结构**:

```sql
CREATE TABLE permission_requests (
  id TEXT PRIMARY KEY,
  agent_id TEXT NOT NULL,
  agent_name TEXT NOT NULL,
  permission_type TEXT NOT NULL,
  reason TEXT,
  status TEXT NOT NULL,  -- pending/approved/rejected/expired
  request_time TEXT NOT NULL,
  processed_time TEXT,
  expiry_time TEXT,
  metadata TEXT
)
```

---

### 3. 用户界面

#### 3.1 权限请求管理界面

**文件**: `lib/screens/permission_request_screen.dart`

**功能**:
- ✅ 显示待审批的权限请求
- ✅ 批准/拒绝权限
- ✅ 查看权限历史
- ✅ 撤销已批准的权限
- ✅ 状态筛选（待审批/已批准/已拒绝/已过期）

**截图**:
```
┌──────────────────────────────────────┐
│ 权限请求管理              🔄         │
├──────────────────────────────────────┤
│ 状态筛选: [待审批] 已批准 已拒绝 已过期 │
├──────────────────────────────────────┤
│ ┌──────────────────────────────────┐ │
│ │ 🤖 OpenClaw Agent         [待审批]│ │
│ │ agent_openclaw_001               │ │
│ │                                  │ │
│ │ 🔒 权限类型: 发起聊天              │ │
│ │ 📝 请求原因: Agent wants to...    │ │
│ │ ⏰ 请求时间: 2026-02-05 07:30     │ │
│ │                                  │ │
│ │           [拒绝] [✅ 批准]        │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

#### 3.2 主动消息通知界面

**文件**: `lib/screens/incoming_message_screen.dart`

**功能**:
- ✅ 接收 OpenClaw 主动消息
- ✅ 消息已读/未读状态
- ✅ 消息通知（SnackBar）
- ✅ 快速回复
- ✅ 删除消息

**截图**:
```
┌──────────────────────────────────────┐
│ 主动消息                   🗑️         │
│ 3 条未读                             │
├──────────────────────────────────────┤
│ ┌──────────────────────────────────┐ │
│ │ 🤖 OpenClaw Agent          🔵    │ │
│ │ 2 分钟前                         │ │
│ │                                  │ │
│ │ 你好，我发现了一个重要的问题...    │ │
│ │                                  │ │
│ │         [标记已读] [💬 回复]      │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

---

## 📡 ACP 协议规范

### 请求格式 (JSON-RPC 2.0)

```json
{
  "jsonrpc": "2.0",
  "id": "request_12345",
  "method": "hub.initiateChat",
  "params": {
    "message": "你好",
    "target_user_id": "user_123"
  },
  "timestamp": "2026-02-05T07:30:00Z",
  "source_agent_id": "agent_openclaw_001"
}
```

### 响应格式

#### 成功响应

```json
{
  "jsonrpc": "2.0",
  "id": "request_12345",
  "result": {
    "status": "success",
    "message_id": "msg_67890",
    "message": "Chat initiated successfully"
  },
  "timestamp": "2026-02-05T07:30:01Z"
}
```

#### 错误响应

```json
{
  "jsonrpc": "2.0",
  "id": "request_12345",
  "error": {
    "code": -32004,
    "message": "Permission request pending user approval",
    "data": {
      "permission_request_id": "perm_123"
    }
  },
  "timestamp": "2026-02-05T07:30:01Z"
}
```

### 错误代码

| 代码 | 名称 | 说明 |
|-----|------|------|
| -32700 | Parse Error | JSON 解析错误 |
| -32600 | Invalid Request | 无效请求 |
| -32601 | Method Not Found | 方法未找到 |
| -32602 | Invalid Params | 无效参数 |
| -32603 | Internal Error | 内部错误 |
| -32001 | Unauthorized | 未授权 |
| -32002 | Permission Denied | 权限被拒绝 |
| -32003 | Not Found | 资源未找到 |
| -32004 | Pending Approval | 等待用户同意 |

---

## 🔧 OpenClaw Gateway 配置

### 步骤 1: 配置 ACP Client

在 OpenClaw Gateway 中添加 ACP Client 配置：

```yaml
# gateway_config.yaml

acp_clients:
  - name: "ai_agent_hub"
    enabled: true
    connection:
      protocol: "ws"
      host: "192.168.1.100"  # AI Agent Hub 的 IP 地址
      port: 18790
      path: "/"
    auth:
      type: "token"
      token: "your_hub_token_here"
    reconnect:
      enabled: true
      max_retries: 10
      retry_interval: 5000  # 毫秒
```

### 步骤 2: 实现主动请求

在 OpenClaw 中添加主动请求逻辑：

```python
# openclaw_hub_integration.py

import asyncio
import websockets
import json

class HubClient:
    def __init__(self, hub_url="ws://192.168.1.100:18790"):
        self.hub_url = hub_url
        self.ws = None
        
    async def connect(self):
        self.ws = await websockets.connect(self.hub_url)
        print(f"✅ Connected to Hub: {self.hub_url}")
        
    async def send_request(self, method, params=None):
        request = {
            "jsonrpc": "2.0",
            "id": str(int(time.time() * 1000)),
            "method": method,
            "params": params or {},
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "source_agent_id": "agent_openclaw_001"
        }
        
        await self.ws.send(json.dumps(request))
        response = await self.ws.recv()
        return json.loads(response)
    
    async def initiate_chat(self, message, target_user_id=None):
        """主动发起聊天"""
        result = await self.send_request(
            "hub.initiateChat",
            {
                "message": message,
                "target_user_id": target_user_id,
                "priority": "normal",
                "requires_response": True
            }
        )
        return result
    
    async def get_agent_list(self):
        """获取 Hub 中的 Agent 列表"""
        result = await self.send_request("hub.getAgentList")
        return result["result"]["agents"]

# 使用示例
async def main():
    client = HubClient()
    await client.connect()
    
    # 主动发起聊天
    response = await client.initiate_chat(
        message="你好，我发现了一个重要的问题",
        target_user_id="user_123"
    )
    print(response)
    
    # 获取 Agent 列表
    agents = await client.get_agent_list()
    print(f"Hub 中有 {len(agents)} 个 Agent")

if __name__ == "__main__":
    asyncio.run(main())
```

---

## 🔐 安全机制

### 1. 权限请求流程

```
OpenClaw                Hub                 User
    |                    |                   |
    |--initiateChat----->|                   |
    |                    |---显示请求------->|
    |                    |                   |
    |                    |<--批准/拒绝-------|
    |<--响应（通过/拒绝）--|                   |
    |                    |                   |
```

### 2. 权限有效期

- **默认有效期**: 永久（直到撤销）
- **可设置有效期**: 1小时、1天、1周、1个月
- **自动过期**: 到期后自动标记为已过期

### 3. 频率限制

```dart
// TODO: 实现频率限制
class RateLimiter {
  final int maxRequestsPerMinute = 60;
  final int maxRequestsPerHour = 1000;
  
  bool isAllowed(String agentId) {
    // 检查频率限制
  }
}
```

---

## 📊 使用场景

### 场景 1: OpenClaw 主动通知

```python
# OpenClaw 检测到重要事件，主动通知用户
await hub_client.initiate_chat(
    message="⚠️ 检测到系统 CPU 使用率超过 90%",
    target_user_id="user_123"
)
```

### 场景 2: OpenClaw 查询其他 Agent

```python
# OpenClaw 需要协作，查询其他 Agent
agents = await hub_client.get_agent_list()
for agent in agents:
    if agent["type"] == "data_analysis":
        # 找到数据分析 Agent，发起协作
        ...
```

### 场景 3: OpenClaw 订阅 Channel 消息

```python
# OpenClaw 订阅某个 Channel，实时接收消息
await hub_client.send_request(
    "hub.subscribeChannel",
    {"channel_id": "ch_project_updates"}
)
```

---

## 🧪 测试指南

### 1. 启动 ACP Server

```bash
# 在 AI Agent Hub 中，ACP Server 会自动启动
flutter run
# 看到: ✅ ACP Server 启动成功 (端口: 18790)
```

### 2. 测试连接

使用 `wscat` 工具测试：

```bash
# 安装 wscat
npm install -g wscat

# 连接到 ACP Server
wscat -c ws://localhost:18790

# 发送测试请求
> {"jsonrpc":"2.0","id":"1","method":"hub.getHubInfo","params":{},"source_agent_id":"test_agent"}

# 预期响应
< {"jsonrpc":"2.0","id":"1","result":{"version":"1.0.0","name":"AI Agent Hub",...}}
```

### 3. 测试权限流程

```bash
# 1. 请求聊天权限（会返回 pending）
> {"jsonrpc":"2.0","id":"2","method":"hub.initiateChat","params":{"message":"测试"},"source_agent_id":"test_agent"}
< {"jsonrpc":"2.0","id":"2","error":{"code":-32004,"message":"Permission request pending user approval"}}

# 2. 在 Hub 中批准权限

# 3. 重新发送请求（会成功）
> {"jsonrpc":"2.0","id":"3","method":"hub.initiateChat","params":{"message":"测试"},"source_agent_id":"test_agent"}
< {"jsonrpc":"2.0","id":"3","result":{"status":"success"}}
```

---

## 📝 文件清单

### 核心实现文件

| 文件 | 功能 | 代码行数 |
|-----|------|---------|
| `lib/models/acp_server_message.dart` | ACP 消息模型 | 350 行 |
| `lib/services/permission_service.dart` | 权限管理服务 | 380 行 |
| `lib/services/acp_server_service.dart` | ACP Server 核心 | 550 行 |
| `lib/screens/permission_request_screen.dart` | 权限管理界面 | 450 行 |
| `lib/screens/incoming_message_screen.dart` | 主动消息界面 | 380 行 |
| `lib/main.dart` | 初始化集成 | +50 行 |

**总计**: 约 2,160 行代码

### 文档文件

| 文件 | 说明 |
|-----|------|
| `docs/BIDIRECTIONAL_COMMUNICATION.md` | 本文档 |
| `docs/ACP_PROTOCOL_SPEC.md` | ACP 协议规范 |
| `docs/OPENCLAW_INTEGRATION_GUIDE.md` | OpenClaw 集成指南 |

---

## 🚀 部署步骤

### 1. 更新依赖

```bash
cd /data/workspace/clawd/ai-agent-hub
flutter pub get
```

### 2. 运行应用

```bash
flutter run
```

### 3. 验证 ACP Server

查看控制台输出：
```
🚀 初始化 ACP Server...
✅ ACP Server 启动成功 (端口: 18790)
```

### 4. 配置 OpenClaw

按照 "OpenClaw Gateway 配置" 部分配置 OpenClaw

### 5. 测试连接

使用 `wscat` 或 Python 脚本测试连接

---

## 🔄 升级路径

### 阶段 1: 基础功能 ✅ (已完成)
- ✅ ACP Server 实现
- ✅ 权限管理系统
- ✅ 用户界面

### 阶段 2: 增强功能 (计划中)
- ⏳ 频率限制
- ⏳ Token 认证
- ⏳ TLS/SSL 支持
- ⏳ 消息持久化

### 阶段 3: 高级功能 (未来)
- 🔜 Agent 间协作
- 🔜 消息转发
- 🔜 事件订阅
- 🔜 WebHook 支持

---

## ❓ 常见问题

### Q1: ACP Server 无法启动？

**A**: 检查端口 18790 是否被占用：

```bash
# Linux/Mac
lsof -i :18790

# Windows
netstat -ano | findstr :18790
```

### Q2: OpenClaw 连接失败？

**A**: 检查：
1. AI Agent Hub 是否正在运行
2. IP 地址是否正确
3. 防火墙是否允许 18790 端口

### Q3: 权限请求一直 pending？

**A**: 在 AI Agent Hub 中：
1. 进入"设置"
2. 选择"权限管理"
3. 查看并批准待审批的请求

---

## 📞 技术支持

如有问题，请联系：
- **项目地址**: /data/workspace/clawd/ai-agent-hub
- **文档路径**: docs/BIDIRECTIONAL_COMMUNICATION.md

---

## 📄 许可证

MIT License - 详见 LICENSE 文件

---

**文档版本**: v1.0.0  
**最后更新**: 2026-02-05  
**作者**: AI Agent Hub Team
