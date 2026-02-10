# LLM Agent Demo

A2A protocol agent server with real LLM integration. Supports OpenAI-compatible APIs, Anthropic Claude, and ZhipuAI GLM.

## Install

```bash
pip install aiohttp
```

## Quick Start

### OpenAI GPT

```bash
export OPENAI_API_KEY=sk-xxx
python demo/llm_agent.py --provider openai --model gpt-4o --port 8080 --token test123
```

### DeepSeek

```bash
python demo/llm_agent.py --provider openai --model deepseek-chat \
    --api-base https://api.deepseek.com/v1 \
    --api-key $DEEPSEEK_API_KEY --port 8080 --token test123
```

### Qwen (DashScope)

```bash
python demo/llm_agent.py --provider openai --model qwen-plus \
    --api-base https://dashscope.aliyuncs.com/compatible-mode/v1 \
    --api-key $DASHSCOPE_API_KEY --port 8080 --token test123
```

### Local Ollama

```bash
# Start Ollama first: ollama serve && ollama pull llama3
python demo/llm_agent.py --provider openai --model llama3 \
    --api-base http://localhost:11434/v1 --port 8080 --token test123
```

### Claude

```bash
export ANTHROPIC_API_KEY=sk-ant-xxx
python demo/llm_agent.py --provider claude --model claude-sonnet-4-20250514 \
    --port 8080 --token test123
```

### GLM-4.7 (ZhipuAI BigModel)

```bash
export GLM_API_KEY=your_id.your_secret
python demo/llm_agent.py --provider glm --model glm-4.7 \
    --port 8080 --token test123
```

> GLM API Key 格式为 `{id}.{secret}`，agent 会自动生成 JWT 进行认证。

## CLI Options

| Flag | Default | Description |
|------|---------|-------------|
| `--provider` | `openai` | `openai`, `claude`, or `glm` |
| `--model` | `gpt-4o` | Model name |
| `--api-base` | auto | API endpoint URL |
| `--api-key` | env var | API key |
| `--system-prompt` | `"You are a helpful AI assistant."` | System prompt |
| `--port` | `8080` | Server port |
| `--token` | (none) | Bearer auth token |
| `--name` | `"LLM Agent"` | Agent display name |
| `--max-history` | `20` | Max conversation turns per session |
| `--no-interactive` | off | Disable interactive message directives (pure text mode) |

## Environment Variables

- `OPENAI_API_KEY` - Used when `--provider openai`
- `ANTHROPIC_API_KEY` - Used when `--provider claude`
- `GLM_API_KEY` / `ZHIPUAI_API_KEY` - Used when `--provider glm`
- `LLM_API_KEY` - Generic fallback for any provider

## Connect from Flutter App

1. Start the agent server (see examples above)
2. In the Flutter app, add a new Agent:
   - Protocol: **A2A**
   - Endpoint: `http://<your-ip>:8080/a2a/task`
   - Token: the value you passed to `--token`
3. Send a message - the response streams in real-time from the LLM

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/a2a/agent_card` | Agent metadata |
| POST | `/a2a/task` | Send message, receive SSE stream |
| POST | `/a2a/rollback` | Remove last conversation turn |
| GET | `/health` | Health check |
| GET | `/info` | Agent info |

## SSE Event Format

The `/a2a/task` endpoint returns a stream of Server-Sent Events:

```
data: {"event_type": "RUN_STARTED", "data": {"task_id": "...", ...}}

data: {"event_type": "TEXT_MESSAGE_CONTENT", "data": {"task_id": "...", "content": "Hello", "is_final": false}}
data: {"event_type": "TEXT_MESSAGE_CONTENT", "data": {"task_id": "...", "content": " world", "is_final": false}}
data: {"event_type": "TEXT_MESSAGE_CONTENT", "data": {"task_id": "...", "content": "", "is_final": true}}

data: {"event_type": "RUN_COMPLETED", "data": {"task_id": "...", "status": "success", ...}}
```

When interactive mode is enabled (the default), the LLM can also emit rich interactive events:

| Event Type | Description |
|---|---|
| `ACTION_CONFIRMATION` | Action buttons (primary / secondary / danger) |
| `SINGLE_SELECT` | Single-choice list |
| `MULTI_SELECT` | Multi-choice list |
| `FILE_UPLOAD` | File upload area |
| `FORM` | Structured form |
| `FILE_MESSAGE` | File / image sent to the user |
| `MESSAGE_METADATA` | Collapsible section metadata |

Use `--no-interactive` to disable this and revert to pure text streaming.

## Custom System Prompt

```bash
python demo/llm_agent.py --provider openai --model gpt-4o \
    --system-prompt "You are a coding assistant. Always respond with code examples." \
    --port 8080 --token test123
```
