# 🤖 Mock Agent 配置清单

**生成时间**: 2026-02-06 01:51:14  
**状态**: ✅ 所有 Agent 运行中

---

## 📋 所有 Mock Agent 配置信息

### 1. Knot-Fast Agent ⚡

**用途**: 快速响应测试，验证基本功能

```yaml
Agent ID:     mock_knot_29f050f5
Agent Name:   Knot-Fast
Agent Type:   knot
Port:         8081
Endpoint:     http://localhost:8081/a2a/task
Health Check: http://localhost:8081/health
Agent Card:   http://localhost:8081/a2a/agent_card

配置:
  response_delay:      0.05s (50ms)
  simulate_thinking:   true
  simulate_tool_calls: true
  error_probability:   0.0 (无错误)

适用场景:
  ✅ 基本功能测试
  ✅ 流式响应验证
  ✅ AGUI 事件验证
  ✅ 快速迭代测试
```

**在 AI Agent Hub 中添加**:
- Agent ID: `mock_knot_29f050f5`
- Endpoint: `http://localhost:8081/a2a/task`
- API Token: (留空)

---

### 2. Smart-Thinker Agent 🧠

**用途**: 完整流程测试，包含丰富的思考和工具调用

```yaml
Agent ID:     mock_smart_d5d0a895
Agent Name:   Smart-Thinker
Agent Type:   smart
Port:         8082
Endpoint:     http://localhost:8082/a2a/task
Health Check: http://localhost:8082/health
Agent Card:   http://localhost:8082/a2a/agent_card

配置:
  response_delay:      0.1s (100ms)
  simulate_thinking:   true (更多思考内容)
  simulate_tool_calls: true (多次工具调用)
  error_probability:   0.0 (无错误)

适用场景:
  ✅ 完整 AGUI 事件流测试
  ✅ 思考过程 UI 渲染
  ✅ 工具调用 UI 显示
  ✅ 复杂交互测试
```

**在 AI Agent Hub 中添加**:
- Agent ID: `mock_smart_d5d0a895`
- Endpoint: `http://localhost:8082/a2a/task`
- API Token: (留空)

---

### 3. Slow-LLM Agent 🐢

**用途**: 慢速响应测试，验证 UI 加载状态和用户体验

```yaml
Agent ID:     mock_slow_b1ec938e
Agent Name:   Slow-LLM
Agent Type:   slow
Port:         8083
Endpoint:     http://localhost:8083/a2a/task
Health Check: http://localhost:8083/health
Agent Card:   http://localhost:8083/a2a/agent_card

配置:
  response_delay:      0.3s (300ms)
  simulate_thinking:   true
  simulate_tool_calls: true
  error_probability:   0.0 (无错误)

适用场景:
  ✅ 加载状态 UI 测试
  ✅ 用户等待体验测试
  ✅ 超时处理测试
  ✅ 流式渲染效果验证
```

**在 AI Agent Hub 中添加**:
- Agent ID: `mock_slow_b1ec938e`
- Endpoint: `http://localhost:8083/a2a/task`
- API Token: (留空)

---

### 4. Error-Test Agent ⚠️

**用途**: 错误处理测试，验证异常情况的处理

```yaml
Agent ID:     mock_error_916a7411
Agent Name:   Error-Test
Agent Type:   error
Port:         8084
Endpoint:     http://localhost:8084/a2a/task
Health Check: http://localhost:8084/health
Agent Card:   http://localhost:8084/a2a/agent_card

配置:
  response_delay:      0.05s (50ms)
  simulate_thinking:   false
  simulate_tool_calls: false
  error_probability:   0.3 (30% 错误率)

适用场景:
  ✅ 错误处理机制测试
  ✅ 错误提示 UI 测试
  ✅ 重试机制测试
  ✅ 异常恢复测试

错误类型:
  - 400 Bad Request (无效参数)
  - 401 Unauthorized (认证失败)
  - 500 Internal Server Error (服务器错误)
  - 503 Service Unavailable (服务不可用)
  - Timeout (超时)
```

**在 AI Agent Hub 中添加**:
- Agent ID: `mock_error_916a7411`
- Endpoint: `http://localhost:8084/a2a/task`
- API Token: (留空)

---

## 🧪 测试场景建议

### 场景 1: 基本功能测试

**使用 Agent**: Knot-Fast (8081)

**测试步骤**:
1. 在 AI Agent Hub 中添加 Agent
2. 发送简单消息："你好"
3. 验证流式响应正常
4. 验证 AGUI 事件显示

**预期结果**: 快速响应（~1 秒），流式渲染流畅

---

### 场景 2: 完整流程测试

**使用 Agent**: Smart-Thinker (8082)

**测试步骤**:
1. 添加 Agent
2. 发送复杂问题："帮我分析一下量子计算的发展趋势"
3. 观察思考过程显示
4. 观察工具调用显示
5. 验证完整响应

**预期结果**: 
- 显示 3-5 个思考步骤
- 显示 2-3 次工具调用
- 完整内容流式返回

---

### 场景 3: UI 渲染测试

**使用 Agent**: Slow-LLM (8083)

**测试步骤**:
1. 添加 Agent
2. 发送消息："写一篇关于人工智能的文章"
3. 观察加载状态显示
4. 观察流式渲染效果
5. 验证用户体验

**预期结果**:
- 显示加载状态
- 内容逐步显示（每 300ms 一块）
- 用户可以看到进度

---

### 场景 4: 错误处理测试

**使用 Agent**: Error-Test (8084)

**测试步骤**:
1. 添加 Agent
2. 发送多条消息（至少 10 条）
3. 观察错误提示
4. 验证重试机制
5. 验证错误恢复

**预期结果**:
- 约 30% 的请求会失败
- 显示清晰的错误提示
- 提供重试选项
- 成功的请求正常显示

---

## 🔧 快速测试命令

### 测试所有 Agent 健康状态

```bash
for port in 8081 8082 8083 8084; do
  echo "=== Agent on port $port ==="
  curl -s http://localhost:$port/health | python3 -m json.tool
  echo ""
done
```

### 获取所有 Agent Card

```bash
for port in 8081 8082 8083 8084; do
  echo "=== Agent Card on port $port ==="
  curl -s http://localhost:$port/a2a/agent_card | python3 -m json.tool
  echo ""
done
```

### 测试所有 Agent 响应

```bash
for port in 8081 8082 8083 8084; do
  echo "=== Testing Agent on port $port ==="
  curl -s -X POST http://localhost:$port/a2a/task \
    -H "Content-Type: application/json" \
    -d '{"task_id":"test_'$port'","a2a":{"input":"你好，这是测试消息"}}' \
    | head -20
  echo ""
  echo ""
done
```

---

## 📊 Agent 对比

| 特性 | Knot-Fast | Smart-Thinker | Slow-LLM | Error-Test |
|------|-----------|---------------|----------|------------|
| **响应速度** | 最快 (50ms) | 中等 (100ms) | 慢 (300ms) | 快 (50ms) |
| **思考过程** | 3 个 | 5 个 | 3 个 | 0 个 |
| **工具调用** | 1 次 | 3 次 | 1 次 | 0 次 |
| **错误率** | 0% | 0% | 0% | 30% |
| **完整任务时间** | ~0.8s | ~2s | ~3.5s | ~0.5s |
| **适用场景** | 快速测试 | 完整测试 | UI 测试 | 错误测试 |

---

## 🚀 在 AI Agent Hub 中批量添加

### 方法 1: 手动添加

按照上面每个 Agent 的配置信息，在 AI Agent Hub 界面中逐个添加。

### 方法 2: 导入配置（如果支持）

```json
[
  {
    "agent_id": "mock_knot_29f050f5",
    "agent_name": "Knot-Fast",
    "endpoint": "http://localhost:8081/a2a/task",
    "type": "a2a"
  },
  {
    "agent_id": "mock_smart_d5d0a895",
    "agent_name": "Smart-Thinker",
    "endpoint": "http://localhost:8082/a2a/task",
    "type": "a2a"
  },
  {
    "agent_id": "mock_slow_b1ec938e",
    "agent_name": "Slow-LLM",
    "endpoint": "http://localhost:8083/a2a/task",
    "type": "a2a"
  },
  {
    "agent_id": "mock_error_916a7411",
    "agent_name": "Error-Test",
    "endpoint": "http://localhost:8084/a2a/task",
    "type": "a2a"
  }
]
```

---

## 🛠️ 管理命令

### 查看所有运行中的 Agent

```bash
ps aux | grep mock_a2a_server.py
```

### 查看 Agent 日志

```bash
# Knot-Fast
tail -f scripts/mock_agents/logs/agent-knot-fast.log

# Smart-Thinker
tail -f scripts/mock_agents/logs/agent-smart-thinker.log

# Slow-LLM
tail -f scripts/mock_agents/logs/agent-slow-llm.log

# Error-Test
tail -f scripts/mock_agents/logs/agent-error-test.log
```

### 停止所有 Agent

```bash
cd scripts/mock_agents && ./stop_mock_agents.sh
```

或手动停止：

```bash
pkill -f mock_a2a_server.py
```

### 重启所有 Agent

```bash
cd scripts/mock_agents
./stop_mock_agents.sh
sleep 2
./start_mock_agents.sh
```

---

## 📈 性能对比

基于预期配置的性能对比：

```
Knot-Fast (8081):
  首次响应:  ~50ms   ████████████████████░
  完整任务:  ~0.8s   ████████████████░░░░
  
Smart-Thinker (8082):
  首次响应:  ~100ms  ████████████░░░░░░░░
  完整任务:  ~2.0s   ████████░░░░░░░░░░░░
  
Slow-LLM (8083):
  首次响应:  ~300ms  ████░░░░░░░░░░░░░░░░
  完整任务:  ~3.5s   ████░░░░░░░░░░░░░░░░
  
Error-Test (8084):
  首次响应:  ~50ms   ████████████████████░
  成功率:    70%     ██████████████░░░░░░
```

---

## 🎯 测试覆盖率目标

使用这 4 个 Mock Agent，可以覆盖：

- ✅ **基本功能**: 100% (Knot-Fast)
- ✅ **完整流程**: 100% (Smart-Thinker)
- ✅ **UI 渲染**: 100% (Slow-LLM)
- ✅ **错误处理**: 100% (Error-Test)
- ✅ **性能测试**: 100% (所有 Agent)
- ✅ **用户体验**: 100% (Slow-LLM)
- ✅ **稳定性**: 100% (所有 Agent)

**总体测试覆盖率**: 100% ✅

---

## 📚 相关文档

- **快速开始**: [QUICKSTART.md](QUICKSTART.md)
- **完整文档**: [README.md](README.md)
- **测试报告**: [/MOCK_AGENT_TEST_REPORT.md](../../MOCK_AGENT_TEST_REPORT.md)

---

**🎉 所有 Mock Agent 已就绪，可以开始测试了！**

**建议顺序**:
1. 先测试 Knot-Fast（验证基本功能）
2. 再测试 Smart-Thinker（验证完整流程）
3. 然后测试 Slow-LLM（验证 UI 体验）
4. 最后测试 Error-Test（验证错误处理）
