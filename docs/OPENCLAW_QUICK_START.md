# OpenClaw Agent 快速开始指南

## 🎯 目标

在 AI Agent Hub 中接入 **OpenClaw (Moltbot)** Agent，实现用户通过本地界面操作 OpenClaw 完成各种任务。

---

## 📋 前置条件

### 1. 安装 OpenClaw

根据 [OpenClaw 官方文档](https://github.com/Moltbot/OpenClaw) 安装：

```bash
# 方式 1: npm 全局安装（推荐）
npm install -g openclaw

# 方式 2: 从源码安装
git clone https://github.com/Moltbot/OpenClaw.git
cd OpenClaw
npm install
npm run build
```

### 2. 启动 OpenClaw Gateway

```bash
# 默认端口 18789
openclaw gateway start --port 18789

# 如需认证
openclaw gateway start --port 18789 --auth-token your-secret-token
```

**验证 Gateway 已启动**:
```bash
# 应该能看到类似输出
✓ OpenClaw Gateway started on ws://localhost:18789
✓ ACP Protocol enabled
✓ Tools: bash, file-system, web-search, code-executor
```

---

## 🚀 在 AI Agent Hub 中添加 OpenClaw Agent

### 步骤 1: 打开 AI Agent Hub

```bash
cd ai-agent-hub
flutter run
```

### 步骤 2: 进入 Agent 管理

1. 点击底部导航栏的 **"Agents"**
2. 点击右下角 **"+"** 浮动按钮
3. 在弹出的菜单中选择 **"🦅 OpenClaw Agent"**

### 步骤 3: 配置 Agent

填写以下信息：

#### 基本信息
- **Agent 名称**: `My OpenClaw Assistant`（必填）
- **Agent 简介**: `一个强大的 OpenClaw Agent，支持命令执行和文件操作`（可选）
- **Avatar**: 选择一个表情（默认 🦅）

#### Gateway 配置
- **Gateway URL**: `ws://localhost:18789`（必填）
  - 本地部署: `ws://localhost:18789`
  - 远程部署: `ws://your-server-ip:18789`
  - 加密连接: `wss://your-domain.com:18789`
- **认证 Token**: 如果 Gateway 启用了认证，填写 Token（可选）

#### 模型配置
- **模型名称**: `claude-3-5-sonnet`（可选，默认使用 OpenClaw Gateway 配置）
- **系统提示词**: 自定义 Agent 行为（可选）

#### 工具选择
勾选需要的工具：
- ✅ **💻 Bash 命令** - 执行 Shell 命令
- ✅ **📁 文件系统** - 读写文件
- ✅ **🔍 Web 搜索** - 搜索互联网
- ⬜ **⚙️ 代码执行** - 运行代码
- ⬜ **📷 屏幕截图** - 截取屏幕
- ⬜ **🌐 浏览器控制** - 自动化浏览器

### 步骤 4: 测试连接

点击 **"🔗 测试连接"** 按钮，验证配置是否正确。

- ✅ **连接成功**：显示绿色提示"连接成功！Gateway 可用。"
- ❌ **连接失败**：显示红色错误信息，检查：
  - OpenClaw Gateway 是否启动
  - URL 格式是否正确（`ws://` 或 `wss://`）
  - 认证 Token 是否正确（如需要）
  - 防火墙是否阻止连接

### 步骤 5: 添加 Agent

点击 **"添加 Agent"** 按钮，完成！

---

## 💬 开始使用

### 方式 1: 在 Agent 列表中使用

1. 返回 Agent 列表页面
2. 找到刚添加的 OpenClaw Agent
3. 点击进入详情页面
4. 在聊天界面发送消息

### 方式 2: 在 Channel 中使用

1. 进入 **"Channels"** 页面
2. 创建或选择一个频道
3. 邀请 OpenClaw Agent 加入
4. 在频道中与 Agent 对话

---

## 📝 使用示例

### 示例 1: 执行 Bash 命令

**用户**: `列出当前目录的所有文件`

**OpenClaw Agent** (自动调用 bash 工具):
```
执行命令: ls -la

结果:
total 48
drwxr-xr-x  12 user  staff   384 Feb  5 10:00 .
drwxr-xr-x   8 user  staff   256 Feb  4 15:30 ..
-rw-r--r--   1 user  staff  1234 Feb  5 09:00 README.md
drwxr-xr-x   5 user  staff   160 Feb  5 10:00 src
...
```

### 示例 2: 文件系统操作

**用户**: `创建一个名为 test.txt 的文件，内容是 "Hello OpenClaw"`

**OpenClaw Agent**:
```
已创建文件 test.txt，内容如下:
Hello OpenClaw

文件路径: /current/directory/test.txt
```

### 示例 3: Web 搜索

**用户**: `搜索一下今天北京的天气`

**OpenClaw Agent** (调用 web-search 工具):
```
根据搜索结果：
今天北京天气：晴，温度 -2°C ~ 8°C，
东北风 3-4 级，空气质量良好。
```

### 示例 4: 组合任务

**用户**: `搜索 Python 最佳实践，并创建一个 best_practices.md 文件总结要点`

**OpenClaw Agent** (自动调用 web-search + file-system):
```
已完成任务！

1. 搜索了 Python 最佳实践
2. 提取了 10 个核心要点
3. 创建了 best_practices.md 文件

文件内容概览:
# Python 最佳实践

## 1. 使用虚拟环境
...

文件路径: /current/directory/best_practices.md
```

---

## 🔧 高级配置

### 自定义模型

```
模型名称: gpt-4
系统提示词: You are a helpful coding assistant specialized in Python.
```

### 多工具组合

启用多个工具以支持复杂任务：
- ✅ Bash 命令
- ✅ 文件系统
- ✅ Web 搜索
- ✅ 代码执行

Agent 会根据任务自动选择合适的工具。

### 远程 Gateway

如果 OpenClaw Gateway 部署在服务器上：

```
Gateway URL: ws://192.168.1.100:18789
或
Gateway URL: wss://openclaw.example.com:18789
```

---

## 🐛 故障排查

### 问题 1: 连接失败

**错误**: `无法连接到 Gateway`

**解决**:
1. 确认 OpenClaw Gateway 已启动：
   ```bash
   ps aux | grep openclaw
   ```
2. 检查端口是否监听：
   ```bash
   lsof -i :18789
   ```
3. 检查防火墙规则：
   ```bash
   # macOS
   sudo pfctl -s rules | grep 18789
   
   # Linux
   sudo iptables -L | grep 18789
   ```

### 问题 2: 认证失败

**错误**: `Authentication failed: Invalid token`

**解决**:
1. 确认 Token 是否正确
2. 检查 Token 是否过期
3. 重新生成 Token：
   ```bash
   openclaw token create --name "ai-agent-hub"
   ```

### 问题 3: 工具调用失败

**错误**: `Task failed: Tool execution error`

**解决**:
1. 检查工具是否启用：
   ```bash
   openclaw config show
   ```
2. 确认权限足够（bash、file-system 需要文件系统权限）
3. 查看 OpenClaw 日志：
   ```bash
   openclaw logs --tail 50
   ```

### 问题 4: 连接频繁断开

**解决**:
1. 启用自动重连（AI Agent Hub 默认开启）
2. 调整心跳间隔（默认 30 秒）
3. 检查网络稳定性
4. 检查 Gateway 配置：
   ```bash
   openclaw config set websocket.timeout 60
   ```

---

## 📊 性能优化

### 连接池管理

AI Agent Hub 自动管理 WebSocket 连接：
- 每个 Agent 维护一个连接
- 自动重连机制
- 心跳保活（30 秒）
- 超时处理（30 秒）

### 消息缓存

- 本地数据库缓存消息历史
- 断线重连后自动恢复会话
- Session ID 持久化

### 流式响应优化

- 使用 `sendMessageStream()` 获得更好的用户体验
- 逐字显示响应内容
- 实时状态更新

---

## 🎯 最佳实践

### 1. 工具选择

**推荐组合**:
- **基础**: bash + file-system
- **增强**: bash + file-system + web-search
- **完整**: 全部工具

### 2. 系统提示词

**示例**:
```
You are a helpful assistant specialized in software development.
When executing commands, always explain what you're doing.
Prioritize safety and ask for confirmation before destructive operations.
```

### 3. 安全考虑

- ⚠️ **Bash 工具**: 谨慎使用，可能执行危险命令
- ⚠️ **文件系统**: 限制访问范围
- ✅ **认证**: 生产环境务必启用 Token 认证
- ✅ **HTTPS**: 远程连接使用 `wss://` 协议

### 4. 错误处理

在代码中使用 try-catch:
```dart
try {
  final response = await acpService.sendMessage(agent, message);
  print('成功: $response');
} catch (e) {
  print('失败: $e');
  // 显示用户友好的错误提示
}
```

---

## 📚 相关文档

- [OpenClaw 集成实施报告](OPENCLAW_INTEGRATION_REPORT.md)
- [OpenClaw ACP 集成设计方案](OPENCLAW_ACP_INTEGRATION_DESIGN.md)
- [AI Agent Hub 主文档](../README.md)

---

## 🆘 获取帮助

### 社区支持

- **OpenClaw GitHub**: https://github.com/Moltbot/OpenClaw
- **AI Agent Hub Issues**: https://github.com/your-repo/ai-agent-hub/issues

### 常见问题

访问 [FAQ 文档](FAQ.md) 查看更多常见问题解答。

---

**祝您使用愉快！** 🎉

如有问题，欢迎提 Issue 或参与讨论！
