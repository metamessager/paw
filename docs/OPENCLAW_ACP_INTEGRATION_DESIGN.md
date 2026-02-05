# OpenClaw (ACP) 集成设计方案

## 🎯 目标

将 **OpenClaw (Moltbot)** 的 AI Agent 接入 **AI Agent Hub**，通过 **ACP (Agent Client Protocol)** 实现通信。

---

## 📐 OpenClaw 架构分析

### 核心组件

```
┌─────────────────────────────────────────┐
│          OpenClaw (Moltbot)             │
├─────────────────────────────────────────┤
│  Gateway Layer                          │
│  ├─ WebSocket Server (port 18789)      │
│  ├─ JSON-RPC Handler                   │
│  └─ Channel Plugins (WhatsApp/Telegram)│
├─────────────────────────────────────────┤
│  Protocol Layer (ACP)                   │
│  ├─ server.ts / client.ts              │
│  ├─ translator.ts                       │
│  └─ JSON-RPC 2.0                        │
├─────────────────────────────────────────┤
│  Agent Runtime                          │
│  ├─ Model Scheduler                    │
│  ├─ Tool/Skill System                  │
│  ├─ Memory (SHORT/LONG term)           │
│  └─ bash-tools, file-tools, etc        │
└─────────────────────────────────────────┘
```

### ACP 协议特点

- **基于**: JSON-RPC 2.0
- **传输**: WebSocket（双向流式）
- **端口**: 默认 18789
- **格式**: 
  ```json
  {
    "jsonrpc": "2.0",
    "method": "chat",
    "params": {...},
    "id": 1
  }
  ```

---

## 🏗️ 集成架构

```
┌──────────────────────────────────────────┐
│     AI Agent Hub (Flutter)               │
│  ┌────────────────────────────────────┐  │
│  │  OpenClawAgent (ACP 实现)          │  │
│  │  - ACP Client                      │  │
│  │  - WebSocket Connection            │  │
│  │  - JSON-RPC Handler                │  │
│  └────────────────────────────────────┘  │
│              ↓                            │
│  ┌────────────────────────────────────┐  │
│  │  ACPService                        │  │
│  │  - connect()                       │  │
│  │  - sendMessage()                   │  │
│  │  - submitTask()                    │  │
│  │  - streamResponse()                │  │
│  └────────────────────────────────────┘  │
│              ↓                            │
│  ┌────────────────────────────────────┐  │
│  │  LocalDatabaseService (SQLite)     │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
              ↓ WebSocket (port 18789)
┌──────────────────────────────────────────┐
│     OpenClaw Gateway                     │
│  ┌────────────────────────────────────┐  │
│  │  ACP Server                        │  │
│  │  ├─ JSON-RPC Handler               │  │
│  │  ├─ Authentication                 │  │
│  │  └─ Message Router                 │  │
│  └────────────────────────────────────┘  │
│              ↓                            │
│  ┌────────────────────────────────────┐  │
│  │  Agent Runtime                     │  │
│  │  ├─ LLM (Claude/GPT-4)            │  │
│  │  ├─ Tool Execution                 │  │
│  │  └─ Memory Management              │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

---

## 📦 技术方案

### 1. ACP 协议实现

#### ACP 消息格式

```dart
// ACP Request
class ACPRequest {
  final String jsonrpc = '2.0';
  final String method;
  final Map<String, dynamic>? params;
  final dynamic id;

  ACPRequest({
    required this.method,
    this.params,
    required this.id,
  });

  Map<String, dynamic> toJson() => {
    'jsonrpc': jsonrpc,
    'method': method,
    if (params != null) 'params': params,
    'id': id,
  };
}

// ACP Response
class ACPResponse {
  final String jsonrpc;
  final dynamic result;
  final ACPError? error;
  final dynamic id;

  ACPResponse({
    required this.jsonrpc,
    this.result,
    this.error,
    required this.id,
  });

  factory ACPResponse.fromJson(Map<String, dynamic> json) {
    return ACPResponse(
      jsonrpc: json['jsonrpc'],
      result: json['result'],
      error: json['error'] != null ? ACPError.fromJson(json['error']) : null,
      id: json['id'],
    );
  }
}

class ACPError {
  final int code;
  final String message;
  final dynamic data;

  ACPError({
    required this.code,
    required this.message,
    this.data,
  });

  factory ACPError.fromJson(Map<String, dynamic> json) {
    return ACPError(
      code: json['code'],
      message: json['message'],
      data: json['data'],
    );
  }
}
```

#### ACP 方法

OpenClaw 支持的核心方法：

1. **chat** - 对话
   ```json
   {
     "method": "chat",
     "params": {
       "message": "Hello!",
       "session_id": "session-123"
     }
   }
   ```

2. **executeTask** - 执行任务
   ```json
   {
     "method": "executeTask",
     "params": {
       "instruction": "List files in current directory",
       "tools": ["bash"]
     }
   }
   ```

3. **streamResponse** - 流式响应
   ```json
   {
     "method": "streamResponse",
     "params": {
       "message": "Write a poem"
     }
   }
   ```

### 2. WebSocket 连接

```dart
import 'package:web_socket_channel/web_socket_channel.dart';

class ACPWebSocketClient {
  final String gatewayUrl;
  final String? authToken;
  
  WebSocketChannel? _channel;
  int _requestId = 0;
  
  ACPWebSocketClient({
    required this.gatewayUrl,
    this.authToken,
  });

  // 连接到 OpenClaw Gateway
  Future<void> connect() async {
    final uri = Uri.parse(gatewayUrl);
    _channel = WebSocketChannel.connect(uri);
    
    // 认证（如果需要）
    if (authToken != null) {
      await _authenticate();
    }
  }

  // 发送 ACP 请求
  Future<ACPResponse> sendRequest(ACPRequest request) async {
    if (_channel == null) {
      throw Exception('Not connected');
    }

    // 发送请求
    _channel!.sink.add(jsonEncode(request.toJson()));

    // 等待响应
    final response = await _channel!.stream
        .map((data) => ACPResponse.fromJson(jsonDecode(data)))
        .firstWhere((resp) => resp.id == request.id);

    return response;
  }

  // 流式接收
  Stream<ACPResponse> streamRequest(ACPRequest request) {
    if (_channel == null) {
      throw Exception('Not connected');
    }

    _channel!.sink.add(jsonEncode(request.toJson()));

    return _channel!.stream
        .map((data) => ACPResponse.fromJson(jsonDecode(data)))
        .where((resp) => resp.id == request.id);
  }

  // 关闭连接
  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  // 生成请求 ID
  int _nextRequestId() => ++_requestId;

  // 认证
  Future<void> _authenticate() async {
    final request = ACPRequest(
      method: 'authenticate',
      params: {'token': authToken},
      id: _nextRequestId(),
    );

    final response = await sendRequest(request);
    
    if (response.error != null) {
      throw Exception('Authentication failed: ${response.error!.message}');
    }
  }
}
```

### 3. OpenClawAgent 数据模型

```dart
class OpenClawAgent extends UniversalAgent {
  /// OpenClaw Gateway URL
  final String gatewayUrl;
  
  /// 认证 Token（可选）
  final String? authToken;
  
  /// 会话 ID
  final String? sessionId;
  
  /// 可用工具列表
  final List<String>? tools;
  
  /// 配置
  final Map<String, dynamic>? config;

  OpenClawAgent({
    required super.id,
    required super.name,
    required super.avatar,
    super.bio,
    required this.gatewayUrl,
    this.authToken,
    this.sessionId,
    this.tools,
    this.config,
    super.status = const AgentStatus(state: 'offline'),
  }) : super(
          type: 'openclaw',
          provider: AgentProvider(
            name: 'OpenClaw',
            platform: 'Moltbot ACP Gateway',
            type: 'openclaw',
          ),
        );

  @override
  Future<String> sendMessage(String message) async {
    throw UnimplementedError('Use ACPService.sendMessage()');
  }

  @override
  Future<A2ATaskResponse> submitTask(A2ATask task) async {
    throw UnimplementedError('Use ACPService.submitTask()');
  }

  @override
  Future<A2AAgentCard?> getAgentCard() async {
    return A2AAgentCard(
      name: name,
      description: bio ?? 'OpenClaw Agent via ACP',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: '$gatewayUrl/tasks',
        stream: '$gatewayUrl/stream',
        status: '$gatewayUrl/status',
      ),
      capabilities: [
        'chat',
        'task_execution',
        'streaming',
        if (tools != null && tools!.isNotEmpty) 'tool_calling',
      ],
      authentication: authToken != null
          ? A2AAuthentication(
              schemes: ['bearer'],
              config: {'header': 'Authorization'},
            )
          : null,
      metadata: {
        'protocol': 'ACP',
        'platform': 'OpenClaw (Moltbot)',
        'tools': tools,
        'session_id': sessionId,
      },
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'bio': bio,
      'type': type,
      'gateway_url': gatewayUrl,
      'auth_token': authToken,
      'session_id': sessionId,
      'tools': tools,
      'config': config,
      'provider': provider.toJson(),
      'status': {'state': status.state},
    };
  }

  factory OpenClawAgent.fromJson(Map<String, dynamic> json) {
    return OpenClawAgent(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      avatar: json['avatar'] ?? '🦅',
      bio: json['bio'],
      gatewayUrl: json['gateway_url'] ?? '',
      authToken: json['auth_token'],
      sessionId: json['session_id'],
      tools: json['tools'] != null ? List<String>.from(json['tools']) : null,
      config: json['config'],
      status: json['status'] != null
          ? AgentStatus.fromJson(json['status'])
          : const AgentStatus(state: 'offline'),
    );
  }
}
```

---

## 🔧 核心服务实现

### ACPService

```dart
class ACPService {
  final Database _db;
  final Map<String, ACPWebSocketClient> _clients = {};

  ACPService(this._db);

  /// 添加 OpenClaw Agent
  Future<OpenClawAgent> addAgent({
    required String name,
    required String gatewayUrl,
    String? authToken,
    String? bio,
    String avatar = '🦅',
    List<String>? tools,
    Map<String, dynamic>? config,
  }) async {
    final agent = OpenClawAgent(
      id: 'openclaw_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      avatar: avatar,
      bio: bio,
      gatewayUrl: gatewayUrl,
      authToken: authToken,
      sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
      tools: tools,
      config: config,
      status: const AgentStatus(state: 'offline'),
    );

    // 保存到数据库
    await _db.insert(
      'agents',
      {
        'id': agent.id,
        'name': agent.name,
        'avatar': agent.avatar,
        'bio': agent.bio,
        'type': agent.type,
        'config': jsonEncode(agent.toJson()),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return agent;
  }

  /// 连接到 Agent
  Future<void> connect(OpenClawAgent agent) async {
    if (_clients.containsKey(agent.id)) {
      return; // 已连接
    }

    final client = ACPWebSocketClient(
      gatewayUrl: agent.gatewayUrl,
      authToken: agent.authToken,
    );

    await client.connect();
    _clients[agent.id] = client;

    // 更新状态
    await _updateAgentStatus(agent.id, 'online');
  }

  /// 发送消息
  Future<String> sendMessage(
    OpenClawAgent agent,
    String message,
  ) async {
    // 确保已连接
    if (!_clients.containsKey(agent.id)) {
      await connect(agent);
    }

    final client = _clients[agent.id]!;

    final request = ACPRequest(
      method: 'chat',
      params: {
        'message': message,
        'session_id': agent.sessionId,
        'tools': agent.tools,
      },
      id: DateTime.now().millisecondsSinceEpoch,
    );

    final response = await client.sendRequest(request);

    if (response.error != null) {
      throw Exception('Chat failed: ${response.error!.message}');
    }

    return response.result['response'] ?? 'No response';
  }

  /// 执行任务（A2A 风格）
  Future<A2ATaskResponse> submitTask(
    OpenClawAgent agent,
    A2ATask task,
  ) async {
    if (!_clients.containsKey(agent.id)) {
      await connect(agent);
    }

    final client = _clients[agent.id]!;

    final request = ACPRequest(
      method: 'executeTask',
      params: {
        'instruction': task.instruction,
        'context': task.context?.map((p) => p.toJson()).toList(),
        'session_id': agent.sessionId,
        'tools': agent.tools,
      },
      id: DateTime.now().millisecondsSinceEpoch,
    );

    final response = await client.sendRequest(request);

    if (response.error != null) {
      throw Exception('Task failed: ${response.error!.message}');
    }

    // 转换为 A2A 格式
    return A2ATaskResponse(
      taskId: response.result['task_id'] ?? 'task_${DateTime.now().millisecondsSinceEpoch}',
      state: 'completed',
      artifacts: response.result['result'] != null
          ? [
              A2AArtifact(
                name: 'openclaw_result',
                parts: [A2APart.text(response.result['result'])],
              )
            ]
          : null,
    );
  }

  /// 流式响应
  Stream<String> streamResponse(
    OpenClawAgent agent,
    String message,
  ) async* {
    if (!_clients.containsKey(agent.id)) {
      await connect(agent);
    }

    final client = _clients[agent.id]!;

    final request = ACPRequest(
      method: 'streamResponse',
      params: {
        'message': message,
        'session_id': agent.sessionId,
      },
      id: DateTime.now().millisecondsSinceEpoch,
    );

    await for (var response in client.streamRequest(request)) {
      if (response.error != null) {
        throw Exception('Stream failed: ${response.error!.message}');
      }

      if (response.result != null && response.result['chunk'] != null) {
        yield response.result['chunk'];
      }
    }
  }

  /// 测试连接
  Future<bool> testConnection(OpenClawAgent agent) async {
    try {
      final client = ACPWebSocketClient(
        gatewayUrl: agent.gatewayUrl,
        authToken: agent.authToken,
      );

      await client.connect();
      client.disconnect();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 断开连接
  Future<void> disconnect(String agentId) async {
    if (_clients.containsKey(agentId)) {
      _clients[agentId]!.disconnect();
      _clients.remove(agentId);
      await _updateAgentStatus(agentId, 'offline');
    }
  }

  /// 更新 Agent 状态
  Future<void> _updateAgentStatus(String agentId, String state) async {
    // 更新数据库中的状态
    final List<Map<String, dynamic>> maps = await _db.query(
      'agents',
      where: 'id = ?',
      whereArgs: [agentId],
    );

    if (maps.isNotEmpty) {
      final config = jsonDecode(maps.first['config']);
      config['status'] = {'state': state};

      await _db.update(
        'agents',
        {'config': jsonEncode(config)},
        where: 'id = ?',
        whereArgs: [agentId],
      );
    }
  }

  /// 清理所有连接
  void dispose() {
    for (var client in _clients.values) {
      client.disconnect();
    }
    _clients.clear();
  }
}
```

---

## 📊 与其他 Agent 对比

| 特性 | A2A Agent | OpenClaw Agent | Knot Agent |
|------|-----------|----------------|------------|
| **协议** | A2A Protocol | ACP (JSON-RPC) | Knot API |
| **传输** | HTTP(S) + SSE | WebSocket | HTTP(S) |
| **发现** | ✅ 自动 | 手动 | 手动 |
| **流式** | ✅ SSE | ✅ WebSocket | ⚠️ 轮询 |
| **工具调用** | ❌ | ✅ Tool System | ⚠️ 部分 |
| **会话管理** | ❌ | ✅ Session ID | ❌ |
| **本地优先** | ❌ | ✅ | ❌ |
| **平台集成** | ❌ | ✅ WhatsApp/Telegram | ❌ |

---

## 🚀 使用流程

### 1. 启动 OpenClaw Gateway

```bash
# 假设 OpenClaw 已安装
openclaw gateway start --port 18789
```

### 2. 在 AI Agent Hub 添加 Agent

```dart
final agent = await acpService.addAgent(
  name: 'My OpenClaw Agent',
  gatewayUrl: 'ws://localhost:18789',
  authToken: 'your-token',  // 可选
  tools: ['bash', 'file-system', 'web-search'],
);
```

### 3. 连接并对话

```dart
// 连接
await acpService.connect(agent);

// 发送消息
final response = await acpService.sendMessage(
  agent,
  'List files in /tmp directory',
);

print('Response: $response');
```

### 4. 流式响应

```dart
await for (var chunk in acpService.streamResponse(agent, 'Write a poem')) {
  print(chunk);
}
```

---

## ✅ 实施清单

### Phase 1: ACP 协议实现 (1-2 天)
- [ ] ACPRequest/ACPResponse 数据模型
- [ ] ACPWebSocketClient (WebSocket 客户端)
- [ ] 连接/断开/认证

### Phase 2: OpenClawAgent 集成 (1-2 天)
- [ ] OpenClawAgent 模型
- [ ] ACPService 服务
- [ ] 消息发送/任务提交/流式响应

### Phase 3: UI 界面 (1 天)
- [ ] 添加 OpenClaw Agent 页面
- [ ] 连接测试
- [ ] 工具配置

### Phase 4: 测试与文档 (1 天)
- [ ] 单元测试
- [ ] 集成测试
- [ ] 用户文档

**总计**: 4-6 天

---

## 🎯 技术挑战

### 1. WebSocket 持久连接
- **挑战**: Flutter 应用可能后台运行，WebSocket 连接可能断开
- **方案**: 实现自动重连机制

### 2. ACP 协议版本
- **挑战**: OpenClaw 的 ACP 实现可能有版本差异
- **方案**: 支持协议版本协商

### 3. 工具调用
- **挑战**: OpenClaw 的工具系统复杂（bash、file-system 等）
- **方案**: 逐步支持，先实现核心工具

---

## 📚 参考资源

- **OpenClaw GitHub**: https://github.com/Moltbot/OpenClaw (假设)
- **ACP 协议**: JSON-RPC 2.0 标准
- **CSDN 分析**: [OpenClaw源代码分析](https://blog.csdn.net/Lnjoying/article/details/157642430)

---

**文档版本**: v1.0.0  
**创建时间**: 2026-02-05  
**作者**: AI Agent Hub Team
