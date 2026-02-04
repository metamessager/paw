/// 环境配置类
class AppConfig {
  final String apiBaseUrl;
  final String wsBaseUrl;
  final String environment;
  final bool enableLogging;
  final bool enableCrashReporting;

  const AppConfig({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.environment,
    this.enableLogging = false,
    this.enableCrashReporting = false,
  });

  /// 开发环境配置
  static const development = AppConfig(
    apiBaseUrl: 'http://localhost:3002',
    wsBaseUrl: 'ws://localhost:3002',
    environment: 'development',
    enableLogging: true,
    enableCrashReporting: false,
  );

  /// 测试环境配置
  static const staging = AppConfig(
    apiBaseUrl: 'https://staging-api.example.com',
    wsBaseUrl: 'wss://staging-api.example.com',
    environment: 'staging',
    enableLogging: true,
    enableCrashReporting: true,
  );

  /// 生产环境配置
  static const production = AppConfig(
    apiBaseUrl: 'https://api.example.com',
    wsBaseUrl: 'wss://api.example.com',
    environment: 'production',
    enableLogging: false,
    enableCrashReporting: true,
  );

  /// 获取当前环境配置
  static AppConfig get current {
    const env = String.fromEnvironment('ENV', defaultValue: 'development');
    switch (env) {
      case 'production':
        return production;
      case 'staging':
        return staging;
      case 'development':
      default:
        return development;
    }
  }

  @override
  String toString() => 'AppConfig(env: $environment, api: $apiBaseUrl)';
}
