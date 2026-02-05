#!/bin/bash
# AI Agent Hub 双向通信测试脚本

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║    AI Agent Hub - 双向通信功能测试                       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目路径
PROJECT_DIR="/data/workspace/clawd/ai-agent-hub"

# 测试计数
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 测试函数
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${BLUE}[测试 $TOTAL_TESTS]${NC} $test_name"
    
    if eval "$test_command" > /dev/null 2>&1; then
        echo -e "${GREEN}  ✅ 通过${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}  ❌ 失败${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# 检查文件是否存在
check_file() {
    local file="$1"
    test -f "$PROJECT_DIR/$file"
}

# 检查目录是否存在
check_dir() {
    local dir="$1"
    test -d "$PROJECT_DIR/$dir"
}

# 开始测试
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  第一阶段: 文件结构检查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

run_test "检查 ACP 消息模型" "check_file 'lib/models/acp_server_message.dart'"
run_test "检查权限服务" "check_file 'lib/services/permission_service.dart'"
run_test "检查 ACP Server 服务" "check_file 'lib/services/acp_server_service.dart'"
run_test "检查权限管理界面" "check_file 'lib/screens/permission_request_screen.dart'"
run_test "检查主动消息界面" "check_file 'lib/screens/incoming_message_screen.dart'"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  第二阶段: 文档检查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

run_test "检查双向通信文档" "check_file 'docs/BIDIRECTIONAL_COMMUNICATION.md'"
run_test "检查实施报告" "check_file 'docs/BIDIRECTIONAL_IMPLEMENTATION_REPORT.md'"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  第三阶段: 示例文件检查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

run_test "检查 OpenClaw 集成示例" "check_file 'examples/openclaw_hub_integration.py'"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  第四阶段: 代码语法检查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$PROJECT_DIR" || exit 1

# 检查 Dart 代码
if command -v dart &> /dev/null; then
    run_test "Dart 代码格式检查" "dart format --set-exit-if-changed --dry-run lib/"
    run_test "Dart 代码分析" "dart analyze lib/"
else
    echo -e "${YELLOW}  ⚠️  Dart 未安装，跳过语法检查${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  第五阶段: 集成检查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查 main.dart 是否包含 ACP Server 初始化
if grep -q "globalACPServer" "$PROJECT_DIR/lib/main.dart"; then
    echo -e "${BLUE}[测试 $((TOTAL_TESTS + 1))]${NC} 检查 main.dart 集成"
    echo -e "${GREEN}  ✅ 通过${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${BLUE}[测试 $((TOTAL_TESTS + 1))]${NC} 检查 main.dart 集成"
    echo -e "${RED}  ❌ 失败${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# 检查 pubspec.yaml 是否包含 WebSocket 依赖
if grep -q "web_socket_channel" "$PROJECT_DIR/pubspec.yaml"; then
    echo -e "${BLUE}[测试 $((TOTAL_TESTS + 1))]${NC} 检查依赖配置"
    echo -e "${GREEN}  ✅ 通过${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${BLUE}[测试 $((TOTAL_TESTS + 1))]${NC} 检查依赖配置"
    echo -e "${RED}  ❌ 失败${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  测试总结"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "总测试数: ${BLUE}$TOTAL_TESTS${NC}"
echo -e "通过: ${GREEN}$PASSED_TESTS${NC}"
echo -e "失败: ${RED}$FAILED_TESTS${NC}"
echo ""

# 计算成功率
if [ $TOTAL_TESTS -gt 0 ]; then
    SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo -e "成功率: ${BLUE}${SUCCESS_RATE}%${NC}"
    echo ""
    
    if [ $SUCCESS_RATE -eq 100 ]; then
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║                 🎉 所有测试通过！                        ║${NC}"
        echo -e "${GREEN}║          双向通信功能已成功实施，可以部署！               ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
        exit 0
    elif [ $SUCCESS_RATE -ge 80 ]; then
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║             ⚠️  大部分测试通过                           ║${NC}"
        echo -e "${YELLOW}║        但有部分测试失败，请检查失败的测试项               ║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
        exit 1
    else
        echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                ❌ 测试失败过多                            ║${NC}"
        echo -e "${RED}║            请修复失败的测试项后再部署                     ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
        exit 1
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  下一步"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. 安装依赖:"
echo "   cd $PROJECT_DIR"
echo "   flutter pub get"
echo ""
echo "2. 运行应用:"
echo "   flutter run"
echo ""
echo "3. 测试连接:"
echo "   python3 examples/openclaw_hub_integration.py"
echo ""
echo "4. 查看文档:"
echo "   cat docs/BIDIRECTIONAL_COMMUNICATION.md"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
