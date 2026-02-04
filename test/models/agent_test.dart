import 'package:flutter_test/flutter_test.dart';
import 'package:ai_agent_hub/models/agent.dart';

void main() {
  group('Agent Model Tests', () {
    test('fromJson创建Agent对象', () {
      final json = {
        'id': 'agent123',
        'name': 'TestAgent',
        'type': 'assistant',
        'status': 'online',
        'avatar': 'https://example.com/agent.png',
      };
      
      final agent = Agent.fromJson(json);
      
      expect(agent.id, 'agent123');
      expect(agent.name, 'TestAgent');
      expect(agent.type, 'assistant');
      expect(agent.status, 'online');
      expect(agent.avatar, 'https://example.com/agent.png');
    });

    test('toJson转换为JSON', () {
      final agent = Agent(
        id: 'agent123',
        name: 'TestAgent',
        type: 'assistant',
        status: 'online',
        avatar: 'https://example.com/agent.png',
      );
      
      final json = agent.toJson();
      
      expect(json['id'], 'agent123');
      expect(json['name'], 'TestAgent');
      expect(json['type'], 'assistant');
      expect(json['status'], 'online');
      expect(json['avatar'], 'https://example.com/agent.png');
    });

    test('Agent状态判断', () {
      final onlineAgent = Agent(
        id: 'agent1',
        name: 'OnlineAgent',
        type: 'assistant',
        status: 'online',
      );
      
      final offlineAgent = Agent(
        id: 'agent2',
        name: 'OfflineAgent',
        type: 'assistant',
        status: 'offline',
      );
      
      expect(onlineAgent.status, 'online');
      expect(offlineAgent.status, 'offline');
    });

    test('处理缺失字段', () {
      final json = {
        'id': 'agent123',
        'name': 'MinimalAgent',
        'type': 'assistant',
      };
      
      final agent = Agent.fromJson(json);
      
      expect(agent.id, 'agent123');
      expect(agent.name, 'MinimalAgent');
      expect(agent.type, 'assistant');
    });
  });
}
