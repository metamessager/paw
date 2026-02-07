#!/bin/bash
# 快速测试增强版 Mock Agent

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Enhanced Mock Agent - 快速测试                        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 测试 A2A Agent
test_a2a_agent() {
    local port=$1
    echo -e "${YELLOW}测试 A2A Agent (端口 $port)...${NC}"

    # 健康检查
    echo -n "  健康检查... "
    response=$(curl -s http://localhost:$port/health)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ (无法连接)${NC}"
        return 1
    fi

    # Agent Card
    echo -n "  Agent Card... "
    response=$(curl -s http://localhost:$port/a2a/agent_card)
    if echo "$response" | grep -q "agent_id"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi

    # 任务提交（需要实际测试流式响应）
    echo -n "  任务提交... "
    response=$(curl -s -X POST http://localhost:$port/a2a/task \
        -H "Content-Type: application/json" \
        -d '{"task_id":"test","a2a":{"input":"test"}}' \
        --max-time 5)
    if echo "$response" | grep -q "RUN_STARTED"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi

    echo ""
    return 0
}

# 测试 ACP Agent (WebSocket)
test_acp_agent() {
    local port=$1
    local token=$2
    echo -e "${YELLOW}测试 ACP Agent (端口 $port)...${NC}"

    # 健康检查（HTTP）
    echo -n "  健康检查... "
    response=$(curl -s http://localhost:$port/health 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ (无法连接)${NC}"
        return 1
    fi

    # Info 端点
    echo -n "  Info 端点... "
    response=$(curl -s http://localhost:$port/info)
    if echo "$response" | grep -q "agent_id"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi

    # WebSocket 测试需要 wscat 或其他工具
    if command -v wscat &> /dev/null; then
        echo -n "  WebSocket 连接... "
        # 这里可以添加 wscat 测试
        echo -e "${YELLOW}⊘ (需要 wscat)${NC}"
    else
        echo -e "  ${YELLOW}WebSocket 测试跳过 (未安装 wscat)${NC}"
    fi

    echo ""
    return 0
}

# 主菜单
echo "选择测试场景:"
echo "  1) 测试本地 A2A Agent (端口 8080)"
echo "  2) 测试本地 ACP Agent (端口 18080)"
echo "  3) 启动测试 Agent 然后测试"
echo "  4) 显示测试命令"
echo ""
read -p "请选择 [1-4]: " choice

case $choice in
    1)
        test_a2a_agent 8080
        ;;
    2)
        test_acp_agent 18080
        ;;
    3)
        echo -e "${BLUE}启动 A2A 测试 Agent...${NC}"
        echo "请在新终端运行:"
        echo "  cd $SCRIPT_DIR"
        echo "  ./start_test_agent.sh a2a-test"
        echo ""
        echo "启动后按回车继续测试..."
        read
        test_a2a_agent 8080
        ;;
    4)
        echo -e "${BLUE}═══════════════════════════════════════${NC}"
        echo -e "${BLUE}手动测试命令${NC}"
        echo -e "${BLUE}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "${YELLOW}1. 启动 A2A Agent:${NC}"
        echo "   ./start_test_agent.sh a2a-test"
        echo ""
        echo -e "${YELLOW}2. 测试健康检查:${NC}"
        echo "   curl http://localhost:8080/health | jq"
        echo ""
        echo -e "${YELLOW}3. 获取 Agent Card:${NC}"
        echo "   curl http://localhost:8080/a2a/agent_card | jq"
        echo ""
        echo -e "${YELLOW}4. 提交任务:${NC}"
        echo "   curl -X POST http://localhost:8080/a2a/task \\"
        echo "     -H 'Content-Type: application/json' \\"
        echo "     -d '{\"task_id\":\"test_001\",\"a2a\":{\"input\":\"你好\"}}'"
        echo ""
        echo -e "${YELLOW}5. 启动 ACP Agent:${NC}"
        echo "   ./start_test_agent.sh acp-auth"
        echo ""
        echo -e "${YELLOW}6. 测试 ACP WebSocket (需要 wscat):${NC}"
        echo "   wscat -c 'ws://localhost:18081/acp?token=YOUR_TOKEN'"
        echo "   > {\"jsonrpc\":\"2.0\",\"method\":\"agent.register\",\"id\":1}"
        echo ""
        echo -e "${YELLOW}7. 在 AI Agent Hub 中添加:${NC}"
        echo "   - 运行 flutter run"
        echo "   - 进入 Agent 管理"
        echo "   - 添加 Remote Agent"
        echo "   - 使用启动时显示的 Token"
        echo ""
        ;;
    *)
        echo -e "${RED}无效选择${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}测试完成！${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo "更多信息:"
echo "  - 完整文档: cat ENHANCED_AGENT_GUIDE.md"
echo "  - 启动脚本: ./start_test_agent.sh --help"
echo ""
