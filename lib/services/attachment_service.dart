import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'local_file_storage_service.dart';
import 'local_database_service.dart';
import '../models/message.dart';
import 'package:uuid/uuid.dart';

/// 附件服务
class AttachmentService {
  final LocalFileStorageService _fileStorage;
  final LocalDatabaseService _database;
  final ImagePicker _imagePicker = ImagePicker();
  final _uuid = const Uuid();

  AttachmentService(this._fileStorage, this._database);

  /// 选择图片
  Future<File?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image == null) return null;

      return File(image.path);
    } catch (e) {
      debugPrint('Error picking image: $e');
      return null;
    }
  }

  /// 选择文件
  Future<File?> pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return null;

      final filePath = result.files.single.path;
      if (filePath == null) return null;

      return File(filePath);
    } catch (e) {
      debugPrint('Error picking file: $e');
      return null;
    }
  }

  /// 保存附件并创建消息
  Future<Message?> saveAttachment({
    required File file,
    required String channelId,
    required String userId,
    required String userName,
    required String agentId,
  }) async {
    try {
      // 生成唯一文件名
      final extension = path.extension(file.path);
      final fileName = '${_uuid.v4()}$extension';
      
      // 保存文件到本地存储
      final savedPath = await _fileStorage.saveFile(
        file: file,
        fileName: fileName,
        subfolder: 'attachments/$channelId',
      );

      if (savedPath == null) {
        throw Exception('Failed to save file');
      }

      // 判断文件类型
      final fileType = _getFileType(file.path);
      final fileSize = await file.length();

      // 创建附件消息
      final attachmentData = {
        'path': savedPath,
        'name': path.basename(file.path),
        'type': fileType,
        'size': fileSize,
      };

      final messageId = _uuid.v4();
      final now = DateTime.now();

      final message = Message(
        id: messageId,
        channelId: channelId,
        from: MessageFrom(
          id: userId,
          type: 'user',
          name: userName,
        ),
        type: fileType == 'image' ? MessageType.image : MessageType.file,
        content: _createAttachmentContent(attachmentData),
        timestampMs: now.millisecondsSinceEpoch,
      );

      // 保存到数据库
      await _database.createMessage(
        id: messageId,
        channelId: channelId,
        senderId: userId,
        senderName: userName,
        content: message.content,
        type: message.type.toString().split('.').last,
        timestamp: now,
        replyToId: null,
        metadata: attachmentData,
      );

      return message;
    } catch (e) {
      debugPrint('Error saving attachment: $e');
      return null;
    }
  }

  /// 删除附件
  Future<bool> deleteAttachment(Message message) async {
    try {
      // 删除文件
      if (message.metadata != null && message.metadata!['path'] != null) {
        await _fileStorage.deleteFile(message.metadata!['path']);
      }

      // 删除数据库记录
      await _database.deleteMessage(message.id);

      return true;
    } catch (e) {
      debugPrint('Error deleting attachment: $e');
      return false;
    }
  }

  /// 获取文件类型
  String _getFileType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    
    final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];
    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.webm'];
    final audioExtensions = ['.mp3', '.wav', '.m4a', '.aac', '.ogg'];
    final documentExtensions = ['.pdf', '.doc', '.docx', '.txt', '.md'];

    if (imageExtensions.contains(extension)) return 'image';
    if (videoExtensions.contains(extension)) return 'video';
    if (audioExtensions.contains(extension)) return 'audio';
    if (documentExtensions.contains(extension)) return 'document';
    
    return 'file';
  }

  /// 创建附件内容
  String _createAttachmentContent(Map<String, dynamic> attachmentData) {
    final fileName = attachmentData['name'] ?? 'Unknown file';
    final fileType = attachmentData['type'] ?? 'file';
    final fileSize = attachmentData['size'] ?? 0;
    
    // 格式化文件大小
    String formattedSize;
    if (fileSize < 1024) {
      formattedSize = '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      formattedSize = '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else {
      formattedSize = '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    if (fileType == 'image') {
      return '📷 Image: $fileName ($formattedSize)';
    } else if (fileType == 'video') {
      return '🎥 Video: $fileName ($formattedSize)';
    } else if (fileType == 'audio') {
      return '🎵 Audio: $fileName ($formattedSize)';
    } else {
      return '📎 File: $fileName ($formattedSize)';
    }
  }

  /// 格式化文件大小
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
