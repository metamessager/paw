#!/bin/bash

# P0/P1 完成验证脚本
echo "======================================"
echo "  AI Agent Hub - P0/P1 验证脚本"
echo "======================================"
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✓${NC} $1"
        return 0
    else
        echo -e "${RED}✗${NC} $1 (缺失)"
        return 1
    fi
}

check_dir() {
    if [ -d "$1" ]; then
        echo -e "${GREEN}✓${NC} $1/"
        return 0
    else
        echo -e "${RED}✗${NC} $1/ (缺失)"
        return 1
    fi
}

echo "📋 检查 P0 任务..."
echo ""

echo "1️⃣  Android 配置"
check_file "android/build.gradle"
check_file "android/app/build.gradle"
check_file "android/app/src/main/AndroidManifest.xml"
check_file "android/app/src/main/kotlin/com/example/ai_agent_hub/MainActivity.kt"
echo ""

echo "2️⃣  环境配置"
check_file "lib/config/app_config.dart"
echo ""

echo "3️⃣  资源目录"
check_dir "assets/images"
check_dir "assets/icons"
check_dir "fonts"
echo ""

echo "4️⃣  单元测试"
check_dir "test"
check_file "test/config/app_config_test.dart"
check_file "test/utils/exceptions_test.dart"
check_file "test/models/user_test.dart"
check_file "test/models/agent_test.dart"
echo ""

echo "📋 检查 P1 任务..."
echo ""

echo "5️⃣  错误处理和日志"
check_file "lib/utils/logger.dart"
check_file "lib/utils/exceptions.dart"
echo ""

echo "6️⃣  网络层增强"
check_file "lib/utils/http_client.dart"
echo ""

echo "7️⃣  安全加固"
check_file "lib/services/secure_key_manager.dart"
echo ""

echo "======================================"
echo "  验证完成"
echo "======================================"
echo ""

echo -e "${YELLOW}建议操作:${NC}"
echo "1. 运行 'flutter pub get' 安装依赖"
echo "2. 运行 'flutter test' 执行测试"
echo "3. 运行 'flutter analyze' 代码分析"
echo "4. 补充资源文件 (logo、图标、字体)"
echo ""

echo -e "${YELLOW}快速测试:${NC}"
echo "flutter run --dart-define=ENV=development"
echo ""
