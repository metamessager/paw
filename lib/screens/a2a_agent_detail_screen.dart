import 'package:flutter/material.dart';
import '../models/universal_agent.dart';
import '../models/a2a/task.dart';
import '../services/universal_agent_service.dart';

/// A2A Agent 详情页面
class A2AAgentDetailScreen extends StatefulWidget {
  final A2AAgent agent;
  final UniversalAgentService agentService;
  final VoidCallback onUpdated;

  const A2AAgentDetailScreen({
    Key? key,
    required this.agent,
    required this.agentService,
    required this.onUpdated,
  }) : super(key: key);

  @override
  State<A2AAgentDetailScreen> createState() => _A2AAgentDetailScreenState();
}

class _A2AAgentDetailScreenState extends State<A2AAgentDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _taskController = TextEditingController();
  List<A2ATaskResponse> _taskHistory = [];
  bool _loadingTasks = false;
  bool _sendingTask = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadTaskHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _taskController.dispose();
    super.dispose();
  }

  Future<void> _loadTaskHistory() async {
    setState(() => _loadingTasks = true);
    try {
      final tasks = await widget.agentService.getAgentTasks(widget.agent.id);
      setState(() {
        _taskHistory = tasks;
        _loadingTasks = false;
      });
    } catch (e) {
      setState(() => _loadingTasks = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.agent.name),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.info), text: '信息'),
            Tab(icon: Icon(Icons.chat), text: '对话'),
            Tab(icon: Icon(Icons.history), text: '历史'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInfoTab(),
          _buildChatTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  // 信息标签页
  Widget _buildInfoTab() {
    final agent = widget.agent;
    final card = agent.agentCard;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Agent 基本信息
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.blue,
                      child: Text(agent.avatar, style: const TextStyle(fontSize: 32)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            agent.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (agent.bio != null) Text(agent.bio!),
                          const SizedBox(height: 4),
                          Chip(
                            label: Text(agent.status.state),
                            avatar: Icon(
                              Icons.circle,
                              size: 12,
                              color: agent.status.isOnline
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 32),
                _buildInfoRow('Agent ID', agent.id),
                _buildInfoRow('类型', 'A2A Protocol'),
                _buildInfoRow('Base URI', agent.baseUri),
                if (agent.apiKey != null)
                  _buildInfoRow('API Key', '●●●●●●●●'),
              ],
            ),
          ),
        ),

        // Agent Card 信息
        if (card != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Agent Card',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('版本', card.version),
                  _buildInfoRow('描述', card.description),
                  const Divider(height: 24),
                  const Text(
                    '端点 (Endpoints)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow('Tasks', card.endpoints.tasks),
                  if (card.endpoints.stream != null)
                    _buildInfoRow('Stream', card.endpoints.stream!),
                  if (card.endpoints.status != null)
                    _buildInfoRow('Status', card.endpoints.status!),
                  const Divider(height: 24),
                  const Text(
                    '能力 (Capabilities)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: card.capabilities
                        .map((cap) => Chip(
                              label: Text(cap),
                              backgroundColor: Colors.blue.shade100,
                            ))
                        .toList(),
                  ),
                  if (card.authentication != null) ...[
                    const Divider(height: 24),
                    const Text(
                      '认证 (Authentication)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: card.authentication!.schemes
                          .map((scheme) => Chip(label: Text(scheme)))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // 对话标签页
  Widget _buildChatTab() {
    return Column(
      children: [
        Expanded(
          child: _taskHistory.isEmpty
              ? const Center(child: Text('发送消息开始对话'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _taskHistory.length,
                  itemBuilder: (context, index) {
                    return _buildTaskMessage(_taskHistory[index]);
                  },
                ),
        ),
        _buildMessageInput(),
      ],
    );
  }

  Widget _buildTaskMessage(A2ATaskResponse task) {
    final hasArtifacts = task.artifacts != null && task.artifacts!.isNotEmpty;
    String responseText = '等待响应...';

    if (task.isCompleted && hasArtifacts) {
      final textParts = task.artifacts!.first.parts
          .where((p) => p.type == 'text')
          .toList();
      if (textParts.isNotEmpty) {
        responseText = textParts.first.content.toString();
      }
    } else if (task.isFailed) {
      responseText = '错误: ${task.error ?? "未知错误"}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  task.isCompleted
                      ? Icons.check_circle
                      : task.isFailed
                          ? Icons.error
                          : Icons.hourglass_empty,
                  size: 16,
                  color: task.isCompleted
                      ? Colors.green
                      : task.isFailed
                          ? Colors.red
                          : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  task.state.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  'Task: ${task.taskId.substring(0, 8)}...',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            const Divider(),
            Text(responseText),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _taskController,
              decoration: const InputDecoration(
                hintText: '输入消息...',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: null,
              enabled: !_sendingTask,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sendingTask ? null : _sendTask,
            icon: _sendingTask
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  Future<void> _sendTask() async {
    final instruction = _taskController.text.trim();
    if (instruction.isEmpty) return;

    setState(() => _sendingTask = true);
    _taskController.clear();

    try {
      final task = A2ATask(instruction: instruction);
      final response = await widget.agentService.sendTaskToA2AAgent(
        widget.agent,
        task,
        waitForCompletion: true,
      );

      await _loadTaskHistory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('任务完成')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    } finally {
      setState(() => _sendingTask = false);
    }
  }

  // 历史标签页
  Widget _buildHistoryTab() {
    if (_loadingTasks) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_taskHistory.isEmpty) {
      return const Center(child: Text('暂无历史记录'));
    }

    return RefreshIndicator(
      onRefresh: _loadTaskHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _taskHistory.length,
        itemBuilder: (context, index) {
          return _buildHistoryCard(_taskHistory[index]);
        },
      ),
    );
  }

  Widget _buildHistoryCard(A2ATaskResponse task) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          task.isCompleted
              ? Icons.check_circle
              : task.isFailed
                  ? Icons.error
                  : Icons.hourglass_empty,
          color: task.isCompleted
              ? Colors.green
              : task.isFailed
                  ? Colors.red
                  : Colors.orange,
        ),
        title: Text('Task ${task.taskId.substring(0, 12)}...'),
        subtitle: Text(task.state),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Task ID: ${task.taskId}'),
                const SizedBox(height: 8),
                if (task.artifacts != null)
                  ...task.artifacts!.map((artifact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Artifact: ${artifact.name}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        ...artifact.parts.map((part) {
                          return Text('${part.type}: ${part.content}');
                        }),
                      ],
                    );
                  }),
                if (task.error != null)
                  Text(
                    'Error: ${task.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
