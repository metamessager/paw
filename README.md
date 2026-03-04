# Paw

> Secure AI Agent Management Platform — Local-first, Multi-protocol, Cross-platform

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)](https://dart.dev/)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20macOS%20%7C%20Windows%20%7C%20Web-lightgrey)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

<p align="center">
  <img src="assets/images/app_icon.png" width="120" alt="Paw Logo" />
</p>

Paw 是一个跨平台的 AI Agent 管理与交互平台。它以本地优先的理念设计，所有数据存储在用户设备上，支持多种 Agent 通信协议，提供丰富的聊天交互体验。

## 功能亮点

**Agent 管理与通信**
- 支持 A2A (Agent-to-Agent, JSON-RPC 2.0) 和 ACP (Agent Communication Protocol) 两种协议
- 双向通信：用户主动对话 & Agent 主动发起对话（需授权）
- 连接状态实时监控、健康检查、Token 认证

**智能聊天**
- 富文本消息气泡（文本、图片、文件、语音、Markdown、代码高亮）
- 交互式组件：表单、单选/多选、操作确认按钮
- 消息回复、上下文菜单、全文搜索
- 实时打字状态指示

**多 Agent 协作**
- Channel / Group 会话，支持多个 Agent 协同工作
- 模型路由配置，灵活切换 LLM 后端
- 本地 LLM Agent 服务，内置工具调用（OS Tools / Skills）

**安全与隐私**
- 全部数据本地存储（SQLite + Hive），无需后端服务器
- 密码 + 生物识别锁屏保护
- Token 加密存储、权限管理、推理日志审计

**跨平台**
- iOS / Android / macOS / Windows / Web
- 桌面端多窗口支持、自适应布局
- 国际化（中文 / English）

## 快速开始

### 环境要求

- Flutter 3.x & Dart SDK 3.x
- Xcode (iOS/macOS) 或 Android Studio (Android)

### 安装与运行

```bash
# 克隆项目
git clone https://github.com/metamessager/paw.git
cd paw

# 安装依赖
flutter pub get

# 运行（选择目标平台）
flutter run                # 默认设备
flutter run -d macos       # macOS
flutter run -d chrome      # Web
```

### 构建发布包

```bash
flutter build apk --release    # Android
flutter build ios --release    # iOS
flutter build macos --release  # macOS
```

## 项目结构

```
paw/
├── lib/
│   ├── main.dart                  # 应用入口
│   ├── models/                    # 数据模型
│   │   ├── agent.dart             # Agent 模型
│   │   ├── remote_agent.dart      # Remote Agent (A2A)
│   │   ├── acp_protocol.dart      # ACP 协议模型
│   │   ├── channel.dart           # Channel 模型
│   │   ├── message.dart           # 消息模型
│   │   ├── llm_provider_config.dart   # LLM 配置
│   │   └── model_routing_config.dart  # 模型路由配置
│   ├── screens/                   # 页面
│   │   ├── home_screen.dart       # 主页（移动端）
│   │   ├── desktop_home_screen.dart   # 主页（桌面端）
│   │   ├── chat_screen.dart       # 聊天界面
│   │   ├── contacts_screen.dart   # 联系人 / Agent 列表
│   │   ├── settings_screen.dart   # 设置
│   │   └── ...                    # 更多页面
│   ├── widgets/                   # UI 组件
│   │   ├── message_bubble.dart    # 消息气泡
│   │   ├── chat/                  # 聊天组件（输入区、消息列表等）
│   │   └── ...                    # 交互式组件
│   ├── services/                  # 核心服务
│   │   ├── chat_service.dart      # 聊天服务
│   │   ├── local_database_service.dart  # 数据库服务
│   │   ├── acp_server_service.dart     # ACP 服务端
│   │   ├── acp_agent_connection.dart   # ACP 连接管理
│   │   ├── remote_agent_service.dart   # A2A Agent 服务
│   │   ├── protocol_router.dart   # 协议路由
│   │   ├── local_llm_agent_service.dart  # 本地 LLM Agent
│   │   ├── permission_service.dart     # 权限管理
│   │   └── ...                    # 更多服务
│   ├── providers/                 # 状态管理 (Provider)
│   │   ├── app_state.dart         # 应用全局状态
│   │   ├── locale_provider.dart   # 国际化
│   │   └── notification_provider.dart
│   ├── controllers/               # 控制器
│   ├── l10n/                      # 国际化资源
│   └── utils/                     # 工具类
├── agents/                        # Agent 示例实现
│   ├── mac_agent/                 # macOS Agent (Python)
│   └── claude_code/               # Claude Code Agent
├── test/                          # 测试
├── scripts/                       # 脚本工具
│   └── mock_agents/               # Mock Agent 测试服务
├── docs/                          # 文档
├── android/                       # Android 平台
├── ios/                           # iOS 平台
├── macos/                         # macOS 平台
├── windows/                       # Windows 平台
└── web/                           # Web 平台
```

## 支持的 Agent 协议

### A2A (Agent-to-Agent Protocol)

- 基于 JSON-RPC 2.0 的标准化协议
- 支持流式响应（SSE）
- 通过 HTTP/HTTPS 接入远程 Agent

### ACP (Agent Communication Protocol)

- 基于 WebSocket 的实时双向通信
- 内置 ACP Server（默认端口 18790）
- 支持工具调用、权限协商

## 开发

```bash
# 代码分析
flutter analyze

# 格式化
dart format lib/

# 运行测试
flutter test

# 运行特定测试
flutter test test/models/
flutter test test/integration/core_integration_test.dart
```

### Mock Agent 测试

项目提供了 Mock Agent 用于本地开发和测试：

```bash
# 启动 Mock Agent
cd scripts/mock_agents
./start_mock_agents.sh

# 停止
./stop_mock_agents.sh
```

### Agent 示例

`agents/` 目录包含 Agent 的参考实现：

```bash
# 运行 macOS Agent (Python)
python agents/mac_agent/mac_agent.py --provider <llm_provider> --model <model_name> --api-key <key> --token <auth_token>
```

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.x / Dart 3.x |
| 状态管理 | Provider |
| 数据库 | SQLite (sqflite) |
| 本地存储 | Hive, SharedPreferences, Flutter Secure Storage |
| 网络 | Dio, http, WebSocket |
| 安全 | crypto, encrypt, local_auth |
| UI | Material Design 3, Markdown 渲染, 代码高亮 |
| 多媒体 | 图片选择、语音录制与播放、文件传输 |
| 桌面 | desktop_multi_window 多窗口支持 |

## 文档

- [快速开始指南](docs/QUICK_START.md)
- [Agent 接入指南](docs/agent_integration_guide.md)

## 许可证

[MIT License](LICENSE)
