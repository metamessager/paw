# AI Agent Hub

> 统一的 AI Agent 管理平台 - 完全本地化、支持多协议、双向通信

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)](https://flutter.dev/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey.svg)]()

## 简介

AI Agent Hub 是一个功能完整的 AI 代理管理平台，支持多种 Agent 协议和双向通信。所有数据完全本地化存储，保护用户隐私。

### 核心特性

- **完全本地化**: 所有数据存储在本地，无需后端服务器
- **多协议支持**: 支持 Remote Agent (A2A 协议) 和 OpenClaw 两种 Agent 类型
- **双向通信**: 支持 Agent 主动发起对话（需用户授权）
- **实时聊天**: 支持与 Agent 实时对话，显示消息历史和打字状态
- **Channel 管理**: 创建频道与 Agent 对话，支持多 Agent 协作
- **数据备份**: 支持完整数据导出导入，保护用户数据
- **高性能**: 数据库索引优化，查询速度快
- **安全可靠**: 密码加密存储，权限管理完善
- **多平台支持**: 支持 iOS、Android 和 macOS

## 快速开始

### 环境要求

- Flutter 3.x
- Dart SDK 3.x
- Android Studio / Xcode (可选)

### 安装步骤

```bash
# 1. 克隆项目
git clone https://git.woa.com/edenzou/ai-agent-hub.git
cd ai-agent-hub

# 2. 安装依赖
flutter pub get

# 3. 运行应用
flutter run
```

### 首次使用

1. 启动应用后完成初始设置
2. 点击右上角「+」添加 Agent
3. 在 Agent 列表中选择一个 Agent
4. 进入 Agent 详情页面，点击「开始对话」
5. 在聊天界面中输入消息并发送
6. 查看实时回复和消息历史

### 聊天功能使用 ⭐

1. **发送消息**: 在输入框中输入消息，点击发送按钮
2. **查看历史**: 消息会自动保存，下次打开时自动加载
3. **实时状态**: Agent 回复时会显示打字状态
4. **附件功能**: 点击附件按钮可上传文件（即将推出）
5. **删除聊天**: 在 Agent 详情页面可删除聊天历史

## 项目结构

```
ai-agent-hub/
├── lib/
│   ├── main.dart                    # 应用入口
│   ├── models/                      # 数据模型
│   │   ├── agent.dart              # Agent 模型
│   │   ├── channel.dart            # Channel 模型
│   │   ├── message.dart            # 消息模型
│   │   ├── remote_agent.dart       # Remote Agent (A2A)
│   │   └── a2a/                    # A2A 协议模型
│   │       ├── task.dart           # 任务模型
│   │       ├── response.dart       # 响应模型
│   │       ├── part.dart           # 部件模型
│   │       └── artifact.dart       # 工件模型
│   ├── screens/                     # UI 界面
│   │   ├── home_screen.dart        # 主页
│   │   ├── chat_screen.dart        # 聊天界面
│   │   ├── agent_list_screen.dart  # Agent 列表
│   │   ├── channel_list_screen.dart
│   │   └── agent_detail_screen.dart
│   ├── widgets/                     # UI 组件
│   │   └── message_bubble.dart     # 消息气泡
│   ├── providers/                   # 状态管理
│   │   └── app_state.dart          # 应用状态
│   └── services/                    # 核心服务
│       ├── chat_service.dart       # 聊天服务 ⭐
│       ├── a2a_protocol_service.dart  # A2A 协议服务
│       ├── local_api_service.dart  # 本地 API
│       ├── local_database_service.dart  # 数据库服务
│       ├── local_file_storage_service.dart  # 文件存储
│       ├── remote_agent_service.dart  # Remote Agent 服务
│       ├── connection_manager.dart  # 连接管理
│       ├── protocol_router.dart    # 协议路由
│       └── token_service.dart      # Token 管理
├── docs/                            # 文档目录
├── test/                            # 测试文件
├── scripts/mock_agents/            # 测试工具
└── macos/                          # macOS 平台配置 ⭐

```

## 支持的 Agent 类型

### 1. Remote Agent (A2A 协议)

- **协议**: Agent-to-Agent Protocol (JSON-RPC 2.0)
- **特性**: 标准化协议、支持流式响应、跨平台兼容
- **用途**: 通用 AI Agent 接入
- **示例**: 自定义 AI Agent、第三方 AI 服务

### 2. OpenClaw Agent

- **来源**: 开源 OpenClaw 项目
- **协议**: ACP (Agent Communication Protocol)
- **特性**: WebSocket 实时通信、工具调用支持
- **用途**: 开源 AI Agent 生态

## 核心功能

### 本地化存储

- SQLite 数据库存储结构化数据
- Hive 存储配置和缓存
- 文件系统存储用户文件和附件
- 完全离线可用，无需网络连接

### 实时聊天 ⭐

- 支持与 Agent 进行实时对话
- 消息历史自动加载和保存
- 显示 Agent 回复时的打字状态
- 支持消息气泡界面（区分发送方）
- 实时更新消息列表
- 错误提示和重试机制

### Agent 管理

- 添加、编辑、删除 Agent
- 支持 Token 认证
- 连接状态实时监控
- 支持自定义 Agent 配置
- 查看 Agent 详细信息和功能

### Channel 管理

- 创建对话频道
- 支持单 Agent 或多 Agent 协作
- 消息历史记录
- 支持文件附件

### 双向通信

- Hub → Agent: 用户主动发送消息
- Agent → Hub: Agent 主动发起对话（需授权）
- 权限管理和频率限制

### 数据安全

- 密码加密存储 (crypto)
- Token 安全管理
- 本地数据加密选项
- 数据导出导入功能

## 开发

### 代码规范

```bash
# 代码分析
flutter analyze

# 代码格式化
flutter format lib/

# 运行测试
flutter test
```

### 构建

```bash
# Debug 构建
flutter build apk --debug

# Release 构建
flutter build apk --release  # Android
flutter build ios --release  # iOS
```

### 测试

项目包含完整的测试套件：

```bash
# 运行所有测试
flutter test

# 运行特定测试
flutter test test/remote_agent_test.dart
flutter test test/integration/core_integration_test.dart
```

## 文档

### 用户文档

- [快速开始指南](docs/QUICK_START.md) - 5 分钟上手
- [完整功能文档](docs/P0_P1_P2_COMPLETION_REPORT.md) - 详细功能说明

### 技术文档

- [Remote Agent (A2A) 接入指南](docs/A2A_UNIVERSAL_AGENT_GUIDE.md)
- [OpenClaw 集成指南](docs/OPENCLAW_INTEGRATION_GUIDE.md)
- [双向通信实现](docs/BIDIRECTIONAL_COMMUNICATION.md)
- [开发指南](DEVELOPMENT.md)

### 架构文档

- [统一 A2A 架构方案](docs/UNIFIED_A2A_INTEGRATION_PLAN.md)
- [上线检查清单](docs/LAUNCH_CHECKLIST.md)

## 依赖

主要依赖库：

```yaml
dependencies:
  flutter:
    sdk: flutter
  sqflite: ^2.3.0              # SQLite 数据库
  hive: ^2.2.3                 # 轻量级存储
  path_provider: ^2.1.1        # 文件路径
  shared_preferences: ^2.2.2   # 配置存储
  web_socket_channel: ^2.4.0   # WebSocket
  http: ^1.1.2                 # HTTP 请求
  dio: ^5.4.0                  # 高级网络库
  provider: ^6.1.1             # 状态管理
  crypto: ^3.0.3               # 加密
  flutter_secure_storage: ^9.0.0  # 安全存储
```

## 版本历史

查看 [CHANGELOG.md](CHANGELOG.md) 了解详细的版本历史。

### v1.0.0 (当前)

- 完全本地化架构
- Remote Agent (A2A 协议) 支持
- OpenClaw Agent 集成
- Channel 管理和多 Agent 协作
- 双向通信支持
- 数据备份和恢复
- 完整的错误处理和日志系统

## 贡献

欢迎提交 Issue 和 Pull Request！

### 贡献流程

1. Fork 本项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'feat: Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

## 联系方式

- **作者**: Eden Zou
- **邮箱**: edenzou@tencent.com
- **项目地址**: https://git.woa.com/edenzou/ai-agent-hub

## 致谢

感谢所有为这个项目做出贡献的开发者！

---

**最后更新**: 2026-02-07
