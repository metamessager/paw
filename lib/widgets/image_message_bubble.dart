import 'dart:io';
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/local_file_storage_service.dart';
import '../screens/image_viewer_screen.dart';

/// Displays image messages as thumbnails in the chat bubble.
/// Tapping the thumbnail navigates to a full-screen gallery viewer
/// that supports swiping between all images in the conversation.
class ImageMessageBubble extends StatefulWidget {
  final Message message;
  final bool isMyMessage;

  /// All image messages in the conversation, used for gallery navigation.
  final List<Message> allImageMessages;

  /// Index of this message within [allImageMessages].
  final int imageIndex;

  const ImageMessageBubble({
    Key? key,
    required this.message,
    required this.isMyMessage,
    this.allImageMessages = const [],
    this.imageIndex = 0,
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

  Future<void> _openViewer() async {
    if (_imageFile == null) return;

    // Build gallery items from all image messages
    final galleryItems = <ImageGalleryItem>[];
    final storageService = LocalFileStorageService();

    if (widget.allImageMessages.isNotEmpty) {
      for (final msg in widget.allImageMessages) {
        final path = msg.metadata?['path'] as String?;
        if (path == null) continue;
        try {
          final fullPath = await storageService.getFullPath(path);
          final file = File(fullPath);
          if (await file.exists()) {
            galleryItems.add(ImageGalleryItem(
              file: file,
              title: msg.metadata?['name'] as String?,
            ));
          }
        } catch (_) {
          // Skip images that can't be resolved
        }
      }
    }

    // Fallback: if gallery building failed, show single image
    if (galleryItems.isEmpty) {
      galleryItems.add(ImageGalleryItem(
        file: _imageFile!,
        title: widget.message.metadata?['name'] as String?,
      ));
    }

    // Determine actual index (may differ if some images failed to load)
    int actualIndex = widget.imageIndex.clamp(0, galleryItems.length - 1);

    if (!mounted) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return ImageViewerScreen(
            images: galleryItems,
            initialIndex: actualIndex,
            heroTagPrefix: 'chat_image',
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
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
      child: Hero(
        tag: 'chat_image_${widget.imageIndex}',
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
      ),
    );
  }
}
