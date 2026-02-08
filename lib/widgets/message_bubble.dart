import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../models/message.dart';
import 'voice_message_bubble.dart';
import 'image_message_bubble.dart';
import 'file_message_bubble.dart';
import 'action_confirmation_buttons.dart';
import 'single_select_bubble.dart';
import 'multi_select_bubble.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMyMessage;
  final bool isStreaming;
  final VoidCallback? onStop;
  final void Function(String confirmationId, String actionId, String actionLabel)? onActionSelected;
  final void Function(String selectId, String optionId, String optionLabel)? onSingleSelectSubmitted;
  final void Function(String selectId, List<String> optionIds, String summary)? onMultiSelectSubmitted;
  final Message? quotedMessage;
  final VoidCallback? onQuoteTap;
  final bool showQuote;

  const MessageBubble({
    Key? key,
    required this.message,
    required this.isMyMessage,
    this.isStreaming = false,
    this.onStop,
    this.onActionSelected,
    this.onSingleSelectSubmitted,
    this.onMultiSelectSubmitted,
    this.quotedMessage,
    this.onQuoteTap,
    this.showQuote = true,
  }) : super(key: key);

  static MarkdownStyleSheet? _cachedMyStyleSheet;
  static MarkdownStyleSheet? _cachedOtherStyleSheet;
  static Color? _cachedPrimaryColor;

  static MarkdownStyleSheet _getStyleSheet(bool isMyMessage, Color primaryColor) {
    if (_cachedPrimaryColor != primaryColor) {
      _cachedMyStyleSheet = null;
      _cachedOtherStyleSheet = null;
      _cachedPrimaryColor = primaryColor;
    }
    if (isMyMessage) {
      return _cachedMyStyleSheet ??= _buildStyleSheet(true);
    } else {
      return _cachedOtherStyleSheet ??= _buildStyleSheet(false);
    }
  }

  static MarkdownStyleSheet _buildStyleSheet(bool isMyMessage) {
    final textColor = isMyMessage ? Colors.white : Colors.black87;
    return MarkdownStyleSheet(
      p: TextStyle(color: textColor, fontSize: 15, height: 1.4),
      h1: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.bold),
      h2: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
      h3: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
      h4: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
      h5: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold),
      h6: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold),
      em: TextStyle(color: textColor, fontStyle: FontStyle.italic),
      strong: TextStyle(color: textColor, fontWeight: FontWeight.bold),
      a: TextStyle(color: isMyMessage ? Colors.lightBlueAccent : Colors.blue, decoration: TextDecoration.underline),
      code: TextStyle(
        color: isMyMessage ? Colors.white : Colors.black87,
        backgroundColor: isMyMessage ? Colors.white24 : Colors.grey[300],
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      codeblockDecoration: BoxDecoration(
        color: isMyMessage ? Colors.white12 : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isMyMessage ? Colors.white54 : Colors.grey[400]!,
            width: 3,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
      listBullet: TextStyle(color: textColor, fontSize: 15),
      tableHead: TextStyle(color: textColor, fontWeight: FontWeight.bold),
      tableBody: TextStyle(color: textColor),
      tableBorder: TableBorder.all(
        color: isMyMessage ? Colors.white38 : Colors.grey[400]!,
        width: 1,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isMyMessage ? Colors.white38 : Colors.grey[400]!,
            width: 1,
          ),
        ),
      ),
    );
  }

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
                  padding: message.type == MessageType.image
                      ? const EdgeInsets.all(4)
                      : const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                  decoration: BoxDecoration(
                    color: isMyMessage
                        ? Theme.of(context).primaryColor.withOpacity(0.75)
                        : (isStreaming ? Colors.blue[50] : Colors.grey[200]),
                    borderRadius: BorderRadius.circular(16),
                    border: isStreaming
                        ? Border.all(color: Colors.blue[200]!, width: 1)
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showQuote && quotedMessage != null)
                        _buildQuoteBlock(context)
                      else if (showQuote && message.replyTo != null)
                        _buildDeletedQuoteBlock(context),
                      _buildMessageContent(context),
                    ],
                  ),
                ),

                // 停止按钮（流式输出时显示）
                if (isStreaming && onStop != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: GestureDetector(
                      onTap: onStop,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.red[300]!, width: 1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.stop, size: 14, color: Colors.red[400]),
                            const SizedBox(width: 4),
                            Text(
                              'Stop',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red[400],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildMessageContent(BuildContext context) {
    switch (message.type) {
      case MessageType.audio:
        return VoiceMessageBubble(
          message: message,
          isMyMessage: isMyMessage,
        );
      case MessageType.image:
        return ImageMessageBubble(
          message: message,
          isMyMessage: isMyMessage,
        );
      case MessageType.file:
        return FileMessageBubble(
          message: message,
          isMyMessage: isMyMessage,
        );
      default:
        final content = message.content.isEmpty ? '...' : message.content;
        final styleSheet = _getStyleSheet(isMyMessage, Theme.of(context).primaryColor);
        final markdownWidget = MarkdownBody(
          data: content,
          selectable: true,
          extensionSet: md.ExtensionSet.gitHubWeb,
          onTapLink: (text, href, title) {
            // Links are rendered but tap handling requires url_launcher
          },
          styleSheet: styleSheet,
        );

        // Check for action confirmation data
        final actionConfirmation = message.metadata?['action_confirmation'] as Map<String, dynamic>?;
        if (actionConfirmation != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              markdownWidget,
              const SizedBox(height: 10),
              ActionConfirmationButtons(
                actionData: actionConfirmation,
                onActionSelected: onActionSelected,
              ),
            ],
          );
        }

        // Check for single-select data
        final singleSelect = message.metadata?['single_select'] as Map<String, dynamic>?;
        if (singleSelect != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              markdownWidget,
              const SizedBox(height: 10),
              SingleSelectBubble(
                selectData: singleSelect,
                onSelectSubmitted: onSingleSelectSubmitted,
              ),
            ],
          );
        }

        // Check for multi-select data
        final multiSelect = message.metadata?['multi_select'] as Map<String, dynamic>?;
        if (multiSelect != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              markdownWidget,
              const SizedBox(height: 10),
              MultiSelectBubble(
                selectData: multiSelect,
                onSelectSubmitted: onMultiSelectSubmitted,
              ),
            ],
          );
        }

        return markdownWidget;
    }
  }

  Widget _buildQuoteBlock(BuildContext context) {
    final quoted = quotedMessage!;
    final accentColor = isMyMessage ? Colors.white70 : Theme.of(context).primaryColor;
    final nameColor = isMyMessage ? Colors.white : Theme.of(context).primaryColor;
    final contentColor = isMyMessage ? Colors.white70 : Colors.black54;
    final bgColor = isMyMessage ? Colors.white.withOpacity(0.15) : Theme.of(context).primaryColor.withOpacity(0.08);

    final previewText = quoted.content.length > 60
        ? '${quoted.content.substring(0, 60)}...'
        : quoted.content;

    return GestureDetector(
      onTap: onQuoteTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            left: BorderSide(color: accentColor, width: 3),
          ),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(4),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              quoted.from.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: nameColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              previewText,
              style: TextStyle(
                fontSize: 12,
                color: contentColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeletedQuoteBlock(BuildContext context) {
    final accentColor = isMyMessage ? Colors.white38 : Colors.grey[400]!;
    final textColor = isMyMessage ? Colors.white54 : Colors.grey;
    final bgColor = isMyMessage ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          left: BorderSide(color: accentColor, width: 3),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Text(
        'Original message unavailable',
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: textColor,
        ),
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
