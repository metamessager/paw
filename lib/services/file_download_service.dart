import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'local_file_storage_service.dart';

/// Result of a file download operation
class FileDownloadResult {
  /// Relative path within local storage
  final String relativePath;

  /// Original file name
  final String fileName;

  /// File size in bytes
  final int fileSize;

  /// MIME type of the file
  final String mimeType;

  /// Whether the file is an image
  final bool isImage;

  FileDownloadResult({
    required this.relativePath,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.isImage,
  });
}

/// Service for downloading files from URLs and saving them locally
class FileDownloadService {
  final LocalFileStorageService _storageService;

  FileDownloadService([LocalFileStorageService? storageService])
      : _storageService = storageService ?? LocalFileStorageService();

  /// Check if a MIME type represents an image
  static bool isImageMimeType(String mimeType) {
    return mimeType.startsWith('image/');
  }

  /// Download a file from [url] and save it locally.
  ///
  /// Returns a [FileDownloadResult] with the local path and metadata.
  Future<FileDownloadResult> downloadAndSave(
    String url, {
    String? fileName,
    String? mimeType,
    int? expectedSize,
    void Function(int received, int? total)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception(
          'Download failed with status ${streamedResponse.statusCode}',
        );
      }

      // Determine MIME type from response or parameter
      final responseMime = streamedResponse.headers['content-type']
              ?.split(';')
              .first
              .trim() ??
          'application/octet-stream';
      final effectiveMime = mimeType ?? responseMime;

      // Determine file name
      final effectiveFileName = fileName ?? _fileNameFromUrl(url, effectiveMime);

      // Determine resource type based on MIME
      final ResourceType resourceType;
      if (effectiveMime.startsWith('image/')) {
        resourceType = ResourceType.images;
      } else if (effectiveMime.startsWith('audio/')) {
        resourceType = ResourceType.audio;
      } else {
        resourceType = ResourceType.documents;
      }

      // Download to a temp file using streaming
      final tempDir = await _storageService.getStorageDirectory();
      final tempFile = File(
        path.join(tempDir.path, 'temp', 'download_${DateTime.now().millisecondsSinceEpoch}'),
      );
      await tempFile.parent.create(recursive: true);

      final total = streamedResponse.contentLength ?? expectedSize;
      int received = 0;
      final sink = tempFile.openWrite();

      try {
        await for (final chunk in streamedResponse.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }

      // Save to permanent storage using LocalFileStorageService
      final relativePath = await _storageService.saveFile(
        tempFile,
        type: resourceType,
        customFileName: effectiveFileName,
      );

      // Clean up temp file
      try {
        await tempFile.delete();
      } catch (_) {}

      final fileSize = received;

      return FileDownloadResult(
        relativePath: relativePath,
        fileName: effectiveFileName,
        fileSize: fileSize,
        mimeType: effectiveMime,
        isImage: isImageMimeType(effectiveMime),
      );
    } finally {
      client.close();
    }
  }

  /// Derive a file name from a URL, falling back to a UUID-based name.
  String _fileNameFromUrl(String url, String mimeType) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        final last = segments.last;
        if (last.contains('.') && last.length <= 255) {
          return last;
        }
      }
    } catch (_) {}

    // Fallback: generate name from timestamp + extension
    final ext = _extensionFromMime(mimeType);
    return 'file_${DateTime.now().millisecondsSinceEpoch}$ext';
  }

  /// Map common MIME types to file extensions.
  String _extensionFromMime(String mimeType) {
    const mimeToExt = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'application/pdf': '.pdf',
      'application/zip': '.zip',
      'text/plain': '.txt',
      'text/html': '.html',
      'audio/mpeg': '.mp3',
      'audio/wav': '.wav',
      'audio/ogg': '.ogg',
      'video/mp4': '.mp4',
    };
    return mimeToExt[mimeType] ?? '';
  }
}
