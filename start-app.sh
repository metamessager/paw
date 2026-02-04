#!/bin/bash

# AI Agent Hub - 一键启动脚本

echo "=================================================="
echo "  AI Agent Hub - 快速启动"
echo "=================================================="
echo ""

PROJECT_DIR="/projects/clawd/ai-agent-hub"
cd "$PROJECT_DIR" || exit 1

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}📦 检查依赖...${NC}"
if [ ! -d "build" ]; then
    echo "首次运行，正在安装依赖..."
    flutter pub get
fi

echo ""
echo -e "${BLUE}🧪 运行测试...${NC}"
./test-password-system.sh

echo ""
echo -e "${GREEN}✅ 测试通过！${NC}"
echo ""

echo -e "${BLUE}🚀 启动应用...${NC}"
echo ""
echo "选择运行平台："
echo "  1) Web (Chrome)"
echo "  2) Android"
echo "  3) iOS"
echo "  4) 查看所有设备"
echo ""
read -p "请选择 [1-4]: " choice

case $choice in
    1)
        echo -e "${GREEN}启动 Web 版本...${NC}"
        flutter run -d chrome
        ;;
    2)
        echo -e "${GREEN}启动 Android 版本...${NC}"
        flutter run -d android
        ;;
    3)
        echo -e "${GREEN}启动 iOS 版本...${NC}"
        flutter run -d ios
        ;;
    4)
        echo -e "${YELLOW}可用设备：${NC}"
        flutter devices
        echo ""
        read -p "请输入设备ID: " device_id
        flutter run -d "$device_id"
        ;;
    *)
        echo -e "${YELLOW}无效选择，启动 Web 版本...${NC}"
        flutter run -d chrome
        ;;
esac
