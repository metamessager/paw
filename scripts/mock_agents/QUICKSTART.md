# 🚀 Mock Agent 快速开始指南

**5 分钟快速启动模拟 Agent 进行测试**

---

## 📋 前置条件

### 1. 检查 Python 环境

```bash
python3 --version
# 应该是 Python 3.7+
```

### 2. 安装依赖

```bash
pip install aiohttp
```

---

## ⚡ 快速启动（3 步）

### 步骤 1: 启动 Mock Agent 集群

```bash
cd /data/workspace/clawd/ai-agent-hub/scripts/mock_agents
./start_mock_agents.sh
```

**预期输出**：
```
==========================================
🚀 Mock Agent Server 启动
==========================================
Agent ID:   mock_knot_abc123
Agent Name: Knot-Fast
Agent Type: knot
Address:    http://0.0.0.0:8081
==========================================
📡 Endpoints:
   POST   http://0.0.0.0:8081/a2a/task
   GET    http://0.0.0.0:8081/a2a/agent_card
   GET    http://0.0.0.0:8081/health
==========================================
✅ 服务器就绪，等待请求...
```

**✅ 成功标志**：看到 4 个 Agent 启动信息（端口 8081-8084）

---

### 步骤 2: 验证 Agent 正常工作

**打开新终端**，运行测试脚本：

```bash
cd /data/workspace/clawd/ai-agent-hub/scripts/mock_agents
./test_mock_agents.sh
```

**预期输出**：
```
==========================================
🧪 测试 Mock Agent 集群
==========================================

📡 测试: Knot-Fast (端口 8081)

   1️⃣  健康检查...
      ✅ 健康检查通过
   2️⃣  获取 Agent Card...
      ✅ Agent Card 获取成功
      Agent ID: mock_knot_abc123
      Agent Name: Mock KNOT Agent
   3️⃣  发送测试任务...
      ✅ 任务执行成功（收到流式响应）
      接收到 12 个事件
      ✅ 任务正常完成

✅ Knot-Fast 测试通过
```

**✅ 成功标志**：所有 4 个 Agent 测试通过，无错误

---

### 步骤 3: 在 AI Agent Hub 中使用

#### 3.1 获取 Agent 配置

```bash
# 获取 Knot-Fast Agent 的配置
curl http://localhost:8081/a2a/agent_card | jq
```

**输出示例**：
```json
{
  "agent_id": "mock_knot_abc123",
  "agent_name": "Mock KNOT Agent",
  "endpoint": "http://localhost:8081/a2a/task",
  "agent_type": "a2a",
  ...
}
```

**记录以下信息**：
- `agent_id`: `mock_knot_abc123`
- `endpoint`: `http://localhost:8081/a2a/task`

#### 3.2 在 AI Agent Hub 中添加 Agent

1. 打开 AI Agent Hub 应用
2. 点击 "添加 Agent"
3. 选择 "A2A Agent"
4. 填写配置：
   - **Agent ID**: `mock_knot_abc123`（从上面复制）
   - **Agent Name**: `Knot-Fast 测试`
   - **Endpoint**: `http://localhost:8081/a2a/task`
   - **API Token**: 留空（Mock Agent 不需要）
5. 保存

#### 3.3 测试 Agent

1. 创建测试 Channel
2. 邀请刚添加的 Mock Agent
3. 发送消息：`你好，这是测试消息`
4. **预期结果**：
   - ✅ 立即收到流式响应
   - ✅ 看到逐字显示的内容
   - ✅ 最后显示完整回复

---

## 🎯 4 种测试场景

### 1. 基础功能测试 - Knot-Fast (8081)

**特点**：
- ⚡ 快速响应（50ms 延迟）
- 📝 简单文本回复
- 🎯 用于测试基础功能

**配置**：
```
Agent ID: (从 http://localhost:8081/a2a/agent_card 获取)
Endpoint: http://localhost:8081/a2a/task
```

**测试用例**：
- 发送消息
- 验证快速响应
- 验证内容正确

---

### 2. 完整流程测试 - Smart-Thinker (8082)

**特点**：
- 💭 包含思考过程
- 🔧 模拟工具调用
- 📊 完整 AGUI 事件

**配置**：
```
Endpoint: http://localhost:8082/a2a/task
```

**测试用例**：
- 验证思考过程显示
- 验证工具调用显示
- 验证事件顺序正确

---

### 3. UI 渲染测试 - Slow-LLM (8083)

**特点**：
- 🐢 慢速响应（200ms 延迟）
- 📝 逐字流式输出
- 🎨 测试 UI 更新

**配置**：
```
Endpoint: http://localhost:8083/a2a/task
```

**测试用例**：
- 验证流式渲染
- 验证 UI 逐步更新
- 验证无卡顿

---

### 4. 错误处理测试 - Error-Test (8084)

**特点**：
- ⚠️ 30% 错误概率
- 🔄 测试重试机制
- 🐛 测试错误提示

**配置**：
```
Endpoint: http://localhost:8084/a2a/task
```

**测试用例**：
- 多次发送消息
- 验证错误提示
- 验证重试机制

---

## 🧪 完整测试流程

### Phase 1: 基础验证（5 分钟）

```bash
# 1. 启动 Mock Agent
./start_mock_agents.sh

# 2. 验证健康状态
curl http://localhost:8081/health | jq
curl http://localhost:8082/health | jq
curl http://localhost:8083/health | jq
curl http://localhost:8084/health | jq

# 3. 运行自动化测试
./test_mock_agents.sh
```

---

### Phase 2: UI 集成测试（10 分钟）

1. **添加所有 4 个 Mock Agent**
   - 获取各自的 agent_id 和 endpoint
   - 在 AI Agent Hub 中添加

2. **创建测试 Channel**
   - 命名：`Mock Agent 测试`
   - 邀请所有 4 个 Mock Agent

3. **测试消息发送**
   ```
   @Knot-Fast 你好
   @Smart-Thinker 分析一下测试场景
   @Slow-LLM 给我一个详细的回复
   @Error-Test 测试错误处理
   ```

4. **验证结果**
   - ✅ Knot-Fast：快速响应
   - ✅ Smart-Thinker：显示思考过程和工具调用
   - ✅ Slow-LLM：逐字渲染
   - ✅ Error-Test：部分请求失败（预期行为）

---

### Phase 3: Dart 集成测试（5 分钟）

```bash
# 确保 Mock Agent 运行中
./start_mock_agents.sh

# 在另一个终端运行 Dart 测试
cd /data/workspace/clawd/ai-agent-hub
flutter test test/integration/mock_agent_integration_test.dart
```

**预期输出**：
```
00:01 +1: Mock Agent 集成测试 应该能连接到 Knot-Fast Agent (8081)
00:02 +2: Mock Agent 集成测试 应该能接收 Knot-Fast 的流式响应
收到事件: RUN_STARTED
收到事件: TEXT_MESSAGE_CONTENT
收到事件: RUN_COMPLETED
...
00:30 +15: All tests passed!
```

---

## 🛑 停止 Mock Agent

### 方法 1: 使用停止脚本

```bash
./stop_mock_agents.sh
```

### 方法 2: 手动停止

如果在前台运行，按 `Ctrl+C`

---

## 📊 测试检查清单

### ✅ 基础功能

- [ ] Mock Agent 成功启动
- [ ] 健康检查通过
- [ ] Agent Card 获取成功
- [ ] 流式任务执行成功

### ✅ UI 集成

- [ ] Agent 添加成功
- [ ] Channel 创建成功
- [ ] 消息发送成功
- [ ] 流式响应显示正确

### ✅ AGUI 事件

- [ ] RUN_STARTED 事件
- [ ] THOUGHT_MESSAGE 事件（Smart Agent）
- [ ] TOOL_CALL 事件（Smart Agent）
- [ ] TEXT_MESSAGE_CONTENT 事件
- [ ] RUN_COMPLETED 事件

### ✅ 错误处理

- [ ] 错误提示显示
- [ ] 重试机制工作
- [ ] 不影响其他 Agent

### ✅ 性能

- [ ] Knot-Fast < 1 秒完成
- [ ] 流式渲染流畅
- [ ] 并发请求正常

---

## 🐛 常见问题

### Q1: 无法启动 - "Address already in use"

**原因**：端口被占用

**解决**：
```bash
# 停止旧的 Agent
./stop_mock_agents.sh

# 或手动查找并杀死进程
lsof -i :8081
kill <PID>
```

---

### Q2: "ModuleNotFoundError: No module named 'aiohttp'"

**原因**：缺少依赖

**解决**：
```bash
pip install aiohttp
```

---

### Q3: 无法连接 Agent - "Connection refused"

**原因**：Agent 未启动或防火墙阻止

**解决**：
```bash
# 1. 检查 Agent 是否运行
curl http://localhost:8081/health

# 2. 查看日志
cat logs/agent-knot-fast.log

# 3. 重启 Agent
./stop_mock_agents.sh
./start_mock_agents.sh
```

---

### Q4: Flutter 测试失败

**原因**：Mock Agent 未运行

**解决**：
```bash
# 确保 Mock Agent 在运行
./start_mock_agents.sh

# 验证连接
curl http://localhost:8081/health

# 然后再运行测试
flutter test test/integration/mock_agent_integration_test.dart
```

---

## 📚 更多资源

- **详细文档**: [README.md](README.md)
- **Knot A2A 指南**: [../../docs/KNOT_A2A_QUICKSTART.md](../../docs/KNOT_A2A_QUICKSTART.md)
- **上线检查清单**: [../../LAUNCH_CHECKLIST_UPDATED.md](../../LAUNCH_CHECKLIST_UPDATED.md)

---

## 🎉 成功标志

当你看到以下结果时，说明一切正常：

1. ✅ 4 个 Mock Agent 全部启动
2. ✅ 自动化测试全部通过
3. ✅ AI Agent Hub 中能添加 Agent
4. ✅ 发送消息能收到流式响应
5. ✅ Dart 集成测试全部通过

**恭喜！你已经成功设置了 Mock Agent 测试环境！🎊**

---

## 💡 下一步

完成 Mock Agent 测试后：

1. **验证核心功能** - 使用 Mock Agent 测试所有核心功能
2. **性能测试** - 验证大量请求的处理能力
3. **真实 Agent 测试** - 使用真实的 Knot Agent 进行测试
4. **准备上线** - 参考 [LAUNCH_CHECKLIST_UPDATED.md](../../LAUNCH_CHECKLIST_UPDATED.md)

---

**最后更新**: 2026-02-05  
**预计完成时间**: 5-10 分钟  
**难度**: ⭐⭐ (简单)
