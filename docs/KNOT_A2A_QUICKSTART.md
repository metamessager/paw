# Knot A2A 快速开始指南

> 5 分钟开始测试 Knot A2A 协议

**日期**: 2026-02-05  
**状态**: ✅ 准备就绪

---

## 🚀 快速开始 (3 步骤)

### 步骤 1: 获取 Knot Agent 配置 (2 分钟)

#### 1.1 获取 Agent Card

访问 Knot 平台:
- 测试环境: https://test.knot.woa.com
- 正式环境: https://knot.woa.com

操作步骤:
1. 登录 Knot 平台
2. 进入"智能体"页面
3. 选择或创建一个智能体
4. 点击"使用配置"
5. 复制 `agent_card` JSON

**示例 Agent Card**:
```json
{
  "agent_id": "3711f0b61fd7421cb2857dbcb815b939",
  "name": "test-agent",
  "description": "测试智能体",
  "endpoint": "http://test.knot.woa.com/apigw/v1/agents/a2a/chat/completions/3711f0b61fd7421cb2857dbcb815b939",
  "model": "deepseek-v3.1",
  "need_history": "no",
  "version": "1.0.0"
}
```

#### 1.2 获取 API Token

访问: https://knot.woa.com/settings/token

操作步骤:
1. 点击"申请 Token"
2. 复制生成的 Token

---

### 步骤 2: 配置环境变量 (1 分钟)

```bash
# 从 Agent Card 中提取
export AGENT_ID='3711f0b61fd7421cb2857dbcb815b939'
export ENDPOINT='http://test.knot.woa.com/apigw/v1/agents/a2a/chat/completions/3711f0b61fd7421cb2857dbcb815b939'

# 从 Token 页面获取
export API_TOKEN='your-api-token-here'

# 你的 RTX ID
export USERNAME='your-rtx-id'
```

---

### 步骤 3: 运行测试 (1 分钟)

```bash
cd /data/workspace/clawd/ai-agent-hub

# 基本测试
./scripts/test_knot_a2a.sh

# 自定义消息
MESSAGE='你好，请介绍一下自己' ./scripts/test_knot_a2a.sh
```

---

## 📊 预期结果

### 成功输出示例

```
========================================
Knot A2A 端点测试脚本
========================================

测试配置:
  Agent ID: 3711f0b61fd7421cb2857dbcb815b939
  Endpoint: http://test.knot.woa.com/apigw/v1/agents/a2a/chat/completions/xxx
  Username: your-rtx
  Conversation ID: 1a2b3c4d-5e6f-7g8h-9i0j-1k2l3m4n5o6p
  Message ID: 2b3c4d5e-6f7g-8h9i-0j1k-2l3m4n5o6p7q
  Call ID: call_3c4d5e6f-7g8h-9i0j-1k2l-3m4n5o6p7q8r
  Message: Hello, Knot! Please say hi.

发送请求...

HTTP 状态码: 200

响应内容:
----------------------------------------
[Chunk 1]
  Message ID: 2b3c4d5e-6f7g-8h9i-0j1k-2l3m4n5o6p7q
  Event Type: RUN_STARTED

[Chunk 2]
  Message ID: 2b3c4d5e-6f7g-8h9i-0j1k-2l3m4n5o6p7q
  Event Type: TEXT_MESSAGE_START

[Chunk 3]
  Message ID: 2b3c4d5e-6f7g-8h9i-0j1k-2l3m4n5o6p7q
  Event Type: TEXT_MESSAGE_CONTENT
  Content: Hi!

[Chunk 4]
  Message ID: 2b3c4d5e-6f7g-8h9i-0j1k-2l3m4n5o6p7q
  Event Type: TEXT_MESSAGE_CONTENT
  Content:  How can I help you today?

[Chunk 5]
  Message ID: 2b3c4d5e-6f7g-8h9i-0j1k-2l3m4n5o6p7q
  Event Type: TEXT_MESSAGE_END

[Chunk 6]
  Message ID: 2b3c4d5e-6f7g-8h9i-0j1k-2l3m4n5o6p7q
  Event Type: RUN_COMPLETED

[流结束]
----------------------------------------

完整回复:
Hi! How can I help you today?

测试完成!
```

### 关键验证点

✅ **HTTP 状态码 200** - 请求成功  
✅ **收到流式响应** - 多个 Chunk  
✅ **解析 AGUI 事件** - RUN_STARTED, TEXT_MESSAGE_CONTENT, RUN_COMPLETED  
✅ **提取完整内容** - 拼接所有 TEXT_MESSAGE_CONTENT  
✅ **流正常结束** - 收到 [DONE] 标志

---

## ❌ 常见错误和解决方案

### 错误 1: HTTP 401 Unauthorized

**原因**: API Token 无效或未设置

**解决**:
```bash
# 检查 Token 是否正确
echo $API_TOKEN

# 重新设置
export API_TOKEN='your-correct-token'
```

---

### 错误 2: HTTP 404 Not Found

**原因**: Agent ID 或 Endpoint 错误

**解决**:
```bash
# 检查配置
echo $AGENT_ID
echo $ENDPOINT

# 确保 Endpoint 包含正确的 Agent ID
# 格式: http://.../agents/a2a/chat/completions/{AGENT_ID}
```

---

### 错误 3: 没有响应内容

**原因**: Agent 可能没有正确配置或模型问题

**解决**:
1. 检查 Agent 在 Knot 平台是否正常工作
2. 尝试在 Knot UI 中直接测试 Agent
3. 检查 model 参数是否支持 (deepseek-v3.1, glm-4.6 等)

---

### 错误 4: 流式响应解析失败

**原因**: jq 未安装或 JSON 格式错误

**解决**:
```bash
# 安装 jq (可选，用于美化输出)
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# 不安装 jq 也可以运行，只是输出不美化
```

---

## 🧪 进阶测试

### 测试不同消息

```bash
# 简单问候
MESSAGE='你好' ./scripts/test_knot_a2a.sh

# 复杂任务
MESSAGE='帮我写一个 Python 排序算法' ./scripts/test_knot_a2a.sh

# 多轮对话 (使用相同 CONV_ID)
CONV_ID='固定-会话-ID' MESSAGE='第一个问题' ./scripts/test_knot_a2a.sh
CONV_ID='固定-会话-ID' MESSAGE='第二个问题' ./scripts/test_knot_a2a.sh
```

### 测试不同模型

修改脚本或请求体中的 `model` 字段:
- `deepseek-v3.1` (推荐)
- `deepseek-v3.2`
- `deepseek-r1-0528`
- `kimi-k2-instruct`
- `glm-4.6`
- `glm-4.7`

### 测试错误处理

```bash
# 测试无效 Agent ID
AGENT_ID='invalid-id' ./scripts/test_knot_a2a.sh

# 测试无效 Token
API_TOKEN='invalid-token' ./scripts/test_knot_a2a.sh
```

---

## 📝 下一步

### 测试成功后

1. ✅ **验证流程** - 确认 Knot A2A 协议工作正常
2. ✅ **记录配置** - 保存 Agent ID, Endpoint, Token
3. ⏳ **编写单元测试** - 在 Dart 中测试 KnotA2AAdapter
4. ⏳ **集成到项目** - 在 UI 中添加 Knot Agent

### 测试失败后

1. ❌ **检查错误信息** - 查看 HTTP 状态码和响应内容
2. ❌ **对照常见错误** - 参考上述错误解决方案
3. ❌ **联系 Knot 团队** - 如果是 Knot 平台问题
4. ❌ **查看详细日志** - 使用 `--verbose` 或 `-v` 参数

---

## 🔗 相关文档

- **实施指南**: [KNOT_A2A_IMPLEMENTATION.md](KNOT_A2A_IMPLEMENTATION.md)
- **Phase 1 报告**: [PHASE1_COMPLETION_REPORT.md](PHASE1_COMPLETION_REPORT.md)
- **统一方案**: [UNIFIED_A2A_INTEGRATION_PLAN.md](UNIFIED_A2A_INTEGRATION_PLAN.md)
- **Knot 官方**: [通过A2A多智能体协议调用智能体](https://iwiki.woa.com/p/4016604641)

---

## 💬 获取帮助

### 项目内部

- 查看 `docs/KNOT_A2A_IMPLEMENTATION.md` 的详细说明
- 查看 `scripts/test_knot_a2a.sh` 的脚本注释
- 查看 `lib/services/knot_a2a_adapter.dart` 的代码注释

### 外部资源

- Knot 平台文档: https://iwiki.woa.com/space/knot
- Knot A2A 文档: https://iwiki.woa.com/p/4016604641
- AGUI 协议: https://iwiki.woa.com/p/4016457374

---

## ✅ 检查清单

测试前:
- [ ] 已获取 Agent Card (含 agent_id 和 endpoint)
- [ ] 已获取 API Token
- [ ] 已设置环境变量 (AGENT_ID, ENDPOINT, API_TOKEN, USERNAME)
- [ ] 已确认脚本有执行权限 (`chmod +x scripts/test_knot_a2a.sh`)

测试中:
- [ ] HTTP 状态码为 200
- [ ] 收到流式响应 (多个 data: 行)
- [ ] 解析出 AGUI 事件 (RUN_STARTED, TEXT_MESSAGE_CONTENT, etc.)
- [ ] 提取到完整回复内容
- [ ] 收到 [DONE] 标志

测试后:
- [ ] 记录成功的配置
- [ ] 准备进入 Phase 2 (单元测试和集成)

---

**文档版本**: v1.0  
**作者**: AI Assistant  
**日期**: 2026-02-05  
**推荐**: ⭐⭐⭐ 立即开始测试！
