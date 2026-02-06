# ✅ UI 集成测试快速检查清单

**预计时间**: 30-40 分钟（快速版）

---

## 🚀 开始前

```bash
# 1. 确认 Mock Agents 运行
./scripts/mock_agents/check_agents.sh

# 2. 启动应用
flutter run
```

---

## ✅ 核心测试清单

### 📝 Phase 1: 添加 Agents (10 分钟)

- [ ] **Knot-Fast** (8081)
  - Agent ID: `mock_knot_29f050f5`
  - Endpoint: `http://localhost:8081/a2a/task`
  
- [ ] **Smart-Thinker** (8082)
  - Agent ID: `mock_smart_d5d0a895`
  - Endpoint: `http://localhost:8082/a2a/task`
  
- [ ] **Slow-LLM** (8083)
  - Agent ID: `mock_slow_b1ec938e`
  - Endpoint: `http://localhost:8083/a2a/task`
  
- [ ] **Error-Test** (8084)
  - Agent ID: `mock_error_916a7411`
  - Endpoint: `http://localhost:8084/a2a/task`

**验证**: 所有 4 个 Agent 显示在列表中 ✅

---

### 💬 Phase 2: 发送测试消息 (10 分钟)

- [ ] **Knot-Fast**: 发送 `"你好，测试一下基本功能"`
  - 验证: 响应快速 (~0.75s)，内容完整 ✅
  
- [ ] **Smart-Thinker**: 发送 `"帮我分析一下AI的发展"`
  - 验证: 响应包含结构化内容 (💡 emoji + 列表) ✅
  
- [ ] **Slow-LLM**: 发送 `"请帮我写一篇文章"`
  - 验证: 响应慢速 (~2.6s)，流式效果明显 ✅
  
- [ ] **Error-Test**: 发送 5 次 `"测试错误 #N"`
  - 验证: 约 1-2 次失败，错误提示清晰 ✅

---

### ⚡ Phase 3: 关键功能 (10 分钟)

- [ ] **流式响应**: 观察内容是否逐步显示
  - 评分: ⭐⭐⭐⭐⭐ / ⭐⭐⭐⭐ / ⭐⭐⭐ / ⭐⭐ / ⭐

- [ ] **错误处理**: 停止一个 Agent，测试错误提示
  ```bash
  pkill -f "mock_a2a_server.py.*8081"
  ```
  - 验证: 显示错误提示，不崩溃 ✅

- [ ] **Agent 管理**:
  - [ ] 编辑 Agent 名称 ✅
  - [ ] 删除 Agent ✅
  - [ ] 列表显示正确 ✅

---

## 📊 快速评估

### 最低标准（Beta 版可上线）

- [ ] 至少 3/4 Agent 可用
- [ ] 消息收发正常
- [ ] 流式响应 ≥ 3 星
- [ ] 基本错误处理
- [ ] 不崩溃

### 理想标准（v1.0 可上线）

- [ ] 所有 4 个 Agent 完全正常
- [ ] 流式响应 ≥ 4 星
- [ ] 完善错误处理
- [ ] AGUI 事件显示
- [ ] 零问题

---

## 🐛 快速问题记录

| # | 问题 | 级别 |
|---|------|------|
| 1 |  | P0/P1/P2 |
| 2 |  | P0/P1/P2 |
| 3 |  | P0/P1/P2 |

---

## ✅ 结论

**通过率**: __/14 (__%)

⬜ **可上线 Beta** - 核心功能正常  
⬜ **需修复** - 有阻塞问题  
⬜ **需改进** - 多个问题

---

**详细指南**: [UI_INTEGRATION_TEST_GUIDE.md](UI_INTEGRATION_TEST_GUIDE.md)
