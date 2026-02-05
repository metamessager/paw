import 'package:flutter/material.dart';
import '../models/knot_agent.dart';
import '../services/local_knot_agent_service.dart';
import 'knot_agent_detail_screen.dart';
import 'knot_task_screen.dart';
import 'knot_settings_screen.dart';

/// Knot Agent 管理页面
class KnotAgentScreen extends StatefulWidget {
  const KnotAgentScreen({Key? key}) : super(key: key);

  @override
  State<KnotAgentScreen> createState() => _KnotAgentScreenState();
}

class _KnotAgentScreenState extends State<KnotAgentScreen> {
  final _knotApiService = LocalKnotAgentService();
  List<KnotAgent> _agents = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  @override
  void dispose() {
    _knotApiService.dispose();
    super.dispose();
  }

  Future<void> _loadAgents() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = await _knotApiService.getToken();
      if (token == null || token.isEmpty) {
        setState(() {
          _error = '请先配置 Knot API Token';
          _isLoading = false;
        });
        return;
      }

      final agents = await _knotApiService.getKnotAgents();
      setState(() {
        _agents = agents;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteAgent(KnotAgent agent) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 Agent "${agent.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _knotApiService.deleteKnotAgent(agent.knotAgentId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除成功')),
      );
      _loadAgents();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e')),
      );
    }
  }

  void _sendTask(KnotAgent agent) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => KnotTaskScreen(agent: agent),
      ),
    );
  }

  void _viewAgentDetail(KnotAgent agent) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => KnotAgentDetailScreen(agent: agent),
      ),
    );

    if (result == true) {
      _loadAgents();
    }
  }

  void _addAgent() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const KnotAgentDetailScreen(),
      ),
    );

    if (result == true) {
      _loadAgents();
    }
  }

  void _goToSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const KnotSettingsScreen(),
      ),
    );

    if (result == true) {
      _loadAgents();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knot Agent 管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _goToSettings,
            tooltip: '设置',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAgents,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAgent,
        tooltip: '添加 Agent',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _error!.contains('Token') ? Icons.key : Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _error!.contains('Token') ? _goToSettings : _loadAgents,
              icon: Icon(_error!.contains('Token') ? Icons.settings : Icons.refresh),
              label: Text(_error!.contains('Token') ? '去设置' : '重试'),
            ),
          ],
        ),
      );
    }

    if (_agents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              '暂无 Knot Agent',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _addAgent,
              icon: const Icon(Icons.add),
              label: const Text('添加第一个 Agent'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAgents,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _agents.length,
        itemBuilder: (context, index) => _buildAgentCard(_agents[index]),
      ),
    );
  }

  Widget _buildAgentCard(KnotAgent agent) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => _viewAgentDetail(agent),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    agent.avatar,
                    style: const TextStyle(fontSize: 40),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          agent.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (agent.bio != null && agent.bio!.isNotEmpty)
                          Text(
                            agent.bio!,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: agent.status.isOnline
                          ? Colors.green[100]
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      agent.status.state,
                      style: TextStyle(
                        color: agent.status.isOnline
                            ? Colors.green[800]
                            : Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              _buildInfoRow(Icons.computer, '模型', agent.config.model),
              if (agent.workspaceId != null)
                _buildInfoRow(Icons.folder, '工作区', agent.workspaceId!),
              if (agent.config.mcpServers.isNotEmpty)
                _buildInfoRow(
                  Icons.extension,
                  'MCP 服务',
                  '${agent.config.mcpServers.length} 个',
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _deleteAgent(agent),
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text(
                      '删除',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _sendTask(agent),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('发送任务'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
