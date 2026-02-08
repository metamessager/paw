import 'dart:io';
import 'package:flutter/material.dart';

/// Full-screen image viewer with pinch-to-zoom and pan support.
class ImageViewerScreen extends StatelessWidget {
  final File imageFile;
  final String? title;

  const ImageViewerScreen({
    Key? key,
    required this.imageFile,
    this.title,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: title != null
            ? Text(
                title!,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              )
            : null,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.file(
              imageFile,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, color: Colors.white54, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'Failed to load image',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
