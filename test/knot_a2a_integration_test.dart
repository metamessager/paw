import 'package:flutter_test/flutter_test.dart';
import 'package:ai_agent_hub/models/universal_agent.dart';
import 'package:ai_agent_hub/models/a2a/agent_card.dart';
import 'package:ai_agent_hub/models/a2a/task.dart';
import 'package:ai_agent_hub/models/a2a/response.dart';

/// Knot A2A 集成测试
void main() {
  group('KnotUniversalAgent Tests', () {
    test('KnotUniversalAgent 应该正确序列化和反序列化', () {
      // 创建 KnotUniversalAgent
      final agent = KnotUniversalAgent(
        id: 'knot_123',
        name: 'Test Knot Agent',
        avatar: '🤖',
        bio: 'A test Knot agent',
        knotId: 'agent-123',
        endpoint: 'https://knot.woa.com/api/v1/agents/agent-123/a2a',
        apiToken: 'test-token-123',
      );

      // 序列化
      final json = agent.toJson();

      expect(json['id'], 'knot_123');
      expect(json['name'], 'Test Knot Agent');
      expect(json['type'], 'knot');
      expect(json['knot_id'], 'agent-123');
      expect(json['endpoint'], 'https://knot.woa.com/api/v1/agents/agent-123/a2a');
      expect(json['api_token'], 'test-token-123');

      // 反序列化
      final deserialized = KnotUniversalAgent.fromJson(json);

      expect(deserialized.id, agent.id);
      expect(deserialized.name, agent.name);
      expect(deserialized.knotId, agent.knotId);
      expect(deserialized.endpoint, agent.endpoint);
      expect(deserialized.apiToken, agent.apiToken);
    });

    test('KnotUniversalAgent 应该支持 AgentCard', () {
      final agentCard = A2AAgentCard(
        name: 'Test Agent',
        description: 'A test agent',
        version: '1.0.0',
        endpoints: A2AEndpoints(
          agentCard: '/card',
          tasks: '/tasks',
          stream: '/stream',
        ),
      );

      final agent = KnotUniversalAgent(
        id: 'knot_123',
        name: 'Test Knot Agent',
        avatar: '🤖',
        knotId: 'agent-123',
        endpoint: 'https://knot.woa.com/api/v1/agents/agent-123/a2a',
        apiToken: 'test-token-123',
        agentCard: agentCard,
      );

      expect(agent.agentCard, isNotNull);
      expect(agent.agentCard?.name, 'Test Agent');
      expect(agent.agentCard?.description, 'A test agent');

      // 序列化后也应该保留 AgentCard
      final json = agent.toJson();
      final deserialized = KnotUniversalAgent.fromJson(json);

      expect(deserialized.agentCard, isNotNull);
      expect(deserialized.agentCard?.name, 'Test Agent');
    });

    test('KnotUniversalAgent 应该正确转换为 Agent', () {
      final agent = KnotUniversalAgent(
        id: 'knot_123',
        name: 'Test Knot Agent',
        avatar: '🤖',
        bio: 'A test agent',
        knotId: 'agent-123',
        endpoint: 'https://knot.woa.com/api/v1/agents/agent-123/a2a',
        apiToken: 'test-token-123',
      );

      final standardAgent = agent.toAgent();

      expect(standardAgent.id, agent.id);
      expect(standardAgent.name, agent.name);
      expect(standardAgent.avatar, agent.avatar);
      expect(standardAgent.bio, agent.bio);
      expect(standardAgent.provider.type, 'knot');
      expect(standardAgent.provider.platform, 'Knot Platform');
    });
  });

  group('A2AResponse Tests', () {
    test('A2AResponse 应该正确解析 RUN_STARTED 事件', () {
      final event = {
        'type': 'RUN_STARTED',
        'data': {
          'message_id': 'msg-123',
        },
      };

      final response = A2AResponse.fromAGUIEvent(event);

      expect(response.messageId, 'msg-123');
      expect(response.type, 'RUN_STARTED');
      expect(response.isDone, false);
      expect(response.isError, false);
    });

    test('A2AResponse 应该正确解析 TEXT_MESSAGE_CONTENT 事件', () {
      final event = {
        'type': 'TEXT_MESSAGE_CONTENT',
        'data': {
          'message_id': 'msg-123',
          'text': 'Hello, world!',
        },
      };

      final response = A2AResponse.fromAGUIEvent(event);

      expect(response.messageId, 'msg-123');
      expect(response.type, 'TEXT_MESSAGE_CONTENT');
      expect(response.content, 'Hello, world!');
      expect(response.hasContent, true);
    });

    test('A2AResponse 应该正确解析 THINKING_MESSAGE_CONTENT 事件', () {
      final event = {
        'type': 'THINKING_MESSAGE_CONTENT',
        'data': {
          'message_id': 'msg-123',
          'thinking': 'Let me think about this...',
        },
      };

      final response = A2AResponse.fromAGUIEvent(event);

      expect(response.messageId, 'msg-123');
      expect(response.type, 'THINKING_MESSAGE_CONTENT');
      expect(response.thinking, 'Let me think about this...');
      expect(response.hasThinking, true);
    });

    test('A2AResponse 应该正确解析 TOOL_CALL_STARTED 事件', () {
      final event = {
        'type': 'TOOL_CALL_STARTED',
        'data': {
          'message_id': 'msg-123',
          'tool_call_id': 'tool-456',
          'tool_name': 'search_web',
        },
      };

      final response = A2AResponse.fromAGUIEvent(event);

      expect(response.messageId, 'msg-123');
      expect(response.type, 'TOOL_CALL_STARTED');
      expect(response.hasToolCall, true);
      expect(response.toolCall?.id, 'tool-456');
      expect(response.toolCall?.name, 'search_web');
      expect(response.toolCall?.status, 'started');
    });

    test('A2AResponse 应该正确解析 TOOL_CALL_COMPLETED 事件', () {
      final event = {
        'type': 'TOOL_CALL_COMPLETED',
        'data': {
          'message_id': 'msg-123',
          'tool_call_id': 'tool-456',
          'tool_name': 'search_web',
          'result': {'found': 3, 'query': 'test'},
        },
      };

      final response = A2AResponse.fromAGUIEvent(event);

      expect(response.messageId, 'msg-123');
      expect(response.type, 'TOOL_CALL_COMPLETED');
      expect(response.hasToolCall, true);
      expect(response.toolCall?.id, 'tool-456');
      expect(response.toolCall?.status, 'completed');
      expect(response.toolCall?.result, isNotNull);
    });

    test('A2AResponse 应该正确解析 PROGRESS 事件', () {
      final event = {
        'type': 'PROGRESS',
        'data': {
          'message_id': 'msg-123',
          'current': 50,
          'total': 100,
          'message': 'Processing...',
        },
      };

      final response = A2AResponse.fromAGUIEvent(event);

      expect(response.messageId, 'msg-123');
      expect(response.type, 'PROGRESS');
      expect(response.hasProgress, true);
      expect(response.progress?.current, 50);
      expect(response.progress?.total, 100);
      expect(response.progress?.percentage, 50.0);
      expect(response.progress?.message, 'Processing...');
    });

    test('A2AResponse 应该正确解析 RUN_COMPLETED 事件', () {
      final event = {
        'type': 'RUN_COMPLETED',
        'data': {
          'message_id': 'msg-123',
        },
      };

      final response = A2AResponse.fromAGUIEvent(event);

      expect(response.messageId, 'msg-123');
      expect(response.type, 'RUN_COMPLETED');
      expect(response.isDone, true);
      expect(response.isError, false);
    });

    test('A2AResponse 应该正确解析 RUN_FAILED 事件', () {
      final event = {
        'type': 'RUN_FAILED',
        'data': {
          'message_id': 'msg-123',
          'error': 'Something went wrong',
        },
      };

      final response = A2AResponse.fromAGUIEvent(event);

      expect(response.messageId, 'msg-123');
      expect(response.type, 'RUN_FAILED');
      expect(response.isDone, true);
      expect(response.isError, true);
      expect(response.error, 'Something went wrong');
    });

    test('A2AResponse 应该正确序列化和反序列化', () {
      final response = A2AResponse(
        messageId: 'msg-123',
        type: 'TEXT_MESSAGE_CONTENT',
        content: 'Hello, world!',
        isDone: false,
        isError: false,
      );

      // 序列化
      final json = response.toJson();

      expect(json['message_id'], 'msg-123');
      expect(json['type'], 'TEXT_MESSAGE_CONTENT');
      expect(json['content'], 'Hello, world!');
      expect(json['is_done'], false);
      expect(json['is_error'], false);

      // 反序列化
      final deserialized = A2AResponse.fromJson(json);

      expect(deserialized.messageId, response.messageId);
      expect(deserialized.type, response.type);
      expect(deserialized.content, response.content);
      expect(deserialized.isDone, response.isDone);
      expect(deserialized.isError, response.isError);
    });
  });

  group('UniversalAgent Factory Tests', () {
    test('UniversalAgent.fromJson 应该正确创建 KnotUniversalAgent', () {
      final json = {
        'id': 'knot_123',
        'name': 'Test Knot Agent',
        'avatar': '🤖',
        'bio': 'A test agent',
        'type': 'knot',
        'knot_id': 'agent-123',
        'endpoint': 'https://knot.woa.com/api/v1/agents/agent-123/a2a',
        'api_token': 'test-token-123',
        'provider': {
          'name': 'Knot Agent',
          'platform': 'Knot Platform',
          'type': 'knot',
        },
        'status': {'state': 'online'},
      };

      final agent = UniversalAgent.fromJson(json);

      expect(agent, isA<KnotUniversalAgent>());
      expect(agent.id, 'knot_123');
      expect(agent.name, 'Test Knot Agent');
      expect(agent.type, 'knot');

      final knotAgent = agent as KnotUniversalAgent;
      expect(knotAgent.knotId, 'agent-123');
      expect(knotAgent.endpoint, 'https://knot.woa.com/api/v1/agents/agent-123/a2a');
      expect(knotAgent.apiToken, 'test-token-123');
    });

    test('UniversalAgent.fromJson 应该正确创建 A2AAgent', () {
      final json = {
        'id': 'a2a_123',
        'name': 'Test A2A Agent',
        'avatar': '🌐',
        'type': 'a2a',
        'base_uri': 'https://example.com',
        'api_key': 'test-key',
        'provider': {
          'name': 'A2A Agent',
          'platform': 'A2A Protocol',
          'type': 'a2a',
        },
        'status': {'state': 'online'},
      };

      final agent = UniversalAgent.fromJson(json);

      expect(agent, isA<A2AAgent>());
      expect(agent.id, 'a2a_123');
      expect(agent.name, 'Test A2A Agent');
      expect(agent.type, 'a2a');

      final a2aAgent = agent as A2AAgent;
      expect(a2aAgent.baseUri, 'https://example.com');
      expect(a2aAgent.apiKey, 'test-key');
    });
  });
}
