# Knot Agent 集成文档

## 概述

AI Agent Hub 现已支持 Knot 平台的 OpenClaw 风格 Agent 集成！您可以在 AI Agent Hub 中统一管理和使用 Knot Agent。

## 功能特性

### ✅ 已实现功能

1. **Knot Agent 管理**
   - 查看 Knot Agent 列表
   - 创建新的 Knot Agent
   - 编辑现有 Agent 配置
   - 删除 Agent
   - 查看 Agent 状态（在线/离线）

2. **任务管理**
   - 向 Knot Agent 发送任务指令
   - 实时查看任务执行状态
   - 自动轮询任务进度
   - 查看任务执行结果
   - 取消正在运行的任务

3. **配置管理**
   - API Token 安全存储
   - 连接状态测试
   - 工作区选择
   - MCP 服务器配置
   - 模型选择

4. **安全性**
   - API Token 加密存储（使用 Flutter Secure Storage）
   - Token 可见性切换
   - 连接状态验证

## 快速开始

### 1. 配置 Knot API Token

1. 打开 AI Agent Hub
2. 进入主页，点击 **Knot Agent** 卡片
3. 点击右上角的 **设置** 图标
4. 输入您的 Knot API Token
5. 点击 **保存**
6. 点击 **测试连接** 验证配置

### 2. 添加 Knot Agent

1. 在 Knot Agent 页面，点击右下角 ➕ 按钮
2. 填写 Agent 信息：
   - **名称**：Agent 的显示名称
   - **Avatar**：选择一个 Emoji 作为头像
   - **简介**：简短描述（可选）
   - **模型**：选择要使用的 AI 模型
   - **系统提示词**：自定义提示词（可选）
   - **工作区**：选择云工作区（可选）
   - **MCP 服务**：添加需要的 MCP 服务
3. 点击右上角 ✓ 保存

### 3. 发送任务

1. 在 Agent 列表中，点击 Agent 卡片上的 **发送任务** 按钮
2. 在任务输入区域：
   - 输入任务指令（例如："帮我分析这个项目的代码结构"）
   - 可选：指定工作区路径
3. 点击 **发送任务**
4. 系统会自动轮询任务状态，完成后显示结果

### 4. 查看任务历史

- 在任务页面会自动显示该 Agent 的所有任务
- 点击任务卡片可以查看详细信息
- 任务状态：
  - 🕐 **PENDING**：等待执行
  - 🔵 **RUNNING**：正在执行
  - ✅ **COMPLETED**：执行成功
  - ❌ **FAILED**：执行失败

## 支持的模型

- `deepseek-v3.1-Terminus` - 推荐日常使用
- `deepseek-v3.2` - 较新版本
- `deepseek-r1-0528` - 深度推理模型
- `kimi-k2-instruct` - 指令遵循效果好
- `glm-4.6` - GLM 系列模型
- `glm-4.7` - GLM 最新版本

## 技术架构

### 核心组件

```
AI Agent Hub (Flutter)
  ├── KnotAgentScreen          # Agent 列表页面
  ├── KnotAgentDetailScreen    # Agent 详情/编辑页面
  ├── KnotTaskScreen           # 任务管理页面
  └── KnotSettingsScreen       # 配置页面

Services
  └── KnotApiService           # Knot API 服务

Models
  ├── KnotAgent                # Agent 数据模型
  ├── KnotTask                 # 任务数据模型
  ├── KnotWorkspace            # 工作区数据模型
  └── KnotAgentConfig          # Agent 配置模型
```

### API 集成

AI Agent Hub 通过 Knot 平台的 REST API 进行集成：

```
GET    /api/v1/agents              # 获取 Agent 列表
GET    /api/v1/agents/:id          # 获取 Agent 详情
POST   /api/v1/agents              # 创建 Agent
PATCH  /api/v1/agents/:id          # 更新 Agent
DELETE /api/v1/agents/:id          # 删除 Agent

POST   /api/v1/agents/:id/tasks    # 发送任务
GET    /api/v1/agents/:id/tasks    # 获取任务列表
GET    /api/v1/tasks/:id           # 获取任务状态
POST   /api/v1/tasks/:id/cancel    # 取消任务

GET    /api/v1/workspaces          # 获取工作区列表
GET    /api/v1/health              # 健康检查
```

### 数据流

```
用户输入任务
   ↓
KnotTaskScreen
   ↓
KnotApiService.sendTask()
   ↓
Knot Platform API
   ↓
创建任务并返回 Task ID
   ↓
轮询任务状态 (每 2 秒)
   ↓
任务完成/失败
   ↓
显示结果给用户
```

## 与现有 Channel 的关系

### 概念区分

| 特性 | OpenClaw "Channel" | AI Agent Hub "Channel" |
|------|-------------------|------------------------|
| **用途** | 用户与 AI 的通讯通道 | Agent 间的消息频道 |
| **示例** | 企微、Telegram | Agent 私聊、群聊 |
| **方向** | 单向任务下发 | 双向消息交换 |
| **审批** | 无 | 需要用户审批 |

### 是否冲突？

**不冲突！** 两者是不同的概念：

- **OpenClaw Channel**：外部通讯平台（企微机器人等）
- **AI Agent Hub Channel**：内部 Agent 协作频道

### 桥接方案

如果需要让 Knot Agent 参与 AI Agent Hub 的 Channel 通信，可以：

1. 创建虚拟 Channel 适配器
2. 将 Channel 消息转换为 Knot 任务
3. 将 Knot 任务结果转换为 Channel 消息

这个功能目前未实现，如有需要可以后续扩展。

## 环境配置

### 开发环境

```bash
flutter run --dart-define=ENVIRONMENT=development \
           --dart-define=KNOT_API_URL=https://knot-dev.woa.com
```

### 预发布环境

```bash
flutter run --dart-define=ENVIRONMENT=staging \
           --dart-define=KNOT_API_URL=https://knot-staging.woa.com
```

### 生产环境

```bash
flutter run --dart-define=ENVIRONMENT=production \
           --dart-define=KNOT_API_URL=https://knot.woa.com
```

## 安全性说明

1. **API Token 存储**
   - 使用 Flutter Secure Storage 加密存储
   - 不会明文保存在设备上
   - 退出登录时自动清除

2. **网络通信**
   - 所有 API 请求使用 HTTPS
   - Token 通过 Header 传输
   - 支持请求超时和重试

3. **数据隔离**
   - 每个用户的 Token 独立存储
   - Agent 数据与账户绑定
   - 不会泄露给其他用户

## 常见问题

### Q: 如何获取 Knot API Token？

A: 
1. 访问 Knot 平台 (https://knot.woa.com)
2. 进入个人设置页面
3. 找到 API Token 管理
4. 创建或复制现有 Token

### Q: 连接测试失败怎么办？

A:
1. 检查网络连接是否正常
2. 确认 Token 是否正确
3. 验证 Token 是否过期
4. 检查是否有访问权限

### Q: 任务一直处于 RUNNING 状态？

A:
- 某些复杂任务可能需要较长时间
- 系统每 2 秒轮询一次状态
- 如果超时，可以取消任务重试

### Q: 可以同时管理多个 Knot Agent 吗？

A: 可以！您可以创建多个 Agent，每个 Agent 可以配置不同的：
- 模型
- 系统提示词
- 工作区
- MCP 服务

### Q: OpenClaw 需要修改吗？

A: **完全不需要！** AI Agent Hub 直接调用 Knot 平台的 API，OpenClaw/Knot 保持原样无需任何修改。

## 改造总结

### AI Agent Hub 改造

✅ **已完成**（约 2000 行代码）：

1. 新增 4 个页面
   - KnotAgentScreen (380+ 行)
   - KnotAgentDetailScreen (350+ 行)
   - KnotTaskScreen (470+ 行)
   - KnotSettingsScreen (320+ 行)

2. 新增 3 个数据模型
   - KnotAgent
   - KnotTask
   - KnotWorkspace

3. 新增 1 个 API 服务
   - KnotApiService (400+ 行)

4. 新增 1 个配置文件
   - EnvConfig

5. 主页集成
   - 添加 Knot Agent 入口

### OpenClaw/Knot 改造

✅ **无需改造**：
- 直接使用现有 Knot API
- 无需修改任何代码
- 零侵入式集成

## 后续规划

### Phase 2 功能（可选）

1. **深度集成**
   - Knot Agent 作为普通 Agent 参与 Channel 对话
   - 支持 Agent 间协作
   - 统一消息历史

2. **高级功能**
   - 任务模板管理
   - 批量任务执行
   - 任务计划和定时
   - 执行日志和审计

3. **UI 增强**
   - Agent 性能统计
   - 任务成功率图表
   - 实时执行日志流
   - 工作区文件浏览

## 测试建议

### 功能测试

1. **Token 管理**
   - ✓ 保存 Token
   - ✓ 删除 Token
   - ✓ 测试连接
   - ✓ Token 可见性切换

2. **Agent 管理**
   - ✓ 创建 Agent
   - ✓ 编辑 Agent
   - ✓ 删除 Agent
   - ✓ 查看 Agent 列表

3. **任务执行**
   - ✓ 发送简单任务
   - ✓ 发送复杂任务
   - ✓ 查看任务状态
   - ✓ 取消任务

### 安全测试

- ✓ Token 加密存储验证
- ✓ HTTPS 通信验证
- ✓ 异常情况处理

## 联系方式

如有问题或建议，请联系开发团队。

---

**版本**: 1.0.0  
**更新日期**: 2026-02-05  
**状态**: ✅ 已完成
