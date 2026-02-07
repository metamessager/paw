#!/bin/bash
# 启动增强版 Mock Agent 的辅助脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_SCRIPT="$SCRIPT_DIR/mock_agent_enhanced.py"

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 显示使用说明
show_usage() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         Enhanced Mock Agent - 快速启动脚本                    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "使用方法："
    echo "  $0 [预设名称]"
    echo ""
    echo "可用的预设："
    echo "  a2a-test      - A2A 测试 Agent (端口 8080, 无 token)"
    echo "  a2a-auth      - A2A 认证 Agent (端口 8081, 需要 token)"
    echo "  acp-test      - ACP 测试 Agent (端口 18080, 无 token)"
    echo "  acp-auth      - ACP 认证 Agent (端口 18081, 需要 token)"
    echo "  dual-agent    - 双协议 Agent (HTTP: 8082, WS: 18082)"
    echo "  custom        - 自定义配置（交互式）"
    echo ""
    echo "快捷方式："
    echo "  $0 1    # a2a-test"
    echo "  $0 2    # a2a-auth"
    echo "  $0 3    # acp-test"
    echo "  $0 4    # acp-auth"
    echo "  $0 5    # dual-agent"
    echo ""
    echo "示例："
    echo "  $0 a2a-test          # 启动 A2A 测试 Agent"
    echo "  $0 acp-auth          # 启动带认证的 ACP Agent"
    echo "  $0                   # 显示交互式菜单"
}

# 检查 Python 和依赖
check_requirements() {
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}❌ Python 3 未安装${NC}"
        exit 1
    fi

    if ! python3 -c "import aiohttp" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  aiohttp 未安装，正在安装...${NC}"
        pip3 install aiohttp
    fi
}

# 生成随机 token
generate_token() {
    python3 -c "import uuid; print(f'agent-{uuid.uuid4().hex[:16]}')"
}

# 启动 Agent
start_agent() {
    local preset=$1

    case $preset in
        "a2a-test"|"1")
            echo -e "${GREEN}🚀 启动 A2A 测试 Agent${NC}"
            python3 "$AGENT_SCRIPT" \
                --protocol a2a \
                --port 8080 \
                --name "A2A Test Agent" \
                --thinking
            ;;

        "a2a-auth"|"2")
            local token=$(generate_token)
            echo -e "${GREEN}🚀 启动 A2A 认证 Agent${NC}"
            echo -e "${YELLOW}🔑 Token: $token${NC}"
            python3 "$AGENT_SCRIPT" \
                --protocol a2a \
                --port 8081 \
                --name "A2A Auth Agent" \
                --token "$token" \
                --thinking
            ;;

        "acp-test"|"3")
            echo -e "${GREEN}🚀 启动 ACP 测试 Agent${NC}"
            python3 "$AGENT_SCRIPT" \
                --protocol acp \
                --port 18080 \
                --name "ACP Test Agent"
            ;;

        "acp-auth"|"4")
            local token=$(generate_token)
            echo -e "${GREEN}🚀 启动 ACP 认证 Agent${NC}"
            echo -e "${YELLOW}🔑 Token: $token${NC}"
            echo -e "${YELLOW}📝 连接 URL: ws://localhost:18081/acp?token=$token${NC}"
            python3 "$AGENT_SCRIPT" \
                --protocol acp \
                --port 18081 \
                --name "ACP Auth Agent" \
                --token "$token"
            ;;

        "dual-agent"|"5")
            local token=$(generate_token)
            echo -e "${GREEN}🚀 启动双协议 Agent${NC}"
            echo -e "${YELLOW}🔑 Token: $token${NC}"
            python3 "$AGENT_SCRIPT" \
                --protocol both \
                --port 8082 \
                --ws-port 18082 \
                --name "Dual Protocol Agent" \
                --token "$token" \
                --thinking \
                --tools
            ;;

        "custom")
            echo -e "${BLUE}📝 自定义配置${NC}"
            read -p "Protocol (a2a/acp/both) [both]: " protocol
            protocol=${protocol:-both}

            read -p "Port [8080]: " port
            port=${port:-8080}

            if [ "$protocol" == "acp" ] || [ "$protocol" == "both" ]; then
                read -p "WebSocket Port [18080]: " ws_port
                ws_port=${ws_port:-18080}
                ws_arg="--ws-port $ws_port"
            fi

            read -p "Agent Name [Custom Agent]: " name
            name=${name:-Custom Agent}

            read -p "需要 Token? (y/n) [n]: " need_token
            if [ "$need_token" == "y" ]; then
                token=$(generate_token)
                echo -e "${YELLOW}🔑 生成 Token: $token${NC}"
                token_arg="--token $token"
            fi

            read -p "启用思考过程? (y/n) [y]: " thinking
            if [ "$thinking" != "n" ]; then
                thinking_arg="--thinking"
            fi

            read -p "启用工具调用? (y/n) [n]: " tools
            if [ "$tools" == "y" ]; then
                tools_arg="--tools"
            fi

            echo -e "${GREEN}🚀 启动自定义 Agent${NC}"
            python3 "$AGENT_SCRIPT" \
                --protocol "$protocol" \
                --port "$port" \
                $ws_arg \
                --name "$name" \
                $token_arg \
                $thinking_arg \
                $tools_arg
            ;;

        *)
            echo -e "${RED}❌ 未知的预设: $preset${NC}"
            show_usage
            exit 1
            ;;
    esac
}

# 交互式菜单
show_menu() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         选择要启动的 Agent 类型                               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  1) A2A 测试 Agent      (端口 8080, 无认证)"
    echo "  2) A2A 认证 Agent      (端口 8081, Token 认证)"
    echo "  3) ACP 测试 Agent      (端口 18080, 无认证)"
    echo "  4) ACP 认证 Agent      (端口 18081, Token 认证)"
    echo "  5) 双协议 Agent        (HTTP: 8082, WS: 18082)"
    echo "  6) 自定义配置"
    echo "  q) 退出"
    echo ""
    read -p "请选择 [1-6]: " choice

    case $choice in
        1) start_agent "1" ;;
        2) start_agent "2" ;;
        3) start_agent "3" ;;
        4) start_agent "4" ;;
        5) start_agent "5" ;;
        6) start_agent "custom" ;;
        q|Q) exit 0 ;;
        *)
            echo -e "${RED}❌ 无效选择${NC}"
            show_menu
            ;;
    esac
}

# 主流程
main() {
    check_requirements

    if [ $# -eq 0 ]; then
        show_menu
    elif [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
        show_usage
    else
        start_agent "$1"
    fi
}

main "$@"
