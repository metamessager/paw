#!/usr/bin/env python3
"""
Mock A2A Agent Server - 模拟远端 A2A Agent

用途：
- 模拟 Knot A2A 协议的远端 Agent
- 支持流式响应和 AGUI 事件
- 用于测试 AI Agent Hub 的 A2A 集成

使用方法：
    python mock_a2a_server.py --port 8080 --agent-type knot
    python mock_a2a_server.py --port 8081 --agent-type smart --delay 0.5

环境变量：
    MOCK_AGENT_PORT=8080
    MOCK_AGENT_TYPE=knot
    MOCK_RESPONSE_DELAY=0.1
"""

import asyncio
import json
import time
import uuid
from datetime import datetime
from typing import AsyncGenerator, Dict, List, Optional
from dataclasses import dataclass, asdict
import argparse
import os

try:
    from aiohttp import web
except ImportError:
    print("❌ 需要安装 aiohttp: pip install aiohttp")
    exit(1)


# ==================== 配置 ====================

@dataclass
class MockAgentConfig:
    """Mock Agent 配置"""
    agent_id: str
    agent_name: str
    agent_type: str  # knot, smart, slow, error
    response_delay: float  # 每个事件的延迟（秒）
    simulate_thinking: bool  # 是否模拟思考过程
    simulate_tool_calls: bool  # 是否模拟工具调用
    error_probability: float  # 错误概率 (0-1)


# ==================== AGUI 事件生成器 ====================

class AGUIEventGenerator:
    """生成模拟的 AGUI 事件流"""
    
    @staticmethod
    async def generate_events(
        task_id: str,
        input_text: str,
        config: MockAgentConfig
    ) -> AsyncGenerator[str, None]:
        """生成完整的 AGUI 事件流"""
        
        # 1. RUN_STARTED
        yield AGUIEventGenerator._create_event(
            "RUN_STARTED",
            {
                "task_id": task_id,
                "agent_id": config.agent_id,
                "agent_name": config.agent_name,
                "started_at": datetime.now().isoformat()
            }
        )
        await asyncio.sleep(config.response_delay)
        
        # 2. 模拟思考过程（如果启用）
        if config.simulate_thinking:
            thoughts = [
                "正在分析用户的问题...",
                "理解了，这是一个关于测试的请求。",
                "准备生成回复..."
            ]
            for thought in thoughts:
                yield AGUIEventGenerator._create_event(
                    "THOUGHT_MESSAGE",
                    {
                        "task_id": task_id,
                        "thought": thought,
                        "timestamp": datetime.now().isoformat()
                    }
                )
                await asyncio.sleep(config.response_delay)
        
        # 3. 模拟工具调用（如果启用）
        if config.simulate_tool_calls:
            # 工具调用开始
            tool_call_id = f"call_{uuid.uuid4().hex[:8]}"
            yield AGUIEventGenerator._create_event(
                "TOOL_CALL_STARTED",
                {
                    "task_id": task_id,
                    "tool_call_id": tool_call_id,
                    "tool_name": "search_database",
                    "tool_input": json.dumps({"query": input_text}),
                    "timestamp": datetime.now().isoformat()
                }
            )
            await asyncio.sleep(config.response_delay * 2)
            
            # 工具调用完成
            yield AGUIEventGenerator._create_event(
                "TOOL_CALL_COMPLETED",
                {
                    "task_id": task_id,
                    "tool_call_id": tool_call_id,
                    "tool_name": "search_database",
                    "tool_output": json.dumps({"results": ["测试结果1", "测试结果2"]}),
                    "timestamp": datetime.now().isoformat()
                }
            )
            await asyncio.sleep(config.response_delay)
        
        # 4. 生成回复内容（分段流式）
        response_text = AGUIEventGenerator._generate_response(input_text, config)
        chunks = AGUIEventGenerator._split_into_chunks(response_text, chunk_size=20)
        
        for i, chunk in enumerate(chunks):
            yield AGUIEventGenerator._create_event(
                "TEXT_MESSAGE_CONTENT",
                {
                    "task_id": task_id,
                    "content": chunk,
                    "is_final": i == len(chunks) - 1,
                    "timestamp": datetime.now().isoformat()
                }
            )
            await asyncio.sleep(config.response_delay)
        
        # 5. RUN_COMPLETED
        yield AGUIEventGenerator._create_event(
            "RUN_COMPLETED",
            {
                "task_id": task_id,
                "status": "success",
                "completed_at": datetime.now().isoformat(),
                "total_tokens": len(response_text)
            }
        )
    
    @staticmethod
    def _create_event(event_type: str, data: Dict) -> str:
        """创建 SSE 格式的事件"""
        event = {
            "event_type": event_type,
            "event_id": uuid.uuid4().hex,
            "timestamp": datetime.now().isoformat(),
            "data": data
        }
        return f"data: {json.dumps(event)}\n\n"
    
    @staticmethod
    def _generate_response(input_text: str, config: MockAgentConfig) -> str:
        """生成模拟的回复内容"""
        responses = {
            "knot": f"[Knot Agent {config.agent_name}] 收到您的请求：「{input_text}」\n\n这是一个模拟的 Knot A2A 响应。我已经理解了您的问题，并准备好进行测试。\n\n当前时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\nAgent ID: {config.agent_id}\n\n测试成功！✅",
            
            "smart": f"💡 智能 Agent 分析结果：\n\n您的输入：{input_text}\n\n经过深度分析，我认为这是一个测试请求。以下是我的建议：\n\n1. 首先验证基础功能\n2. 然后进行集成测试\n3. 最后进行性能测试\n\n希望这些建议对您有帮助！",
            
            "slow": f"🐢 慢速 Agent（模拟大模型）：\n\n正在处理您的请求...\n\n{input_text}\n\n这是一个模拟的慢速响应，用于测试流式渲染和 UI 更新。每个字符都会逐步返回，就像真实的大模型一样。\n\n测试完成！",
            
            "error": f"⚠️ 错误测试 Agent：\n\n您的请求：{input_text}\n\n注意：这个 Agent 可能会随机产生错误，用于测试错误处理机制。"
        }
        
        return responses.get(config.agent_type, responses["knot"])
    
    @staticmethod
    def _split_into_chunks(text: str, chunk_size: int = 20) -> List[str]:
        """将文本分割成小块（模拟流式响应）"""
        chunks = []
        for i in range(0, len(text), chunk_size):
            chunks.append(text[i:i + chunk_size])
        return chunks


# ==================== Mock A2A Server ====================

class MockA2AServer:
    """Mock A2A Agent Server"""
    
    def __init__(self, config: MockAgentConfig):
        self.config = config
        self.app = web.Application()
        self.setup_routes()
    
    def setup_routes(self):
        """设置路由"""
        self.app.router.add_post('/a2a/task', self.handle_task)
        self.app.router.add_get('/a2a/agent_card', self.handle_agent_card)
        self.app.router.add_get('/.well-known/agent.json', self.handle_agent_card)  # 标准 A2A 发现端点
        self.app.router.add_get('/health', self.handle_health)
    
    async def handle_task(self, request: web.Request) -> web.StreamResponse:
        """处理 A2A 任务请求"""
        try:
            # 解析请求
            body = await request.json()
            task_id = body.get('task_id', uuid.uuid4().hex)
            input_data = body.get('a2a', {})
            input_text = input_data.get('input', '测试输入')
            
            print(f"📥 收到任务请求:")
            print(f"   Task ID: {task_id}")
            print(f"   Input: {input_text}")
            
            # 模拟错误（如果配置了错误概率）
            import random
            if random.random() < self.config.error_probability:
                return web.json_response(
                    {
                        "error": "MOCK_ERROR",
                        "message": "模拟的随机错误（用于测试错误处理）"
                    },
                    status=500
                )
            
            # 创建流式响应
            response = web.StreamResponse(
                status=200,
                headers={
                    'Content-Type': 'text/event-stream',
                    'Cache-Control': 'no-cache',
                    'Connection': 'keep-alive',
                }
            )
            await response.prepare(request)
            
            # 生成并发送 AGUI 事件流
            async for event in AGUIEventGenerator.generate_events(
                task_id=task_id,
                input_text=input_text,
                config=self.config
            ):
                await response.write(event.encode('utf-8'))
            
            # 发送结束标记
            await response.write(b"data: [DONE]\n\n")
            await response.write_eof()
            
            print(f"✅ 任务完成: {task_id}")
            return response
            
        except Exception as e:
            print(f"❌ 处理任务失败: {e}")
            return web.json_response(
                {"error": str(e)},
                status=500
            )
    
    async def handle_agent_card(self, request: web.Request) -> web.Response:
        """返回 Agent Card"""
        agent_card = {
            "agent_id": self.config.agent_id,
            "agent_name": self.config.agent_name,
            "agent_type": "a2a",
            "version": "1.0.0",
            "description": f"Mock {self.config.agent_type.upper()} Agent for testing",
            "capabilities": [
                "text_generation",
                "stream_response",
                "agui_events"
            ],
            "endpoint": f"http://localhost:{request.app['port']}/a2a/task",
            "auth_type": "none",
            "supported_events": [
                "RUN_STARTED",
                "THOUGHT_MESSAGE",
                "TOOL_CALL_STARTED",
                "TOOL_CALL_COMPLETED",
                "TEXT_MESSAGE_CONTENT",
                "RUN_COMPLETED"
            ],
            "config": {
                "response_delay": self.config.response_delay,
                "simulate_thinking": self.config.simulate_thinking,
                "simulate_tool_calls": self.config.simulate_tool_calls
            }
        }
        return web.json_response(agent_card)
    
    async def handle_health(self, request: web.Request) -> web.Response:
        """健康检查"""
        return web.json_response({
            "status": "healthy",
            "agent_id": self.config.agent_id,
            "agent_name": self.config.agent_name,
            "uptime": time.time() - request.app['start_time']
        })
    
    def run(self, host: str = '0.0.0.0', port: int = 8080):
        """启动服务器"""
        self.app['port'] = port
        self.app['start_time'] = time.time()
        
        print("=" * 60)
        print(f"🚀 Mock A2A Agent Server 启动")
        print("=" * 60)
        print(f"Agent ID:   {self.config.agent_id}")
        print(f"Agent Name: {self.config.agent_name}")
        print(f"Agent Type: {self.config.agent_type}")
        print(f"Address:    http://{host}:{port}")
        print("=" * 60)
        print(f"📡 Endpoints:")
        print(f"   POST   http://{host}:{port}/a2a/task")
        print(f"   GET    http://{host}:{port}/a2a/agent_card")
        print(f"   GET    http://{host}:{port}/.well-known/agent.json")
        print(f"   GET    http://{host}:{port}/health")
        print("=" * 60)
        print(f"⚙️  Config:")
        print(f"   Response Delay:     {self.config.response_delay}s")
        print(f"   Simulate Thinking:  {self.config.simulate_thinking}")
        print(f"   Simulate Tools:     {self.config.simulate_tool_calls}")
        print(f"   Error Probability:  {self.config.error_probability}")
        print("=" * 60)
        print("✅ 服务器就绪，等待请求...")
        print()
        
        web.run_app(self.app, host=host, port=port)


# ==================== CLI ====================

def main():
    parser = argparse.ArgumentParser(
        description='Mock A2A Agent Server - 模拟远端 A2A Agent'
    )
    
    parser.add_argument(
        '--port',
        type=int,
        default=int(os.getenv('MOCK_AGENT_PORT', 8080)),
        help='服务器端口 (默认: 8080)'
    )
    
    parser.add_argument(
        '--host',
        type=str,
        default='0.0.0.0',
        help='服务器地址 (默认: 0.0.0.0)'
    )
    
    parser.add_argument(
        '--agent-type',
        type=str,
        choices=['knot', 'smart', 'slow', 'error'],
        default=os.getenv('MOCK_AGENT_TYPE', 'knot'),
        help='Agent 类型 (默认: knot)'
    )
    
    parser.add_argument(
        '--agent-id',
        type=str,
        default=None,
        help='Agent ID (默认: 自动生成)'
    )
    
    parser.add_argument(
        '--agent-name',
        type=str,
        default=None,
        help='Agent 名称 (默认: 基于类型自动生成)'
    )
    
    parser.add_argument(
        '--delay',
        type=float,
        default=float(os.getenv('MOCK_RESPONSE_DELAY', 0.1)),
        help='响应延迟（秒） (默认: 0.1)'
    )
    
    parser.add_argument(
        '--no-thinking',
        action='store_true',
        help='禁用思考过程模拟'
    )
    
    parser.add_argument(
        '--no-tools',
        action='store_true',
        help='禁用工具调用模拟'
    )
    
    parser.add_argument(
        '--error-rate',
        type=float,
        default=0.0,
        help='错误概率 0-1 (默认: 0.0)'
    )
    
    args = parser.parse_args()
    
    # 生成配置
    agent_id = args.agent_id or f"mock_{args.agent_type}_{uuid.uuid4().hex[:8]}"
    agent_name = args.agent_name or f"Mock {args.agent_type.upper()} Agent"
    
    config = MockAgentConfig(
        agent_id=agent_id,
        agent_name=agent_name,
        agent_type=args.agent_type,
        response_delay=args.delay,
        simulate_thinking=not args.no_thinking,
        simulate_tool_calls=not args.no_tools,
        error_probability=args.error_rate
    )
    
    # 启动服务器
    server = MockA2AServer(config)
    server.run(host=args.host, port=args.port)


if __name__ == '__main__':
    main()
