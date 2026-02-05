import 'package:flutter/material.dart';
import '../models/knot_agent.dart';
import '../models/channel.dart';
import '../services/local_knot_agent_service.dart';
import '../services/knot_channel_bridge_service.dart';

/// Knot Agent 桥接管理页面
class KnotBridgeManagementScreen extends StatefulWidget {
  final String channelId;
  final String channelName;

  const KnotBridgeManagementScreen({
    Key? key,
    required this.channelId,
    required this.channelName,
  }) : super(key: key);

  @override
  State<KnotBridgeManagementScreen> createState() =>
      _KnotBridgeManagementScreenState();
}

class _KnotBridgeManagementScreenState
    extends State<KnotBridgeManagementScreen> {
  final _knotApiService = LocalKnotAgentService();
  late final KnotChannelBridgeService _bridgeService;

  List<KnotAgent> _availableAgents = [];
  List<KnotBridgeConfig> _bridgedAgents = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bridgeService = KnotChannelBridgeService(_knotApiService);
    _loadData();
  }

  @override
  void dispose() {
    _knotApiService.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 加载可用的 Knot Agents
      final agents = await _knotApiService.getKnotAgents();
      
      // 加载已桥接的 Agents
      final bridged = _bridgeService.getBridgesForChannel(widget.channelId);

      setState(() {
        _availableAgents = agents;
        _bridgedAgents = bridged;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _addBridge(KnotAgent agent) async {
    try {
      await _bridgeService.createBridge(
        knotAgentId: agent.knotAgentId,
        channelId: widget.channelId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加 ${agent.name} 到频道')),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    }
  }

  Future<void> _removeBridge(KnotBridgeConfig config) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认移除'),
        content: const Text('确定要将此 Agent 从频道移除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _bridgeService.deleteBridge(
        knotAgentId: config.knotAgentId,
        channelId: config.channelId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已移除')),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移除失败: $e')),
        );
      }
    }
  }

  Future<void> _toggleBridge(KnotBridgeConfig config) async {
    try {
      await _bridgeService.toggleBridge(
        knotAgentId: config.knotAgentId,
        channelId: config.channelId,
        enabled: !config.enabled,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(config.enabled ? '已禁用' : '已启用'),
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  void _showAddAgentDialog() {
    // 过滤出未桥接的 Agents
    final unbridgedAgents = _availableAgents.where((agent) {
      return !_bridgedAgents.any((b) => b.knotAgentId == agent.knotAgentId);
    }).toList();

    if (unbridgedAgents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可添加的 Knot Agent')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加 Knot Agent'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: unbridgedAgents.length,
            itemBuilder: (context, index) {
              final agent = unbridgedAgents[index];
              return ListTile(
                leading: Text(
                  agent.avatar,
                  style: const TextStyle(fontSize: 32),
                ),
                title: Text(agent.name),
                subtitle: Text(agent.config.model),
                onTap: () {
                  Navigator.pop(context);
                  _addBridge(agent);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Knot Agent 桥接'),
            Text(
              widget.channelName,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddAgentDialog,
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
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_bridgedAgents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.link_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '暂无桥接的 Knot Agent',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              '点击右下角 + 按钮添加',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddAgentDialog,
              icon: const Icon(Icons.add),
              label: const Text('添加 Knot Agent'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard(),
        const SizedBox(height: 16),
        ..._bridgedAgents.map((config) => _buildBridgeCard(config)),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  '关于 Knot Agent 桥接',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '• 桥接后，Knot Agent 可以接收和响应此频道的消息\n'
              '• 消息会被转换为 Knot 任务，执行结果返回到频道\n'
              '• 每个消息的响应时间取决于任务复杂度\n'
              '• 可随时启用/禁用或移除桥接',
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue[800],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBridgeCard(KnotBridgeConfig config) {
    // 查找对应的 Agent
    final agent = _availableAgents.firstWhere(
      (a) => a.knotAgentId == config.knotAgentId,
      orElse: () => KnotAgent(
        id: config.knotAgentId,
        name: '未知 Agent',
        knotAgentId: config.knotAgentId,
        config: KnotAgentConfig(model: 'unknown'),
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: config.enabled
                                  ? Colors.green[100]
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              config.enabled ? '已启用' : '已禁用',
                              style: TextStyle(
                                color: config.enabled
                                    ? Colors.green[800]
                                    : Colors.grey[600],
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '模型: ${agent.config.model}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _removeBridge(config),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text(
                    '移除',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _toggleBridge(config),
                  icon: Icon(config.enabled ? Icons.pause : Icons.play_arrow),
                  label: Text(config.enabled ? '禁用' : '启用'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
