/// 应用异常基类
abstract class AppException implements Exception {
  final String message;
  final int? code;
  final dynamic originalError;

  AppException(this.message, {this.code, this.originalError});

  @override
  String toString() => message;
}

/// 网络异常
class NetworkException extends AppException {
  NetworkException(String message, {int? code, dynamic originalError})
      : super(message, code: code, originalError: originalError);
}

/// API异常
class ApiException extends AppException {
  ApiException(String message, {int? code, dynamic originalError})
      : super(message, code: code, originalError: originalError);
}

/// 认证异常
class AuthException extends AppException {
  AuthException(String message, {int? code, dynamic originalError})
      : super(message, code: code, originalError: originalError);
}

/// 验证异常
class ValidationException extends AppException {
  ValidationException(String message, {int? code, dynamic originalError})
      : super(message, code: code, originalError: originalError);
}

/// 存储异常
class StorageException extends AppException {
  StorageException(String message, {int? code, dynamic originalError})
      : super(message, code: code, originalError: originalError);
}

/// WebSocket异常
class WebSocketException extends AppException {
  WebSocketException(String message, {int? code, dynamic originalError})
      : super(message, code: code, originalError: originalError);
}

/// 异常工具类
class ExceptionHandler {
  /// 将通用异常转换为应用异常
  static AppException handle(dynamic error) {
    if (error is AppException) {
      return error;
    }

    if (error is FormatException) {
      return ApiException('数据格式错误', originalError: error);
    }

    if (error.toString().contains('SocketException')) {
      return NetworkException('网络连接失败，请检查网络设置', originalError: error);
    }

    if (error.toString().contains('TimeoutException')) {
      return NetworkException('网络请求超时，请稍后重试', originalError: error);
    }

    return ApiException('发生未知错误: ${error.toString()}', originalError: error);
  }

  /// 获取用户友好的错误信息
  static String getUserMessage(dynamic error) {
    if (error is AppException) {
      return error.message;
    }
    return '操作失败，请稍后重试';
  }
}
