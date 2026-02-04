import 'package:flutter/material.dart';
import '../models/agent.dart';
import '../services/api_service.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import 'agent_detail_screen.dart';

/// Agent 列表页面
class AgentListScreen extends StatefulWidget {
  const AgentListScreen({Key? key}) : super(key: key);

  @override
  State<AgentListScreen> createState() => _AgentListScreenState();
}

class _AgentListScreenState extends State<AgentListScreen> {
  final ApiService _apiService = ApiService();
  List<Agent> _agents = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  /// 加载 Agent 列表
  Future<void> _loadAgents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final agents = await _apiService.getAgents();
      setState(() {
        _agents = agents;
        _isLoading = false;
      });
      AppLogger.info('加载了 ${agents.length} 个 Agent');
    } catch (e) {
      AppLogger.error('加载 Agent 列表失败', e);
      setState(() {
        _errorMessage = ExceptionHandler.getUserMessage(e);
        _isLoading = false;
      });
    }
  }

  /// 删除 Agent
  Future<void> _deleteAgent(Agent agent) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 Agent "${agent.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _apiService.deleteAgent(agent.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 ${agent.name}')),
      );
      _loadAgents(); // 刷新列表
    } catch (e) {
      AppLogger.error('删除 Agent 失败', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ExceptionHandler.getUserMessage(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent 管理'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAgents,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToAddAgent(),
        icon: const Icon(Icons.add),
        label: const Text('添加 Agent'),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadAgents,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
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
            Icon(
              Icons.smart_toy_outlined,
              size: 100,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              '暂无 Agent',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击下方按钮添加您的第一个 Agent',
              style: TextStyle(color: Colors.grey[600]),
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
        itemBuilder: (context, index) {
          final agent = _agents[index];
          return _buildAgentCard(agent);
        },
      ),
    );
  }

  Widget _buildAgentCard(Agent agent) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _navigateToAgentDetail(agent),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 30,
                backgroundColor: _getStatusColor(agent.status).withOpacity(0.2),
                child: agent.avatar != null && agent.avatar!.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          agent.avatar!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.smart_toy,
                              size: 30,
                              color: _getStatusColor(agent.status),
                            );
                          },
                        ),
                      )
                    : Icon(
                        Icons.smart_toy,
                        size: 30,
                        color: _getStatusColor(agent.status),
                      ),
              ),
              const SizedBox(width: 16),

              // Agent 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            agent.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _buildStatusChip(agent.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${agent.id}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '类型: ${agent.type}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),

              // 操作按钮
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'detail':
                      _navigateToAgentDetail(agent);
                      break;
                    case 'delete':
                      _deleteAgent(agent);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'detail',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline),
                        SizedBox(width: 8),
                        Text('查看详情'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red),
                        SizedBox(width: 8),
                        Text('删除', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        _getStatusText(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return Colors.green;
      case 'offline':
        return Colors.grey;
      case 'busy':
        return Colors.orange;
      case 'error':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return '在线';
      case 'offline':
        return '离线';
      case 'busy':
        return '忙碌';
      case 'error':
        return '错误';
      default:
        return status;
    }
  }

  void _navigateToAgentDetail(Agent agent) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AgentDetailScreen(agent: agent),
      ),
    ).then((_) => _loadAgents()); // 返回后刷新
  }

  void _navigateToAddAgent() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AgentDetailScreen(),
      ),
    ).then((_) => _loadAgents()); // 返回后刷新
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }
}
