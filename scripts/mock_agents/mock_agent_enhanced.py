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

        print(f"📥 [A2AProtocol] 收到任务请求")
        print(f"   - Method: {request.method}")
        print(f"   - Headers: {dict(request.headers)}")
        print(f"   - Content-Type: {request.headers.get('Content-Type', 'N/A')}")

        # Token 验证
        if config.token and not verify_token(request, config):
            print(f"❌ [A2AProtocol] Token 验证失败")
            return web.json_response(
                {"error": "Unauthorized", "message": "Invalid or missing token"},
                status=401
            )

        print(f"✅ [A2AProtocol] Token 验证通过")

        # 解析请求
        try:
            data = await request.json()
            print(f"✅ [A2AProtocol] JSON 解析成功")
            print(f"\n{'='*60}")
            print(f"📨 收到的完整指令内容:")
            print(f"{'='*60}")
            print(json.dumps(data, indent=2, ensure_ascii=False))
            print(f"{'='*60}\n")
        except Exception as e:
            print(f"❌ [A2AProtocol] JSON 解析失败: {e}")
            return web.json_response(
                {"error": "Invalid JSON", "message": str(e)},
                status=400
            )

        task_id = data.get('task_id', data.get('id', str(uuid.uuid4())))
        print(f"   - Task ID: {task_id}")

        # Check for action confirmation response
        metadata = data.get('metadata', {})
        instruction = data.get('instruction', '')
        is_action_response = 'Selected action:' in instruction
        is_select_response = 'Selected:' in instruction
        is_file_upload_response = 'Uploaded files:' in instruction
        is_form_response = 'Form submitted:' in instruction

        # 尝试从不同位置获取输入
        a2a_data = data.get('a2a', {})
        input_text = a2a_data.get('input', data.get('instruction', ''))
        print(f"   - Input text: {input_text[:100] if input_text else '(empty)'}")

        if not input_text:
            print(f"❌ [A2AProtocol] 缺少输入字段")
            print(f"   - Available keys: {list(data.keys())}")
            return web.json_response(
                {"error": "Missing input", "message": "No input found in a2a.input or instruction"},
                status=400
            )

        print(f"✅ [A2AProtocol] 开始创建 SSE 响应")

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
        print(f"✅ [A2AProtocol] SSE 响应已准备")

        # 生成事件流
        try:
            if is_action_response:
                async for event in A2AProtocol._generate_action_response_events(task_id, input_text, config):
                    await response.write(event.encode('utf-8'))
                    print(f"   📤 Sent event: {event[:100]}")
            elif is_select_response:
                async for event in A2AProtocol._generate_select_response_events(task_id, input_text, config):
                    await response.write(event.encode('utf-8'))
                    print(f"   📤 Sent event: {event[:100]}")
            elif is_file_upload_response:
                async for event in A2AProtocol._generate_file_upload_response_events(task_id, input_text, config):
                    await response.write(event.encode('utf-8'))
                    print(f"   📤 Sent event: {event[:100]}")
            elif is_form_response:
                async for event in A2AProtocol._generate_form_response_events(task_id, input_text, config):
                    await response.write(event.encode('utf-8'))
                    print(f"   📤 Sent event: {event[:100]}")
            else:
                async for event in A2AProtocol._generate_events(task_id, input_text, config):
                    await response.write(event.encode('utf-8'))
                    print(f"   📤 Sent event: {event[:100]}")
        except (ConnectionResetError, BrokenPipeError, RuntimeError) as e:
            print(f"⚠️ Client disconnected: {e}")
        finally:
            await response.write_eof()
            print(f"✅ [A2AProtocol] SSE 响应已结束")
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
        await asyncio.sleep(0.1)

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
                await asyncio.sleep(0.1)

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
            await asyncio.sleep(0.2)

            # 工具调用完成
            yield A2AProtocol._create_sse_event({
                "event_type": "TOOL_CALL_COMPLETED",
                "data": {
                    "task_id": task_id,
                    "tool_call_id": tool_call_id,
                    "tool_output": json.dumps({"results": ["Result 1", "Result 2"]})
                }
            })
            await asyncio.sleep(0.1)

        # 4. 流式文本响应 - 模拟模型逐字输出，每秒3个字符
        # Check for action confirmation trigger keywords
        trigger_keywords = ['confirm', 'deploy', 'action', 'approve', 'choose']
        should_send_action = any(kw in input_text.lower() for kw in trigger_keywords)

        # Check for single-select trigger keywords
        single_select_keywords = ['select', 'pick', 'which one']
        should_send_single_select = any(kw in input_text.lower() for kw in single_select_keywords)

        # Check for multi-select trigger keywords
        multi_select_keywords = ['multi', 'checkbox', 'features', 'survey']
        should_send_multi_select = any(kw in input_text.lower() for kw in multi_select_keywords)

        # Check for file upload trigger keywords
        file_upload_keywords = ['upload', 'file', 'document', 'attachment', 'resume']
        should_send_file_upload = any(kw in input_text.lower() for kw in file_upload_keywords)

        # Check for form trigger keywords
        form_keywords = ['form', 'register', 'signup', 'application', 'questionnaire']
        should_send_form = any(kw in input_text.lower() for kw in form_keywords)

        if should_send_action:
            response_text = (
                f"I've analyzed your request regarding: 「{input_text}」\n\n"
                f"I have a few options available for you. Please select one of the following actions:"
            )
        elif should_send_single_select:
            response_text = (
                f"I've prepared a list of options for you based on: 「{input_text}」\n\n"
                f"Please choose one option below:"
            )
        elif should_send_multi_select:
            response_text = (
                f"Here are some features related to: 「{input_text}」\n\n"
                f"Select all that apply:"
            )
        elif should_send_form:
            response_text = (
                f"I've prepared a form for you based on: 「{input_text}」\n\n"
                f"Please fill in all the required fields below:"
            )
        elif should_send_file_upload:
            response_text = (
                f"I need some files from you regarding: 「{input_text}」\n\n"
                f"Please upload the required documents below:"
            )
        else:
            response_text = (
                f"你好！我是 `{config.agent_name}`，很高兴为你服务。\n\n"
                f"你刚才说的是：**「{input_text}」**\n\n"
                f"让我来详细回答你的问题。这是一段模拟的 AI 模型回复，\n\n"
                f"| 姓名   | 年龄 | 城市     | 职业       |\n\
|--------|------|----------|------------|\n\
| 赵六   | 30   | 杭州     | UI设计师   |\n\n"
                f"用于测试流式输出效果。每秒钟会输出大约3个字符，"
                f"模拟真实大语言模型的生成速度。\n\n"
                f"当前时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
                f"希望这个回复对你有帮助！😊"
            )

        print(f"\n📝 即将流式输出的完整回复内容：")
        print(f"   {response_text[:200]}...")
        print(f"   总长度: {len(response_text)} 字符\n")

        # 每次发送3个字符，间隔约1秒（模拟1秒3个字符的速度）
        chunk_size = 10
        chars_per_second = 10
        delay = chunk_size / chars_per_second  # 每个chunk的延迟 = 1秒

        chunks = [response_text[i:i+chunk_size] for i in range(0, len(response_text), chunk_size)]
        for i, chunk in enumerate(chunks):
            yield A2AProtocol._create_sse_event({
                "event_type": "TEXT_MESSAGE_CONTENT",
                "data": {
                    "task_id": task_id,
                    "content": chunk,
                    "is_final": i == len(chunks) - 1
                }
            })
            await asyncio.sleep(0.1)

        # 4b. Send ACTION_CONFIRMATION if triggered
        if should_send_action:
            confirmation_id = f"confirm_{uuid.uuid4().hex[:8]}"
            yield A2AProtocol._create_sse_event({
                "event_type": "ACTION_CONFIRMATION",
                "data": {
                    "task_id": task_id,
                    "confirmation_id": confirmation_id,
                    "prompt": "Please select an action:",
                    "actions": [
                        {"id": "action_approve", "label": "Approve & Deploy", "style": "primary"},
                        {"id": "action_test", "label": "Run More Tests", "style": "secondary"},
                        {"id": "action_cancel", "label": "Cancel", "style": "danger"}
                    ]
                }
            })
            await asyncio.sleep(0.1)

        # 4c. Send SINGLE_SELECT if triggered
        if should_send_single_select:
            select_id = f"select_{uuid.uuid4().hex[:8]}"
            yield A2AProtocol._create_sse_event({
                "event_type": "SINGLE_SELECT",
                "data": {
                    "select_id": select_id,
                    "prompt": "Please choose one:",
                    "options": [
                        {"id": "opt1", "label": "Option A - Standard Plan"},
                        {"id": "opt2", "label": "Option B - Premium Plan"},
                        {"id": "opt3", "label": "Option C - Enterprise Plan"},
                        {"id": "opt4", "label": "Option D - Custom Plan"}
                    ],
                    "selected_option_id": None
                }
            })
            await asyncio.sleep(0.1)

        # 4d. Send MULTI_SELECT if triggered
        if should_send_multi_select:
            select_id = f"mselect_{uuid.uuid4().hex[:8]}"
            yield A2AProtocol._create_sse_event({
                "event_type": "MULTI_SELECT",
                "data": {
                    "select_id": select_id,
                    "prompt": "Select all that apply:",
                    "options": [
                        {"id": "feat1", "label": "Dark Mode"},
                        {"id": "feat2", "label": "Push Notifications"},
                        {"id": "feat3", "label": "Offline Support"},
                        {"id": "feat4", "label": "Multi-language"},
                        {"id": "feat5", "label": "Analytics Dashboard"}
                    ],
                    "min_select": 1,
                    "max_select": None,
                    "selected_option_ids": None
                }
            })
            await asyncio.sleep(0.1)

        # 4e. Send FILE_UPLOAD if triggered
        if should_send_file_upload:
            upload_id = f"upload_{uuid.uuid4().hex[:8]}"
            yield A2AProtocol._create_sse_event({
                "event_type": "FILE_UPLOAD",
                "data": {
                    "upload_id": upload_id,
                    "prompt": "Please upload the required documents:",
                    "accept_types": ["pdf", "doc", "docx", "txt", "png", "jpg"],
                    "max_files": 5,
                    "max_size_mb": 20,
                    "uploaded_files": None
                }
            })
            await asyncio.sleep(0.1)

        # 4f. Send FORM if triggered
        if should_send_form:
            form_id = f"form_{uuid.uuid4().hex[:8]}"
            yield A2AProtocol._create_sse_event({
                "event_type": "FORM",
                "data": {
                    "form_id": form_id,
                    "title": "User Registration",
                    "description": "Please fill in the information below to complete your registration.",
                    "fields": [
                        {
                            "field_id": "name",
                            "type": "text_input",
                            "label": "Full Name",
                            "placeholder": "Enter your full name",
                            "required": True,
                            "max_lines": 1
                        },
                        {
                            "field_id": "email",
                            "type": "text_input",
                            "label": "Email Address",
                            "placeholder": "example@email.com",
                            "required": True,
                            "max_lines": 1
                        },
                        {
                            "field_id": "role",
                            "type": "single_select",
                            "label": "Role",
                            "required": True,
                            "options": [
                                {"id": "developer", "label": "Developer"},
                                {"id": "designer", "label": "Designer"},
                                {"id": "pm", "label": "Product Manager"},
                                {"id": "other", "label": "Other"}
                            ]
                        },
                        {
                            "field_id": "skills",
                            "type": "multi_select",
                            "label": "Skills",
                            "required": False,
                            "options": [
                                {"id": "flutter", "label": "Flutter"},
                                {"id": "react", "label": "React"},
                                {"id": "python", "label": "Python"},
                                {"id": "go", "label": "Go"},
                                {"id": "rust", "label": "Rust"}
                            ]
                        },
                        {
                            "field_id": "bio",
                            "type": "text_input",
                            "label": "Short Bio",
                            "placeholder": "Tell us about yourself...",
                            "required": False,
                            "max_lines": 3
                        },
                        {
                            "field_id": "resume",
                            "type": "file_upload",
                            "label": "Resume / CV",
                            "required": False,
                            "accept_types": ["pdf", "doc", "docx"],
                            "max_files": 1,
                            "max_size_mb": 10
                        }
                    ],
                    "submitted_values": None
                }
            })
            await asyncio.sleep(0.1)

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

    @staticmethod
    async def _generate_action_response_events(
        task_id: str,
        input_text: str,
        config: AgentConfig
    ) -> AsyncGenerator[str, None]:
        """Generate events for an action confirmation response."""

        # Extract the selected action from input_text
        # Format: "Selected action: <label>"
        selected_label = input_text.replace('Selected action: ', '').strip()

        # 1. RUN_STARTED
        yield A2AProtocol._create_sse_event({
            "event_type": "RUN_STARTED",
            "data": {
                "task_id": task_id,
                "agent_id": config.agent_id,
                "started_at": datetime.now().isoformat()
            }
        })
        await asyncio.sleep(0.1)

        # 2. Generate tailored response based on selection
        if 'approve' in selected_label.lower() or 'deploy' in selected_label.lower():
            response_text = (
                f"Great choice! You selected **{selected_label}**.\n\n"
                f"Initiating deployment process...\n"
                f"- Building artifacts... Done\n"
                f"- Running pre-deploy checks... Passed\n"
                f"- Deploying to production... Success!\n\n"
                f"Deployment completed at {datetime.now().strftime('%H:%M:%S')}."
            )
        elif 'cancel' in selected_label.lower():
            response_text = (
                f"Understood. You selected **{selected_label}**.\n\n"
                f"The operation has been cancelled. No changes were made.\n"
                f"Let me know if you need anything else."
            )
        else:
            response_text = (
                f"Got it! You selected **{selected_label}**.\n\n"
                f"Processing your request...\n"
                f"Running additional tests on the current build...\n"
                f"All tests passed! Ready for the next step whenever you are."
            )

        # 3. Stream the response text
        chunk_size = 3
        chars_per_second = 3
        delay = chunk_size / chars_per_second

        chunks = [response_text[i:i+chunk_size] for i in range(0, len(response_text), chunk_size)]
        for i, chunk in enumerate(chunks):
            yield A2AProtocol._create_sse_event({
                "event_type": "TEXT_MESSAGE_CONTENT",
                "data": {
                    "task_id": task_id,
                    "content": chunk,
                    "is_final": i == len(chunks) - 1
                }
            })
            await asyncio.sleep(0.1)

        # 4. RUN_COMPLETED
        yield A2AProtocol._create_sse_event({
            "event_type": "RUN_COMPLETED",
            "data": {
                "task_id": task_id,
                "status": "success",
                "completed_at": datetime.now().isoformat()
            }
        })

    @staticmethod
    async def _generate_select_response_events(
        task_id: str,
        input_text: str,
        config: AgentConfig
    ) -> AsyncGenerator[str, None]:
        """Generate events for a single/multi-select response."""

        # Extract the selection from input_text
        # Format: "Selected: <labels>"
        selected_text = input_text.replace('Selected: ', '').strip()

        # 1. RUN_STARTED
        yield A2AProtocol._create_sse_event({
            "event_type": "RUN_STARTED",
            "data": {
                "task_id": task_id,
                "agent_id": config.agent_id,
                "started_at": datetime.now().isoformat()
            }
        })
        await asyncio.sleep(0.1)

        # 2. Generate tailored response
        response_text = (
            f"Thank you for your selection: **{selected_text}**.\n\n"
            f"I've recorded your choice and will proceed accordingly.\n"
            f"Processing at {datetime.now().strftime('%H:%M:%S')}..."
        )

        # 3. Stream the response text
        chunk_size = 3
        chunks = [response_text[i:i+chunk_size] for i in range(0, len(response_text), chunk_size)]
        for i, chunk in enumerate(chunks):
            yield A2AProtocol._create_sse_event({
                "event_type": "TEXT_MESSAGE_CONTENT",
                "data": {
                    "task_id": task_id,
                    "content": chunk,
                    "is_final": i == len(chunks) - 1
                }
            })
            await asyncio.sleep(0.1)

        # 4. RUN_COMPLETED
        yield A2AProtocol._create_sse_event({
            "event_type": "RUN_COMPLETED",
            "data": {
                "task_id": task_id,
                "status": "success",
                "completed_at": datetime.now().isoformat()
            }
        })

    @staticmethod
    async def _generate_file_upload_response_events(
        task_id: str,
        input_text: str,
        config: AgentConfig
    ) -> AsyncGenerator[str, None]:
        """Generate events for a file upload response."""

        # Extract the file names from input_text
        # Format: "Uploaded files: file1.pdf, file2.doc"
        files_text = input_text.replace('Uploaded files: ', '').strip()

        # 1. RUN_STARTED
        yield A2AProtocol._create_sse_event({
            "event_type": "RUN_STARTED",
            "data": {
                "task_id": task_id,
                "agent_id": config.agent_id,
                "started_at": datetime.now().isoformat()
            }
        })
        await asyncio.sleep(0.1)

        # 2. Generate tailored response
        response_text = (
            f"Thank you! I've received your files: **{files_text}**.\n\n"
            f"Processing your uploaded documents...\n"
            f"- Validating file formats... Done\n"
            f"- Scanning for content... Done\n"
            f"- Indexing documents... Done\n\n"
            f"All files have been processed successfully at {datetime.now().strftime('%H:%M:%S')}.\n"
            f"I can now help you with questions about these documents."
        )

        # 3. Stream the response text
        chunk_size = 3
        chunks = [response_text[i:i+chunk_size] for i in range(0, len(response_text), chunk_size)]
        for i, chunk in enumerate(chunks):
            yield A2AProtocol._create_sse_event({
                "event_type": "TEXT_MESSAGE_CONTENT",
                "data": {
                    "task_id": task_id,
                    "content": chunk,
                    "is_final": i == len(chunks) - 1
                }
            })
            await asyncio.sleep(0.1)

        # 4. RUN_COMPLETED
        yield A2AProtocol._create_sse_event({
            "event_type": "RUN_COMPLETED",
            "data": {
                "task_id": task_id,
                "status": "success",
                "completed_at": datetime.now().isoformat()
            }
        })

    @staticmethod
    async def _generate_form_response_events(
        task_id: str,
        input_text: str,
        config: AgentConfig
    ) -> AsyncGenerator[str, None]:
        """Generate events for a form submission response."""

        # Extract the form summary from input_text
        # Format: "Form submitted: field1: value1; field2: value2"
        form_text = input_text.replace('Form submitted: ', '').strip()

        # 1. RUN_STARTED
        yield A2AProtocol._create_sse_event({
            "event_type": "RUN_STARTED",
            "data": {
                "task_id": task_id,
                "agent_id": config.agent_id,
                "started_at": datetime.now().isoformat()
            }
        })
        await asyncio.sleep(0.1)

        # 2. Generate tailored response
        response_text = (
            f"Thank you for submitting the form!\n\n"
            f"**Submission Summary:**\n"
            f"{form_text}\n\n"
            f"Your information has been recorded successfully.\n"
            f"- Data validation... Passed\n"
            f"- Record created... Done\n"
            f"- Confirmation sent... Done\n\n"
            f"Submission completed at {datetime.now().strftime('%H:%M:%S')}.\n"
            f"You will receive a confirmation shortly."
        )

        # 3. Stream the response text
        chunk_size = 3
        chunks = [response_text[i:i+chunk_size] for i in range(0, len(response_text), chunk_size)]
        for i, chunk in enumerate(chunks):
            yield A2AProtocol._create_sse_event({
                "event_type": "TEXT_MESSAGE_CONTENT",
                "data": {
                    "task_id": task_id,
                    "content": chunk,
                    "is_final": i == len(chunks) - 1
                }
            })
            await asyncio.sleep(0.1)

        # 4. RUN_COMPLETED
        yield A2AProtocol._create_sse_event({
            "event_type": "RUN_COMPLETED",
            "data": {
                "task_id": task_id,
                "status": "success",
                "completed_at": datetime.now().isoformat()
            }
        })


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

                        print(f"\n{'='*60}")
                        print(f"📨 [WebSocket] 收到的完整指令内容:")
                        print(f"{'='*60}")
                        print(json.dumps(data, indent=2, ensure_ascii=False))
                        print(f"{'='*60}\n")

                        response = await ACPProtocol._handle_jsonrpc(data, config)

                        # 如果是流式响应
                        if isinstance(response, list):
                            for item in response:
                                await ws.send_json(item)
                                # chat.content 类型使用慢速输出（1秒3字符）
                                if item.get('result', {}).get('type') == 'chat.content':
                                    await asyncio.sleep(0.3)
                                else:
                                    await asyncio.sleep(0.1)
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

        # 流式内容 - 每次3个字符
        reply = (
            f"你好！我是 {config.agent_name}，很高兴为你服务。\n\n"
            f"你刚才说的是：「{message}」\n\n"
            f"让我来详细回答你的问题。这是一段模拟的 AI 模型回复，"
            f"用于测试流式输出效果。\n"
            f"当前时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        )

        print(f"\n📝 [WebSocket] 即将流式输出的完整回复内容：")
        print(f"   {reply[:200]}...")
        print(f"   总长度: {len(reply)} 字符\n")

        chunk_size = 3
        chunks = [reply[i:i+chunk_size] for i in range(0, len(reply), chunk_size)]

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


async def handle_rollback(request: web.Request) -> web.Response:
    """处理 rollback 请求"""
    config: AgentConfig = request.app['config']

    # Token 验证
    if config.token and not verify_token(request, config):
        return web.json_response(
            {"error": "Unauthorized", "message": "Invalid or missing token"},
            status=401
        )

    try:
        data = await request.json()
    except Exception as e:
        return web.json_response(
            {"error": "Invalid JSON", "message": str(e)},
            status=400
        )

    message_id = data.get('message_id', 'unknown')
    print(f"\n{'='*60}")
    print(f"🔄 [Rollback] Received rollback request")
    print(f"   - Message ID: {message_id}")
    print(f"   - Timestamp: {datetime.now().isoformat()}")
    print(f"{'='*60}\n")

    return web.json_response({
        "status": "ok",
        "message_id": message_id,
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
        app.router.add_post('/a2a/rollback', handle_rollback)

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
        print(f"  A2A Rollback:   http://localhost:{config.port}/a2a/rollback")

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
