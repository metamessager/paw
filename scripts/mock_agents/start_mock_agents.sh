#!/bin/bash
# 启动多个 Mock Agent 服务器用于测试

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${PYTHON:-python3}"

echo "=========================================="
echo "🚀 启动 Mock Agent 集群"
echo "=========================================="
echo ""

# 检查 Python 和依赖
if ! command -v $PYTHON &> /dev/null; then
    echo "❌ 错误: 找不到 Python 3"
    exit 1
fi

# 检查 aiohttp
if ! $PYTHON -c "import aiohttp" 2>/dev/null; then
    echo "📦 安装依赖: aiohttp"
    pip install aiohttp
fi

# 创建日志目录
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# 清理旧日志
rm -f "$LOG_DIR"/*.log

# 启动 Agent 1: Knot Agent (快速响应)
echo "▶️  启动 Agent 1: Knot Agent (端口 8081)"
$PYTHON "$SCRIPT_DIR/mock_a2a_server.py" \
    --port 8081 \
    --agent-type knot \
    --agent-name "Knot-Fast" \
    --delay 0.05 \
    > "$LOG_DIR/agent-knot-fast.log" 2>&1 &
AGENT1_PID=$!
echo "   PID: $AGENT1_PID"

sleep 1

# 启动 Agent 2: Smart Agent (带思考过程)
echo "▶️  启动 Agent 2: Smart Agent (端口 8082)"
$PYTHON "$SCRIPT_DIR/mock_a2a_server.py" \
    --port 8082 \
    --agent-type smart \
    --agent-name "Smart-Thinker" \
    --delay 0.1 \
    > "$LOG_DIR/agent-smart.log" 2>&1 &
AGENT2_PID=$!
echo "   PID: $AGENT2_PID"

sleep 1

# 启动 Agent 3: Slow Agent (模拟大模型)
echo "▶️  启动 Agent 3: Slow Agent (端口 8083)"
$PYTHON "$SCRIPT_DIR/mock_a2a_server.py" \
    --port 8083 \
    --agent-type slow \
    --agent-name "Slow-LLM" \
    --delay 0.2 \
    > "$LOG_DIR/agent-slow.log" 2>&1 &
AGENT3_PID=$!
echo "   PID: $AGENT3_PID"

sleep 1

# 启动 Agent 4: Error Agent (测试错误处理)
echo "▶️  启动 Agent 4: Error Agent (端口 8084)"
$PYTHON "$SCRIPT_DIR/mock_a2a_server.py" \
    --port 8084 \
    --agent-type error \
    --agent-name "Error-Test" \
    --delay 0.1 \
    --error-rate 0.3 \
    > "$LOG_DIR/agent-error.log" 2>&1 &
AGENT4_PID=$!
echo "   PID: $AGENT4_PID"

sleep 2

echo ""
echo "=========================================="
echo "✅ Mock Agent 集群已启动"
echo "=========================================="
echo ""
echo "📡 Agent 列表:"
echo ""
echo "1. Knot-Fast (快速响应)"
echo "   URL: http://localhost:8081/a2a/task"
echo "   Card: http://localhost:8081/a2a/agent_card"
echo "   Health: http://localhost:8081/health"
echo ""
echo "2. Smart-Thinker (带思考过程)"
echo "   URL: http://localhost:8082/a2a/task"
echo "   Card: http://localhost:8082/a2a/agent_card"
echo "   Health: http://localhost:8082/health"
echo ""
echo "3. Slow-LLM (模拟大模型)"
echo "   URL: http://localhost:8083/a2a/task"
echo "   Card: http://localhost:8083/a2a/agent_card"
echo "   Health: http://localhost:8083/health"
echo ""
echo "4. Error-Test (30%错误率)"
echo "   URL: http://localhost:8084/a2a/task"
echo "   Card: http://localhost:8084/a2a/agent_card"
echo "   Health: http://localhost:8084/health"
echo ""
echo "=========================================="
echo "📝 日志目录: $LOG_DIR"
echo ""
echo "💡 测试命令:"
echo "   curl http://localhost:8081/health"
echo "   curl http://localhost:8081/a2a/agent_card"
echo ""
echo "🛑 停止所有 Agent:"
echo "   kill $AGENT1_PID $AGENT2_PID $AGENT3_PID $AGENT4_PID"
echo "   或运行: ./stop_mock_agents.sh"
echo "=========================================="
echo ""

# 保存 PID 到文件
echo "$AGENT1_PID" > "$SCRIPT_DIR/.agent_pids"
echo "$AGENT2_PID" >> "$SCRIPT_DIR/.agent_pids"
echo "$AGENT3_PID" >> "$SCRIPT_DIR/.agent_pids"
echo "$AGENT4_PID" >> "$SCRIPT_DIR/.agent_pids"

# 等待用户中断
echo "⏳ 按 Ctrl+C 停止所有 Agent..."
echo ""

# 捕获 Ctrl+C
trap "echo ''; echo '🛑 停止所有 Agent...'; kill $AGENT1_PID $AGENT2_PID $AGENT3_PID $AGENT4_PID 2>/dev/null; rm -f '$SCRIPT_DIR/.agent_pids'; echo '✅ 已停止'; exit 0" INT

# 持续运行
wait
