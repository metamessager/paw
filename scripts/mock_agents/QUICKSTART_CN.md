# 🚀 快速开始 - 使用 Enhanced Mock Agent

## 📦 你已经获得了什么

我为你创建了一个增强版的测试 Agent，支持以下功能：

- ✅ **A2A 协议** - 用于 REST API + Server-Sent Events
- ✅ **ACP 协议** - 用于 WebSocket + JSON-RPC 2.0
- ✅ **Token 认证** - 模拟真实的安全场景
- ✅ **流式响应** - 模拟真实 LLM 的流式输出
- ✅ **可配置** - 支持自定义延迟、思考过程、工具调用等

## 🎯 三步开始使用

### 步骤 1: 安装依赖

```bash
pip3 install aiohttp
```

### 步骤 2: 启动测试 Agent

```bash
cd scripts/mock_agents
./start_test_agent.sh
```

然后选择一个预设，推荐：
- 选择 `4` (ACP 认证 Agent) - **最适合测试你的 AI Agent Hub**

启动后会显示类似输出：
```
🔑 Token: agent-abc123def456
📝 连接 URL: ws://localhost:18081/acp?token=agent-abc123def456
```

**记下这个 Token！**你需要在 AI Agent Hub 中使用它。

### 步骤 3: 在 AI Agent Hub 中添加

1. 在 Flutter 应用中，进入 **Agent 管理**页面
2. 点击右下角的 **+** 按钮
3. 选择 **"OpenClaw Agent"**
4. 填写信息：
   - **名称**: Test Agent
   - **Token**: `agent-abc123def456` (从步骤2复制)
   - **Endpoint**: `ws://localhost:18081/acp`
   - **Protocol**: ACP
5. 保存并测试

## 📝 快速命令参考

### 启动不同类型的 Agent

```bash
# A2A 测试 Agent (无认证)
./start_test_agent.sh 1

# A2A 认证 Agent (带 Token)
./start_test_agent.sh 2

# ACP 测试 Agent (无认证)
./start_test_agent.sh 3

# ACP 认证 Agent (带 Token) ⭐ 推荐
./start_test_agent.sh 4

# 双协议 Agent (同时支持 A2A 和 ACP)
./start_test_agent.sh 5
```

### 快速测试

```bash
# 测试 Agent 是否正常运行
./test_enhanced_agent.sh

# 或手动测试
curl http://localhost:18081/health
curl http://localhost:18081/info
```

## 📚 完整文档

- **[ENHANCED_AGENT_GUIDE.md](./ENHANCED_AGENT_GUIDE.md)** - 详细使用指南
  - 所有命令行参数
  - API 端点说明
  - 测试示例
  - 故障排除

- **[启动脚本](./start_test_agent.sh)** - 交互式启动工具
  ```bash
  ./start_test_agent.sh --help
  ```

- **[测试脚本](./test_enhanced_agent.sh)** - 自动化测试工具

## 💡 使用场景

### 场景 1: 快速本地测试
```bash
# 启动简单的 A2A Agent
./start_test_agent.sh 1

# 在另一个终端测试
curl -X POST http://localhost:8080/a2a/task \
  -H "Content-Type: application/json" \
  -d '{"task_id":"test","a2a":{"input":"Hello"}}'
```

### 场景 2: 测试 Token 认证
```bash
# 启动带认证的 Agent
./start_test_agent.sh 4

# 记下输出的 Token
# 在 AI Agent Hub 中使用这个 Token 添加 Agent
```

### 场景 3: 全功能测试
```bash
# 启动双协议 Agent（包含所有功能）
./start_test_agent.sh 5

# 同时测试 A2A 和 ACP 协议
# 包含思考过程和工具调用演示
```

## 🎨 自定义配置

如果预设不满足需求，可以自定义：

```bash
./start_test_agent.sh 6  # 选择自定义配置
```

或直接使用 Python：

```bash
python3 mock_agent_enhanced.py \
  --protocol acp \
  --port 18080 \
  --token my-custom-token \
  --name "My Test Agent" \
  --thinking \
  --delay 0.2
```

## 🔧 常见问题

### Q: 端口被占用怎么办？
A: 使用自定义配置选择其他端口，或杀死占用进程：
```bash
lsof -i :8080
kill -9 <PID>
```

### Q: 如何同时运行多个 Agent？
A: 在不同终端使用不同端口启动：
```bash
# 终端 1
./start_test_agent.sh 1  # 端口 8080

# 终端 2
./start_test_agent.sh 4  # 端口 18081
```

### Q: Token 在哪里？
A: 启动 Agent 时会显示在输出中：
```
🔑 Token: agent-abc123def456
```

### Q: 如何验证 Agent 正常工作？
A: 运行测试脚本：
```bash
./test_enhanced_agent.sh
```

或手动测试：
```bash
curl http://localhost:端口号/health
```

## 🎯 下一步

1. ✅ 启动测试 Agent
2. ✅ 记录 Token
3. ✅ 在 AI Agent Hub 中添加 Agent
4. ✅ 发送测试消息
5. ✅ 观察流式响应

## 📞 需要帮助？

- 查看详细文档: `cat ENHANCED_AGENT_GUIDE.md`
- 查看启动选项: `./start_test_agent.sh --help`
- 运行测试: `./test_enhanced_agent.sh`

---

**提示**: 现在你的 Flutter 应用正在运行（iPhone 16 Pro 模拟器），你可以：
1. 打开新终端
2. 运行 `./start_test_agent.sh 4` 启动测试 Agent
3. 在应用中添加这个 Agent 进行测试

祝测试顺利！🎉
