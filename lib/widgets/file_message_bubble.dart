import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import '../models/message.dart';
import '../services/local_file_storage_service.dart';
import '../services/attachment_service.dart';

/// Displays file messages as a card component showing icon, name, and size.
/// Tapping opens the file with the system's default app.
class FileMessageBubble extends StatelessWidget {
  final Message message;
  final bool isMyMessage;

  const FileMessageBubble({
    Key? key,
    required this.message,
    required this.isMyMessage,
  }) : super(key: key);

  String get _fileName =>
      message.metadata?['name'] as String? ?? 'Unknown file';

  int get _fileSize => message.metadata?['size'] as int? ?? 0;

  String get _fileType => message.metadata?['type'] as String? ?? 'file';

  IconData get _fileIcon {
    switch (_fileType) {
      case 'document':
        return Icons.description;
      case 'video':
        return Icons.videocam;
      case 'audio':
        return Icons.audiotrack;
      default:
        final ext = _fileName.split('.').last.toLowerCase();
        switch (ext) {
          case 'pdf':
            return Icons.picture_as_pdf;
          case 'doc':
          case 'docx':
            return Icons.article;
          case 'xls':
          case 'xlsx':
            return Icons.table_chart;
          case 'ppt':
          case 'pptx':
            return Icons.slideshow;
          case 'zip':
          case 'rar':
          case '7z':
          case 'tar':
          case 'gz':
            return Icons.folder_zip;
          case 'txt':
          case 'md':
            return Icons.text_snippet;
          default:
            return Icons.insert_drive_file;
        }
    }
  }

  Color get _iconColor {
    final ext = _fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      case 'zip':
      case 'rar':
      case '7z':
        return Colors.amber[700]!;
      default:
        return Colors.blueGrey;
    }
  }

  Future<void> _openFile(BuildContext context) async {
    final relativePath = message.metadata?['path'] as String?;
    if (relativePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File path not found')),
      );
      return;
    }

    try {
      final fullPath =
          await LocalFileStorageService().getFullPath(relativePath);
      await OpenFile.open(fullPath);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open file: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = isMyMessage
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.05);
    final textColor = isMyMessage ? Colors.white : Colors.black87;
    final subtitleColor = isMyMessage ? Colors.white70 : Colors.black54;

    return GestureDetector(
      onTap: () => _openFile(context),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_fileIcon, color: _iconColor, size: 22),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fileName,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AttachmentService.formatFileSize(_fileSize),
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
