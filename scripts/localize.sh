#!/bin/bash

# AI Agent Hub 本地化改造自动化脚本
# 用途：自动替换 UI 层的服务调用

echo "🚀 开始本地化改造..."

# 1. 安装依赖
echo "📦 步骤 1: 安装依赖..."
flutter pub get

# 2. 替换 agent_list_screen.dart
echo "🔧 步骤 2: 更新 agent_list_screen.dart..."
sed -i "s|import '../services/api_service.dart'|import '../services/local_api_service.dart'|g" lib/screens/agent_list_screen.dart
sed -i 's/ApiService()/LocalApiService()/g' lib/screens/agent_list_screen.dart
sed -i 's/final ApiService _apiService/final LocalApiService _apiService/g' lib/screens/agent_list_screen.dart

# 3. 替换 agent_detail_screen.dart
echo "🔧 步骤 3: 更新 agent_detail_screen.dart..."
sed -i "s|import '../services/api_service.dart'|import '../services/local_api_service.dart'|g" lib/screens/agent_detail_screen.dart
sed -i 's/ApiService()/LocalApiService()/g' lib/screens/agent_detail_screen.dart
sed -i 's/final ApiService _apiService/final LocalApiService _apiService/g' lib/screens/agent_detail_screen.dart

# 4. 替换 channel_list_screen.dart
echo "🔧 步骤 4: 更新 channel_list_screen.dart..."
sed -i "s|import '../services/api_service.dart'|import '../services/local_api_service.dart'|g" lib/screens/channel_list_screen.dart
sed -i 's/ApiService()/LocalApiService()/g' lib/screens/channel_list_screen.dart
sed -i 's/final ApiService _apiService/final LocalApiService _apiService/g' lib/screens/channel_list_screen.dart

# 5. 替换 app_state.dart
echo "🔧 步骤 5: 更新 app_state.dart..."
sed -i "s|import '../services/api_service.dart'|import '../services/local_api_service.dart'|g" lib/providers/app_state.dart
sed -i 's/ApiService()/LocalApiService()/g' lib/providers/app_state.dart
sed -i 's/final ApiService _apiService/final LocalApiService _apiService/g' lib/providers/app_state.dart

# 6. 替换 Knot 相关的服务
echo "🔧 步骤 6: 更新 Knot Agent 服务调用..."
find lib/screens -name "knot_*.dart" -exec sed -i "s|import '../services/knot_api_service.dart'|import '../services/local_knot_agent_service.dart'|g" {} \;
find lib/screens -name "knot_*.dart" -exec sed -i 's/KnotApiService()/LocalKnotAgentService()/g' {} \;
find lib/screens -name "knot_*.dart" -exec sed -i 's/final KnotApiService _knotService/final LocalKnotAgentService _knotService/g' {} \;

# 7. 格式化代码
echo "✨ 步骤 7: 格式化代码..."
flutter format lib/

# 8. 分析代码
echo "🔍 步骤 8: 分析代码..."
flutter analyze --no-fatal-infos

echo ""
echo "✅ 本地化改造完成！"
echo ""
echo "📋 下一步操作："
echo "   1. 运行应用: flutter run"
echo "   2. 测试功能: Agent 管理、Channel 管理、消息发送"
echo "   3. 查看文档: docs/LOCALIZATION_REPORT.md"
echo ""
