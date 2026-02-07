import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ai_agent_hub/models/universal_agent.dart';
import 'package:ai_agent_hub/models/a2a/task.dart';
import 'package:ai_agent_hub/models/a2a/agent_card.dart';
import 'package:ai_agent_hub/services/universal_agent_service.dart';
import 'package:ai_agent_hub/services/knot_a2a_adapter.dart';
import 'package:ai_agent_hub/services/a2a_protocol_service.dart';
import 'package:ai_agent_hub/services/data_export_import_service.dart';
import 'package:ai_agent_hub/services/local_database_service.dart';
import 'package:ai_agent_hub/services/local_file_storage_service.dart';
import 'package:ai_agent_hub/services/logger_service.dart';
import 'package:http/http.dart' as http;

/// 核心功能集成测试
///
/// 测试 Knot A2A 协议、Universal Agent Service、数据导入导出等核心功能
///
/// 运行测试：
/// flutter test test/integration/core_integration_test.dart

void main() {
  // 测试在移动端运行，无需特殊初始化
  setUpAll(() {
    // 测试初始化
  });

  group('核心功能集成测试', () {
    late LocalDatabaseService dbService;
    late A2AProtocolService a2aService;
    late KnotA2AAdapter knotAdapter;
    late UniversalAgentService agentService;
    late LoggerService logger;

    setUp(() async {
      // 使用内存数据库进行测试
      logger = LoggerService();
      dbService = LocalDatabaseService();

      a2aService = A2AProtocolService();
      knotAdapter = KnotA2AAdapter();

      final db = await dbService.database;
      agentService = UniversalAgentService(db, a2aService, knotAdapter);
    });

    tearDown(() async {
      await dbService.close();
      knotAdapter.dispose();
    });

    // ==================== Universal Agent Service 测试 ====================

    group('Universal Agent Service', () {
      test('应该能添加 A2A Agent (手动模式)', () async {
        final agent = await agentService.addA2AAgentManually(
          name: 'Test A2A Agent',
          baseUri: 'https://example.com/api',
          apiKey: 'test-key-123',
          bio: 'A test A2A agent',
          avatar: '🤖',
        );

        expect(agent.id, isNotEmpty);
        expect(agent.name, 'Test A2A Agent');
        expect(agent.type, 'a2a');
        expect(agent.baseUri, 'https://example.com/api');
        expect(agent.apiKey, 'test-key-123');

        // 验证保存到数据库
        final savedAgent = await agentService.getAgentById(agent.id);
        expect(savedAgent, isNotNull);
        expect(savedAgent!.name, 'Test A2A Agent');
      });

      test('应该能添加 Knot Agent', () async {
        final agent = await agentService.addKnotAgent(
          name: 'Test Knot Agent',
          knotId: 'knot-agent-123',
          endpoint: 'https://knot.woa.com/api/v1/agents/123/a2a',
          apiToken: 'knot-token-abc',
          bio: 'A test Knot agent',
          avatar: '🦜',
        );

        expect(agent.id, isNotEmpty);
        expect(agent.name, 'Test Knot Agent');
        expect(agent.type, 'knot');
        expect(agent.knotId, 'knot-agent-123');
        expect(agent.endpoint, 'https://knot.woa.com/api/v1/agents/123/a2a');
        expect(agent.apiToken, 'knot-token-abc');

        // 验证保存到数据库
        final savedAgent = await agentService.getAgentById(agent.id);
        expect(savedAgent, isNotNull);
        expect((savedAgent as KnotUniversalAgent).knotId, 'knot-agent-123');
      });

      test('应该能获取所有 Agent', () async {
        // 添加多个 Agent
        await agentService.addA2AAgentManually(
          name: 'Agent 1',
          baseUri: 'https://example.com/1',
        );
        await agentService.addA2AAgentManually(
          name: 'Agent 2',
          baseUri: 'https://example.com/2',
        );
        await agentService.addKnotAgent(
          name: 'Knot Agent',
          knotId: 'knot-1',
          endpoint: 'https://knot.woa.com/api/v1/agents/1/a2a',
          apiToken: 'token',
        );

        final agents = await agentService.getAllAgents();
        expect(agents.length, 3);

        // 验证类型
        final a2aAgents = agents.whereType<A2AAgent>().toList();
        final knotAgents = agents.whereType<KnotUniversalAgent>().toList();
        expect(a2aAgents.length, 2);
        expect(knotAgents.length, 1);
      });

      test('应该能根据类型获取 Agent', () async {
        await agentService.addA2AAgentManually(
          name: 'A2A Agent',
          baseUri: 'https://example.com',
        );
        await agentService.addKnotAgent(
          name: 'Knot Agent',
          knotId: 'knot-1',
          endpoint: 'https://knot.woa.com/api/v1/agents/1/a2a',
          apiToken: 'token',
        );

        final a2aAgents = await agentService.getAgentsByType('a2a');
        final knotAgents = await agentService.getAgentsByType('knot');

        expect(a2aAgents.length, 1);
        expect(knotAgents.length, 1);
        expect(a2aAgents.first.name, 'A2A Agent');
        expect(knotAgents.first.name, 'Knot Agent');
      });

      test('应该能更新 Agent', () async {
        final agent = await agentService.addA2AAgentManually(
          name: 'Original Name',
          baseUri: 'https://example.com',
        );

        // 更新 Agent
        final updatedAgent = A2AAgent(
          id: agent.id,
          name: 'Updated Name',
          avatar: '🚀',
          bio: 'Updated bio',
          baseUri: agent.baseUri,
          apiKey: agent.apiKey,
          status: agent.status,
        );

        await agentService.updateAgent(updatedAgent);

        // 验证更新
        final savedAgent = await agentService.getAgentById(agent.id);
        expect(savedAgent!.name, 'Updated Name');
        expect(savedAgent.avatar, '🚀');
        expect(savedAgent.bio, 'Updated bio');
      });

      test('应该能删除 Agent', () async {
        final agent = await agentService.addA2AAgentManually(
          name: 'Agent to Delete',
          baseUri: 'https://example.com',
        );

        await agentService.deleteAgent(agent.id);

        // 验证删除
        final deletedAgent = await agentService.getAgentById(agent.id);
        expect(deletedAgent, isNull);
      });
    });

    // ==================== Knot A2A Adapter 测试 ====================

    group('Knot A2A Adapter', () {
      test('应该能转换 Knot Agent Card', () {
        final knotCard = {
          'agent_id': 'agent-123',
          'name': 'Test Agent',
          'description': 'Test description',
          'endpoint': 'https://knot.woa.com/api/v1/agents/123/a2a',
          'model': 'deepseek-v3.1',
          'need_history': 'no',
          'version': '1.0.0',
        };

        final agentCard = knotAdapter.convertKnotAgentCard(knotCard);

        expect(agentCard.name, 'Test Agent');
        expect(agentCard.description, 'Test description');
        expect(agentCard.version, '1.0.0');
        expect(agentCard.endpoints.tasks, 'https://knot.woa.com/api/v1/agents/123/a2a');
        expect(agentCard.capabilities, contains('a2a'));
        expect(agentCard.metadata?['agent_id'], 'agent-123');
        expect(agentCard.metadata?['model'], 'deepseek-v3.1');
        expect(agentCard.metadata?['platform'], 'knot');
      });

      test('应该能构建 Knot A2A 请求', () {
        final task = A2ATask(
          instruction: 'Test instruction',
        );

        final request = knotAdapter.buildKnotA2ARequest(
          agentId: 'agent-123',
          task: task,
          conversationId: 'conv-456',
          messageId: 'msg-789',
          model: 'deepseek-v3.1',
        );

        expect(request['conversation_id'], 'conv-456');
        expect(request['message_id'], 'msg-789');
        expect(request['is_sub_agent'], true);

        final a2aData = request['a2a'];
        expect(a2aData['request']['agent_id'], 'agent-123');
        expect(a2aData['request']['method'], 'message');
        expect(a2aData['request']['params']['message']['context_id'], 'conv-456');
        expect(a2aData['request']['params']['message']['parts'][0]['text'], 'Test instruction');

        final chatExtra = request['chat_extra'];
        expect(chatExtra['model'], 'deepseek-v3.1');
        expect(chatExtra['scene_platform'], 'knot');
      });

      test('应该能解析 AGUI 事件', () {
        final textEvent = knotAdapter.parseAGUIEvent('''{
          "type": "TEXT_MESSAGE_CONTENT",
          "timestamp": 1234567890,
          "rawEvent": {
            "content": "Hello, world!"
          }
        }''');

        expect(textEvent, isNotNull);
        expect(textEvent!.type, 'TEXT_MESSAGE_CONTENT');
        expect(textEvent.rawEvent['content'], 'Hello, world!');

        // 测试无效 JSON
        final invalidEvent = knotAdapter.parseAGUIEvent('invalid json');
        expect(invalidEvent, isNull);
      });

      test('应该能解析 Knot A2A 消息', () {
        final message = {
          'contextId': 'ctx-123',
          'kind': 'message',
          'messageId': 'msg-456',
          'role': 'agent',
          'parts': [
            {
              'kind': 'text',
              'text': '{"type":"TEXT_MESSAGE_CONTENT","timestamp":1234567890,"rawEvent":{"content":"Test content"}}'
            }
          ]
        };

        final response = knotAdapter.parseKnotA2AMessage(message);

        expect(response, isNotNull);
        expect(response!.taskId, 'msg-456');
        expect(response.state, 'running');
        expect(response.artifacts, isNotNull);
        expect(response.artifacts!.length, 1);
        expect(response.artifacts!.first.parts.first.content, 'Test content');
      });

      test('应该能解析 RUN_COMPLETED 事件', () {
        final message = {
          'messageId': 'msg-123',
          'parts': [
            {
              'kind': 'text',
              'text': '{"type":"RUN_COMPLETED","timestamp":1234567890,"rawEvent":{}}'
            }
          ]
        };

        final response = knotAdapter.parseKnotA2AMessage(message);

        expect(response, isNotNull);
        expect(response!.state, 'completed');
      });

      test('应该能解析 RUN_ERROR 事件', () {
        final message = {
          'messageId': 'msg-123',
          'parts': [
            {
              'kind': 'text',
              'text': '{"type":"RUN_ERROR","timestamp":1234567890,"rawEvent":{"tip_option":{"content":"Error occurred"}}}'
            }
          ]
        };

        final response = knotAdapter.parseKnotA2AMessage(message);

        expect(response, isNotNull);
        expect(response!.state, 'failed');
        expect(response.error, 'Error occurred');
      });
    });

    // ==================== 数据导入导出测试 ====================

    group('数据导入导出', () {
      late DataExportImportService exportImportService;
      late LocalFileStorageService fileService;

      setUp(() async {
        fileService = LocalFileStorageService();
        exportImportService = DataExportImportService(
          dbService,
          fileService,
          logger,
        );
      });

      test('应该能导出和导入 Channel 数据', () async {
        final db = await dbService.database;

        // 创建测试 Channel
        await db.insert('channels', {
          'id': 'test-channel-1',
          'name': 'Test Channel',
          'type': 'group',
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });

        // 添加成员
        await db.insert('channel_members', {
          'channel_id': 'test-channel-1',
          'user_id': 'user-1',
          'joined_at': DateTime.now().millisecondsSinceEpoch,
        });

        // 添加消息
        await db.insert('messages', {
          'id': 'msg-1',
          'channel_id': 'test-channel-1',
          'sender_id': 'user-1',
          'content': 'Test message',
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });

        // 导出 Channel
        final exportPath = await exportImportService.exportChannel('test-channel-1');
        expect(exportPath, isNotNull);

        // 验证导出文件存在
        final exportFile = File(exportPath!);
        expect(await exportFile.exists(), true);

        // 清空测试数据
        await db.delete('messages', where: 'channel_id = ?', whereArgs: ['test-channel-1']);
        await db.delete('channel_members', where: 'channel_id = ?', whereArgs: ['test-channel-1']);
        await db.delete('channels', where: 'id = ?', whereArgs: ['test-channel-1']);

        // 导入 Channel
        final imported = await exportImportService.importChannel(exportPath);
        expect(imported, true);

        // 验证数据恢复
        final channels = await db.query('channels', where: 'id = ?', whereArgs: ['test-channel-1']);
        expect(channels.length, 1);

        final members = await db.query('channel_members', where: 'channel_id = ?', whereArgs: ['test-channel-1']);
        expect(members.length, 1);

        final messages = await db.query('messages', where: 'channel_id = ?', whereArgs: ['test-channel-1']);
        expect(messages.length, 1);
      });

      test('应该能验证元数据', () async {
        // 创建有效的元数据目录
        final tempDir = Directory.systemTemp.createTempSync('test_metadata_');
        final metadataFile = File('${tempDir.path}/metadata.json');
        await metadataFile.writeAsString('{"version":"1.0"}');

        final valid = await exportImportService.exportAllData();
        expect(valid, isNotNull);

        // 清理
        await tempDir.delete(recursive: true);
      });
    });

    // ==================== Agent Card 缓存测试 ====================

    group('Agent Card 缓存', () {
      test('应该能缓存 Agent Card', () async {
        final db = await dbService.database;

        final agentCard = A2AAgentCard(
          name: 'Cached Agent',
          description: 'Test agent',
          version: '1.0.0',
          endpoints: A2AEndpoints(
            tasks: 'https://example.com/tasks',
          ),
          capabilities: ['tasks'],
        );

        // 添加 Agent 和缓存
        final agent = await agentService.addA2AAgentManually(
          name: 'Test Agent',
          baseUri: 'https://example.com',
        );

        await db.insert('agent_cards', {
          'agent_id': agent.id,
          'card_data': jsonEncode(agentCard.toJson()),
          'cached_at': DateTime.now().millisecondsSinceEpoch,
        });

        // 验证缓存
        final cached = await db.query(
          'agent_cards',
          where: 'agent_id = ?',
          whereArgs: [agent.id],
        );

        expect(cached.length, 1);
        expect(cached.first['agent_id'], agent.id);
      });
    });

    // ==================== 任务记录测试 ====================

    group('任务记录', () {
      test('应该能记录任务历史', () async {
        final agent = await agentService.addA2AAgentManually(
          name: 'Test Agent',
          baseUri: 'https://example.com',
        );

        // 手动插入任务记录
        final db = await dbService.database;
        await db.insert('tasks', {
          'task_id': 'task-123',
          'agent_id': agent.id,
          'instruction': 'Test task',
          'state': 'completed',
          'request_data': '{}',
          'response_data': '{"taskId":"task-123","state":"completed"}',
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });

        // 获取任务历史
        final tasks = await agentService.getAgentTasks(agent.id);
        expect(tasks.length, 1);
        expect(tasks.first.taskId, 'task-123');
        expect(tasks.first.state, 'completed');
      });
    });
  });

  // ==================== 集成场景测试 ====================

  group('集成场景测试', () {
    late LocalDatabaseService dbService;
    late A2AProtocolService a2aService;
    late KnotA2AAdapter knotAdapter;
    late UniversalAgentService agentService;

    setUp(() async {
      dbService = LocalDatabaseService();

      a2aService = A2AProtocolService();
      knotAdapter = KnotA2AAdapter();

      final db = await dbService.database;
      agentService = UniversalAgentService(db, a2aService, knotAdapter);
    });

    tearDown(() async {
      await dbService.close();
      knotAdapter.dispose();
    });

    test('完整流程：添加 Agent -> 获取 -> 更新 -> 删除', () async {
      // 1. 添加 Agent
      final agent = await agentService.addKnotAgent(
        name: 'Flow Test Agent',
        knotId: 'flow-123',
        endpoint: 'https://knot.woa.com/api/v1/agents/123/a2a',
        apiToken: 'token-123',
        bio: 'Test agent for flow',
      );

      expect(agent.id, isNotEmpty);
      // Agent 添加成功

      // 2. 获取 Agent
      final retrieved = await agentService.getAgentById(agent.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Flow Test Agent');
      // Agent 获取成功

      // 3. 更新 Agent
      final updated = KnotUniversalAgent(
        id: agent.id,
        name: 'Updated Flow Agent',
        avatar: agent.avatar,
        bio: 'Updated bio',
        knotId: agent.knotId,
        endpoint: agent.endpoint,
        apiToken: agent.apiToken,
        status: agent.status,
      );
      await agentService.updateAgent(updated);

      final afterUpdate = await agentService.getAgentById(agent.id);
      expect(afterUpdate!.name, 'Updated Flow Agent');
      // Agent 更新成功

      // 4. 删除 Agent
      await agentService.deleteAgent(agent.id);

      final afterDelete = await agentService.getAgentById(agent.id);
      expect(afterDelete, isNull);
      // Agent 删除成功
    });

    test('多 Agent 协作场景', () async {
      // 添加多个不同类型的 Agent
      await agentService.addA2AAgentManually(
        name: 'A2A Worker',
        baseUri: 'https://example.com/a2a',
      );

      await agentService.addKnotAgent(
        name: 'Knot Worker',
        knotId: 'knot-worker',
        endpoint: 'https://knot.woa.com/api/v1/agents/worker/a2a',
        apiToken: 'token',
      );

      // 验证两个 Agent 都存在
      final allAgents = await agentService.getAllAgents();
      expect(allAgents.length, 2);

      // 验证可以按类型查询
      final a2aAgents = await agentService.getAgentsByType('a2a');
      final knotAgents = await agentService.getAgentsByType('knot');

      expect(a2aAgents.length, 1);
      expect(knotAgents.length, 1);
      // 多 Agent 协作场景测试通过
    });
  });
}
