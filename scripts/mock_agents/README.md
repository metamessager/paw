# Mock Agent 测试环境

用于模拟远端 A2A Agent 进行测试。

## 📦 包含的 Mock Agent

### 1. Knot-Fast (端口 8081)
- **类型**: Knot Agent
- **特点**: 快速响应（延迟 0.05s）
- **用途**: 测试基础功能和快速响应

### 2. Smart-Thinker (端口 8082)
- **类型**: Smart Agent
- **特点**: 包含思考过程和工具调用
- **用途**: 测试 AGUI 事件的完整流程

### 3. Slow-LLM (端口 8083)
- **类型**: Slow Agent
- **特点**: 慢速响应（延迟 0.2s）
- **用途**: 测试流式渲染和 UI 更新

### 4. Error-Test (端口 8084)
- **类型**: Error Agent
- **特点**: 30% 错误概率
- **用途**: 测试错误处理机制

## 🚀 快速开始

### 1. 安装依赖

```bash
pip install aiohttp
```

### 2. 启动所有 Mock Agent

```bash
cd /data/workspace/clawd/ai-agent-hub/scripts/mock_agents
chmod +x *.sh
./start_mock_agents.sh
```

### 3. 测试 Agent

在另一个终端运行：

```bash
./test_mock_agents.sh
```

### 4. 停止所有 Agent

```bash
./stop_mock_agents.sh
```

或按 `Ctrl+C`（如果在前台运行）

## 📡 API 端点

每个 Agent 提供以下端点：

- `POST /a2a/task` - 提交任务（流式响应）
- `GET /a2a/agent_card` - 获取 Agent Card
- `GET /health` - 健康检查

## 💡 使用示例

### 获取 Agent Card

```bash
curl http://localhost:8081/a2a/agent_card | jq
```

### 发送任务

```bash
curl -X POST http://localhost:8081/a2a/task \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "test_001",
    "a2a": {
      "input": "测试消息"
    }
  }'
```

### 健康检查

```bash
curl http://localhost:8081/health | jq
```

## 🧪 在 AI Agent Hub 中使用

### 1. 添加 Mock Agent

在 AI Agent Hub 中添加 Agent 时，使用以下配置：

**Knot-Fast Agent**:
- Agent ID: `mock_knot_xxxxxxxx`
- Endpoint: `http://localhost:8081/a2a/task`
- 类型: A2A Agent

**Smart-Thinker Agent**:
- Agent ID: `mock_smart_xxxxxxxx`
- Endpoint: `http://localhost:8082/a2a/task`
- 类型: A2A Agent

### 2. 获取实际配置

启动 Mock Agent 后，运行以下命令获取实际的 Agent ID：

```bash
curl http://localhost:8081/a2a/agent_card | jq -r '.agent_id'
```

### 3. 测试流程

1. 启动 Mock Agent 集群
2. 在 AI Agent Hub 中添加 Agent
3. 创建 Channel 并邀请 Agent
4. 发送消息测试
5. 验证流式响应和 AGUI 事件

## 🎯 测试场景

### 基础功能测试
- 使用 **Knot-Fast** (8081)
- 快速响应，无额外事件
- 验证基础消息收发

### 完整流程测试
- 使用 **Smart-Thinker** (8082)
- 包含思考过程、工具调用
- 验证所有 AGUI 事件类型

### UI 渲染测试
- 使用 **Slow-LLM** (8083)
- 慢速流式响应
- 验证 UI 逐步更新

### 错误处理测试
- 使用 **Error-Test** (8084)
- 30% 概率返回错误
- 验证错误处理和重试机制

## 🔧 高级配置

### 自定义 Mock Agent

手动启动自定义配置的 Agent：

```bash
# 极快响应（无延迟）
python mock_a2a_server.py \
  --port 9001 \
  --agent-type knot \
  --agent-name "Ultra-Fast" \
  --delay 0 \
  --no-thinking \
  --no-tools

# 高错误率（80%）
python mock_a2a_server.py \
  --port 9002 \
  --agent-type error \
  --agent-name "High-Error" \
  --delay 0.1 \
  --error-rate 0.8

# 完整模拟（包含所有事件）
python mock_a2a_server.py \
  --port 9003 \
  --agent-type smart \
  --agent-name "Full-Simulation" \
  --delay 0.15
```

### 环境变量

```bash
export MOCK_AGENT_PORT=8080
export MOCK_AGENT_TYPE=knot
export MOCK_RESPONSE_DELAY=0.1
python mock_a2a_server.py
```

## 📊 支持的 AGUI 事件

Mock Agent 支持以下 AGUI 事件：

1. `RUN_STARTED` - 任务开始
2. `THOUGHT_MESSAGE` - 思考过程（可选）
3. `TOOL_CALL_STARTED` - 工具调用开始（可选）
4. `TOOL_CALL_COMPLETED` - 工具调用完成（可选）
5. `TEXT_MESSAGE_CONTENT` - 文本内容（流式）
6. `RUN_COMPLETED` - 任务完成

## 🐛 故障排除

### Agent 无法启动

**问题**: `ModuleNotFoundError: No module named 'aiohttp'`

**解决**:
```bash
pip install aiohttp
```

### 端口被占用

**问题**: `OSError: [Errno 48] Address already in use`

**解决**:
```bash
# 查找占用端口的进程
lsof -i :8081

# 停止旧的 Agent
./stop_mock_agents.sh

# 或手动杀死进程
kill <PID>
```

### 无法连接

**问题**: `Connection refused`

**解决**:
1. 确认 Agent 已启动：`curl http://localhost:8081/health`
2. 检查日志：`cat logs/agent-knot-fast.log`
3. 检查防火墙设置

## 📝 日志

所有 Agent 的日志保存在 `logs/` 目录：

```bash
logs/
├── agent-knot-fast.log
├── agent-smart.log
├── agent-slow.log
└── agent-error.log
```

查看实时日志：

```bash
tail -f logs/agent-knot-fast.log
```

## 🎉 完整测试流程

### 1. 启动环境

```bash
# 终端 1: 启动 Mock Agent
./start_mock_agents.sh
```

### 2. 验证 Agent

```bash
# 终端 2: 测试 Agent
./test_mock_agents.sh
```

### 3. 集成测试

```bash
# 在 AI Agent Hub 中：
# 1. 添加 4 个 Mock Agent
# 2. 创建测试 Channel
# 3. 发送消息测试
# 4. 验证流式响应
# 5. 验证 AGUI 事件
```

### 4. 清理

```bash
# 停止所有 Agent
./stop_mock_agents.sh

# 清理日志
rm -rf logs/*.log
```

## 🔗 相关文档

- [Knot A2A 快速开始](../../docs/KNOT_A2A_QUICKSTART.md)
- [Knot A2A 实施指南](../../docs/KNOT_A2A_IMPLEMENTATION.md)
- [上线检查清单](../../LAUNCH_CHECKLIST_UPDATED.md)

## 💬 反馈

如果遇到问题或有改进建议，请：

1. 查看日志文件
2. 检查 API 响应
3. 提交问题反馈

---

**最后更新**: 2026-02-05
