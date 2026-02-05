import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/knot_agent.dart';
import '../services/local_knot_agent_service.dart';

/// Knot 任务发送和管理页面
class KnotTaskScreen extends StatefulWidget {
  final KnotAgent agent;

  const KnotTaskScreen({Key? key, required this.agent}) : super(key: key);

  @override
  State<KnotTaskScreen> createState() => _KnotTaskScreenState();
}

class _KnotTaskScreenState extends State<KnotTaskScreen> {
  final _knotApiService = LocalKnotAgentService();
  final _promptController = TextEditingController();
  final _workspacePathController = TextEditingController();
  
  List<KnotTask> _tasks = [];
  bool _isLoading = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _workspacePathController.text = widget.agent.workspacePath ?? '';
    _loadTasks();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _workspacePathController.dispose();
    _knotApiService.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);

    try {
      final tasks = await _knotApiService.getAgentTasks(
        widget.agent.knotAgentId,
      );
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载任务失败: $e')),
        );
      }
    }
  }

  Future<void> _sendTask() async {
    if (_promptController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入任务指令')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final taskResult = await _knotApiService.sendTask(
        widget.agent.knotAgentId,
        _promptController.text.trim(),
      );

      _promptController.clear();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('任务已发送')),
        );
        _loadTasks();
        
        // 开始轮询任务状态
        _pollTaskStatus(taskResult.taskId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _pollTaskStatus(String taskId) async {
    while (mounted) {
      try {
        final task = await _knotApiService.getTaskStatus(taskId);
        
        if (task == null) {
          break;
        }
        
        // 更新任务列表
        setState(() {
          final index = _tasks.indexWhere((t) => t.id == taskId);
          if (index != -1) {
            _tasks[index] = task;
          }
        });

        if (task.isFinished) {
          if (task.isCompleted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('任务完成: ${task.id}')),
            );
          } else if (task.isFailed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('任务失败: ${task.error ?? "未知错误"}'),
                backgroundColor: Colors.red,
              ),
            );
          }
          break;
        }

        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        break;
      }
    }
  }

  Future<void> _cancelTask(KnotTask task) async {
    try {
      await _knotApiService.cancelTask(task.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('任务已取消')),
      );
      _loadTasks();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取消失败: $e')),
      );
    }
  }

  void _showTaskDetail(KnotTask task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: ListView(
              controller: scrollController,
              children: [
                Row(
                  children: [
                    const Text(
                      '任务详情',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 16),
                _buildDetailItem('任务 ID', task.id),
                _buildDetailItem('状态', task.status),
                _buildDetailItem(
                  '创建时间',
                  DateFormat('yyyy-MM-dd HH:mm:ss').format(task.createdAt),
                ),
                if (task.startedAt != null)
                  _buildDetailItem(
                    '开始时间',
                    DateFormat('yyyy-MM-dd HH:mm:ss').format(task.startedAt!),
                  ),
                if (task.completedAt != null)
                  _buildDetailItem(
                    '完成时间',
                    DateFormat('yyyy-MM-dd HH:mm:ss').format(task.completedAt!),
                  ),
                const SizedBox(height: 16),
                const Text(
                  '任务指令',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(task.prompt),
                ),
                if (task.result != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '执行结果',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(task.result!),
                  ),
                ],
                if (task.error != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '错误信息',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      task.error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
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
            const Text('发送任务'),
            Text(
              widget.agent.name,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadTasks,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          // 任务输入区
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _promptController,
                  decoration: const InputDecoration(
                    labelText: '任务指令',
                    hintText: '例如：帮我分析这个项目的代码结构',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.chat),
                  ),
                  maxLines: 3,
                  enabled: !_isSending,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _workspacePathController,
                  decoration: const InputDecoration(
                    labelText: '工作区路径（可选）',
                    hintText: '例如：/workspace/my-project',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.folder),
                  ),
                  enabled: !_isSending,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSending ? null : _sendTask,
                    icon: _isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(_isSending ? '发送中...' : '发送任务'),
                  ),
                ),
              ],
            ),
          ),
          
          // 任务列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _tasks.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无任务\n请在上方输入任务指令',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadTasks,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _tasks.length,
                          itemBuilder: (context, index) {
                            return _buildTaskCard(_tasks[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(KnotTask task) {
    Color statusColor;
    IconData statusIcon;
    
    switch (task.status) {
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case 'running':
        statusColor = Colors.blue;
        statusIcon = Icons.pending;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.schedule;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showTaskDetail(task),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    task.status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('HH:mm:ss').format(task.createdAt),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  if (task.isRunning) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _cancelTask(task),
                      icon: const Icon(Icons.stop, color: Colors.red, size: 20),
                      tooltip: '取消任务',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                task.prompt,
                style: const TextStyle(fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (task.result != null || task.error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: task.error != null ? Colors.red[50] : Colors.green[50],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    task.error ?? task.result!,
                    style: TextStyle(
                      fontSize: 12,
                      color: task.error != null ? Colors.red[800] : Colors.green[800],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
