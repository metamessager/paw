# Enhanced Mock Agent - 使用指南

这是一个增强版的测试 Agent，支持 A2A 和 ACP 两种协议，可以模拟远程 Agent 进行开发和测试。

## 🎯 特性

- ✅ 支持 **A2A 协议** (REST + Server-Sent Events)
- ✅ 支持 **ACP 协议** (WebSocket + JSON-RPC 2.0)
- ✅ **Token 认证**支持
- ✅ **可配置**的响应行为（延迟、思考过程、工具调用）
- ✅ **流式响应**
- ✅ 命令行参数和环境变量配置
- ✅ 交互式启动脚本

## 📦 安装依赖

```bash
pip3 install aiohttp
```

## 🚀 快速开始

### 方式一：使用启动脚本（推荐）

```bash
cd scripts/mock_agents

# 交互式菜单
./start_test_agent.sh

# 或直接指定预设
./start_test_agent.sh a2a-test      # A2A 测试 Agent
./start_test_agent.sh acp-auth      # ACP 认证 Agent
./start_test_agent.sh dual-agent    # 双协议 Agent

# 快捷数字
./start_test_agent.sh 1   # a2a-test
./start_test_agent.sh 2   # a2a-auth
./start_test_agent.sh 4   # acp-auth
```

### 方式二：直接使用 Python

```bash
# 启动 A2A Agent (无认证)
python3 mock_agent_enhanced.py --protocol a2a --port 8080

# 启动 ACP Agent (带 Token)
python3 mock_agent_enhanced.py --protocol acp --port 18080 --token my-secret-token

# 双协议模式
python3 mock_agent_enhanced.py --protocol both --port 8080 --ws-port 18080 --token agent-123
```

## 📚 预设配置

### 1. A2A 测试 Agent
```bash
./start_test_agent.sh a2a-test
```
- **端口**: 8080
- **认证**: 无
- **用途**: 快速测试 A2A 协议
- **端点**: http://localhost:8080/a2a/task

### 2. A2A 认证 Agent
```bash
./start_test_agent.sh a2a-auth
```
- **端口**: 8081
- **认证**: Token（自动生成）
- **用途**: 测试 Token 认证
- **端点**: http://localhost:8081/a2a/task

### 3. ACP 测试 Agent
```bash
./start_test_agent.sh acp-test
```
- **端口**: 18080
- **协议**: WebSocket
- **认证**: 无
- **端点**: ws://localhost:18080/acp

### 4. ACP 认证 Agent
```bash
./start_test_agent.sh acp-auth
```
- **端口**: 18081
- **认证**: Token（自动生成）
- **端点**: ws://localhost:18081/acp?token=YOUR_TOKEN

### 5. 双协议 Agent
```bash
./start_test_agent.sh dual-agent
```
- **HTTP 端口**: 8082 (A2A)
- **WebSocket 端口**: 18082 (ACP)
- **认证**: Token（自动生成）
- **功能**: 思考过程 + 工具调用

## 🎨 命令行参数

```bash
python3 mock_agent_enhanced.py [选项]

选项：
  --protocol {a2a,acp,both}   协议类型 (默认: both)
  --port PORT                 HTTP 端口 (默认: 8080)
  --ws-port WS_PORT          WebSocket 端口 (默认: 同 --port)
  --token TOKEN              认证 Token (可选)
  --name NAME                Agent 名称
  --agent-id AGENT_ID        Agent ID (自动生成)
  --delay DELAY              响应延迟秒数 (默认: 0.1)
  --thinking                 启用思考过程
  --tools                    启用工具调用
```

## 🌍 环境变量

```bash
export AGENT_PROTOCOL=both
export AGENT_PORT=8080
export AGENT_WS_PORT=18080
export AGENT_TOKEN=your-token-here
export AGENT_NAME="My Test Agent"
export RESPONSE_DELAY=0.1
export SIMULATE_THINKING=true
export SIMULATE_TOOLS=false

python3 mock_agent_enhanced.py
```

## 📡 API 端点

### 通用端点

#### GET /health
健康检查

**示例**:
```bash
curl http://localhost:8080/health
```

**响应**:
```json
{
  "status": "healthy",
  "agent_id": "agent_abc123",
  "agent_name": "Mock Agent",
  "protocol": "both",
  "timestamp": "2026-02-07T10:30:00"
}
```

#### GET /info
Agent 信息

**示例**:
```bash
curl http://localhost:8080/info
```

**响应**:
```json
{
  "agent_id": "agent_abc123",
  "name": "Mock Agent",
  "protocol": "both",
  "endpoints": {
    "a2a": "http://localhost:8080/a2a/task",
    "acp": "ws://localhost:18080/acp",
    "health": "http://localhost:8080/health",
    "info": "http://localhost:8080/info"
  },
  "auth": "Bearer token required",
  "features": {
    "streaming": true,
    "thinking": true,
    "tools": false
  }
}
```

### A2A 协议端点

#### GET /a2a/agent_card
获取 Agent Card

**示例**:
```bash
curl http://localhost:8080/a2a/agent_card
```

#### POST /a2a/task
提交任务（流式响应）

**示例**:
```bash
curl -X POST http://localhost:8080/a2a/task \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-token" \
  -d '{
    "task_id": "test_001",
    "a2a": {
      "input": "你好，这是测试消息"
    }
  }'
```

**响应** (Server-Sent Events):
```
data: {"event_type":"RUN_STARTED","data":{"task_id":"test_001",...}}

data: {"event_type":"THOUGHT_MESSAGE","data":{"thought":"正在分析..."}}

data: {"event_type":"TEXT_MESSAGE_CONTENT","data":{"content":"这是回复..."}}

data: {"event_type":"RUN_COMPLETED","data":{"status":"success"}}
```

### ACP 协议端点

#### WebSocket /acp
WebSocket 连接 (JSON-RPC 2.0)

**连接**:
```javascript
// 无认证
const ws = new WebSocket('ws://localhost:18080/acp');

// 带 Token
const ws = new WebSocket('ws://localhost:18080/acp?token=your-token');
```

**支持的方法**:

##### agent.register
注册 Agent
```json
{
  "jsonrpc": "2.0",
  "method": "agent.register",
  "params": {},
  "id": 1
}
```

##### agent.heartbeat
心跳
```json
{
  "jsonrpc": "2.0",
  "method": "agent.heartbeat",
  "params": {},
  "id": 2
}
```

##### chat
聊天（流式）
```json
{
  "jsonrpc": "2.0",
  "method": "chat",
  "params": {
    "message": "你好"
  },
  "id": 3
}
```

##### task.execute
执行任务
```json
{
  "jsonrpc": "2.0",
  "method": "task.execute",
  "params": {
    "instruction": "执行某个任务"
  },
  "id": 4
}
```

## 🧪 在 AI Agent Hub 中使用

### 1. 启动 Mock Agent

```bash
cd scripts/mock_agents
./start_test_agent.sh acp-auth
```

记录输出的 **Agent ID** 和 **Token**：
```
🔑 Token: agent-abc123def456
📝 连接 URL: ws://localhost:18081/acp?token=agent-abc123def456
```

### 2. 在 AI Agent Hub 中添加 Agent

在 Flutter 应用中：
1. 进入 **Agent 管理** 页面
2. 点击 **+** 按钮
3. 选择 **"OpenClaw Agent"** 或 **"自定义 Agent"**
4. 填写信息：
   - **名称**: Test Mock Agent
   - **Token**: `agent-abc123def456`（从启动输出复制）
   - **Endpoint**: `ws://localhost:18081/acp`（如果是 ACP）
   - **Protocol**: ACP
5. 保存

### 3. 测试连接

在应用中：
1. 创建或选择一个 Channel
2. 邀请刚添加的 Mock Agent
3. 发送测试消息
4. 观察流式响应

## 💡 使用示例

### 示例 1: 快速测试 A2A

```bash
# 终端 1: 启动 Agent
cd scripts/mock_agents
./start_test_agent.sh a2a-test

# 终端 2: 测试
curl -X POST http://localhost:8080/a2a/task \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "quick_test",
    "a2a": {"input": "Hello"}
  }'
```

### 示例 2: 测试 ACP 协议

```bash
# 启动带认证的 ACP Agent
./start_test_agent.sh acp-auth

# 输出会显示：
# 🔑 Token: agent-xyz789
# 📝 连接 URL: ws://localhost:18081/acp?token=agent-xyz789

# 使用 wscat 测试 (需要安装: npm install -g wscat)
wscat -c "ws://localhost:18081/acp?token=agent-xyz789"

# 发送 JSON-RPC 请求
> {"jsonrpc":"2.0","method":"agent.register","id":1}
< {"jsonrpc":"2.0","result":{"agent_id":"..."},"id":1}

> {"jsonrpc":"2.0","method":"chat","params":{"message":"测试"},"id":2}
< {"jsonrpc":"2.0","result":{"type":"chat.started"},"id":2}
< {"jsonrpc":"2.0","result":{"type":"chat.content","content":"..."},"id":2}
```

### 示例 3: 集成到 Flutter 测试

在 AI Agent Hub 应用中测试完整流程：

```bash
# 1. 启动双协议 Agent（支持 A2A 和 ACP）
./start_test_agent.sh dual-agent
# 记录 Token: agent-abc123

# 2. 启动 Flutter 应用
cd ../../
flutter run

# 3. 在应用中操作
# - 添加 Remote Agent
# - 使用 Token: agent-abc123
# - 测试连接和消息
```

## 🔧 高级配置

### 自定义响应延迟

```bash
# 极快（无延迟）
python3 mock_agent_enhanced.py --delay 0

# 慢速（模拟真实 LLM）
python3 mock_agent_enhanced.py --delay 0.5
```

### 启用完整功能

```bash
python3 mock_agent_enhanced.py \
  --protocol both \
  --port 8080 \
  --ws-port 18080 \
  --token my-token \
  --thinking \
  --tools \
  --delay 0.15
```

### 多个 Agent 实例

```bash
# Agent 1 - A2A (端口 8080)
python3 mock_agent_enhanced.py --protocol a2a --port 8080 &

# Agent 2 - ACP (端口 18080)
python3 mock_agent_enhanced.py --protocol acp --port 18080 --token token1 &

# Agent 3 - 双协议 (端口 8081/18081)
python3 mock_agent_enhanced.py --protocol both --port 8081 --ws-port 18081 --token token2 &
```

## 🐛 故障排除

### 端口被占用

```bash
# 查找占用端口的进程
lsof -i :8080

# 杀死进程
kill -9 <PID>

# 或使用其他端口
./start_test_agent.sh custom
# 然后输入其他端口号
```

### aiohttp 未安装

```bash
pip3 install aiohttp

# 或使用 requirements
cd scripts/mock_agents
pip3 install -r requirements.txt  # 如果存在
```

### Token 认证失败

确保在请求中包含正确的 Token：

**HTTP (A2A)**:
```bash
curl -H "Authorization: Bearer your-token" ...
```

**WebSocket (ACP)**:
```
ws://localhost:18080/acp?token=your-token
```

## 📊 事件类型

### A2A 事件

1. **RUN_STARTED** - 任务开始
2. **THOUGHT_MESSAGE** - 思考过程
3. **TOOL_CALL_STARTED** - 工具调用开始
4. **TOOL_CALL_COMPLETED** - 工具调用完成
5. **TEXT_MESSAGE_CONTENT** - 文本内容（流式）
6. **RUN_COMPLETED** - 任务完成

### ACP 响应类型

1. **chat.started** - 聊天开始
2. **chat.content** - 聊天内容（流式）
3. **chat.completed** - 聊天完成

## 🎯 测试场景

### 基础连接测试
```bash
./start_test_agent.sh a2a-test
curl http://localhost:8080/health
```

### 认证测试
```bash
./start_test_agent.sh a2a-auth
# 使用输出的 Token 进行请求
```

### 流式响应测试
```bash
./start_test_agent.sh a2a-test
# 发送任务并观察 SSE 流
```

### 协议切换测试
```bash
./start_test_agent.sh dual-agent
# 同时测试 A2A 和 ACP 端点
```

## 📝 开发建议

1. **本地测试**: 使用 `a2a-test` 或 `acp-test` 进行快速开发
2. **认证测试**: 使用 `a2a-auth` 或 `acp-auth` 测试 Token 流程
3. **完整测试**: 使用 `dual-agent` 测试所有功能
4. **生产模拟**: 自定义配置，设置适当的延迟和功能

## 🔗 相关文档

- [BUG_FIX_REPORT.md](../../BUG_FIX_REPORT.md) - Agent 管理修复报告
- [AGENT_MANAGEMENT_TEST_GUIDE.md](../../AGENT_MANAGEMENT_TEST_GUIDE.md) - Agent 管理测试指南
- [Mock Agents README](./README.md) - 原始 Mock Agent 文档

---

**最后更新**: 2026-02-07
**版本**: 1.0.0
