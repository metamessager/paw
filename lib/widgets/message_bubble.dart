import 'package:flutter/material.dart';
import '../models/message.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMyMessage;

  const MessageBubble({
    Key? key,
    required this.message,
    required this.isMyMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 系统消息
    if (message.isSystemMessage) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.content,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      );
    }

    // 检查是否正在流式输出
    final isStreaming = message.metadata?['streaming'] == true;

    // 普通消息
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMyMessage) ...[
            // Agent/用户头像
            CircleAvatar(
              radius: 16,
              backgroundColor: isStreaming ? Colors.blue[100] : null,
              child: isStreaming
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).primaryColor,
                        ),
                      ),
                    )
                  : Text(
                      _getAvatar(),
                      style: const TextStyle(fontSize: 14),
                    ),
            ),
            const SizedBox(width: 8),
          ],
          
          // 消息内容
          Flexible(
            child: Column(
              crossAxisAlignment: isMyMessage
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // 发送者名字 (非自己的消息)
                if (!isMyMessage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.from.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        if (isStreaming) ...[
                          const SizedBox(width: 4),
                          const Text(
                            '正在输入...',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                
                // 消息气泡
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isMyMessage
                        ? Theme.of(context).primaryColor
                        : (isStreaming ? Colors.blue[50] : Colors.grey[200]),
                    borderRadius: BorderRadius.circular(16),
                    border: isStreaming
                        ? Border.all(color: Colors.blue[200]!, width: 1)
                        : null,
                  ),
                  child: Text(
                    message.content.isEmpty ? '...' : message.content,
                    style: TextStyle(
                      color: isMyMessage ? Colors.white : Colors.black87,
                      fontSize: 15,
                    ),
                  ),
                ),
                
                // 时间
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    message.timeString,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          if (isMyMessage) ...[
            const SizedBox(width: 8),
            // 自己的头像
            CircleAvatar(
              radius: 16,
              child: Text(
                _getAvatar(),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getAvatar() {
    // 尝试从 from.name 中提取 emoji
    if (message.from.name.isNotEmpty) {
      final firstChar = message.from.name.runes.first;
      if (firstChar >= 0x1F300 && firstChar <= 0x1F9FF) {
        return String.fromCharCode(firstChar);
      }
    }
    
    // 默认头像
    return message.from.isAgent ? '🤖' : '👤';
  }
}
