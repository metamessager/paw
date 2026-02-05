import 'package:flutter/material.dart';
import 'logger_service.dart';

/// 全局错误处理服务
/// 
/// P0: 统一的错误处理和用户提示
class ErrorHandlerService {
  final LoggerService _logger;

  ErrorHandlerService(this._logger);

  /// 处理错误并显示用户友好的提示
  void handleError(
    BuildContext context,
    dynamic error, {
    String? title,
    String? message,
    VoidCallback? onRetry,
  }) {
    // 记录错误日志
    _logger.error('Error occurred', error: error);

    // 生成用户友好的错误消息
    final userMessage = _getUserFriendlyMessage(error);

    // 显示错误对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text(title ?? '操作失败'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message ?? userMessage),
            if (error is Error || error is Exception) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              ExpansionTile(
                title: const Text('技术详情', style: TextStyle(fontSize: 14)),
                children: [
                  SelectableText(
                    error.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          if (onRetry != null)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onRetry();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示成功提示
  void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 显示警告提示
  void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 显示信息提示
  void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 显示加载对话框
  void showLoading(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }

  /// 确认对话框
  Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '确定',
    String cancelText = '取消',
    bool isDangerous = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDangerous ? Colors.red : null,
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 将错误转换为用户友好的消息
  String _getUserFriendlyMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    // 网络错误
    if (errorStr.contains('socket') ||
        errorStr.contains('network') ||
        errorStr.contains('connection')) {
      return '网络连接失败，请检查您的网络设置';
    }

    // 超时错误
    if (errorStr.contains('timeout')) {
      return '请求超时，请稍后重试';
    }

    // 认证错误
    if (errorStr.contains('unauthorized') ||
        errorStr.contains('authentication') ||
        errorStr.contains('token')) {
      return '认证失败，请检查您的凭证是否正确';
    }

    // 权限错误
    if (errorStr.contains('permission') || errorStr.contains('forbidden')) {
      return '您没有权限执行此操作';
    }

    // 404 错误
    if (errorStr.contains('not found') || errorStr.contains('404')) {
      return '请求的资源不存在';
    }

    // 服务器错误
    if (errorStr.contains('500') || errorStr.contains('server error')) {
      return '服务器错误，请稍后重试';
    }

    // 数据库错误
    if (errorStr.contains('database') || errorStr.contains('sql')) {
      return '数据存储错误，请重启应用';
    }

    // 默认错误
    return '操作失败，请稍后重试';
  }
}
