import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../services/api_service.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';

/// 频道列表页面
class ChannelListScreen extends StatefulWidget {
  const ChannelListScreen({Key? key}) : super(key: key);

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  final ApiService _apiService = ApiService();
  List<Channel> _channels = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  /// 加载频道列表
  Future<void> _loadChannels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final channels = await _apiService.getChannels();
      setState(() {
        _channels = channels;
        _isLoading = false;
      });
      AppLogger.info('加载了 ${channels.length} 个频道');
    } catch (e) {
      AppLogger.error('加载频道列表失败', e);
      setState(() {
        _errorMessage = ExceptionHandler.getUserMessage(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('频道管理'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChannels,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateChannelDialog(),
        icon: const Icon(Icons.add),
        label: const Text('创建频道'),
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
              onPressed: _loadChannels,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 100,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              '暂无频道',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击下方按钮创建您的第一个频道',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadChannels,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _channels.length,
        itemBuilder: (context, index) {
          final channel = _channels[index];
          return _buildChannelCard(channel);
        },
      ),
    );
  }

  Widget _buildChannelCard(Channel channel) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.purple.withOpacity(0.2),
          child: const Icon(
            Icons.forum,
            color: Colors.purple,
          ),
        ),
        title: Text(
          channel.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${channel.id}'),
            if (channel.description != null && channel.description!.isNotEmpty)
              Text(
                channel.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // TODO: 导航到频道详情
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('打开频道: ${channel.name}')),
          );
        },
      ),
    );
  }

  /// 显示创建频道对话框
  void _showCreateChannelDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建频道'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '频道名称',
                hintText: '输入频道名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: '频道描述（可选）',
                hintText: '输入频道描述',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入频道名称')),
                );
                return;
              }

              Navigator.pop(context);
              await _createChannel(name, descController.text.trim());
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  /// 创建频道
  Future<void> _createChannel(String name, String description) async {
    try {
      final channel = Channel(
        id: '',
        name: name,
        description: description.isEmpty ? null : description,
      );

      await _apiService.createChannel(channel);
      AppLogger.info('成功创建频道: $name');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('频道 "$name" 创建成功')),
        );
        _loadChannels();
      }
    } catch (e) {
      AppLogger.error('创建频道失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ExceptionHandler.getUserMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }
}
