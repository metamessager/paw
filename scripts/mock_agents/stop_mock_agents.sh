#!/bin/bash
# 停止所有 Mock Agent 服务器

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/.agent_pids"

echo "🛑 停止 Mock Agent 集群..."
echo ""

if [ ! -f "$PID_FILE" ]; then
    echo "❌ 未找到运行中的 Agent (PID 文件不存在)"
    exit 1
fi

# 读取并停止所有进程
while IFS= read -r pid; do
    if ps -p "$pid" > /dev/null 2>&1; then
        echo "   停止 PID: $pid"
        kill "$pid" 2>/dev/null || true
    else
        echo "   PID $pid 已经停止"
    fi
done < "$PID_FILE"

# 删除 PID 文件
rm -f "$PID_FILE"

echo ""
echo "✅ 所有 Mock Agent 已停止"
