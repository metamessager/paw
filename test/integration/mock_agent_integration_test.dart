import 'package:flutter_test/flutter_test.dart';
import 'package:ai_agent_hub/models/universal_agent.dart';
import 'package:ai_agent_hub/models/a2a/response.dart';
import 'package:ai_agent_hub/services/knot_a2a_adapter.dart';
import 'package:ai_agent_hub/services/universal_agent_service.dart';

/// Mock Agent 集成测试
/// 
/// 前置条件：
/// 1. 启动 Mock Agent 服务器: ./scripts/mock_agents/start_mock_agents.sh
/// 2. 确认所有 Agent 健康: ./scripts/mock_agents/test_mock_agents.sh
/// 
/// 运行测试：
/// flutter test test/integration/mock_agent_integration_test.dart

void main() {
  group('Mock Agent 集成测试', () {
    late UniversalAgentService agentService;
    
    setUp(() {
      agentService = UniversalAgentService();
    });
    
    tearDown(() {
      // 清理
    });
    
    // ==================== 基础连接测试 ====================
    
    test('应该能连接到 Knot-Fast Agent (8081)', () async {
      // 创建 Mock Agent
      final agent = UniversalAgent(
        id: 'test_knot_fast',
        name: 'Knot-Fast',
        type: AgentType.knot,
        endpoint: 'http://localhost:8081/a2a/task',
        apiToken: null, // Mock Agent 不需要 token
        description: 'Mock Knot Agent for testing',
        isActive: true,
      );
      
      // 添加 Agent
      await agentService.addKnotAgent(agent);
      
      // 验证 Agent 已添加
      final agents = await agentService.getAllAgents();
      expect(agents.any((a) => a.id == 'test_knot_fast'), true);
    });
    
    test('应该能连接到 Smart-Thinker Agent (8082)', () async {
      final agent = UniversalAgent(
        id: 'test_smart_thinker',
        name: 'Smart-Thinker',
        type: AgentType.knot,
        endpoint: 'http://localhost:8082/a2a/task',
        apiToken: null,
        description: 'Mock Smart Agent with thinking process',
        isActive: true,
      );
      
      await agentService.addKnotAgent(agent);
      
      final agents = await agentService.getAllAgents();
      expect(agents.any((a) => a.id == 'test_smart_thinker'), true);
    });
    
    // ==================== 流式响应测试 ====================
    
    test('应该能接收 Knot-Fast 的流式响应', () async {
      final agent = UniversalAgent(
        id: 'test_knot_fast_stream',
        name: 'Knot-Fast',
        type: AgentType.knot,
        endpoint: 'http://localhost:8081/a2a/task',
        apiToken: null,
        isActive: true,
      );
      
      // 发送流式任务
      final stream = agentService.streamTaskToKnotAgent(
        agent,
        'Flutter 集成测试消息',
      );
      
      // 收集所有响应
      final List<A2AResponse> responses = [];
      await for (final response in stream) {
        responses.add(response);
        print('收到事件: ${response.eventType}');
      }
      
      // 验证响应
      expect(responses.isNotEmpty, true);
      expect(
        responses.any((r) => r.eventType == A2AEventType.runStarted),
        true,
        reason: '应该收到 RUN_STARTED 事件',
      );
      expect(
        responses.any((r) => r.eventType == A2AEventType.textMessageContent),
        true,
        reason: '应该收到 TEXT_MESSAGE_CONTENT 事件',
      );
      expect(
        responses.any((r) => r.eventType == A2AEventType.runCompleted),
        true,
        reason: '应该收到 RUN_COMPLETED 事件',
      );
    });
    
    test('应该能接收 Smart-Thinker 的思考过程', () async {
      final agent = UniversalAgent(
        id: 'test_smart_stream',
        name: 'Smart-Thinker',
        type: AgentType.knot,
        endpoint: 'http://localhost:8082/a2a/task',
        apiToken: null,
        isActive: true,
      );
      
      final stream = agentService.streamTaskToKnotAgent(
        agent,
        '请分析这个测试场景',
      );
      
      final List<A2AResponse> responses = [];
      await for (final response in stream) {
        responses.add(response);
        
        // 打印思考过程
        if (response.eventType == A2AEventType.thoughtMessage) {
          print('💭 思考: ${response.data['thought']}');
        }
      }
      
      // 验证包含思考过程
      expect(
        responses.any((r) => r.eventType == A2AEventType.thoughtMessage),
        true,
        reason: 'Smart Agent 应该返回思考过程',
      );
      
      // 验证包含工具调用
      expect(
        responses.any((r) => r.eventType == A2AEventType.toolCallStarted),
        true,
        reason: 'Smart Agent 应该有工具调用',
      );
    });
    
    test('应该能正确处理 Slow-LLM 的慢速响应', () async {
      final agent = UniversalAgent(
        id: 'test_slow_stream',
        name: 'Slow-LLM',
        type: AgentType.knot,
        endpoint: 'http://localhost:8083/a2a/task',
        apiToken: null,
        isActive: true,
      );
      
      final stream = agentService.streamTaskToKnotAgent(
        agent,
        '测试慢速流式响应',
      );
      
      final List<String> contentChunks = [];
      final List<DateTime> timestamps = [];
      
      await for (final response in stream) {
        if (response.eventType == A2AEventType.textMessageContent) {
          contentChunks.add(response.data['content'] ?? '');
          timestamps.add(DateTime.now());
        }
      }
      
      // 验证收到多个内容块
      expect(contentChunks.length, greaterThan(1));
      
      // 验证时间间隔（慢速响应应该有明显的时间间隔）
      if (timestamps.length > 1) {
        final duration = timestamps.last.difference(timestamps.first);
        expect(duration.inMilliseconds, greaterThan(100));
      }
      
      // 拼接完整内容
      final fullContent = contentChunks.join('');
      print('完整响应: $fullContent');
      expect(fullContent.isNotEmpty, true);
    });
    
    // ==================== 错误处理测试 ====================
    
    test('应该能正确处理 Error-Test Agent 的错误', () async {
      final agent = UniversalAgent(
        id: 'test_error_agent',
        name: 'Error-Test',
        type: AgentType.knot,
        endpoint: 'http://localhost:8084/a2a/task',
        apiToken: null,
        isActive: true,
      );
      
      // 多次尝试，总会遇到错误（30% 概率）
      int errorCount = 0;
      int successCount = 0;
      
      for (int i = 0; i < 10; i++) {
        try {
          final stream = agentService.streamTaskToKnotAgent(
            agent,
            '测试错误处理 - 尝试 $i',
          );
          
          await for (final response in stream) {
            // 收集响应
          }
          
          successCount++;
        } catch (e) {
          errorCount++;
          print('预期的错误 #$errorCount: $e');
        }
      }
      
      print('成功: $successCount, 错误: $errorCount');
      
      // 验证至少遇到一次错误
      expect(errorCount, greaterThan(0), reason: '应该捕获到 30% 的错误');
      
      // 验证也有成功的情况
      expect(successCount, greaterThan(0), reason: '应该有成功的请求');
    });
    
    // ==================== 并发测试 ====================
    
    test('应该能同时处理多个 Agent 的请求', () async {
      final agents = [
        UniversalAgent(
          id: 'concurrent_knot',
          name: 'Knot-Fast',
          type: AgentType.knot,
          endpoint: 'http://localhost:8081/a2a/task',
          apiToken: null,
          isActive: true,
        ),
        UniversalAgent(
          id: 'concurrent_smart',
          name: 'Smart-Thinker',
          type: AgentType.knot,
          endpoint: 'http://localhost:8082/a2a/task',
          apiToken: null,
          isActive: true,
        ),
        UniversalAgent(
          id: 'concurrent_slow',
          name: 'Slow-LLM',
          type: AgentType.knot,
          endpoint: 'http://localhost:8083/a2a/task',
          apiToken: null,
          isActive: true,
        ),
      ];
      
      // 并发发送任务
      final futures = agents.map((agent) async {
        final stream = agentService.streamTaskToKnotAgent(
          agent,
          '并发测试消息',
        );
        
        final List<A2AResponse> responses = [];
        await for (final response in stream) {
          responses.add(response);
        }
        
        return responses;
      }).toList();
      
      // 等待所有任务完成
      final results = await Future.wait(futures);
      
      // 验证所有 Agent 都返回了结果
      expect(results.length, 3);
      for (final responses in results) {
        expect(responses.isNotEmpty, true);
        expect(
          responses.any((r) => r.eventType == A2AEventType.runCompleted),
          true,
        );
      }
    });
    
    // ==================== 内容提取测试 ====================
    
    test('应该能正确提取完整的响应内容', () async {
      final agent = UniversalAgent(
        id: 'test_content_extraction',
        name: 'Knot-Fast',
        type: AgentType.knot,
        endpoint: 'http://localhost:8081/a2a/task',
        apiToken: null,
        isActive: true,
      );
      
      final stream = agentService.streamTaskToKnotAgent(
        agent,
        '这是一个内容提取测试',
      );
      
      String fullContent = '';
      
      await for (final response in stream) {
        if (response.eventType == A2AEventType.textMessageContent) {
          fullContent += response.data['content'] ?? '';
        }
      }
      
      print('提取的完整内容:\n$fullContent');
      
      // 验证内容包含预期的关键词
      expect(fullContent.isNotEmpty, true);
      expect(fullContent.contains('测试'), true);
      expect(fullContent.contains('Agent'), true);
    });
    
    // ==================== AGUI 事件顺序测试 ====================
    
    test('AGUI 事件应该按正确顺序返回', () async {
      final agent = UniversalAgent(
        id: 'test_event_order',
        name: 'Smart-Thinker',
        type: AgentType.knot,
        endpoint: 'http://localhost:8082/a2a/task',
        apiToken: null,
        isActive: true,
      );
      
      final stream = agentService.streamTaskToKnotAgent(
        agent,
        '测试事件顺序',
      );
      
      final List<A2AEventType> eventOrder = [];
      
      await for (final response in stream) {
        eventOrder.add(response.eventType);
      }
      
      print('事件顺序: ${eventOrder.map((e) => e.toString()).join(' → ')}');
      
      // 验证第一个事件是 RUN_STARTED
      expect(eventOrder.first, A2AEventType.runStarted);
      
      // 验证最后一个事件是 RUN_COMPLETED
      expect(eventOrder.last, A2AEventType.runCompleted);
      
      // 验证 THOUGHT_MESSAGE 在 TEXT_MESSAGE_CONTENT 之前
      final thoughtIndex = eventOrder.indexOf(A2AEventType.thoughtMessage);
      final contentIndex = eventOrder.indexOf(A2AEventType.textMessageContent);
      
      if (thoughtIndex != -1 && contentIndex != -1) {
        expect(thoughtIndex, lessThan(contentIndex));
      }
    });
  });
  
  // ==================== 性能测试 ====================
  
  group('Mock Agent 性能测试', () {
    late UniversalAgentService agentService;
    
    setUp(() {
      agentService = UniversalAgentService();
    });
    
    test('快速 Agent 应该在 1 秒内完成', () async {
      final agent = UniversalAgent(
        id: 'perf_test_fast',
        name: 'Knot-Fast',
        type: AgentType.knot,
        endpoint: 'http://localhost:8081/a2a/task',
        apiToken: null,
        isActive: true,
      );
      
      final startTime = DateTime.now();
      
      final stream = agentService.streamTaskToKnotAgent(
        agent,
        '性能测试',
      );
      
      await for (final response in stream) {
        // 处理响应
      }
      
      final duration = DateTime.now().difference(startTime);
      print('Knot-Fast 完成时间: ${duration.inMilliseconds}ms');
      
      expect(duration.inSeconds, lessThan(1));
    });
    
    test('应该能处理大量连续请求', () async {
      final agent = UniversalAgent(
        id: 'stress_test',
        name: 'Knot-Fast',
        type: AgentType.knot,
        endpoint: 'http://localhost:8081/a2a/task',
        apiToken: null,
        isActive: true,
      );
      
      final startTime = DateTime.now();
      const requestCount = 20;
      
      for (int i = 0; i < requestCount; i++) {
        final stream = agentService.streamTaskToKnotAgent(
          agent,
          '压力测试请求 #$i',
        );
        
        await for (final response in stream) {
          // 处理响应
        }
      }
      
      final duration = DateTime.now().difference(startTime);
      final avgTime = duration.inMilliseconds / requestCount;
      
      print('完成 $requestCount 个请求');
      print('总时间: ${duration.inMilliseconds}ms');
      print('平均时间: ${avgTime.toStringAsFixed(2)}ms');
      
      expect(avgTime, lessThan(500)); // 每个请求平均 < 500ms
    });
  });
}
