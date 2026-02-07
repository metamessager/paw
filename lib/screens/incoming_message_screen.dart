/// 主动消息通知界面
/// 展示 OpenClaw Agent 主动发起的聊天消息
library;

import 'package:flutter/material.dart';
import '../models/acp_server_message.dart';
import '../services/acp_server_service.dart';
import '../widgets/common_widgets.dart';

class IncomingMessageScreen extends StatefulWidget {
  final ACPServerService acpServerService;

  const IncomingMessageScreen({
    Key? key,
    required this.acpServerService,
  }) : super(key: key);

  @override
  State<IncomingMessageScreen> createState() => _IncomingMessageScreenState();
}

class _IncomingMessageScreenState extends State<IncomingMessageScreen> {
  final List<IncomingMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _listenToIncomingMessages();
  }

  void _listenToIncomingMessages() {
    widget.acpServerService.requestStream.listen((request) {
      if (request.requestType == ACPRequestType.initiateChat) {
        setState(() {
          _messages.insert(
            0,
            IncomingMessage(
              id: request.id,
              agentId: request.sourceAgentId ?? 'unknown',
              message: request.params?['message'] ?? '',
              timestamp: request.timestamp,
              isRead: false,
            ),
          );
        });

        // 显示通知
        _showNotification(request);
      }
    });
  }

  void _showNotification(ACPServerRequest request) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.message, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    request.sourceAgentId ?? 'Unknown Agent',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    request.params?['message'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: '查看',
          textColor: Colors.white,
          onPressed: () {
            // 跳转到消息详情
          },
        ),
        duration: const Duration(seconds: 5),
        backgroundColor: Colors.blue[700],
      ),
    );
  }

  void _markAsRead(IncomingMessage message) {
    setState(() {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        _messages[index] = message.copyWith(isRead: true);
      }
    });
  }

  void _deleteMessage(IncomingMessage message) {
    setState(() {
      _messages.removeWhere((m) => m.id == message.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _messages.where((m) => !m.isRead).length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('主动消息'),
            if (unreadCount > 0)
              Text(
                '$unreadCount 条未读',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _showClearAllDialog,
              tooltip: '清空所有消息',
            ),
        ],
      ),
      body: _messages.isEmpty
          ? const EmptyState(
              title: '暂无主动消息',
              icon: Icons.inbox,
              message: '当 Agent 主动联系您时，消息会显示在这里',
            )
          : ListView.separated(
              itemCount: _messages.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                return _buildMessageItem(_messages[index]);
              },
            ),
    );
  }

  Widget _buildMessageItem(IncomingMessage message) {
    return Dismissible(
      key: Key(message.id),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _deleteMessage(message),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: message.isRead ? null : Colors.blue[50],
        child: InkWell(
          onTap: () => _showMessageDetail(message),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: const Icon(Icons.smart_toy, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.agentId,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            _formatTime(message.timestamp),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!message.isRead)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // Message content
                Text(
                  message.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),

                const SizedBox(height: 12),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!message.isRead)
                      TextButton.icon(
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('标记已读'),
                        onPressed: () => _markAsRead(message),
                      ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.reply, size: 16),
                      label: const Text('回复'),
                      onPressed: () => _replyToMessage(message),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMessageDetail(IncomingMessage message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.message),
            const SizedBox(width: 8),
            Expanded(child: Text(message.agentId)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '时间: ${_formatDateTime(message.timestamp)}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              Text(message.message),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _markAsRead(message);
            },
            child: const Text('标记已读'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _replyToMessage(message);
            },
            child: const Text('回复'),
          ),
        ],
      ),
    );

    _markAsRead(message);
  }

  void _replyToMessage(IncomingMessage message) {
    // TODO: 实现回复功能
    // 这里应该打开聊天界面并自动填充回复对象
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('回复功能开发中...')),
    );
  }

  Future<void> _showClearAllDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空所有消息'),
        content: const Text('确定要清空所有消息吗？此操作不可撤销。'),
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
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _messages.clear();
      });
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} 分钟前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} 小时前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} 天前';
    } else {
      return _formatDateTime(dateTime);
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

/// 主动消息数据模型
class IncomingMessage {
  final String id;
  final String agentId;
  final String message;
  final DateTime timestamp;
  final bool isRead;

  IncomingMessage({
    required this.id,
    required this.agentId,
    required this.message,
    required this.timestamp,
    required this.isRead,
  });

  IncomingMessage copyWith({
    String? id,
    String? agentId,
    String? message,
    DateTime? timestamp,
    bool? isRead,
  }) {
    return IncomingMessage(
      id: id ?? this.id,
      agentId: agentId ?? this.agentId,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }
}
