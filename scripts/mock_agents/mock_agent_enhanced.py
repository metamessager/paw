#!/usr/bin/env python3
"""
Enhanced Mock Agent Server - 支持 A2A 和 ACP 协议的模拟 Agent

特性：
- 支持 A2A 协议 (REST + Server-Sent Events)
- 支持 ACP 协议 (WebSocket + JSON-RPC 2.0)
- Token 认证
- 可配置的响应行为

使用方法：
    # 启动 A2A Agent
    python mock_agent_enhanced.py --protocol a2a --port 8080 --token my-secret-token

    # 启动 ACP Agent
    python mock_agent_enhanced.py --protocol acp --port 18080 --token agent-token-123

    # 双协议模式（同时支持 A2A 和 ACP）
    python mock_agent_enhanced.py --protocol both --port 8080 --ws-port 18080 --token my-token

环境变量：
    AGENT_PROTOCOL=a2a|acp|both
    AGENT_PORT=8080
    AGENT_WS_PORT=18080
    AGENT_TOKEN=your-token-here
    AGENT_NAME="My Test Agent"
"""

import asyncio
import json
import time
import uuid
import argparse
import os
import sys
from datetime import datetime
from typing import AsyncGenerator, Dict, Optional
from dataclasses import dataclass

try:
    from aiohttp import web
    import aiohttp
except ImportError:
    print("❌ 需要安装 aiohttp: pip install aiohttp")
    sys.exit(1)


# ==================== 配置 ====================

@dataclass
class AgentConfig:
    """Agent 配置"""
    agent_id: str
    agent_name: str
    protocol: str  # a2a, acp, both
    port: int
    ws_port: Optional[int]
    token: str
    response_delay: float = 0.1
    simulate_thinking: bool = True
    simulate_tool_calls: bool = False


# ==================== Token 验证 ====================

def verify_token(request: web.Request, config: AgentConfig) -> bool:
    """验证请求的 Token"""
    # 从 Authorization header 获取
    auth_header = request.headers.get('Authorization', '')
    if auth_header.startswith('Bearer '):
        token = auth_header[7:]
        return token == config.token

    # 从 query parameter 获取
    token = request.query.get('token', '')
    if token == config.token:
        return True

    # 从 body 获取（如果是 JSON）
    if request.can_read_body:
        try:
            body = request.get('_cached_body')
            if body and 'token' in body:
                return body.get('token') == config.token
        except:
            pass

    return False


# ==================== A2A 协议实现 ====================

class A2AProtocol:
    """A2A 协议处理器"""

    @staticmethod
    async def handle_agent_card(request: web.Request) -> web.Response:
        """返回 Agent Card"""
        config: AgentConfig = request.app['config']

        card = {
            "agent_id": config.agent_id,
            "name": config.agent_name,
            "description": f"Mock {config.protocol.upper()} Agent for testing",
            "version": "1.0.0",
            "capabilities": [
                "chat",
                "streaming",
                "task_execution"
            ],
            "supported_protocols": ["a2a"] if config.protocol == "a2a" else ["a2a", "acp"],
            "metadata": {
                "framework": "Mock Agent Enhanced",
                "created_at": datetime.now().isoformat(),
                "endpoint": f"http://localhost:{config.port}/a2a/task"
            }
        }

        return web.json_response(card)

    @staticmethod
    async def handle_task(request: web.Request) -> web.StreamResponse:
        """处理 A2A 任务请求（流式响应）"""
        config: AgentConfig = request.app['config']

        # Token 验证
        if config.token and not verify_token(request, config):
            return web.json_response(
                {"error": "Unauthorized", "message": "Invalid or missing token"},
                status=401
            )

        # 解析请求
        try:
            data = await request.json()
        except:
            return web.json_response(
                {"error": "Invalid JSON"},
                status=400
            )

        task_id = data.get('task_id', str(uuid.uuid4()))
        input_text = data.get('a2a', {}).get('input', '')

        if not input_text:
            return web.json_response(
                {"error": "Missing input"},
                status=400
            )

        # 设置 SSE 响应
        response = web.StreamResponse(
            status=200,
            reason='OK',
            headers={
                'Content-Type': 'text/event-stream',
                'Cache-Control': 'no-cache',
                'Connection': 'keep-alive',
                'X-Accel-Buffering': 'no',
            }
        )
        await response.prepare(request)

        # 生成事件流
        async for event in A2AProtocol._generate_events(task_id, input_text, config):
            await response.write(event.encode('utf-8'))
            await response.drain()

        await response.write_eof()
        return response

    @staticmethod
    async def _generate_events(
        task_id: str,
        input_text: str,
        config: AgentConfig
    ) -> AsyncGenerator[str, None]:
        """生成 A2A 事件流"""

        # 1. RUN_STARTED
        yield A2AProtocol._create_sse_event({
            "event_type": "RUN_STARTED",
            "data": {
                "task_id": task_id,
                "agent_id": config.agent_id,
                "started_at": datetime.now().isoformat()
            }
        })
        await asyncio.sleep(config.response_delay)

        # 2. 思考过程
        if config.simulate_thinking:
            thoughts = [
                "收到用户消息，正在分析...",
                f"理解了：{input_text[:50]}...",
                "准备生成回复..."
            ]
            for thought in thoughts:
                yield A2AProtocol._create_sse_event({
                    "event_type": "THOUGHT_MESSAGE",
                    "data": {
                        "task_id": task_id,
                        "thought": thought
                    }
                })
                await asyncio.sleep(config.response_delay)

        # 3. 工具调用
        if config.simulate_tool_calls:
            tool_call_id = f"call_{uuid.uuid4().hex[:8]}"

            # 工具调用开始
            yield A2AProtocol._create_sse_event({
                "event_type": "TOOL_CALL_STARTED",
                "data": {
                    "task_id": task_id,
                    "tool_call_id": tool_call_id,
                    "tool_name": "search",
                    "tool_input": json.dumps({"query": input_text})
                }
            })
            await asyncio.sleep(config.response_delay * 2)

            # 工具调用完成
            yield A2AProtocol._create_sse_event({
                "event_type": "TOOL_CALL_COMPLETED",
                "data": {
                    "task_id": task_id,
                    "tool_call_id": tool_call_id,
                    "tool_output": json.dumps({"results": ["Result 1", "Result 2"]})
                }
            })
            await asyncio.sleep(config.response_delay)

        # 4. 流式文本响应
        response_text = f"这是 {config.agent_name} 的回复。\n\n"
        response_text += f"你的消息是：{input_text}\n\n"
        response_text += f"我已经成功处理了你的请求。"
        response_text += f"当前时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"

        # 分段发送
        chunks = [response_text[i:i+30] for i in range(0, len(response_text), 30)]
        for i, chunk in enumerate(chunks):
            yield A2AProtocol._create_sse_event({
                "event_type": "TEXT_MESSAGE_CONTENT",
                "data": {
                    "task_id": task_id,
                    "content": chunk,
                    "is_final": i == len(chunks) - 1
                }
            })
            await asyncio.sleep(config.response_delay)

        # 5. RUN_COMPLETED
        yield A2AProtocol._create_sse_event({
            "event_type": "RUN_COMPLETED",
            "data": {
                "task_id": task_id,
                "status": "success",
                "completed_at": datetime.now().isoformat()
            }
        })

    @staticmethod
    def _create_sse_event(data: Dict) -> str:
        """创建 SSE 事件"""
        return f"data: {json.dumps(data)}\n\n"


# ==================== ACP 协议实现 ====================

class ACPProtocol:
    """ACP (Agent Client Protocol) 协议处理器 - JSON-RPC 2.0 over WebSocket"""

    @staticmethod
    async def handle_websocket(request: web.Request) -> web.WebSocketResponse:
        """处理 WebSocket 连接"""
        config: AgentConfig = request.app['config']

        # Token 验证
        if config.token:
            token = request.query.get('token', '')
            if token != config.token:
                ws = web.WebSocketResponse()
                await ws.prepare(request)
                await ws.send_json({
                    "jsonrpc": "2.0",
                    "error": {
                        "code": -32001,
                        "message": "Unauthorized"
                    },
                    "id": None
                })
                await ws.close()
                return ws

        ws = web.WebSocketResponse()
        await ws.prepare(request)

        print(f"✅ WebSocket 连接建立")

        try:
            async for msg in ws:
                if msg.type == aiohttp.WSMsgType.TEXT:
                    try:
                        data = json.loads(msg.data)
                        response = await ACPProtocol._handle_jsonrpc(data, config)

                        # 如果是流式响应
                        if isinstance(response, list):
                            for item in response:
                                await ws.send_json(item)
                                await asyncio.sleep(config.response_delay)
                        else:
                            await ws.send_json(response)

                    except json.JSONDecodeError:
                        await ws.send_json({
                            "jsonrpc": "2.0",
                            "error": {
                                "code": -32700,
                                "message": "Parse error"
                            },
                            "id": None
                        })

                elif msg.type == aiohttp.WSMsgType.ERROR:
                    print(f'❌ WebSocket error: {ws.exception()}')

        finally:
            print(f"🔌 WebSocket 连接关闭")

        return ws

    @staticmethod
    async def _handle_jsonrpc(request: Dict, config: AgentConfig) -> Dict:
        """处理 JSON-RPC 请求"""
        method = request.get('method')
        params = request.get('params', {})
        request_id = request.get('id')

        if method == 'agent.register':
            return {
                "jsonrpc": "2.0",
                "result": {
                    "agent_id": config.agent_id,
                    "name": config.agent_name,
                    "status": "registered",
                    "timestamp": datetime.now().isoformat()
                },
                "id": request_id
            }

        elif method == 'agent.heartbeat':
            return {
                "jsonrpc": "2.0",
                "result": {
                    "status": "alive",
                    "timestamp": datetime.now().isoformat()
                },
                "id": request_id
            }

        elif method == 'chat':
            # 流式聊天响应
            message = params.get('message', '')
            return await ACPProtocol._generate_chat_stream(message, config, request_id)

        elif method == 'task.execute':
            instruction = params.get('instruction', '')
            return await ACPProtocol._execute_task(instruction, config, request_id)

        else:
            return {
                "jsonrpc": "2.0",
                "error": {
                    "code": -32601,
                    "message": f"Method not found: {method}"
                },
                "id": request_id
            }

    @staticmethod
    async def _generate_chat_stream(message: str, config: AgentConfig, request_id) -> list:
        """生成聊天流式响应"""
        responses = []

        # 开始
        responses.append({
            "jsonrpc": "2.0",
            "result": {
                "type": "chat.started",
                "timestamp": datetime.now().isoformat()
            },
            "id": request_id
        })

        # 流式内容
        reply = f"[{config.agent_name}] 收到消息: {message}\n这是我的回复。"
        chunks = [reply[i:i+20] for i in range(0, len(reply), 20)]

        for chunk in chunks:
            responses.append({
                "jsonrpc": "2.0",
                "result": {
                    "type": "chat.content",
                    "content": chunk
                },
                "id": request_id
            })

        # 完成
        responses.append({
            "jsonrpc": "2.0",
            "result": {
                "type": "chat.completed",
                "timestamp": datetime.now().isoformat()
            },
            "id": request_id
        })

        return responses

    @staticmethod
    async def _execute_task(instruction: str, config: AgentConfig, request_id) -> Dict:
        """执行任务"""
        return {
            "jsonrpc": "2.0",
            "result": {
                "task_id": str(uuid.uuid4()),
                "status": "completed",
                "result": f"Task executed: {instruction}",
                "timestamp": datetime.now().isoformat()
            },
            "id": request_id
        }


# ==================== HTTP Server ====================

async def handle_health(request: web.Request) -> web.Response:
    """健康检查"""
    config: AgentConfig = request.app['config']
    return web.json_response({
        "status": "healthy",
        "agent_id": config.agent_id,
        "agent_name": config.agent_name,
        "protocol": config.protocol,
        "timestamp": datetime.now().isoformat()
    })


async def handle_info(request: web.Request) -> web.Response:
    """Agent 信息"""
    config: AgentConfig = request.app['config']
    return web.json_response({
        "agent_id": config.agent_id,
        "name": config.agent_name,
        "protocol": config.protocol,
        "endpoints": {
            "a2a": f"http://localhost:{config.port}/a2a/task" if config.protocol in ["a2a", "both"] else None,
            "acp": f"ws://localhost:{config.ws_port or config.port}/acp" if config.protocol in ["acp", "both"] else None,
            "health": f"http://localhost:{config.port}/health",
            "info": f"http://localhost:{config.port}/info"
        },
        "auth": "Bearer token required" if config.token else "No auth required",
        "features": {
            "streaming": True,
            "thinking": config.simulate_thinking,
            "tools": config.simulate_tool_calls
        }
    })


def create_app(config: AgentConfig) -> web.Application:
    """创建 Web 应用"""
    app = web.Application()
    app['config'] = config

    # 通用路由
    app.router.add_get('/health', handle_health)
    app.router.add_get('/info', handle_info)

    # A2A 路由
    if config.protocol in ['a2a', 'both']:
        app.router.add_get('/a2a/agent_card', A2AProtocol.handle_agent_card)
        app.router.add_post('/a2a/task', A2AProtocol.handle_task)

    # ACP 路由
    if config.protocol in ['acp', 'both']:
        app.router.add_get('/acp', ACPProtocol.handle_websocket)

    return app


# ==================== Main ====================

def parse_args():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(description='Enhanced Mock Agent Server')

    parser.add_argument('--protocol',
                       default=os.getenv('AGENT_PROTOCOL', 'both'),
                       choices=['a2a', 'acp', 'both'],
                       help='Protocol to support (default: both)')

    parser.add_argument('--port',
                       type=int,
                       default=int(os.getenv('AGENT_PORT', '8080')),
                       help='HTTP port (default: 8080)')

    parser.add_argument('--ws-port',
                       type=int,
                       default=int(os.getenv('AGENT_WS_PORT', '0')),
                       help='WebSocket port for ACP (default: same as --port)')

    parser.add_argument('--token',
                       default=os.getenv('AGENT_TOKEN', ''),
                       help='Authentication token (optional)')

    parser.add_argument('--name',
                       default=os.getenv('AGENT_NAME', 'Mock Agent'),
                       help='Agent name')

    parser.add_argument('--agent-id',
                       default=os.getenv('AGENT_ID', f'agent_{uuid.uuid4().hex[:8]}'),
                       help='Agent ID')

    parser.add_argument('--delay',
                       type=float,
                       default=float(os.getenv('RESPONSE_DELAY', '0.1')),
                       help='Response delay in seconds (default: 0.1)')

    parser.add_argument('--thinking',
                       action='store_true',
                       default=os.getenv('SIMULATE_THINKING', 'true').lower() == 'true',
                       help='Simulate thinking process')

    parser.add_argument('--tools',
                       action='store_true',
                       default=os.getenv('SIMULATE_TOOLS', 'false').lower() == 'true',
                       help='Simulate tool calls')

    return parser.parse_args()


def main():
    """主函数"""
    args = parse_args()

    # 创建配置
    config = AgentConfig(
        agent_id=args.agent_id,
        agent_name=args.name,
        protocol=args.protocol,
        port=args.port,
        ws_port=args.ws_port if args.ws_port > 0 else args.port,
        token=args.token,
        response_delay=args.delay,
        simulate_thinking=args.thinking,
        simulate_tool_calls=args.tools
    )

    # 打印启动信息
    print("=" * 60)
    print(f"🚀 Enhanced Mock Agent Server")
    print("=" * 60)
    print(f"  Agent ID:   {config.agent_id}")
    print(f"  Agent Name: {config.agent_name}")
    print(f"  Protocol:   {config.protocol.upper()}")
    print(f"  Port:       {config.port}")
    if config.protocol in ['acp', 'both'] and config.ws_port != config.port:
        print(f"  WS Port:    {config.ws_port}")
    print(f"  Auth:       {'✅ Token required' if config.token else '❌ No auth'}")
    print(f"  Features:   Thinking={config.simulate_thinking}, Tools={config.simulate_tool_calls}")
    print("-" * 60)

    # 打印端点信息
    if config.protocol in ['a2a', 'both']:
        print(f"  A2A Agent Card: http://localhost:{config.port}/a2a/agent_card")
        print(f"  A2A Task:       http://localhost:{config.port}/a2a/task")

    if config.protocol in ['acp', 'both']:
        ws_port = config.ws_port if config.ws_port != config.port else config.port
        print(f"  ACP WebSocket:  ws://localhost:{ws_port}/acp")
        if config.token:
            print(f"  ACP (w/ token): ws://localhost:{ws_port}/acp?token={config.token}")

    print(f"  Health Check:   http://localhost:{config.port}/health")
    print(f"  Info:           http://localhost:{config.port}/info")
    print("-" * 60)

    if config.token:
        print(f"  🔑 Token: {config.token}")
        print(f"  📝 Usage: Authorization: Bearer {config.token}")
        print("-" * 60)

    print(f"\n✅ Server is running... Press Ctrl+C to stop\n")

    # 启动服务器
    app = create_app(config)
    web.run_app(app, host='0.0.0.0', port=config.port)


if __name__ == '__main__':
    main()
