#!/bin/bash

# Knot A2A 端点测试脚本
# 用于验证 Knot A2A 协议是否正常工作

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Knot A2A 端点测试脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查配置
if [ -z "$AGENT_ID" ]; then
  echo -e "${RED}错误: 请设置 AGENT_ID 环境变量${NC}"
  echo "示例: export AGENT_ID='your-agent-id'"
  exit 1
fi

if [ -z "$ENDPOINT" ]; then
  echo -e "${RED}错误: 请设置 ENDPOINT 环境变量${NC}"
  echo "示例: export ENDPOINT='http://test.knot.woa.com/apigw/v1/agents/a2a/chat/completions/xxx'"
  exit 1
fi

if [ -z "$API_TOKEN" ]; then
  echo -e "${YELLOW}警告: 未设置 API_TOKEN，可能会认证失败${NC}"
  echo "示例: export API_TOKEN='your-api-token'"
  echo "获取方式: https://knot.woa.com/settings/token"
  echo ""
fi

# 默认值
USERNAME=${USERNAME:-"anonymous"}
MESSAGE=${MESSAGE:-"Hello, Knot! Please say hi."}

# 生成 UUID (兼容 Linux 和 macOS)
generate_uuid() {
  if command -v uuidgen &> /dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

CONV_ID=$(generate_uuid)
MSG_ID=$(generate_uuid)
CALL_ID="call_$(generate_uuid)"

echo -e "${GREEN}测试配置:${NC}"
echo "  Agent ID: $AGENT_ID"
echo "  Endpoint: $ENDPOINT"
echo "  Username: $USERNAME"
echo "  Conversation ID: $CONV_ID"
echo "  Message ID: $MSG_ID"
echo "  Call ID: $CALL_ID"
echo "  Message: $MESSAGE"
echo ""

# 构建请求体
REQUEST_BODY=$(cat <<EOF
{
  "a2a": {
    "agent_cards": [],
    "request": {
      "agent_id": "$AGENT_ID",
      "id": "$CALL_ID",
      "method": "message",
      "need_history": "no",
      "params": {
        "message": {
          "context_id": "$CONV_ID",
          "kind": "message",
          "message_id": "$MSG_ID",
          "parts": [
            {
              "kind": "text",
              "text": "$MESSAGE"
            }
          ],
          "role": "user"
        }
      },
      "parent_agent_id": "",
      "parent_id": null
    }
  },
  "chat_extra": {
    "extra_header": {
      "X-Platform": "knot"
    },
    "model": "deepseek-v3.1",
    "scene_platform": "knot"
  },
  "conversation_id": "$CONV_ID",
  "is_sub_agent": true,
  "message_id": "$MSG_ID"
}
EOF
)

echo -e "${GREEN}发送请求...${NC}"
echo ""

# 发送请求
RESPONSE_FILE=$(mktemp)
HTTP_CODE=$(curl -w "%{http_code}" -o "$RESPONSE_FILE" \
  -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -H "Connection: keep-alive" \
  -H "X-Conversation-Id: $CONV_ID" \
  -H "X-Request-Id: $MSG_ID" \
  -H "X-Username: $USERNAME" \
  -H "X-Request-Platform: knot" \
  ${API_TOKEN:+-H "x-knot-api-token: $API_TOKEN"} \
  -d "$REQUEST_BODY" \
  --no-buffer \
  2>/dev/null)

echo -e "${GREEN}HTTP 状态码: $HTTP_CODE${NC}"
echo ""

if [ "$HTTP_CODE" != "200" ]; then
  echo -e "${RED}请求失败!${NC}"
  echo -e "${RED}响应内容:${NC}"
  cat "$RESPONSE_FILE"
  rm -f "$RESPONSE_FILE"
  exit 1
fi

echo -e "${GREEN}响应内容:${NC}"
echo "----------------------------------------"

# 解析流式响应
MESSAGE_BUFFER=""
LINE_COUNT=0

while IFS= read -r line; do
  # 跳过空行
  if [ -z "$line" ]; then
    continue
  fi

  # 移除 "data: " 前缀
  if [[ "$line" == data:* ]]; then
    line="${line#data:}"
    line="${line# }"
  fi

  # 检查是否为结束标志
  if [ "$line" = "[DONE]" ]; then
    echo -e "\n${GREEN}[流结束]${NC}"
    break
  fi

  LINE_COUNT=$((LINE_COUNT + 1))

  # 解析 JSON
  if command -v jq &> /dev/null; then
    # 使用 jq 美化输出
    echo -e "${YELLOW}[Chunk $LINE_COUNT]${NC}"
    
    # 提取关键信息
    MESSAGE_ID=$(echo "$line" | jq -r '.messageId // empty')
    PARTS=$(echo "$line" | jq -r '.parts[0].text // empty')
    
    if [ -n "$MESSAGE_ID" ]; then
      echo "  Message ID: $MESSAGE_ID"
    fi
    
    if [ -n "$PARTS" ]; then
      # 尝试解析 AGUI 事件
      EVENT_TYPE=$(echo "$PARTS" | jq -r '.type // empty' 2>/dev/null)
      
      if [ -n "$EVENT_TYPE" ]; then
        echo "  Event Type: $EVENT_TYPE"
        
        # 提取消息内容
        CONTENT=$(echo "$PARTS" | jq -r '.rawEvent.content // empty' 2>/dev/null)
        if [ -n "$CONTENT" ]; then
          echo "  Content: $CONTENT"
          MESSAGE_BUFFER="${MESSAGE_BUFFER}${CONTENT}"
        fi
        
        # 提取错误信息
        ERROR=$(echo "$PARTS" | jq -r '.rawEvent.tip_option.content // empty' 2>/dev/null)
        if [ -n "$ERROR" ]; then
          echo -e "  ${RED}Error: $ERROR${NC}"
        fi
      else
        echo "  Text: $PARTS"
      fi
    fi
    
    echo ""
  else
    # 不使用 jq，直接输出原始 JSON
    echo "$line"
    echo ""
  fi
done < "$RESPONSE_FILE"

echo "----------------------------------------"
echo ""

if [ -n "$MESSAGE_BUFFER" ]; then
  echo -e "${GREEN}完整回复:${NC}"
  echo "$MESSAGE_BUFFER"
  echo ""
fi

echo -e "${GREEN}测试完成!${NC}"

# 清理
rm -f "$RESPONSE_FILE"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}使用说明:${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "1. 设置环境变量:"
echo "   export AGENT_ID='your-agent-id'"
echo "   export ENDPOINT='http://test.knot.woa.com/apigw/v1/agents/a2a/chat/completions/xxx'"
echo "   export API_TOKEN='your-api-token'"
echo "   export USERNAME='your-rtx'"
echo ""
echo "2. 运行测试:"
echo "   ./scripts/test_knot_a2a.sh"
echo ""
echo "3. 自定义消息:"
echo "   MESSAGE='你的问题' ./scripts/test_knot_a2a.sh"
echo ""
