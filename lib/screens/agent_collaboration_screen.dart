import 'package:flutter/material.dart';
import '../models/agent.dart';
import '../services/agent_collaboration_service.dart';
import '../services/local_api_service.dart';
import '../services/logger_service.dart';
import '../services/error_handler_service.dart';

/// Agent 协作界面
/// 
/// P2: 提供 Agent 协作任务创建和执行界面
class AgentCollaborationScreen extends StatefulWidget {
  final LocalApiService apiService;

  const AgentCollaborationScreen({
    Key? key,
    required this.apiService,
  }) : super(key: key);

  @override
  State<AgentCollaborationScreen> createState() => _AgentCollaborationScreenState();
}

class _AgentCollaborationScreenState extends State<AgentCollaborationScreen> {
  late final AgentCollaborationService _collaborationService;
  late final ErrorHandlerService _errorHandler;
  final _logger = LoggerService();

  final _formKey = GlobalKey<FormState>();
  final _taskNameController = TextEditingController();
  final _taskDescriptionController = TextEditingController();
  final _messageController = TextEditingController();

  List<Agent> _availableAgents = [];
  List<Agent> _selectedAgents = [];
  CollaborationStrategy _selectedStrategy = CollaborationStrategy.sequential;
  bool _loading = false;
  CollaborationResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _collaborationService = AgentCollaborationService(widget.apiService, _logger);
    _errorHandler = ErrorHandlerService(_logger);
    _loadAgents();
  }

  @override
  void dispose() {
    _taskNameController.dispose();
    _taskDescriptionController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadAgents() async {
    try {
      final agents = await widget.apiService.listAgents();
      setState(() {
        _availableAgents = agents;
      });
    } catch (e) {
      if (mounted) {
        _errorHandler.handleError(context, e, title: '加载 Agent 失败');
      }
    }
  }

  Future<void> _executeCollaboration() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAgents.isEmpty) {
      _errorHandler.showWarning(context, '请至少选择一个 Agent');
      return;
    }

    setState(() => _loading = true);

    try {
      // 创建协作任务
      final task = await _collaborationService.createCollaborationTask(
        taskName: _taskNameController.text,
        taskDescription: _taskDescriptionController.text,
        agentIds: _selectedAgents.map((a) => a.id).toList(),
        initiatorId: 'user',
        strategy: _selectedStrategy,
      );

      // 执行任务
      final result = await _collaborationService.executeCollaboration(
        task,
        _messageController.text,
      );

      setState(() {
        _lastResult = result;
        _loading = false;
      });

      if (result.status == CollaborationStatus.completed) {
        _errorHandler.showSuccess(context, '协作任务执行成功');
      } else {
        _errorHandler.showWarning(context, '协作任务执行失败: ${result.error}');
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        _errorHandler.handleError(context, e, title: '执行协作任务失败');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent 协作'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelp(),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 协作说明卡片
            Card(
              color: Colors.purple.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.groups, size: 32, color: Colors.purple),
                        const SizedBox(width: 12),
                        Text(
                          'Agent 协作',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '让多个 Agent 协作完成复杂任务，支持多种协作策略。',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 任务名称
            TextFormField(
              controller: _taskNameController,
              decoration: const InputDecoration(
                labelText: '任务名称',
                hintText: '例: 市场调研报告',
                prefixIcon: Icon(Icons.title),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入任务名称';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 任务描述
            TextFormField(
              controller: _taskDescriptionController,
              decoration: const InputDecoration(
                labelText: '任务描述',
                hintText: '详细描述要完成的任务',
                prefixIcon: Icon(Icons.description),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入任务描述';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 初始消息
            TextFormField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: '初始消息',
                hintText: '开始协作的消息',
                prefixIcon: Icon(Icons.message),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入初始消息';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // 选择协作策略
            const Text(
              '协作策略',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...CollaborationStrategy.values.map((strategy) {
              return RadioListTile<CollaborationStrategy>(
                value: strategy,
                groupValue: _selectedStrategy,
                onChanged: (value) {
                  setState(() => _selectedStrategy = value!);
                },
                title: Text(_getStrategyName(strategy)),
                subtitle: Text(_getStrategyDescription(strategy)),
              );
            }),
            const SizedBox(height: 24),

            // 选择 Agent
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '选择 Agent',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '已选择 ${_selectedAgents.length}/${_availableAgents.length}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_availableAgents.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('暂无可用的 Agent'),
                ),
              )
            else
              ...List.Agent.map((agent) {
                final isSelected = _selectedAgents.contains(agent);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (selected) {
                    setState(() {
                      if (selected == true) {
                        _selectedAgents.add(agent);
                      } else {
                        _selectedAgents.remove(agent);
                      }
                    });
                  },
                  title: Text(agent.name),
                  subtitle: Text(agent.description ?? '无描述'),
                  secondary: CircleAvatar(
                    child: Text(agent.name[0]),
                  ),
                );
              }),
            const SizedBox(height: 24),

            // 执行按钮
            ElevatedButton(
              onPressed: _loading ? null : _executeCollaboration,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.purple,
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('开始协作', style: TextStyle(fontSize: 16)),
            ),

            // 结果展示
            if (_lastResult != null) ...[
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              _buildResultSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultSection() {
    if (_lastResult == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _lastResult!.status == CollaborationStatus.completed
                  ? Icons.check_circle
                  : Icons.error,
              color: _lastResult!.status == CollaborationStatus.completed
                  ? Colors.green
                  : Colors.red,
            ),
            const SizedBox(width: 8),
            const Text(
              '协作结果',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 最终输出
        if (_lastResult!.finalOutput != null) ...[
          const Text(
            '最终输出',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(_lastResult!.finalOutput!),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 各Agent结果
        if (_lastResult!.results.isNotEmpty) ...[
          const Text(
            '各 Agent 结果',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._lastResult!.results.entries.map((entry) {
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(entry.key[0]),
                ),
                title: Text(entry.key),
                subtitle: Text(entry.value),
              ),
            );
          }),
        ],
      ],
    );
  }

  String _getStrategyName(CollaborationStrategy strategy) {
    switch (strategy) {
      case CollaborationStrategy.sequential:
        return '顺序执行';
      case CollaborationStrategy.parallel:
        return '并行执行';
      case CollaborationStrategy.voting:
        return '投票机制';
      case CollaborationStrategy.pipeline:
        return '流水线';
    }
  }

  String _getStrategyDescription(CollaborationStrategy strategy) {
    switch (strategy) {
      case CollaborationStrategy.sequential:
        return 'Agent 按顺序依次处理，上一个的输出作为下一个的输入';
      case CollaborationStrategy.parallel:
        return '所有 Agent 同时处理相同的输入';
      case CollaborationStrategy.voting:
        return '多个 Agent 投票选择最佳结果';
      case CollaborationStrategy.pipeline:
        return '每个 Agent 处理特定阶段';
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('协作策略说明'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('顺序执行', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Agent 按顺序依次处理，适合需要逐步优化的任务。\n'),
              Text('并行执行', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('所有 Agent 同时处理，适合需要多角度分析的任务。\n'),
              Text('投票机制', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('多个 Agent 投票选择最佳方案，适合决策类任务。\n'),
              Text('流水线', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('每个 Agent 处理特定阶段，适合复杂的分步任务。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
