import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/a2a/agent_card.dart';
import '../models/a2a/task.dart';
import '../models/a2a/response.dart';
import '../models/a2a/artifact.dart';
import '../models/a2a/part.dart';

/// Knot A2A 适配器
///
/// 将标准 A2A 调用转换为 Knot 特定的 A2A 格式
/// 基于 Knot 官方文档：https://iwiki.woa.com/p/4016604641
class KnotA2AAdapter {
  final http.Client _httpClient;
  final _uuid = const Uuid();

  KnotA2AAdapter({http.Client? httpClient  /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
})
      : _httpClient = httpClient ?? http.Client();

  /// 转换 Knot Agent Card 为标准 A2A Agent Card
  ///
  /// Knot Agent Card 格式:
  /// ```json
  /// {
  ///   "agent_id": "xxx",
  ///   "name": "Agent Name",
  ///   "description": "Description",
  ///   "endpoint": "http://knot.woa.com/apigw/v1/agents/a2a/chat/completions/xxx",
  ///   "model": "deepseek-v3.1",
  ///   "need_history": "no",
  ///   "version": "1.0.0"
  ///   /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
  /// ```
  A2AAgentCard convertKnotAgentCard(Map<String, dynamic> knotCard) {
    return A2AAgentCard(
      name: knotCard['name'] ?? '',
      description: knotCard['description'] ?? '',
      version: knotCard['version'] ?? '1.0.0',
      endpoints: A2AEndpoints(
        tasks: knotCard['endpoint'],
        stream: null, // Knot 使用同一端点返回流式响应
        status: null, // Knot 不提供单独的状态查询端点
      ),
      capabilities: ['chat', 'a2a', 'agui', 'streaming'],
      authentication: A2AAuthentication(
        schemes: ['bearer', 'apiKey'],
      ),
      metadata: {
        'agent_id': knotCard['agent_id'],
        'need_history': knotCard['need_history'] ?? 'no',
        'model': knotCard['model'] ?? '',
        'platform': 'knot',
        /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
},
    );
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

  /// 构建 Knot A2A 请求体
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [task]: A2A Task (包含用户消息)
  /// - [conversationId]: 会话 ID
  /// - [messageId]: 消息 ID
  /// - [model]: 模型名称 (可选: deepseek-v3.1, deepseek-v3.2, glm-4.6, etc.)
  Map<String, dynamic> buildKnotA2ARequest({
    required String agentId,
    required A2ATask task,
    required String conversationId,
    required String messageId,
    String model = 'deepseek-v3.1',
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}) {
    final callId = 'call_${_uuid.v4()  /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}';

    return {
      'a2a': {
        'agent_cards': [], // Knot 会自动注入 sub_agent
        'request': {
          'agent_id': agentId,
          'id': callId,
          'method': 'message',
          'need_history': 'no',
          'params': {
            'message': {
              'context_id': conversationId,
              'kind': 'message',
              'message_id': messageId,
              'parts': [
                {
                  'kind': 'text',
                  'text': task.instruction,
                  /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
              ],
              'role': 'user',
              /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
            /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
},
          'parent_agent_id': '',
          'parent_id': null,
          /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
        /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
},
      'chat_extra': {
        'extra_header': {
          'X-Platform': 'knot',
          /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
},
        'model': model,
        'scene_platform': 'knot',
        /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
},
      'conversation_id': conversationId,
      'is_sub_agent': true,
      'message_id': messageId,
      /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
};
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

  /// 解析 AGUI 事件
  ///
  /// AGUI 事件在 A2A Response 的 parts[0].text 中以 JSON 字符串形式返回
  AGUIEvent? parseAGUIEvent(String text) {
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      return AGUIEvent.fromJson(json);
      /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
} catch (e) {
      // 不是有效的 AGUI JSON，忽略
      return null;
      /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

  /// 解析 Knot A2A Response (单条消息)
  ///
  /// Knot 返回的流式消息格式:
  /// ```json
  /// {
  ///   "contextId": "xxx",
  ///   "kind": "message",
  ///   "messageId": "xxx",
  ///   "parts": [
  ///     {
  ///       "kind": "text",
  ///       "text": "{\"type\":\"TEXT_MESSAGE_CONTENT\",\"rawEvent\":{...  /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}  /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}"
  ///       /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
  ///   ],
  ///   "role": "agent"
  ///   /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
  /// ```
  A2AResponse? parseKnotA2AMessage(Map<String, dynamic> message) {
    final parts = message['parts'] as List? ?? [];
    final textBuffer = StringBuffer();
    String state = 'running';
    String? error;

    for (var part in parts) {
      if (part['kind'] == 'text') {
        final text = part['text'] as String;

        // 尝试解析 AGUI 事件
        final aguiEvent = parseAGUIEvent(text);
        if (aguiEvent != null) {
          switch (aguiEvent.type.toUpperCase()) {
            case 'TEXT_MESSAGE_CONTENT':
              final content = aguiEvent.rawEvent['content'] as String?;
              if (content != null) {
                textBuffer.write(content);
                /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
              break;

            case 'TEXT_MESSAGE_END':
              // 文本消息结束，但任务可能还在运行
              break;

            case 'RUN_COMPLETED':
              state = 'completed';
              break;

            case 'RUN_ERROR':
              state = 'failed';
              final tipOption = aguiEvent.rawEvent['tip_option'];
              error = tipOption?['content'] ?? 'Unknown error';
              break;

            // 思考消息事件
            case 'THINKING_TEXT_MESSAGE_CONTENT':
              // 可以选择显示思考过程
              break;

            // 工具调用事件
            case 'TOOL_CALL_START':
            case 'TOOL_CALL_ARGS':
            case 'TOOL_CALL_END':
            case 'TOOL_CALL_RESULT':
              // 可以记录工具调用日志
              break;

            // 生命周期事件
            case 'STEP_STARTED':
            case 'STEP_FINISHED':
              // 可以记录步骤信息
              break;

            default:
              // 其他事件暂不处理
              break;
            /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
          /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
} else {
          // 如果不是 JSON，直接追加文本
          textBuffer.write(text);
          /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
        /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
      /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

    return A2AResponse(
      taskId: message['messageId'] ?? '',
      state: state,
      artifacts: textBuffer.isNotEmpty
          ? [
              A2AArtifact(
                parts: [
                  A2APart(
                    type: 'text',
                    content: textBuffer.toString(),
                  )
                ],
              )
            ]
          : null,
      error: error,
    );
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

  /// 提交任务到 Knot (流式响应)
  ///
  /// 参数:
  /// - [agentCard]: A2A Agent Card (通过 convertKnotAgentCard 转换)
  /// - [task]: A2A Task
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名 (RTX ID)
  /// - [apiToken]: Knot API Token (从 knot.woa.com/settings/token 获取)
  ///
  /// 返回:
  /// 流式 A2A Response，实时返回消息内容
  Stream<A2AResponse> submitTaskToKnot({
    required A2AAgentCard agentCard,
    required A2ATask task,
    required String conversationId,
    String? username,
    String? apiToken,
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}) async* {
    final messageId = _uuid.v4();
    final agentId = agentCard.metadata?['agent_id'] as String?;

    if (agentId == null) {
      throw Exception('Knot agent_id not found in agent card metadata');
      /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

    final model = (agentCard.metadata?['model'] as String?)?.isEmpty ?? true
        ? 'deepseek-v3.1'
        : agentCard.metadata!['model'] as String;

    // 构建请求
    final requestBody = buildKnotA2ARequest(
      agentId: agentId,
      task: task,
      conversationId: conversationId,
      messageId: messageId,
      model: model,
    );

    // 创建流式请求
    final request = http.Request(
      'POST',
      Uri.parse(agentCard.endpoints.tasks),
    );

    request.headers.addAll({
      'Content-Type': 'application/json',
      'Connection': 'keep-alive',
      'X-Conversation-Id': conversationId,
      'X-Request-Id': messageId,
      'X-Username': username ?? 'anonymous',
      'X-Request-Platform': 'knot',
      /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
});

    // 添加认证
    if (apiToken != null) {
      request.headers['x-knot-api-token'] = apiToken;
      /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

    request.body = jsonEncode(requestBody);

    // 发送流式请求
    final streamedResponse = await _httpClient.send(request);

    if (streamedResponse.statusCode != 200) {
      throw Exception(
        'Knot A2A request failed: ${streamedResponse.statusCode  /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}',
      );
      /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

    // 解析流式响应
    A2AResponse? lastResponse;
    final completeTextBuffer = StringBuffer();

    await for (var chunk in streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (chunk.trim().isEmpty) continue;

      // 移除 "data: " 前缀
      var jsonStr = chunk.trim();
      if (jsonStr.startsWith('data:')) {
        jsonStr = jsonStr.substring(5).trim();
        /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

      if (jsonStr == '[DONE]') {
        // 流结束
        if (lastResponse != null) {
          yield lastResponse.copyWith(state: 'completed');
          /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
        break;
        /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        final response = parseKnotA2AMessage(json);

        if (response != null) {
          // 累积完整内容
          if (response.artifacts != null && response.artifacts!.isNotEmpty) {
            final newContent =
                response.artifacts!.first.parts.first.content ?? '';
            completeTextBuffer.write(newContent);

            // 创建包含累积内容的响应
            final cumulativeResponse = A2AResponse(
              taskId: response.taskId,
              state: response.state,
              artifacts: [
                A2AArtifact(
                  parts: [
                    A2APart(
                      type: 'text',
                      content: completeTextBuffer.toString(),
                    )
                  ],
                )
              ],
              error: response.error,
            );

            lastResponse = cumulativeResponse;
            yield cumulativeResponse;
            /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
} else {
            lastResponse = response;
            yield response;
            /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

          // 如果任务完成或失败，提前退出
          if (response.state == 'completed' || response.state == 'failed') {
            break;
            /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
          /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
        /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
} catch (e) {
        print('Failed to parse Knot A2A chunk: $jsonStr, error: $e');
        /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
      /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

  /// 提交任务到 Knot (同步，等待完成)
  ///
  /// 与 [submitTaskToKnot] 相同，但会等待任务完成后返回最终结果
  Future<A2AResponse> submitTaskToKnotSync({
    required A2AAgentCard agentCard,
    required A2ATask task,
    required String conversationId,
    String? username,
    String? apiToken,
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}) async {
    A2AResponse? finalResponse;

    await for (var response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      finalResponse = response;

      if (response.state == 'completed' || response.state == 'failed') {
        break;
        /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
      /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

    return finalResponse ??
        A2AResponse(
          taskId: '',
          state: 'failed',
          error: 'No response received from Knot',
        );
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

  void dispose() {
    _httpClient.close();
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
  /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

/// AGUI 事件模型
///
/// 基于 Knot 官方 AGUI 协议
/// 参考: https://iwiki.woa.com/p/4016457374
class AGUIEvent {
  /// 事件类型
  ///
  /// 常用类型:
  /// - TEXT_MESSAGE_START: 文本消息开始
  /// - TEXT_MESSAGE_CONTENT: 文本消息内容
  /// - TEXT_MESSAGE_END: 文本消息结束
  /// - RUN_STARTED: 任务开始
  /// - RUN_COMPLETED: 任务完成
  /// - RUN_ERROR: 任务错误
  /// - THINKING_TEXT_MESSAGE_*: 思考消息
  /// - TOOL_CALL_*: 工具调用
  /// - STEP_STARTED/STEP_FINISHED: 生命周期事件
  final String type;

  /// 时间戳 (Unix timestamp)
  final int timestamp;

  /// 原始事件数据
  ///
  /// 包含事件特定字段，例如:
  /// - message_id: 消息 ID
  /// - conversation_id: 会话 ID
  /// - content: 消息内容 (TEXT_MESSAGE_CONTENT)
  /// - tip_option: 错误提示 (RUN_ERROR)
  /// - token_usage: Token 使用统计 (STEP_FINISHED)
  final Map<String, dynamic> rawEvent;

  /// 线程 ID (通常等于 conversation_id)
  final String? threadId;

  /// 运行 ID (通常等于 message_id)
  final String? runId;

  AGUIEvent({
    required this.type,
    required this.timestamp,
    required this.rawEvent,
    this.threadId,
    this.runId,
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
});

  factory AGUIEvent.fromJson(Map<String, dynamic> json) {
    return AGUIEvent(
      type: json['type'] as String,
      timestamp: json['timestamp'] as int,
      rawEvent: json['rawEvent'] as Map<String, dynamic>,
      threadId: json['threadId'] as String?,
      runId: json['runId'] as String?,
    );
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'timestamp': timestamp,
      'rawEvent': rawEvent,
      if (threadId != null) 'threadId': threadId,
      if (runId != null) 'runId': runId,
      /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
};
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}

  @override
  String toString() {
    return 'AGUIEvent(type: $type, timestamp: $timestamp, rawEvent: $rawEvent)';
    /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
  /// 流式发送消息到 Knot Agent（简化方法）
  ///
  /// 参数:
  /// - [agentId]: Knot Agent ID
  /// - [endpoint]: Knot Agent A2A 端点
  /// - [apiToken]: Knot API Token
  /// - [message]: 用户消息文本
  /// - [conversationId]: 会话 ID
  /// - [username]: 用户名（可选）
  ///
  /// 返回:
  /// 流式 A2A Response
  Stream<A2AResponse> streamMessageToKnotAgent({
    required String agentId,
    required String endpoint,
    required String apiToken,
    required String message,
    required String conversationId,
    String? username,
  }) async* {
    // 创建 Agent Card
    final agentCard = A2AAgentCard(
      name: 'Knot Agent',
      description: 'Knot Agent',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: endpoint,
        stream: null,
        status: null,
      ),
      capabilities: ['chat', 'a2a', 'streaming'],
      authentication: A2AAuthentication(schemes: ['bearer']),
      metadata: {
        'agent_id': agentId,
        'platform': 'knot',
      },
    );

    // 创建任务
    final task = A2ATask(
      instruction: message,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    // 流式提交任务
    await for (final response in submitTaskToKnot(
      agentCard: agentCard,
      task: task,
      conversationId: conversationId,
      username: username,
      apiToken: apiToken,
    )) {
      yield response;
    }
  }
}
