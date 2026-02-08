import 'dart:io';
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/local_file_storage_service.dart';
import '../screens/image_viewer_screen.dart';

/// Displays image messages as thumbnails in the chat bubble.
/// Tapping the thumbnail navigates to a full-screen viewer with zoom.
class ImageMessageBubble extends StatefulWidget {
  final Message message;
  final bool isMyMessage;

  const ImageMessageBubble({
    Key? key,
    required this.message,
    required this.isMyMessage,
  }) : super(key: key);

  @override
  State<ImageMessageBubble> createState() => _ImageMessageBubbleState();
}

class _ImageMessageBubbleState extends State<ImageMessageBubble> {
  File? _imageFile;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final relativePath = widget.message.metadata?['path'] as String?;
    if (relativePath == null) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }

    try {
      final fullPath =
          await LocalFileStorageService().getFullPath(relativePath);
      final file = File(fullPath);
      if (await file.exists()) {
        setState(() {
          _imageFile = file;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _openViewer() {
    if (_imageFile == null) return;
    final fileName = widget.message.metadata?['name'] as String?;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          imageFile: _imageFile!,
          title: fileName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 180,
        height: 120,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_error || _imageFile == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image,
            size: 20,
            color: widget.isMyMessage ? Colors.white70 : Colors.grey,
          ),
          const SizedBox(width: 6),
          Text(
            widget.message.content.isNotEmpty
                ? widget.message.content
                : 'Image not available',
            style: TextStyle(
              color: widget.isMyMessage ? Colors.white70 : Colors.black54,
              fontSize: 14,
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: _openViewer,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 220,
            maxHeight: 220,
          ),
          child: Image.file(
            _imageFile!,
            fit: BoxFit.cover,
            cacheWidth: 440,
            cacheHeight: 440,
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox(
                width: 180,
                height: 80,
                child: Center(
                  child: Icon(Icons.broken_image, color: Colors.grey),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
