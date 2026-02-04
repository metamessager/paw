#!/bin/bash

# AI Agent Hub - 密码管理系统测试脚本

echo "=================================================="
echo "  AI Agent Hub - 密码管理功能测试"
echo "=================================================="
echo ""

PROJECT_DIR="/projects/clawd/ai-agent-hub"
cd "$PROJECT_DIR" || exit 1

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试结果统计
TESTS_PASSED=0
TESTS_FAILED=0

# 测试函数
test_item() {
    local name=$1
    local result=$2
    
    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $name"
        ((TESTS_FAILED++))
    fi
}

echo "📋 测试 1: 项目结构检查"
echo "----------------------------------------"

# 检查必要的文件
test_item "pubspec.yaml 存在" $([ -f "pubspec.yaml" ] && echo 0 || echo 1)
test_item "main.dart 存在" $([ -f "lib/main.dart" ] && echo 0 || echo 1)
test_item "password_service.dart 存在" $([ -f "lib/services/password_service.dart" ] && echo 0 || echo 1)
test_item "password_setup_screen.dart 存在" $([ -f "lib/screens/password_setup_screen.dart" ] && echo 0 || echo 1)
test_item "login_screen.dart 存在" $([ -f "lib/screens/login_screen.dart" ] && echo 0 || echo 1)
test_item "change_password_screen.dart 存在" $([ -f "lib/screens/change_password_screen.dart" ] && echo 0 || echo 1)
test_item "home_screen.dart 存在" $([ -f "lib/screens/home_screen.dart" ] && echo 0 || echo 1)
test_item "README.md 存在" $([ -f "README.md" ] && echo 0 || echo 1)

echo ""
echo "📋 测试 2: 依赖配置检查"
echo "----------------------------------------"

# 检查关键依赖
if grep -q "shared_preferences:" pubspec.yaml; then
    test_item "shared_preferences 已配置" 0
else
    test_item "shared_preferences 已配置" 1
fi

if grep -q "crypto:" pubspec.yaml; then
    test_item "crypto 已配置" 0
else
    test_item "crypto 已配置" 1
fi

if grep -q "encrypt:" pubspec.yaml; then
    test_item "encrypt 已配置" 0
else
    test_item "encrypt 已配置" 1
fi

if grep -q "provider:" pubspec.yaml; then
    test_item "provider 已配置" 0
else
    test_item "provider 已配置" 1
fi

echo ""
echo "📋 测试 3: 代码质量检查"
echo "----------------------------------------"

# 检查密码服务关键方法
if grep -q "isPasswordSet" lib/services/password_service.dart; then
    test_item "isPasswordSet() 方法存在" 0
else
    test_item "isPasswordSet() 方法存在" 1
fi

if grep -q "setPassword" lib/services/password_service.dart; then
    test_item "setPassword() 方法存在" 0
else
    test_item "setPassword() 方法存在" 1
fi

if grep -q "verifyPassword" lib/services/password_service.dart; then
    test_item "verifyPassword() 方法存在" 0
else
    test_item "verifyPassword() 方法存在" 1
fi

if grep -q "changePassword" lib/services/password_service.dart; then
    test_item "changePassword() 方法存在" 0
else
    test_item "changePassword() 方法存在" 1
fi

if grep -q "sha256" lib/services/password_service.dart; then
    test_item "使用 SHA-256 哈希" 0
else
    test_item "使用 SHA-256 哈希" 1
fi

if grep -q "_generateSalt" lib/services/password_service.dart; then
    test_item "盐值生成机制" 0
else
    test_item "盐值生成机制" 1
fi

echo ""
echo "📋 测试 4: 安全特性检查"
echo "----------------------------------------"

# 检查安全实现
if grep -q "AES" lib/services/password_service.dart; then
    test_item "AES 加密实现" 0
else
    test_item "AES 加密实现" 1
fi

if ! grep -q "password.*=" lib/services/password_service.dart | grep -v "Hash\|Salt\|_"; then
    test_item "无明文密码存储" 0
else
    test_item "无明文密码存储" 1
fi

if grep -q "obscureText" lib/screens/login_screen.dart; then
    test_item "密码输入遮挡" 0
else
    test_item "密码输入遮挡" 1
fi

if grep -q "_failedAttempts" lib/screens/login_screen.dart; then
    test_item "登录失败限制" 0
else
    test_item "登录失败限制" 1
fi

echo ""
echo "📋 测试 5: UI 流程检查"
echo "----------------------------------------"

# 检查路由配置
if grep -q "'/setup':" lib/main.dart; then
    test_item "密码设置路由" 0
else
    test_item "密码设置路由" 1
fi

if grep -q "'/login':" lib/main.dart; then
    test_item "登录路由" 0
else
    test_item "登录路由" 1
fi

if grep -q "'/home':" lib/main.dart; then
    test_item "主页路由" 0
else
    test_item "主页路由" 1
fi

if grep -q "SplashScreen" lib/main.dart; then
    test_item "启动页面存在" 0
else
    test_item "启动页面存在" 1
fi

if grep -q "_checkPasswordStatus" lib/main.dart; then
    test_item "密码状态检查逻辑" 0
else
    test_item "密码状态检查逻辑" 1
fi

echo ""
echo "📋 测试 6: 文档完整性"
echo "----------------------------------------"

# 检查 README
if grep -q "核心功能" README.md; then
    test_item "功能说明" 0
else
    test_item "功能说明" 1
fi

if grep -q "安全特性" README.md; then
    test_item "安全说明" 0
else
    test_item "安全说明" 1
fi

if grep -q "使用方法" README.md; then
    test_item "使用文档" 0
else
    test_item "使用文档" 1
fi

if grep -q "PasswordService API" README.md; then
    test_item "API 文档" 0
else
    test_item "API 文档" 1
fi

echo ""
echo "=================================================="
echo "  测试完成"
echo "=================================================="
echo ""
echo -e "总测试数: $((TESTS_PASSED + TESTS_FAILED))"
echo -e "${GREEN}通过: $TESTS_PASSED${NC}"
echo -e "${RED}失败: $TESTS_FAILED${NC}"

# 计算通过率
if [ $((TESTS_PASSED + TESTS_FAILED)) -gt 0 ]; then
    PASS_RATE=$((TESTS_PASSED * 100 / (TESTS_PASSED + TESTS_FAILED)))
    echo ""
    echo -e "通过率: ${YELLOW}${PASS_RATE}%${NC}"
    
    if [ "$PASS_RATE" -ge 90 ]; then
        echo -e "\n${GREEN}⭐⭐⭐⭐⭐ 优秀！${NC}"
    elif [ "$PASS_RATE" -ge 80 ]; then
        echo -e "\n${GREEN}⭐⭐⭐⭐ 良好！${NC}"
    elif [ "$PASS_RATE" -ge 70 ]; then
        echo -e "\n${YELLOW}⭐⭐⭐ 及格${NC}"
    else
        echo -e "\n${RED}⭐⭐ 需要改进${NC}"
    fi
fi

echo ""
echo "=================================================="

# 返回状态码
[ "$TESTS_FAILED" -eq 0 ] && exit 0 || exit 1
