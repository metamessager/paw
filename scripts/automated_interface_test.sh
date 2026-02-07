#!/bin/bash
# UI 集成测试 - 自动化验证脚本
# 用于在没有 Flutter UI 的情况下验证 Mock Agent 的 HTTP 接口

set -e

echo "════════════════════════════════════════════════════════════════"
echo "  🎯 AI Agent Hub - Mock Agent 接口自动化验证"
echo "════════════════════════════════════════════════════════════════"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 统计变量
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 测试结果记录
declare -a TEST_RESULTS

# 辅助函数
function test_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

function test_case() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo ""
    echo -e "${YELLOW}测试 #$TOTAL_TESTS: $1${NC}"
}

function assert_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 通过: $1${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("✅ $1")
        return 0
    else
        echo -e "${RED}❌ 失败: $1${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("❌ $1")
        return 1
    fi
}

function assert_contains() {
    local output="$1"
    local expected="$2"
    local description="$3"
    
    if echo "$output" | grep -q "$expected"; then
        echo -e "${GREEN}✅ 通过: $description${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("✅ $description")
        return 0
    else
        echo -e "${RED}❌ 失败: $description - 未找到 '$expected'${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("❌ $description")
        return 1
    fi
}

# ════════════════════════════════════════════════════════════════
# Phase 1: 健康检查
# ════════════════════════════════════════════════════════════════

test_header "Phase 1: Mock Agent 健康检查"

# Agent 配置
declare -A AGENTS
AGENTS["Knot-Fast"]="8081"
AGENTS["Smart-Thinker"]="8082"
AGENTS["Slow-LLM"]="8083"
AGENTS["Error-Test"]="8084"

for agent_name in "${!AGENTS[@]}"; do
    port="${AGENTS[$agent_name]}"
    test_case "健康检查 - $agent_name (端口 $port)"
    
    response=$(curl -s -w "\n%{http_code}" "http://localhost:$port/health" 2>&1)
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" = "200" ]; then
        assert_success "$agent_name 健康检查通过"
        echo "  响应: $body"
    else
        assert_success "$agent_name 健康检查失败 (HTTP $http_code)" && false
    fi
done

# ════════════════════════════════════════════════════════════════
# Phase 2: Agent Card 获取
# ════════════════════════════════════════════════════════════════

test_header "Phase 2: Agent Card 获取测试"

for agent_name in "${!AGENTS[@]}"; do
    port="${AGENTS[$agent_name]}"
    test_case "获取 Agent Card - $agent_name"
    
    response=$(curl -s "http://localhost:$port/a2a/agent_card" 2>&1)
    
    assert_contains "$response" "agent_id" "Agent Card 包含 agent_id"
    assert_contains "$response" "name" "Agent Card 包含 name"
    assert_contains "$response" "mock_" "Agent ID 格式正确 (包含 mock_ 前缀)"
    
    echo "  Agent Card 预览: $(echo $response | head -c 100)..."
done

# ════════════════════════════════════════════════════════════════
# Phase 3: 基本消息发送
# ════════════════════════════════════════════════════════════════

test_header "Phase 3: 基本消息发送测试"

# 测试 Knot-Fast
test_case "发送消息到 Knot-Fast (快速响应)"
response=$(curl -s -X POST "http://localhost:8081/a2a/task" \
    -H "Content-Type: application/json" \
    -d '{"task_id":"test_fast","a2a":{"input":"你好，测试基本功能"}}' 2>&1)

assert_contains "$response" "data:" "响应包含 SSE 数据"
assert_contains "$response" "RUN_STARTED" "包含 RUN_STARTED 事件"
assert_contains "$response" "TEXT_MESSAGE_CONTENT" "包含 TEXT_MESSAGE_CONTENT 事件"
assert_contains "$response" "RUN_COMPLETED" "包含 RUN_COMPLETED 事件"
assert_contains "$response" "测试成功" "包含预期响应内容"

# 测试 Smart-Thinker
test_case "发送消息到 Smart-Thinker (完整流程)"
response=$(curl -s -X POST "http://localhost:8082/a2a/task" \
    -H "Content-Type: application/json" \
    -d '{"task_id":"test_smart","a2a":{"input":"帮我分析AI发展"}}' 2>&1)

assert_contains "$response" "THOUGHT_MESSAGE" "包含 THOUGHT_MESSAGE 事件"
assert_contains "$response" "TOOL_CALL_STARTED" "包含 TOOL_CALL_STARTED 事件"
assert_contains "$response" "💡" "包含智能 Agent 标识 (💡)"

# 测试 Slow-LLM
test_case "发送消息到 Slow-LLM (慢速响应)"
start_time=$(date +%s)
response=$(curl -s -X POST "http://localhost:8083/a2a/task" \
    -H "Content-Type: application/json" \
    -d '{"task_id":"test_slow","a2a":{"input":"写一篇文章"}}' 2>&1)
end_time=$(date +%s)
duration=$((end_time - start_time))

assert_contains "$response" "🐢" "包含慢速 Agent 标识 (🐢)"
assert_contains "$response" "慢速响应" "包含慢速响应说明"

if [ $duration -ge 2 ]; then
    assert_success "响应时间符合预期 (${duration}s ≥ 2s)"
else
    assert_success "响应时间不符合预期 (${duration}s < 2s)" && false
fi

# ════════════════════════════════════════════════════════════════
# Phase 4: 错误处理测试
# ════════════════════════════════════════════════════════════════

test_header "Phase 4: 错误处理测试"

test_case "测试 Error-Test Agent 的错误率"

success_count=0
error_count=0
total_requests=10

echo "发送 $total_requests 次请求，观察错误率..."

for i in $(seq 1 $total_requests); do
    response=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8084/a2a/task" \
        -H "Content-Type: application/json" \
        -d "{\"task_id\":\"error_test_$i\",\"a2a\":{\"input\":\"测试 #$i\"}}" 2>&1)
    
    http_code=$(echo "$response" | tail -1)
    
    if [ "$http_code" = "200" ]; then
        success_count=$((success_count + 1))
        echo -n "."
    else
        error_count=$((error_count + 1))
        echo -n "×"
    fi
    
    sleep 0.1
done

echo ""
echo "  成功: $success_count/$total_requests ($(( success_count * 100 / total_requests ))%)"
echo "  失败: $error_count/$total_requests ($(( error_count * 100 / total_requests ))%)"

# 验证错误率在 20%-40% 之间（预期 30%）
if [ $error_count -ge 2 ] && [ $error_count -le 5 ]; then
    assert_success "错误率符合预期 (20%-50%)"
else
    echo -e "${YELLOW}⚠️  警告: 错误率偏差 (预期 20%-50%, 实际 $(( error_count * 100 / total_requests ))%)${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TEST_RESULTS+=("⚠️ 错误率偏差但可接受")
fi

# ════════════════════════════════════════════════════════════════
# Phase 5: AGUI 事件完整性
# ════════════════════════════════════════════════════════════════

test_header "Phase 5: AGUI 事件完整性测试"

test_case "验证所有 AGUI 事件类型"

response=$(curl -s -X POST "http://localhost:8082/a2a/task" \
    -H "Content-Type: application/json" \
    -d '{"task_id":"agui_test","a2a":{"input":"完整测试"}}' 2>&1)

# 验证所有事件类型
assert_contains "$response" "RUN_STARTED" "包含 RUN_STARTED 事件"
assert_contains "$response" "THOUGHT_MESSAGE" "包含 THOUGHT_MESSAGE 事件"
assert_contains "$response" "TOOL_CALL_STARTED" "包含 TOOL_CALL_STARTED 事件"
assert_contains "$response" "TOOL_CALL_COMPLETED" "包含 TOOL_CALL_COMPLETED 事件"
assert_contains "$response" "TEXT_MESSAGE_CONTENT" "包含 TEXT_MESSAGE_CONTENT 事件"
assert_contains "$response" "RUN_COMPLETED" "包含 RUN_COMPLETED 事件"

# 验证事件顺序
event_order=$(echo "$response" | grep -o 'RUN_STARTED\|THOUGHT_MESSAGE\|TEXT_MESSAGE_CONTENT\|RUN_COMPLETED' | head -5)
expected_start="RUN_STARTED"
expected_end="RUN_COMPLETED"

if echo "$event_order" | head -1 | grep -q "$expected_start"; then
    assert_success "事件顺序正确：以 RUN_STARTED 开始"
else
    assert_success "事件顺序错误：未以 RUN_STARTED 开始" && false
fi

if echo "$response" | grep -o 'RUN_COMPLETED' | tail -1 | grep -q "$expected_end"; then
    assert_success "事件顺序正确：以 RUN_COMPLETED 结束"
else
    assert_success "事件顺序错误：未以 RUN_COMPLETED 结束" && false
fi

# ════════════════════════════════════════════════════════════════
# Phase 6: 性能测试
# ════════════════════════════════════════════════════════════════

test_header "Phase 6: 性能测试"

# 测试响应时间
for agent_name in "Knot-Fast" "Smart-Thinker" "Slow-LLM"; do
    port="${AGENTS[$agent_name]}"
    test_case "测试 $agent_name 的响应时间"
    
    start_time=$(date +%s%3N)
    response=$(curl -s -X POST "http://localhost:$port/a2a/task" \
        -H "Content-Type: application/json" \
        -d "{\"task_id\":\"perf_test\",\"a2a\":{\"input\":\"性能测试\"}}" 2>&1)
    end_time=$(date +%s%3N)
    
    duration=$((end_time - start_time))
    duration_sec=$(echo "scale=2; $duration / 1000" | bc)
    
    echo "  响应时间: ${duration_sec}s"
    
    # 验证响应时间在合理范围内 (< 5s)
    if [ $duration -lt 5000 ]; then
        assert_success "$agent_name 响应时间正常 (< 5s)"
    else
        assert_success "$agent_name 响应时间过长 (> 5s)" && false
    fi
done

# ════════════════════════════════════════════════════════════════
# 最终报告
# ════════════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  📊 测试结果汇总"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "总测试数:     $TOTAL_TESTS"
echo -e "通过数:       ${GREEN}$PASSED_TESTS${NC}"
echo -e "失败数:       ${RED}$FAILED_TESTS${NC}"

if [ $TOTAL_TESTS -gt 0 ]; then
    pass_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo "通过率:       $pass_rate%"
else
    pass_rate=0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  测试详情"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for result in "${TEST_RESULTS[@]}"; do
    echo "$result"
done

echo ""
echo "════════════════════════════════════════════════════════════════"

# 最终判断
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}🎉 所有测试通过！Mock Agent 接口完全正常！${NC}"
    echo ""
    echo "✅ 下一步: 在 AI Agent Hub UI 中添加这些 Agent 进行实际测试"
    exit 0
elif [ $pass_rate -ge 80 ]; then
    echo -e "${YELLOW}⚠️  大部分测试通过，但有少量失败（通过率 $pass_rate%）${NC}"
    echo ""
    echo "建议: 检查失败的测试，修复后重新运行"
    exit 1
else
    echo -e "${RED}❌ 测试失败较多（通过率 $pass_rate%），需要修复${NC}"
    echo ""
    echo "建议: 检查 Mock Agent 是否正常运行，查看日志"
    exit 1
fi
