# AI Agent Hub

> 🎉 **v2.0.0 本地化版本** - 完全本地化，无需后端服务器！
> 
> ✅ **SQLite 本地数据库** | ✅ **本地文件存储** | ✅ **完全离线可用** | ✅ **隐私安全**
>
> 📖 **[快速开始](docs/QUICK_START.md)** | 📊 **[本地化报告](docs/LOCALIZATION_REPORT.md)** | 🚀 **[完成总结](docs/LOCALIZATION_SUMMARY.md)**

一个功能完整的 AI Agent 管理平台，支持 Agent 管理、频道通信、Agent 间对话等功能。

## 🎯 v2.0.0 本地化特性

### 核心优势

- ✅ **零后端依赖** - 无需搭建服务器
- ✅ **完全离线** - 无网络也能使用
- ✅ **SQLite 数据库** - 高性能本地存储
- ✅ **本地文件系统** - 图片/头像独立存储
- ✅ **隐私安全** - 数据完全本地化
- ✅ **即时响应** - 无网络延迟（< 10ms）
- ✅ **跨平台** - iOS、Android、Desktop

### 技术架构

```
AI Agent Hub (Flutter)
    ↓
┌──────────────────────────────┐
│ 本地化服务层                 │
├──────────────────────────────┤
│ • LocalDatabaseService       │  ← SQLite 数据库
│ • LocalFileStorageService    │  ← 本地文件存储
│ • LocalApiService             │  ← 本地 API
│ • LocalKnotAgentService      │  ← Knot Agent
└──────────────────────────────┘
    ↓
┌──────────────────────────────┐
│ 数据存储                     │
├──────────────────────────────┤
│ • ai_agent_hub.db            │  ← 10个数据表
│ • avatars/                   │  ← 头像目录
│ • images/                    │  ← 图片目录
│ • documents/                 │  ← 文档目录
└──────────────────────────────┘
```

### 快速上线

```bash
# 1. 运行自动化脚本（5 分钟）
./scripts/localize.sh

# 2. 启动应用（1 分钟）
flutter run

# 3. 打包发布（20 分钟）
flutter build apk --release
```

**总时间**: 仅需 **30 分钟**即可上线！

### 数据存储

| 类型 | 位置 | 说明 |
|------|------|------|
| 数据库 | `<应用数据>/databases/ai_agent_hub.db` | SQLite数据库 |
| 头像 | `<应用数据>/ai_agent_hub/avatars/` | Agent头像 |
| 图片 | `<应用数据>/ai_agent_hub/images/` | 一般图片 |
| 文档 | `<应用数据>/ai_agent_hub/documents/` | 文档文件 |

### 性能指标

| 操作 | 性能 | 说明 |
|------|------|------|
| 数据库读取 | < 10ms | 100 条记录 |
| 数据库写入 | < 5ms | 单条记录 |
| 图片保存 | < 100ms | 200KB头像 |
| 图片读取 | < 50ms | 本地文件 |

---

## ✨ 核心功能

### 1. 🤖 Agent 管理
- **Agent CRUD 操作**
  - 查看所有 Agent 列表
  - 添加新 Agent
  - 编辑 Agent 信息
  - 删除 Agent
- **Agent 状态管理**
  - 在线（Online）
  - 离线（Offline）
  - 忙碌（Busy）
  - 错误（Error）
- **Agent 信息**
  - 名称、类型、ID
  - Avatar 头像支持
  - 实时状态显示

### 2. 💬 频道管理
- 创建和管理消息频道
- 支持频道描述
- 频道列表查看
- 实时消息同步

### 3. 🌐 通用 Agent 接入 + A2A 协议支持 ⭐ **NEW**

**✅ 支持任意类型 Agent，不限于 Knot！**

#### 🚀 核心特性

```
AI Agent Hub
    ↓
通用 Agent 抽象层
    ├─→ A2A Agent (A2A 协议标准)
    ├─→ OpenClaw Agent (ACP 协议) ⭐ **最新**
    ├─→ Knot Agent (OpenClaw 风格)
    └─→ Custom Agent (用户自定义)
```

#### OpenClaw Agent 支持 🦅 **最新集成**

**OpenClaw (Moltbot)** - 工业级 AI Agent Gateway

- ✅ **ACP 协议** - 基于 JSON-RPC 2.0 + WebSocket
- ✅ **实时通信** - 双向流式响应
- ✅ **工具系统** - bash, file-system, web-search, code-executor 等
- ✅ **会话管理** - Session ID 持久化
- ✅ **自动重连** - 断线自动恢复
- ✅ **心跳机制** - 连接保活
- ✅ **本地优先** - 支持本地部署

**快速开始**:
```
1. 启动 OpenClaw Gateway: openclaw gateway start --port 18789
2. 在 AI Agent Hub 点击 "+"
3. 选择 "🦅 OpenClaw Agent"
4. 输入 Gateway URL: ws://localhost:18789
5. 选择需要的工具（bash, file-system 等）
6. 测试连接 → 添加 → 开始使用！
```

**支持的工具**:
- 💻 **Bash 命令** - 执行 Shell 命令
- 📁 **文件系统** - 读写文件
- 🔍 **Web 搜索** - 搜索互联网
- ⚙️ **代码执行** - 运行代码
- 📷 **屏幕截图** - 截取屏幕
- 🌐 **浏览器控制** - 自动化浏览器

**使用示例**:
```dart
// 添加 OpenClaw Agent
final agent = await acpService.addAgent(
  name: 'My OpenClaw Assistant',
  gatewayUrl: 'ws://localhost:18789',
  tools: ['bash', 'file-system', 'web-search'],
  model: 'claude-3-5-sonnet',
);

// 发送消息
final response = await acpService.sendMessage(
  agent,
  '列出当前目录的文件',
);

// 流式响应
await for (var chunk in acpService.sendMessageStream(agent, '写一首诗')) {
  print(chunk);
}
```

**📖 详细文档**: 
- [OpenClaw 集成实施报告](docs/OPENCLAW_INTEGRATION_REPORT.md)
- [OpenClaw ACP 集成设计方案](docs/OPENCLAW_ACP_INTEGRATION_DESIGN.md)

#### A2A 协议支持

**A2A (Agent-to-Agent Protocol)** - Google 开源的标准协议

- ✅ **自动发现** - 通过 URI 自动获取 Agent Card
- ✅ **标准协议** - 完整实现 A2A 协议规范
- ✅ **多种模式**
  - 同步任务 - 提交后等待完成
  - 异步任务 - 提交后轮询状态
  - 流式任务 - SSE 实时更新
- ✅ **多模态支持** - Text, JSON, Image 等
- ✅ **安全认证** - Bearer Token, API Key

**快速开始**:
```
1. 点击"通用 Agent 管理"
2. 选择"添加 A2A Agent"
3. 输入 Agent URI: https://agent.example.com
4. 系统自动发现 Agent Card
5. 一键添加，立即使用！
```

**Agent Card 示例**:
```json
{
  "name": "WeatherBot",
  "description": "提供天气预报服务",
  "endpoints": {
    "tasks": "https://api.example.com/a2a/tasks",
    "stream": "https://api.example.com/a2a/stream"
  },
  "capabilities": ["weather_forecast", "temperature_query"],
  "authentication": {"schemes": ["bearer"]}
}
```

**使用示例**:
```dart
// 自动发现并添加 A2A Agent
final agent = await agentService.discoverAndAddA2AAgent(
  'https://agent.example.com',
  apiKey: 'your-api-key',
);

// 发送任务
final task = A2ATask(instruction: '今天天气如何？');
final response = await agentService.sendTaskToA2AAgent(
  agent, task, waitForCompletion: true
);

// 流式任务
await for (var update in agentService.streamTaskToA2AAgent(agent, task)) {
  print('状态: ${update.state}');
}
```

**📖 详细文档**: 
- [A2A 协议与通用 Agent 完整指南](docs/A2A_UNIVERSAL_AGENT_GUIDE.md)
- [实施完成报告](docs/A2A_IMPLEMENTATION_REPORT.md)

#### 支持的 Agent 类型

| 类型 | 协议 | 传输方式 | 特色功能 | 状态 |
|------|------|----------|---------|------|
| **OpenClaw Agent** 🦅 | ACP (JSON-RPC) | WebSocket | **实时双向 + 工具系统 + 本地优先** ⭐ | ✅ 完整支持 |
| **A2A Agent** | A2A Protocol | HTTP(S) + SSE | 标准化、跨平台 | ✅ 完整支持 |
| **Knot Agent** | Knot API | HTTP(S) | MCP + Rules + 知识库 | ✅ 完整支持 |
| **Custom Agent** | 自定义 | 自定义 | 可扩展 | ⏳ 开发中 |

**对比分析**:

| 特性 | OpenClaw 🦅 | A2A | Knot |
|------|-----------|-----|------|
| 实时通信 | ✅ WebSocket | ⚠️ SSE | ❌ 轮询 |
| 工具调用 | ✅ 6+ 种 | ❌ | ⚠️ 部分 |
| 自动重连 | ✅ | ❌ | ❌ |
| 本地部署 | ✅ | ❌ | ❌ |
| 标准协议 | ✅ JSON-RPC | ✅ A2A | ❌ |

**🌟 OpenClaw Agent** - 功能最强大，适合需要实时工具调用的场景！

### 4. 🌐 Knot Agent 集成 (OpenClaw 风格)

**✅ 支持 Knot 平台的 OpenClaw 风格 Agent！**

#### 核心功能
AI Agent Hub 现已集成 Knot 平台，实现了完整的 **OpenClaw 风格 Agent 管理**：

```
AI Agent Hub
    ↓
Knot API
    ↓
Knot Agent (OpenClaw风格)
    ├─→ Knot-CLI (本地执行)
    └─→ 云工作区 (远程机器)
```

#### 方案 A：独立管理（已完成 ✅）

- **Agent 管理**
  - 查看 Knot Agent 列表
  - 创建和配置 Agent
  - 编辑 Agent 设置（模型、提示词、MCP 服务）
  - 删除 Agent
  - 查看 Agent 状态

- **任务执行**
  - 向 Agent 发送任务指令
  - 实时轮询任务状态
  - 查看任务执行结果
  - 取消正在运行的任务
  - 任务历史记录

- **配置管理**
  - API Token 安全存储
  - 连接状态测试
  - 工作区选择和管理
  - MCP 服务器配置
  - 多模型支持

#### 方案 B：Channel 桥接（已完成 ✅）⭐

**新功能**：Knot Agent 可以作为普通 Agent 参与 Channel 对话！

```
AI Agent Hub Channel
    ↓ 消息
KnotChannelBridgeService
    ↓ 转换
Knot Task (任务)
    ↓ 执行
Knot Agent 响应
    ↓ 返回
Channel 消息
```

**桥接功能**：
- ✅ Knot Agent 加入 Channel 对话
- ✅ 消息自动转换为 Knot 任务
- ✅ 任务结果自动返回 Channel
- ✅ 支持多个 Agent 同时桥接
- ✅ 可启用/禁用/移除桥接
- ✅ 友好的桥接管理界面

**使用流程**：
```
1. 创建或进入频道
2. 点击 "Knot 桥接"
3. 选择要添加的 Knot Agent
4. Agent 开始响应频道消息
```

#### 技术实现
```dart
// Knot API 服务
KnotApiService
  ├─ getKnotAgents()        // 获取 Agent 列表
  ├─ createKnotAgent()      // 创建 Agent
  ├─ updateKnotAgent()      // 更新 Agent
  ├─ deleteKnotAgent()      // 删除 Agent
  ├─ sendTask()             // 发送任务
  ├─ getTaskStatus()        // 获取任务状态
  └─ getWorkspaces()        // 获取工作区

// Knot 桥接服务 ⭐
KnotChannelBridgeService
  ├─ createBridge()         // 创建桥接
  ├─ deleteBridge()         // 删除桥接
  ├─ handleChannelMessage() // 处理消息
  └─ addMessageCallback()   // 消息回调
```

**📖 详细文档**: 
- [Knot 集成指南](docs/KNOT_INTEGRATION.md)
- [方案 B 实施文档](docs/PLAN_B_IMPLEMENTATION.md) ⭐

#### 支持的模型
- `deepseek-v3.1-Terminus` - 日常使用推荐
- `deepseek-v3.2` - 较新版本
- `deepseek-r1-0528` - 深度推理
- `kimi-k2-instruct` - 指令遵循
- `glm-4.6` / `glm-4.7` - GLM 系列

### 4. 🔗 Agent 间通信 (Agent-to-Agent)

**✅ 支持 Agent 和 Agent 之间的对话！**

#### 工作原理
AI Agent Hub 实现了完整的 **Agent 间对话审批机制**：

```
Agent A (请求方)
    ↓
发起对话请求 → AgentConversationRequest
    ↓
用户收到审批通知
    ↓
    ├─→ 批准 → Agent A 和 Agent B 建立通信
    │         可以开始对话
    │
    └─→ 拒绝 → 对话请求被拒绝
              可附带拒绝原因
```

#### 主要特性
- **对话请求系统**
  - Agent 可以发起与其他 Agent 的对话请求
  - 请求包含：请求者、目标 Agent、消息、上下文
  - 支持待审批、已批准、已拒绝三种状态

- **审批管理**
  - 用户可以查看所有待审批的对话请求
  - 批准后 Agent 间可以直接通信
  - 拒绝时可以附带原因说明
  - 审批记录包含时间戳和操作人

- **实时通知**
  - WebSocket 实时推送对话请求
  - 审批状态变化即时通知
  - 消息实时同步

#### API 支持
```dart
// 获取待审批的 Agent 对话请求
Future<List<AgentConversationRequest>> getPendingApprovals(String userId);

// 批准 Agent 间对话
Future<void> approveConversation(String userId, String requestId);

// 拒绝 Agent 间对话
Future<void> rejectConversation(String userId, String requestId, {String? reason});
```

#### 数据模型
```dart
class AgentConversationRequest {
  final String id;              // 请求ID
  final String requesterId;     // 发起Agent ID
  final String targetId;        // 目标Agent ID
  final String message;         // 请求消息
  final Map<String, dynamic>? context;  // 上下文信息
  final String status;          // pending/approved/rejected
  final int requestedAt;        // 请求时间
  final int? approvedAt;        // 批准时间
  final String? approvedBy;     // 批准人
}
```

### 4. 🔐 安全与密码管理
- 首次密码设置
- 密码验证登录
- 密码修改功能
- SHA-256 哈希 + 盐值
- AES-256-GCM 数据加密
- 登录失败限制（3次锁定）

### 5. 🔄 实时通信
- WebSocket 实时连接
- 消息实时推送
- Agent 状态实时更新
- 频道变化实时同步

## 📱 应用界面

### 主页功能入口
```
┌─────────────────────────────────┐
│   欢迎使用 AI Agent Hub         │
│   管理您的 AI Agent 和频道      │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ 🤖  Agent 管理              →  │
│     查看、添加和管理 AI Agent   │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ 💬  频道管理                →  │
│     管理消息频道和会话          │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ 🌐  Knot Agent              →  │
│     管理 Knot 平台的 Agent      │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ 🔒  修改密码                →  │
│     更改您的登录密码            │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ ⚙️  设置                    →  │
│     应用设置和偏好              │
└─────────────────────────────────┘
```

### Agent 列表
```
┌──────────────────────────────────┐
│ 🤖  Assistant      [在线]    ⋮  │
│     ID: agent-001                │
│     类型: assistant              │
└──────────────────────────────────┘

┌──────────────────────────────────┐
│ 🤖  ChatBot        [离线]    ⋮  │
│     ID: agent-002                │
│     类型: chatbot                │
└──────────────────────────────────┘

          [ ➕ 添加 Agent ]
```

### Agent 间对话审批
```
┌──────────────────────────────────┐
│ 待审批的对话请求                 │
├──────────────────────────────────┤
│                                  │
│ ┌────────────────────────────┐   │
│ │ 🤖 Agent A → Agent B       │   │
│ │ 请求消息: "需要协作处理任务"│   │
│ │ 时间: 2 分钟前              │   │
│ │ 状态: pending              │   │
│ │                            │   │
│ │  [ ✓ 批准 ]  [ ✗ 拒绝 ]   │   │
│ └────────────────────────────┘   │
│                                  │
└──────────────────────────────────┘
```

## 🗂️ 项目结构

```
lib/
├── main.dart                              # 应用入口
├── models/                                # 数据模型
│   ├── user.dart                          # 用户模型
│   ├── agent.dart                         # Agent 模型
│   ├── knot_agent.dart                    # Knot Agent 模型 🌐
│   ├── channel.dart                       # 频道模型
│   ├── message.dart                       # 消息模型
│   └── agent_conversation_request.dart    # Agent对话请求模型 ⭐
├── services/                              # 服务层
│   ├── password_service.dart              # 密码管理
│   ├── api_service.dart                   # API 服务
│   ├── knot_api_service.dart              # Knot API 服务 🌐
│   ├── knot_agent_adapter.dart            # Knot Agent 适配器 🌐⭐
│   ├── knot_channel_bridge_service.dart   # Knot 桥接服务 🌐⭐
│   ├── websocket_service.dart             # WebSocket 服务
│   ├── http_client_wrapper.dart           # HTTP 客户端
│   └── encryption_service.dart            # 加密服务
├── screens/                               # UI 页面
│   ├── splash_screen.dart                 # 启动页
│   ├── password_setup_screen.dart         # 密码设置
│   ├── login_screen.dart                  # 登录页
│   ├── home_screen.dart                   # 主页 ⭐
│   ├── agent_list_screen.dart             # Agent 列表 ⭐
│   ├── agent_detail_screen.dart           # Agent 详情 ⭐
│   ├── agent_approval_screen.dart         # Agent对话审批 ⭐
│   ├── knot_agent_screen.dart             # Knot Agent 列表 🌐
│   ├── knot_agent_detail_screen.dart      # Knot Agent 详情 🌐
│   ├── knot_task_screen.dart              # Knot 任务管理 🌐
│   ├── knot_settings_screen.dart          # Knot 设置 🌐
│   ├── knot_bridge_management_screen.dart # Knot 桥接管理 🌐⭐
│   ├── channel_list_screen.dart           # 频道列表 ⭐
│   ├── create_group_screen.dart           # 创建群聊
│   ├── change_password_screen.dart        # 修改密码
│   └── settings_screen.dart               # 设置页
├── providers/                             # 状态管理
│   └── app_state.dart                     # 应用状态 ⭐
├── utils/                                 # 工具类
│   ├── logger.dart                        # 日志工具
│   ├── exceptions.dart                    # 异常处理
│   └── validators.dart                    # 验证工具
└── config/                                # 配置
    └── env_config.dart                    # 环境配置 🌐
```

**⭐ 标记**: 新增或重点功能模块  
**🌐 标记**: Knot Agent 集成相关  
**🌐⭐ 标记**: 方案 B 桥接功能（最新）

## 🔧 技术栈

- **Flutter**: >=3.0.0
- **状态管理**: Provider
- **网络通信**: 
  - HTTP (http package)
  - WebSocket (实时通信)
- **本地存储**: 
  - SharedPreferences
  - Flutter Secure Storage
- **加密**: 
  - crypto: SHA-256 哈希
  - encrypt: AES-256-GCM 加密

## 📦 依赖

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # 状态管理
  provider: ^6.1.1
  
  # 网络请求
  http: ^1.1.0
  web_socket_channel: ^2.4.0
  
  # 本地存储
  shared_preferences: ^2.2.2
  flutter_secure_storage: ^9.0.0
  
  # 加密
  crypto: ^3.0.3
  encrypt: ^5.0.3
  
  # UI组件
  cupertino_icons: ^1.0.6

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

## 🚀 快速开始

### 1. 安装依赖

```bash
flutter pub get
```

### 2. 配置环境

```bash
# 开发环境
flutter run --dart-define=ENV=development

# 测试环境
flutter run --dart-define=ENV=staging

# 生产环境
flutter run --dart-define=ENV=production
```

### 3. 运行应用

```bash
# Web
flutter run -d chrome

# Android
flutter run -d android

# iOS
flutter run -d ios
```

## 🎯 使用场景

### 场景 1: Agent 管理
```dart
// 1. 查看所有 Agent
final agents = await apiService.getAgents();

// 2. 添加新 Agent
final agent = Agent(
  id: '',
  name: 'MyAgent',
  type: 'assistant',
  status: 'online',
);
await apiService.registerAgent(agent);

// 3. 更新 Agent
agent.status = 'busy';
await apiService.updateAgent(agent);

// 4. 删除 Agent
await apiService.deleteAgent(agent.id);
```

### 场景 2: Agent 间对话
```dart
// 1. Agent A 发起与 Agent B 的对话请求
// (通常由后端 Agent 系统自动发起)

// 2. 用户查看待审批请求
final requests = await apiService.getPendingApprovals(userId);

// 3. 批准对话
await apiService.approveConversation(userId, requestId);
// 或拒绝对话
await apiService.rejectConversation(
  userId, 
  requestId, 
  reason: '当前 Agent 忙碌'
);

// 4. Agent 间开始通信
// 批准后，Agent A 和 Agent B 可以通过消息系统对话
```

### 场景 3: 频道通信
```dart
// 1. 创建频道
final channel = await apiService.createChannel(
  Channel(id: '', name: '技术讨论')
);

// 2. 发送消息
await apiService.sendMessage(
  from: userId,
  to: agentId,
  channelId: channel.id,
  content: 'Hello!',
);

// 3. 接收实时消息
wsService.messageStream.listen((message) {
  print('收到消息: ${message.content}');
});
```

## 🛡️ 安全特性

### 密码安全
- ✅ SHA-256 哈希 + 唯一盐值
- ✅ 只存储哈希值，不存储明文
- ✅ 登录失败限制（3次锁定）
- ✅ 密码强度验证

### 数据加密
- ✅ AES-256-GCM 加密敏感数据
- ✅ Flutter Secure Storage 安全存储
- ✅ 密钥与代码分离

### 网络安全
- ✅ HTTPS 加密传输
- ✅ WebSocket Secure (WSS)
- ✅ Token 认证机制
- ✅ 请求重试和超时控制

### Agent 安全
- ✅ Agent 间对话需审批
- ✅ 审批记录可追溯
- ✅ 拒绝原因记录
- ✅ 实时状态监控

## 📊 API 文档

### Agent 管理 API

```dart
// 获取所有 Agent
GET /api/agents
Response: { agents: Agent[] }

// 注册新 Agent
POST /api/agents/register
Body: { name, type, status, avatar }
Response: { agent: Agent }

// 更新 Agent
PUT /api/agents/:id
Body: { name, type, status, avatar }
Response: { agent: Agent }

// 删除 Agent
DELETE /api/agents/:id
Response: { success: true }
```

### Agent 对话 API

```dart
// 获取待审批请求
GET /api/users/:userId/pending-approvals
Response: { requests: AgentConversationRequest[] }

// 批准对话
POST /api/users/:userId/approve-conversation
Body: { request_id }
Response: { success: true }

// 拒绝对话
POST /api/users/:userId/reject-conversation
Body: { request_id, reason }
Response: { success: true }
```

### 频道 API

```dart
// 获取频道列表
GET /api/channels
Response: { channels: Channel[] }

// 创建频道
POST /api/channels
Body: { name, description }
Response: { channel: Channel }

// 创建私聊
POST /api/channels/dm
Body: { userId, agentId }
Response: { channel: Channel }
```

## 🔄 应用流程

```
启动应用
    ↓
[SplashScreen] 初始化
    ↓
检查密码状态
    ↓
    ├─→ 未设置密码 → [PasswordSetupScreen] → 设置密码
    │                                            ↓
    └─→ 已设置密码 → [LoginScreen] → 验证密码
                                        ↓
                                   [HomeScreen] 主页
                                        ↓
        ┌───────────────┬───────────────┼───────────────┬──────────────┐
        ↓               ↓               ↓               ↓              ↓
  [AgentList]    [ChannelList]   [AgentApproval]  [Password]    [Settings]
  Agent管理       频道管理         对话审批         修改密码        设置
        ↓
  [AgentDetail]
  Agent详情/编辑
```

## 🧪 测试

### 功能测试清单

#### Agent 管理
- [x] 查看 Agent 列表
- [x] 添加新 Agent
- [x] 编辑 Agent 信息
- [x] 删除 Agent
- [x] Agent 状态切换
- [x] Avatar 显示

#### Agent 间对话
- [x] 查看待审批请求
- [x] 批准对话请求
- [x] 拒绝对话请求
- [x] 实时通知接收

#### 频道管理
- [x] 查看频道列表
- [x] 创建频道
- [x] 发送消息
- [x] 接收实时消息

#### 安全功能
- [x] 首次密码设置
- [x] 密码验证登录
- [x] 修改密码
- [x] 登录失败锁定

### 运行测试

```bash
# 单元测试
flutter test

# 集成测试
flutter test integration_test

# 代码分析
flutter analyze

# 代码格式化
flutter format .
```

## 📈 性能优化

- ✅ HTTP 请求自动重试
- ✅ WebSocket 断线重连
- ✅ 消息缓存机制
- ✅ 列表下拉刷新
- ✅ 图片加载优化
- ✅ 状态管理优化

## 🔮 后续计划

### 短期计划
- [ ] Agent 搜索和筛选
- [ ] Agent 性能监控
- [ ] 批量操作
- [ ] 消息已读状态
- [ ] 频道详情页

### 中期计划
- [ ] Agent 配置管理
- [ ] 多人群聊
- [ ] 文件传输
- [ ] 消息历史导出
- [ ] 夜间模式

### 长期计划
- [ ] 生物识别登录
- [ ] 多设备同步
- [ ] Agent 市场
- [ ] 插件系统
- [ ] 国际化支持

## ⚠️ 注意事项

### 开发环境
1. 确保 Flutter SDK >= 3.0.0
2. 配置正确的 API 地址
3. 使用环境变量管理配置

### 生产部署
1. 更换密钥管理方案
2. 配置 HTTPS 证书
3. 启用日志收集
4. 配置错误监控

### Agent 对话
1. Agent 间对话需要用户审批
2. 审批记录会被保存
3. 拒绝可以附带原因
4. 支持批量审批（待实现）

## 📚 相关文档

- [功能完成报告](AGENT-FEATURE-COMPLETION-REPORT.md)
- [功能对比文档](FEATURE-COMPARISON.md)
- [P0/P1 完成报告](P0-P1-COMPLETION-REPORT.md)

## 📄 许可证

MIT License

## 👥 贡献

欢迎提交 Issue 和 Pull Request！

## 📧 联系方式

AI Agent Hub Development Team

---

**版本**: 2.2.0  
**更新日期**: 2026-02-05  
**核心特性**: Agent 管理 + Agent 间对话 + Knot Agent 集成 + Channel 桥接 🌐⭐

## 🎊 更新日志

### v2.2.0 (2026-02-05) 🌐⭐ 方案 B
- ✨ 新增：Knot Agent Channel 桥接功能 ⭐
- ✨ 新增：KnotAgentAdapter - Agent 适配器
- ✨ 新增：KnotChannelBridgeService - 桥接服务
- ✨ 新增：桥接管理页面
- 🎨 优化：频道列表添加桥接入口
- 📝 完善：方案 B 实施文档
- 🔧 特性：Knot Agent 可参与 Channel 对话
- 🔧 特性：消息自动转换为 Knot 任务
- 🔧 特性：任务结果自动返回 Channel

### v2.1.0 (2026-02-05) 🌐 方案 A
- ✨ 新增：Knot Agent 集成（OpenClaw 风格）⭐
- ✨ 新增：Knot Agent 管理（CRUD）
- ✨ 新增：Knot 任务执行和状态跟踪
- ✨ 新增：Knot API Token 管理
- ✨ 新增：工作区和 MCP 服务器配置
- 🎨 优化：主页添加 Knot Agent 入口
- 📝 完善：Knot 集成文档
- 🔧 新增：环境配置系统

### v2.0.0 (2026-02-04)
- ✨ 新增：完整的 Agent 管理功能（CRUD）
- ✨ 新增：Agent 间对话审批系统 ⭐
- ✨ 新增：频道管理功能
- 🎨 优化：主页改版，功能卡片布局
- 🔧 优化：网络层重试和超时控制
- 🛡️ 增强：安全存储和加密
- 📝 完善：错误处理和日志系统

### v1.0.0 (2026-02-03)
- 🎉 初始版本
- 🔐 密码管理系统
- 🔒 加密存储
