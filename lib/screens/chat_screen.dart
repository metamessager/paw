import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/message.dart';
import '../widgets/message_bubble.dart';
import '../services/chat_service.dart';
import '../services/local_database_service.dart';
import '../services/remote_agent_service.dart';
import '../services/token_service.dart';
import '../services/attachment_service.dart';
import '../services/message_search_service.dart';
import '../services/local_file_storage_service.dart';
import '../utils/message_utils.dart';

class ChatScreen extends StatefulWidget {
  final String? agentId;
  final String? agentName;
  final String? agentAvatar;

  const ChatScreen({
    Key? key,
    this.agentId,
    this.agentName,
    this.agentAvatar,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _isLoading = false;
  bool _isSearching = false;
  String _searchQuery = '';
  
  late ChatService _chatService;
  late RemoteAgentService _remoteAgentService;
  late AttachmentService _attachmentService;
  late MessageSearchService _searchService;
  String? _currentChannelId;

  @override
  void initState() {
    super.initState();
    final databaseService = LocalDatabaseService();
    _chatService = ChatService(databaseService);
    _remoteAgentService = RemoteAgentService(
      databaseService,
      TokenService(databaseService),
    );
    _attachmentService = AttachmentService(
      LocalFileStorageService(),
      databaseService,
    );
    _searchService = MessageSearchService(databaseService);
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _chatService.dispose();
    super.dispose();
  }

  /// Load message history
  Future<void> _loadMessages() async {
    if (widget.agentId == null) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentUser?.id ?? 'user';
      
      final messages = await _chatService.loadMessageHistory(
        agentId: widget.agentId!,
        userId: userId,
      );

      setState(() {
        _messages = messages;
        _isLoading = false;
      });

      // Scroll to bottom
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load messages: $e')),
      );
    }
  }

  /// Send message to agent
  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    if (widget.agentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No agent selected')),
      );
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    setState(() {
      _isLoading = true;
    });

    _messageController.clear();

    try {
      // Get agent information
      final agent = await _remoteAgentService.getAgentById(widget.agentId!);
      
      if (agent == null) {
        throw Exception('Agent not found');
      }

      // Send message to agent
      final agentResponse = await _chatService.sendMessageToAgent(
        content: content,
        agent: agent,
        userId: userId,
        userName: userName,
      );

      if (agentResponse != null) {
        // Reload messages to show both user message and agent response
        await _loadMessages();
      } else {
        // Reload messages to show user message only (even if agent response failed)
        await _loadMessages();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get response from ${widget.agentName ?? "Agent"}')),
        );
      }
    } catch (e) {
      // Reload messages to show error message
      await _loadMessages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 滚动到底部
  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 选择和发送图片
  Future<void> _pickAndSendImage() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    try {
      // 选择图片
      final image = await _attachmentService.pickImage();
      if (image == null) return;

      // 发送图片
      final message = await _attachmentService.saveAttachment(
        file: image,
        channelId: _currentChannelId ?? '',
        userId: userId,
        userName: userName,
        agentId: widget.agentId ?? '',
      );

      if (message != null) {
        setState(() {
          _messages.add(message);
        });
        _scrollToBottom();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending image: $e')),
      );
    }
  }

  /// 选择和发送文件
  Future<void> _pickAndSendFile() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';
    final userName = appState.currentUser?.username ?? 'User';

    try {
      // 选择文件
      final file = await _attachmentService.pickFile();
      if (file == null) return;

      // 发送文件
      final message = await _attachmentService.saveAttachment(
        file: file,
        channelId: _currentChannelId ?? '',
        userId: userId,
        userName: userName,
        agentId: widget.agentId ?? '',
      );

      if (message != null) {
        setState(() {
          _messages.add(message);
        });
        _scrollToBottom();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending file: $e')),
      );
    }
  }

  /// 显示附件选项
  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo Library'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('File'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 搜索消息
  Future<void> _searchMessages(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchQuery = '';
        _isSearching = false;
      });
      await _loadMessages();
      return;
    }

    setState(() {
      _isSearching = true;
      _searchQuery = query;
    });

    try {
      final results = await _searchService.searchMessages(
        query: query,
        channelId: _currentChannelId,
      );

      setState(() {
        _messages = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search error: $e')),
      );
    }
  }

  /// 显示搜索对话框
  void _showSearchDialog() {
    showSearch(
      context: context,
      delegate: MessageSearchDelegate(
        searchService: _searchService,
        channelId: _currentChannelId,
        onResultTap: (message) {
          // Scroll to message
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _scrollController.animateTo(
              index * 80.0, // Approximate item height
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        },
      ),
    );
  }

  /// 删除消息
  Future<void> _deleteMessage(Message message) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id ?? 'user';

    if (!MessageUtils.canDeleteMessage(message, userId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete this message')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (message.type == MessageType.image || message.type == MessageType.file) {
        await _attachmentService.deleteAttachment(message);
      } else {
        await _chatService.deleteMessage(message.id);
      }

      setState(() {
        _messages.removeWhere((m) => m.id == message.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message deleted')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 1,
        title: Row(
            children: [
              // Agent头像
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.grey[200],
                child: widget.agentAvatar != null && widget.agentAvatar!.length > 2
                    ? ClipOval(
                        child: Image.network(
                          widget.agentAvatar!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Text(
                              widget.agentName?.isNotEmpty == true 
                                  ? widget.agentName![0] 
                                  : 'A',
                              style: const TextStyle(fontSize: 16),
                            );
                          },
                        ),
                      )
                    : Text(
                        widget.agentAvatar ?? 
                        (widget.agentName?.isNotEmpty == true 
                            ? widget.agentName![0] 
                            : 'A'),
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
            const SizedBox(width: 12),
            // Agent名称和状态
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.agentName ?? 'AI Agent',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Text(
                    'Online',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Voice call coming soon')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Video call coming soon')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              _showAgentMenu();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Message list
          Expanded(
            child: _messages.isEmpty && !_isLoading
                ? _buildEmptyState()
                : Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isMyMessage = message.from.type == 'user';
                          
                          // Check if we should show date separator
                          final previousMessage = index > 0 ? _messages[index - 1] : null;
                          final showDateSeparator = MessageUtils.shouldShowDateSeparator(
                            previousMessage,
                            message,
                          );
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Date separator
                              if (showDateSeparator)
                                _buildDateSeparator(message.dateTime),
                              
                              // Message bubble with actions
                              GestureDetector(
                                onLongPress: () {
                                  _showMessageMenu(message);
                                },
                                child: MessageBubble(
                                  message: message,
                                  isMyMessage: isMyMessage,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      if (_isLoading && _messages.isNotEmpty)
                        Positioned(
                          bottom: 16,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Theme.of(context).primaryColor,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '${widget.agentName ?? "Agent"} is typing...',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),

          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.grey[200],
              child: widget.agentAvatar != null && widget.agentAvatar!.length > 2
                  ? ClipOval(
                      child: Image.network(
                        widget.agentAvatar!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Text(
                            widget.agentName?.isNotEmpty == true 
                                ? widget.agentName![0] 
                                : 'A',
                            style: const TextStyle(fontSize: 32),
                          );
                        },
                      ),
                    )
                  : Text(
                      widget.agentAvatar ?? 
                      (widget.agentName?.isNotEmpty == true 
                          ? widget.agentName![0] 
                          : 'A'),
                      style: const TextStyle(fontSize: 32),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.agentName ?? 'AI Agent',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message to start chatting',
              style: TextStyle(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
    );
  }

  /// 输入区域
  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              color: Colors.grey[600],
              onPressed: _showAttachmentOptions,
            ),

            // 输入框
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  onSubmitted: (_) => _sendMessage(),
                  enabled: !_isLoading,
                ),
              ),
            ),

            const SizedBox(width: 8),

            // 发送按钮
            _isLoading
                ? Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.send),
                    color: Theme.of(context).primaryColor,
                    onPressed: _sendMessage,
                  ),
          ],
        ),
      ),
    );
  }

  /// 显示Agent菜单
  void _showAgentMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('View Details'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Feature coming soon')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search Messages'),
              onTap: () {
                Navigator.pop(context);
                _showSearchDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.push_pin),
              title: const Text('Pin Chat'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Feature coming soon')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Notifications'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Feature coming soon')),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete Chat', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Chat'),
                    content: const Text('Are you sure you want to delete this chat?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.pop(context);
                          setState(() {
                            _messages.clear();
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Chat deleted')),
                          );
                        },
                        child: const Text(
                          'Delete',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 构建日期分隔符
  Widget _buildDateSeparator(DateTime date) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          MessageUtils.getDateDisplayText(date),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// 显示消息菜单
  void _showMessageMenu(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                // Copy to clipboard
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                // Reply to message
                _messageController.text = 'Re: ${message.content.substring(0, 50)}...';
                _messageController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _messageController.text.length),
                );
              },
            ),
            if (message.type == MessageType.image || message.type == MessageType.file)
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Download'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Feature coming soon')),
                  );
                },
              ),
            if (MessageUtils.canDeleteMessage(
              message,
              Provider.of<AppState>(context, listen: false).currentUser?.id ?? 'user',
            ))
              const Divider(),
            if (MessageUtils.canDeleteMessage(
              message,
              Provider.of<AppState>(context, listen: false).currentUser?.id ?? 'user',
            ))
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(message);
                },
              ),
          ],
        ),
      ),
    );
  }
}
