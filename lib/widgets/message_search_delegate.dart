import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/message_search_service.dart';
import '../widgets/message_bubble.dart';
import '../utils/message_utils.dart';

/// 消息搜索委托
class MessageSearchDelegate extends SearchDelegate<String> {
  final MessageSearchService searchService;
  final String? channelId;
  final Function(Message)? onResultTap;

  MessageSearchDelegate({
    required this.searchService,
    this.channelId,
    this.onResultTap,
  });

  List<Message> _results = [];
  bool _isSearching = false;

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return _buildRecentSearches(context);
    }
    
    // Perform search
    _performSearch(query);
    
    return _buildSearchResults(context);
  }

  /// 执行搜索
  Future<void> _performSearch(String query) async {
    if (_isSearching) return;
    
    setState(() {
      _isSearching = true;
    });

    try {
      final results = await searchService.searchMessages(
        query: query,
        channelId: channelId,
        limit: 20,
      );

      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
    }
  }

  /// 构建搜索结果
  Widget _buildSearchResults(BuildContext context) {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    // Group results by date
    final grouped = MessageUtils.groupMessagesByDate(_results);

    return ListView.builder(
      itemCount: grouped.keys.length + _results.length,
      itemBuilder: (context, index) {
        // Calculate actual position considering date separators
        int dateIndex = 0;
        int resultIndex = index;
        
        for (final date in grouped.keys) {
          if (resultIndex == 0) {
            return _buildDateSeparator(date);
          }
          resultIndex--;
          
          final messages = grouped[date]!;
          if (resultIndex < messages.length) {
            final message = messages[resultIndex];
            return _buildSearchResultTile(context, message);
          }
          resultIndex -= messages.length;
          dateIndex++;
        }
        
        return const SizedBox.shrink();
      },
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

  /// 构建搜索结果项
  Widget _buildSearchResultTile(BuildContext context, Message message) {
    final isMyMessage = message.from.type == 'user';

    return InkWell(
      onTap: () {
        onResultTap?.call(message);
        close(context, message.id);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  message.senderName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isMyMessage ? Theme.of(context).primaryColor : Colors.grey[800],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  MessageUtils.formatMessageTime(message),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              message.content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建最近搜索
  Widget _buildRecentSearches(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Search messages',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Type to search in your chat history',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}
