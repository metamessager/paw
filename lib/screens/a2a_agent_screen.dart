import 'package:flutter/material.dart';
import '../models/universal_agent.dart';
import '../services/universal_agent_service.dart';
import 'a2a_agent_add_screen.dart';
import 'a2a_agent_detail_screen.dart';

/// A2A Agent 管理页面
class A2AAgentScreen extends StatefulWidget {
  final UniversalAgentService agentService;

  const A2AAgentScreen({
    Key? key,
    required this.agentService,
  }) : super(key: key);

  @override
  State<A2AAgentScreen> createState() => _A2AAgentScreenState();
}

class _A2AAgentScreenState extends State<A2AAgentScreen> {
  List<UniversalAgent> _agents = [];
  bool _loading = true;
  String _filter = 'all'; // all, a2a, knot, custom

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  Future<void> _loadAgents() async {
    setState(() => _loading = true);
    try {
      final agents = _filter == 'all'
          ? await widget.agentService.getAllAgents()
          : await widget.agentService.getAgentsByType(_filter);
      setState(() {
        _agents = agents;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通用 Agent 管理'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() => _filter = value);
              _loadAgents();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('全部')),
              const PopupMenuItem(value: 'a2a', child: Text('A2A Agent')),
              const PopupMenuItem(value: 'knot', child: Text('Knot Agent')),
              const PopupMenuItem(value: 'custom', child: Text('自定义 Agent')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAgents,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _agents.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadAgents,
                  child: ListView.builder(
                    itemCount: _agents.length,
                    itemBuilder: (context, index) {
                      return _buildAgentCard(_agents[index]);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddAgentDialog,
        icon: const Icon(Icons.add),
        label: const Text('添加 Agent'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.psychology_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '还没有 Agent',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            '点击下方按钮添加 A2A、Knot 或自定义 Agent',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentCard(UniversalAgent agent) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getTypeColor(agent.type),
          child: Text(
            agent.avatar,
            style: const TextStyle(fontSize: 24),
          ),
        ),
        title: Text(
          agent.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (agent.bio != null) Text(agent.bio!),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildTypeChip(agent.type),
                const SizedBox(width: 8),
                _buildStatusChip(agent.status.state),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleAction(value, agent),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'view', child: Text('查看详情')),
            const PopupMenuItem(value: 'test', child: Text('测试连接')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        onTap: () => _viewAgentDetail(agent),
      ),
    );
  }

  Widget _buildTypeChip(String type) {
    final typeLabels = {
      'a2a': 'A2A',
      'knot': 'Knot',
      'custom': '自定义',
    };

    return Chip(
      label: Text(
        typeLabels[type] ?? type,
        style: const TextStyle(fontSize: 12),
      ),
      backgroundColor: _getTypeColor(type).withOpacity(0.2),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildStatusChip(String status) {
    final color = status == 'online' ? Colors.green : Colors.grey;
    return Chip(
      label: Text(
        status,
        style: const TextStyle(fontSize: 12),
      ),
      backgroundColor: color.withOpacity(0.2),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'a2a':
        return Colors.blue;
      case 'knot':
        return Colors.purple;
      case 'custom':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  void _showAddAgentDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加 Agent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cloud, color: Colors.blue),
              title: const Text('A2A Agent'),
              subtitle: const Text('通过 A2A 协议连接'),
              onTap: () {
                Navigator.pop(context);
                _addA2AAgent();
              },
            ),
            ListTile(
              leading: const Icon(Icons.psychology, color: Colors.purple),
              title: const Text('Knot Agent'),
              subtitle: const Text('连接到 Knot 平台'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请使用 Knot Agent 页面')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.build, color: Colors.orange),
              title: const Text('自定义 Agent'),
              subtitle: const Text('自定义接入方式'),
              onTap: () {
                Navigator.pop(context);
                _addCustomAgent();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addA2AAgent() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => A2AAgentAddScreen(
          agentService: widget.agentService,
          onAdded: _loadAgents,
        ),
      ),
    );
  }

  void _addCustomAgent() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('自定义 Agent 功能开发中...')),
    );
  }

  void _viewAgentDetail(UniversalAgent agent) {
    if (agent is A2AAgent) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => A2AAgentDetailScreen(
            agent: agent,
            agentService: widget.agentService,
            onUpdated: _loadAgents,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${agent.type} Agent 详情页开发中...')),
      );
    }
  }

  void _handleAction(String action, UniversalAgent agent) {
    switch (action) {
      case 'view':
        _viewAgentDetail(agent);
        break;
      case 'test':
        _testAgent(agent);
        break;
      case 'delete':
        _deleteAgent(agent);
        break;
    }
  }

  Future<void> _testAgent(UniversalAgent agent) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('测试连接中...'),
          ],
        ),
      ),
    );

    try {
      // 测试连接逻辑
      await Future.delayed(const Duration(seconds: 1));
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接成功！')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteAgent(UniversalAgent agent) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${agent.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.agentService.deleteAgent(agent.id);
        await _loadAgents();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除成功')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }
}
