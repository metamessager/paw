import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/logger_service.dart';

/// 日志查看器界面
/// 
/// P1: 提供日志查看和导出功能
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({Key? key}) : super(key: key);

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  final _logger = LoggerService();
  List<LogEntry> _logs = [];
  LogLevel? _selectedLevel;
  bool _autoScroll = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadLogs() {
    setState(() {
      _logs = _logger.getMemoryLogs(level: _selectedLevel);
      if (_autoScroll && _logs.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    });
  }

  Future<void> _exportLogs() async {
    final path = await _logger.exportLogs();
    if (path != null && mounted) {
      await Share.shareXFiles(
        [XFile(path)],
        subject: 'AI Agent Hub Logs',
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('日志已导出')),
        );
      }
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除日志'),
        content: const Text('确定要清除所有日志吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _logger.clearOldLogs(daysToKeep: 0);
      _loadLogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统日志'),
        actions: [
          // 日志级别筛选
          PopupMenuButton<LogLevel?>(
            icon: const Icon(Icons.filter_list),
            tooltip: '筛选日志级别',
            initialValue: _selectedLevel,
            onSelected: (level) {
              setState(() {
                _selectedLevel = level;
                _loadLogs();
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: null,
                child: Text('全部'),
              ),
              const PopupMenuItem(
                value: LogLevel.debug,
                child: Text('🐛 Debug'),
              ),
              const PopupMenuItem(
                value: LogLevel.info,
                child: Text('ℹ️ Info'),
              ),
              const PopupMenuItem(
                value: LogLevel.warning,
                child: Text('⚠️ Warning'),
              ),
              const PopupMenuItem(
                value: LogLevel.error,
                child: Text('❌ Error'),
              ),
            ],
          ),
          
          // 自动滚动开关
          IconButton(
            icon: Icon(_autoScroll ? Icons.lock_open : Icons.lock),
            tooltip: _autoScroll ? '禁用自动滚动' : '启用自动滚动',
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
            },
          ),

          // 更多操作
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'export':
                  _exportLogs();
                  break;
                case 'clear':
                  _clearLogs();
                  break;
                case 'refresh':
                  _loadLogs();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('刷新'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.share),
                  title: Text('导出日志'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete, color: Colors.red),
                  title: Text('清除日志', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 统计信息栏
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('总计', _logs.length, Colors.blue),
                _buildStatItem(
                  'Error',
                  _logs.where((l) => l.level == LogLevel.error).length,
                  Colors.red,
                ),
                _buildStatItem(
                  'Warning',
                  _logs.where((l) => l.level == LogLevel.warning).length,
                  Colors.orange,
                ),
                _buildStatItem(
                  'Info',
                  _logs.where((l) => l.level == LogLevel.info).length,
                  Colors.green,
                ),
              ],
            ),
          ),

          // 日志列表
          Expanded(
            child: _logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '暂无日志',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      return _buildLogItem(_logs[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildLogItem(LogEntry log) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        leading: _getLogIcon(log.level),
        title: Text(
          log.message,
          style: const TextStyle(fontSize: 14),
        ),
        subtitle: Text(
          '${log.timeString} • ${log.levelString}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        children: [
          if (log.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  'Error: ${log.error}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
            ),
          if (log.stackTrace != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  log.stackTrace.toString(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Icon _getLogIcon(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return const Icon(Icons.bug_report, color: Colors.grey);
      case LogLevel.info:
        return const Icon(Icons.info_outline, color: Colors.blue);
      case LogLevel.warning:
        return const Icon(Icons.warning_amber, color: Colors.orange);
      case LogLevel.error:
        return const Icon(Icons.error_outline, color: Colors.red);
    }
  }
}
