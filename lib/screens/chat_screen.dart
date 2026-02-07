import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/message.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final appState = Provider.of<AppState>(context, listen: false);
    
    // 检查用户登录
    if (appState.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先登录'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    final channel = appState.currentChannel;

    // 检查频道选择
    if (channel == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先选择一个频道'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    _messageController.clear();

    // 显示发送状态
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('发送中...'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    // 使用流式发送消息
    try {
      await for (final message in appState.sendMessageStream(
        content,
        channelId: channel.id,
      )) {
        // 消息已通过 AppState 自动更新到 UI
        // 滚动到底部
        if (_scrollController.hasClients && mounted) {
          Future.delayed(const Duration(milliseconds: 50), () {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: '关闭',
              textColor: Colors.white,
              onPressed: () => appState.clearError(),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<AppState>(
          builder: (context, appState, _) {
            final channel = appState.currentChannel;
            if (channel == null) return const Text('Chat');

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(channel.name),
                if (channel.isGroup || channel.isPublic)
                  Text(
                    '${channel.memberCount} 成员',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // TODO: 显示频道信息
            },
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          final messages = appState.currentChannelMessages;

          return Column(
            children: [
              // 错误提示横幅
              if (appState.error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.red.shade100,
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          appState.error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        color: Colors.red,
                        onPressed: () => appState.clearError(),
                      ),
                    ],
                  ),
                ),

              // 消息列表
              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Text(
                              '💬',
                              style: TextStyle(fontSize: 64),
                            ),
                            SizedBox(height: 16),
                            Text('还没有消息'),
                            SizedBox(height: 8),
                            Text(
                              '发送一条消息开始对话',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final isMyMessage = message.from.id == appState.currentUser?.id;
                          
                          return MessageBubble(
                            message: message,
                            isMyMessage: isMyMessage,
                          );
                        },
                      ),
              ),

              // 输入框
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      // 附件按钮
                      IconButton(
                        icon: const Icon(Icons.attach_file),
                        onPressed: () {
                          // TODO: 附件功能
                        },
                      ),

                      // 输入框
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: '输入消息...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // 发送按钮
                      IconButton(
                        icon: const Icon(Icons.send),
                        color: Theme.of(context).primaryColor,
                        onPressed: _sendMessage,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
