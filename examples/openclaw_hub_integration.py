#!/usr/bin/env python3
"""
OpenClaw Hub Integration Example
演示如何在 OpenClaw 中集成 AI Agent Hub 的双向通信功能
"""

import asyncio
import websockets
import json
import time
from datetime import datetime
from typing import Optional, Dict, Any, List


class HubClient:
    """AI Agent Hub 客户端"""
    
    def __init__(
        self,
        hub_url: str = "ws://192.168.1.100:18790",
        agent_id: str = "agent_openclaw_001",
        agent_name: str = "OpenClaw Agent"
    ):
        self.hub_url = hub_url
        self.agent_id = agent_id
        self.agent_name = agent_name
        self.ws: Optional[websockets.WebSocketClientProtocol] = None
        self.request_id = 0
        
    async def connect(self) -> bool:
        """连接到 Hub"""
        try:
            self.ws = await websockets.connect(self.hub_url)
            print(f"✅ Connected to Hub: {self.hub_url}")
            return True
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            return False
    
    async def disconnect(self):
        """断开连接"""
        if self.ws:
            await self.ws.close()
            print("👋 Disconnected from Hub")
    
    def _generate_request_id(self) -> str:
        """生成请求 ID"""
        self.request_id += 1
        return f"{self.agent_id}_{self.request_id}_{int(time.time() * 1000)}"
    
    async def send_request(
        self,
        method: str,
        params: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """发送请求到 Hub"""
        if not self.ws:
            raise RuntimeError("Not connected to Hub")
        
        request = {
            "jsonrpc": "2.0",
            "id": self._generate_request_id(),
            "method": method,
            "params": params or {},
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "source_agent_id": self.agent_id
        }
        
        print(f"\n📤 Sending request: {method}")
        print(f"   Request ID: {request['id']}")
        
        await self.ws.send(json.dumps(request))
        response_raw = await self.ws.recv()
        response = json.loads(response_raw)
        
        print(f"📥 Received response")
        
        return response
    
    async def initiate_chat(
        self,
        message: str,
        target_user_id: Optional[str] = None,
        target_channel_id: Optional[str] = None,
        priority: str = "normal",
        requires_response: bool = False
    ) -> Dict[str, Any]:
        """
        主动发起聊天
        
        Args:
            message: 消息内容
            target_user_id: 目标用户 ID（可选）
            target_channel_id: 目标频道 ID（可选）
            priority: 优先级（normal/high/urgent）
            requires_response: 是否需要响应
        """
        params = {
            "message": message,
            "priority": priority,
            "requires_response": requires_response
        }
        
        if target_user_id:
            params["target_user_id"] = target_user_id
        if target_channel_id:
            params["target_channel_id"] = target_channel_id
        
        return await self.send_request("hub.initiateChat", params)
    
    async def get_agent_list(self) -> List[Dict[str, Any]]:
        """获取 Hub 中的 Agent 列表"""
        response = await self.send_request("hub.getAgentList")
        
        if "result" in response:
            return response["result"]["agents"]
        else:
            print(f"❌ Error: {response.get('error', {}).get('message')}")
            return []
    
    async def get_agent_capabilities(self, agent_id: str) -> Dict[str, Any]:
        """获取指定 Agent 的能力"""
        response = await self.send_request(
            "hub.getAgentCapabilities",
            {"agent_id": agent_id}
        )
        
        if "result" in response:
            return response["result"]
        else:
            print(f"❌ Error: {response.get('error', {}).get('message')}")
            return {}
    
    async def get_hub_info(self) -> Dict[str, Any]:
        """获取 Hub 信息"""
        response = await self.send_request("hub.getHubInfo")
        
        if "result" in response:
            return response["result"]
        else:
            print(f"❌ Error: {response.get('error', {}).get('message')}")
            return {}
    
    async def subscribe_channel(self, channel_id: str) -> bool:
        """订阅 Channel"""
        response = await self.send_request(
            "hub.subscribeChannel",
            {"channel_id": channel_id}
        )
        
        if "result" in response:
            print(f"✅ Subscribed to channel: {channel_id}")
            return True
        else:
            print(f"❌ Failed to subscribe: {response.get('error', {}).get('message')}")
            return False
    
    async def unsubscribe_channel(self, channel_id: str) -> bool:
        """取消订阅 Channel"""
        response = await self.send_request(
            "hub.unsubscribeChannel",
            {"channel_id": channel_id}
        )
        
        if "result" in response:
            print(f"✅ Unsubscribed from channel: {channel_id}")
            return True
        else:
            print(f"❌ Failed to unsubscribe: {response.get('error', {}).get('message')}")
            return False


# ==================== 使用示例 ====================

async def example_basic_connection():
    """示例 1: 基本连接和获取信息"""
    print("=" * 60)
    print("示例 1: 基本连接和获取 Hub 信息")
    print("=" * 60)
    
    client = HubClient()
    
    # 连接到 Hub
    if not await client.connect():
        return
    
    try:
        # 获取 Hub 信息
        hub_info = await client.get_hub_info()
        print("\n📊 Hub 信息:")
        print(f"   名称: {hub_info.get('name')}")
        print(f"   版本: {hub_info.get('version')}")
        print(f"   Agent 数量: {hub_info.get('agent_count')}")
        print(f"   频道数量: {hub_info.get('channel_count')}")
        print(f"   在线用户: {hub_info.get('online_user_count')}")
        
    finally:
        await client.disconnect()


async def example_get_agents():
    """示例 2: 获取 Agent 列表"""
    print("\n" + "=" * 60)
    print("示例 2: 获取 Agent 列表")
    print("=" * 60)
    
    client = HubClient()
    
    if not await client.connect():
        return
    
    try:
        # 获取 Agent 列表
        agents = await client.get_agent_list()
        
        print(f"\n📋 共有 {len(agents)} 个 Agent:")
        for agent in agents:
            print(f"\n   🤖 {agent['name']}")
            print(f"      ID: {agent['id']}")
            print(f"      类型: {agent['type']}")
            print(f"      状态: {agent['status']}")
            print(f"      描述: {agent['description']}")
        
    finally:
        await client.disconnect()


async def example_initiate_chat():
    """示例 3: 主动发起聊天"""
    print("\n" + "=" * 60)
    print("示例 3: 主动发起聊天")
    print("=" * 60)
    
    client = HubClient()
    
    if not await client.connect():
        return
    
    try:
        # 发起聊天
        response = await client.initiate_chat(
            message="⚠️ 检测到系统 CPU 使用率超过 90%，请注意！",
            priority="high",
            requires_response=True
        )
        
        if "result" in response:
            print("\n✅ 聊天发起成功")
            print(f"   消息 ID: {response['result'].get('message_id')}")
            print(f"   状态: {response['result'].get('status')}")
        elif "error" in response:
            error = response["error"]
            if error["code"] == -32004:
                # 需要用户批准
                print("\n⏳ 等待用户批准权限...")
                print(f"   权限请求 ID: {error['data'].get('permission_request_id')}")
                print("\n💡 提示: 请在 AI Agent Hub 中批准权限请求")
            else:
                print(f"\n❌ 错误: {error['message']}")
        
    finally:
        await client.disconnect()


async def example_subscribe_channel():
    """示例 4: 订阅 Channel"""
    print("\n" + "=" * 60)
    print("示例 4: 订阅 Channel")
    print("=" * 60)
    
    client = HubClient()
    
    if not await client.connect():
        return
    
    try:
        # 订阅 Channel
        channel_id = "ch_project_updates"
        success = await client.subscribe_channel(channel_id)
        
        if success:
            print(f"\n✅ 已订阅频道: {channel_id}")
            print("💡 现在可以实时接收该频道的消息")
        
    finally:
        await client.disconnect()


async def example_agent_collaboration():
    """示例 5: Agent 间协作"""
    print("\n" + "=" * 60)
    print("示例 5: Agent 间协作 - 查找数据分析 Agent")
    print("=" * 60)
    
    client = HubClient()
    
    if not await client.connect():
        return
    
    try:
        # 获取所有 Agent
        agents = await client.get_agent_list()
        
        # 查找特定类型的 Agent
        target_type = "a2a"
        matching_agents = [a for a in agents if a["type"] == target_type]
        
        if matching_agents:
            print(f"\n✅ 找到 {len(matching_agents)} 个 {target_type} Agent:")
            for agent in matching_agents:
                print(f"\n   🤖 {agent['name']}")
                
                # 获取 Agent 能力
                capabilities = await client.get_agent_capabilities(agent["id"])
                print(f"      能力: {capabilities.get('capabilities', [])}")
                print(f"      工具: {capabilities.get('tools', [])}")
        else:
            print(f"\n⚠️ 未找到 {target_type} 类型的 Agent")
        
    finally:
        await client.disconnect()


async def example_monitoring_system():
    """示例 6: 完整的监控系统示例"""
    print("\n" + "=" * 60)
    print("示例 6: 系统监控与主动通知")
    print("=" * 60)
    
    client = HubClient()
    
    if not await client.connect():
        return
    
    try:
        # 模拟系统监控
        print("\n🔍 开始监控系统状态...")
        
        # 模拟检测到问题
        await asyncio.sleep(2)
        print("\n⚠️ 检测到问题: CPU 使用率过高")
        
        # 主动通知用户
        response = await client.initiate_chat(
            message="⚠️ 警告: 系统 CPU 使用率达到 95%\n\n"
                   "建议操作:\n"
                   "1. 检查运行中的进程\n"
                   "2. 考虑扩容资源\n"
                   "3. 优化应用性能",
            priority="urgent",
            requires_response=True
        )
        
        if "result" in response:
            print("\n✅ 已成功通知用户")
        elif "error" in response and response["error"]["code"] == -32004:
            print("\n⏳ 首次通知需要用户批准权限")
            print("💡 请在 Hub 中批准后，后续通知将自动发送")
        
        # 继续监控...
        print("\n🔍 继续监控中...")
        
    finally:
        await client.disconnect()


async def main():
    """运行所有示例"""
    print("""
╔═══════════════════════════════════════════════════════════╗
║         OpenClaw Hub Integration Examples                 ║
║         AI Agent Hub 双向通信示例                         ║
╚═══════════════════════════════════════════════════════════╝
    """)
    
    # 运行示例
    try:
        await example_basic_connection()
        await asyncio.sleep(1)
        
        await example_get_agents()
        await asyncio.sleep(1)
        
        await example_initiate_chat()
        await asyncio.sleep(1)
        
        await example_subscribe_channel()
        await asyncio.sleep(1)
        
        await example_agent_collaboration()
        await asyncio.sleep(1)
        
        await example_monitoring_system()
        
    except KeyboardInterrupt:
        print("\n\n👋 已中断")
    except Exception as e:
        print(f"\n\n❌ 错误: {e}")
        import traceback
        traceback.print_exc()
    
    print("\n" + "=" * 60)
    print("✅ 所有示例运行完成")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
