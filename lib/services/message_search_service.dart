import 'package:logger/logger.dart';
import '../models/message.dart';
import 'local_database_service.dart';

/// 消息搜索服务
class MessageSearchService {
  final LocalDatabaseService _database;
  final Logger _logger = Logger();

  MessageSearchService(this._database);

  /// 搜索消息
  Future<List<Message>> searchMessages({
    required String query,
    String? channelId,
    String? userId,
    int limit = 50,
  }) async {
    try {
      if (query.trim().isEmpty) {
        return [];
      }

      final db = await _database.database;
      
      String sql = '''
        SELECT * FROM messages
        WHERE content LIKE ?
        ${channelId != null ? 'AND channel_id = ?' : ''}
        ORDER BY timestamp DESC
        LIMIT ?
      ''';

      List<dynamic> args = ['%$query%'];
      if (channelId != null) {
        args.add(channelId);
      }
      args.add(limit);

      final List<Map<String, dynamic>> maps = await db.rawQuery(sql, args);

      return maps.map((map) {
        // Parse metadata
        Map<String, dynamic>? metadata;
        if (map['metadata'] != null) {
          try {
            if (map['metadata'] is String) {
              // JSON string
              metadata = map['metadata'] as Map<String, dynamic>;
            } else if (map['metadata'] is Map) {
              metadata = Map<String, dynamic>.from(map['metadata']);
            }
          } catch (e) {
            _logger.e('Error parsing metadata: $e');
          }
        }

        // Parse reply_to
        String? replyTo;
        if (metadata != null && metadata['reply_to'] != null) {
          replyTo = metadata['reply_to'].toString();
        }

        return Message(
          id: map['id'],
          from: MessageFrom(
            id: map['sender_id'] ?? '',
            type: 'user',
            name: map['sender_name'] ?? '',
          ),
          channelId: map['channel_id'],
          type: _parseMessageType(map['type'] ?? 'text'),
          content: map['content'] ?? '',
          timestampMs: map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
          replyTo: replyTo,
          metadata: metadata,
        );
      }).toList();
    } catch (e) {
      _logger.e('Error searching messages: $e');
      return [];
    }
  }

  /// 按日期搜索消息
  Future<List<Message>> searchMessagesByDate({
    required DateTime startDate,
    required DateTime endDate,
    String? channelId,
  }) async {
    try {
      final db = await _database.database;
      
      String sql = '''
        SELECT * FROM messages
        WHERE timestamp >= ? AND timestamp <= ?
        ${channelId != null ? 'AND channel_id = ?' : ''}
        ORDER BY timestamp DESC
      ''';

      List<dynamic> args = [
        startDate.millisecondsSinceEpoch,
        endDate.millisecondsSinceEpoch,
      ];
      if (channelId != null) {
        args.add(channelId);
      }

      final List<Map<String, dynamic>> maps = await db.rawQuery(sql, args);

      return maps.map((map) {
        Map<String, dynamic>? metadata;
        if (map['metadata'] != null && map['metadata'] is Map) {
          metadata = Map<String, dynamic>.from(map['metadata']);
        }

        return Message(
          id: map['id'],
          from: MessageFrom(
            id: map['sender_id'] ?? '',
            type: 'user',
            name: map['sender_name'] ?? '',
          ),
          channelId: map['channel_id'],
          type: _parseMessageType(map['type'] ?? 'text'),
          content: map['content'] ?? '',
          timestampMs: map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
          metadata: metadata,
        );
      }).toList();
    } catch (e) {
      _logger.e('Error searching messages by date: $e');
      return [];
    }
  }

  /// 获取搜索建议
  Future<List<String>> getSearchSuggestions({
    required String query,
    String? channelId,
    int limit = 10,
  }) async {
    try {
      if (query.length < 2) return [];

      final db = await _database.database;
      
      String sql = '''
        SELECT DISTINCT 
          SUBSTR(content, 1, 100) as snippet
        FROM messages
        WHERE content LIKE ?
        ${channelId != null ? 'AND channel_id = ?' : ''}
        LIMIT ?
      ''';

      List<dynamic> args = ['%$query%'];
      if (channelId != null) {
        args.add(channelId);
      }
      args.add(limit);

      final List<Map<String, dynamic>> maps = await db.rawQuery(sql, args);

      return maps.map((map) => map['snippet'] as String).toList();
    } catch (e) {
      _logger.e('Error getting search suggestions: $e');
      return [];
    }
  }

  /// 解析消息类型
  MessageType _parseMessageType(String type) {
    switch (type.toLowerCase()) {
      case 'image':
        return MessageType.image;
      case 'file':
        return MessageType.file;
      case 'system':
        return MessageType.system;
      case 'text':
      default:
        return MessageType.text;
    }
  }
}
