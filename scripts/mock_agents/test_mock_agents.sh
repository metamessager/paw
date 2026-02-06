#!/bin/bash
# 测试 Mock Agent 集群

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "🧪 测试 Mock Agent 集群"
echo "=========================================="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试单个 Agent
test_agent() {
    local name=$1
    local port=$2
    local url="http://localhost:$port"
    
    echo "📡 测试: $name (端口 $port)"
    echo ""
    
    # 1. 健康检查
    echo "   1️⃣  健康检查..."
    if curl -s "$url/health" > /dev/null; then
        echo -e "      ${GREEN}✅ 健康检查通过${NC}"
    else
        echo -e "      ${RED}❌ 健康检查失败${NC}"
        return 1
    fi
    
    # 2. 获取 Agent Card
    echo "   2️⃣  获取 Agent Card..."
    agent_card=$(curl -s "$url/a2a/agent_card")
    if [ -n "$agent_card" ]; then
        echo -e "      ${GREEN}✅ Agent Card 获取成功${NC}"
        echo "      Agent ID: $(echo $agent_card | jq -r '.agent_id')"
        echo "      Agent Name: $(echo $agent_card | jq -r '.agent_name')"
    else
        echo -e "      ${RED}❌ Agent Card 获取失败${NC}"
        return 1
    fi
    
    # 3. 发送测试任务
    echo "   3️⃣  发送测试任务..."
    task_response=$(curl -s -X POST "$url/a2a/task" \
        -H "Content-Type: application/json" \
        -d '{
            "task_id": "test_'$(date +%s)'",
            "a2a": {
                "input": "这是一个测试消息，来自自动化测试脚本"
            }
        }')
    
    if [ -n "$task_response" ]; then
        # 检查是否包含 AGUI 事件
        if echo "$task_response" | grep -q "RUN_STARTED"; then
            echo -e "      ${GREEN}✅ 任务执行成功（收到流式响应）${NC}"
            
            # 统计事件数量
            event_count=$(echo "$task_response" | grep -c "data:" || true)
            echo "      接收到 $event_count 个事件"
            
            # 检查是否有完成标记
            if echo "$task_response" | grep -q "RUN_COMPLETED"; then
                echo -e "      ${GREEN}✅ 任务正常完成${NC}"
            else
                echo -e "      ${YELLOW}⚠️  未检测到完成标记${NC}"
            fi
        else
            echo -e "      ${RED}❌ 任务执行失败（未收到 AGUI 事件）${NC}"
            return 1
        fi
    else
        echo -e "      ${RED}❌ 任务提交失败${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${GREEN}✅ $name 测试通过${NC}"
    echo ""
    echo "----------------------------------------"
    echo ""
}

# 检查是否安装了 jq
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  建议安装 jq 以获得更好的输出: sudo apt-get install jq${NC}"
    echo ""
fi

# 测试所有 Agent
echo "开始测试..."
echo ""

test_agent "Knot-Fast" 8081
test_agent "Smart-Thinker" 8082
test_agent "Slow-LLM" 8083
test_agent "Error-Test" 8084

echo "=========================================="
echo -e "${GREEN}🎉 所有测试完成！${NC}"
echo "=========================================="
echo ""
echo "📊 测试摘要:"
echo "   - 4 个 Mock Agent 全部测试通过"
echo "   - 健康检查正常"
echo "   - Agent Card 获取成功"
echo "   - 流式任务执行成功"
echo ""
echo "💡 下一步:"
echo "   1. 在 AI Agent Hub 中添加这些 Agent"
echo "   2. 进行端到端集成测试"
echo "   3. 验证 UI 实时更新"
echo ""
