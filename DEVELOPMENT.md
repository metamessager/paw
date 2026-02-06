# 开发指南

> AI Agent Hub 开发者指南

---

## 🚀 快速开始

### 环境配置

```bash
# 1. 安装 Flutter
# 参考: https://flutter.dev/docs/get-started/install

# 2. 验证安装
flutter doctor

# 3. 克隆项目
git clone https://git.woa.com/edenzou/ai-agent-hub.git
cd ai-agent-hub

# 4. 安装依赖
flutter pub get

# 5. 运行项目
flutter run
```

---

## 📝 代码规范

### 命名规范

```dart
// 类名: PascalCase
class AgentListScreen {}
class LocalApiService {}

// 变量/函数: camelCase
final userName = 'John';
void sendMessage() {}

// 常量: UPPER_CASE
const API_TIMEOUT = 30;

// 私有成员: _开头
class Example {
  final String _privateField;
  void _privateMethod() {}
}
```

### 文件组织

```dart
// 1. 导入顺序
import 'dart:async';              // Dart SDK
import 'package:flutter/material.dart';  // Flutter
import 'package:provider/provider.dart';  // 第三方包
import '../models/agent.dart';    // 项目内部

// 2. 类结构
class MyWidget extends StatefulWidget {
  // 1. 静态成员
  static const routeName = '/my-widget';
  
  // 2. 成员变量
  final String title;
  
  // 3. 构造函数
  const MyWidget({Key? key, required this.title}) : super(key: key);
  
  // 4. 方法
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  // 1. 成员变量
  bool _loading = false;
  
  // 2. 生命周期方法
  @override
  void initState() {
    super.initState();
  }
  
  @override
  void dispose() {
    super.dispose();
  }
  
  // 3. 构建方法
  @override
  Widget build(BuildContext context) {
    return Scaffold();
  }
  
  // 4. 私有方法
  void _handleTap() {}
}
```

### 注释规范

```dart
/// 文档注释：描述公共 API
/// 
/// 使用三斜线，支持 Markdown
/// 
/// Example:
/// ```dart
/// final service = AgentService();
/// await service.addAgent(agent);
/// ```
class AgentService {
  // 普通注释：解释实现细节
  void _processAgent() {
    // TODO: 添加错误处理
    // FIXME: 修复并发问题
    // NOTE: 这里需要优化性能
  }
}
```

---

## 🏗️ 架构设计

### 分层架构

```
┌─────────────────────────────────────┐
│           UI Layer (Screens)        │  ← 用户界面
├─────────────────────────────────────┤
│        State Management (Provider)  │  ← 状态管理
├─────────────────────────────────────┤
│         Service Layer (Services)    │  ← 业务逻辑
├─────────────────────────────────────┤
│         Data Layer (Models)         │  ← 数据模型
├─────────────────────────────────────┤
│    Storage (Database + FileSystem)  │  ← 数据存储
└─────────────────────────────────────┘
```

### 依赖注入

```dart
// 推荐：通过构造函数注入
class AgentListScreen extends StatefulWidget {
  final LocalApiService apiService;
  
  const AgentListScreen({
    Key? key,
    required this.apiService,
  }) : super(key: key);
}

// 或者使用 Provider
final apiService = Provider.of<LocalApiService>(context);
```

---

## 🔧 常用开发任务

### 添加新的数据模型

```dart
// 1. 创建模型类
class MyModel {
  final String id;
  final String name;
  
  MyModel({required this.id, required this.name});
  
  // 2. 序列化
  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name};
  }
  
  // 3. 反序列化
  factory MyModel.fromMap(Map<String, dynamic> map) {
    return MyModel(
      id: map['id'],
      name: map['name'],
    );
  }
}

// 4. 更新数据库 schema
// 在 local_database_service.dart 的 _onCreate 中添加表
await db.execute('''
  CREATE TABLE my_models (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL
  )
''');
```

### 添加新的 UI 界面

```dart
// 1. 创建 StatefulWidget
class MyScreen extends StatefulWidget {
  const MyScreen({Key? key}) : super(key: key);
  
  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  // 2. 状态变量
  bool _loading = false;
  
  // 3. 生命周期
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  // 4. 业务逻辑
  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 加载数据
    } catch (e) {
      // 错误处理
    } finally {
      setState(() => _loading = false);
    }
  }
  
  // 5. 构建 UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Screen')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }
  
  Widget _buildContent() {
    return ListView();
  }
}
```

### 添加新的服务

```dart
// 1. 创建服务类
class MyService {
  final LocalDatabaseService _dbService;
  final LoggerService _logger;
  
  MyService(this._dbService, this._logger);
  
  // 2. 实现业务方法
  Future<void> doSomething() async {
    _logger.info('Doing something');
    try {
      // 业务逻辑
    } catch (e, stackTrace) {
      _logger.error('Failed to do something', 
        error: e, 
        stackTrace: stackTrace
      );
      rethrow;
    }
  }
}

// 3. 在需要的地方使用
final myService = MyService(dbService, logger);
await myService.doSomething();
```

---

## 🧪 测试

### 单元测试

```dart
// test/services/my_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_agent_hub/services/my_service.dart';

void main() {
  group('MyService', () {
    late MyService service;
    
    setUp(() {
      service = MyService();
    });
    
    test('should do something', () async {
      final result = await service.doSomething();
      expect(result, isNotNull);
    });
  });
}

// 运行测试
// flutter test test/services/my_service_test.dart
```

### Widget 测试

```dart
// test/screens/my_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_agent_hub/screens/my_screen.dart';

void main() {
  testWidgets('MyScreen displays title', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MyScreen()),
    );
    
    expect(find.text('My Screen'), findsOneWidget);
  });
}
```

---

## 🐛 调试技巧

### 日志输出

```dart
// 使用 LoggerService
final logger = LoggerService();
logger.debug('Debug info');
logger.info('Operation completed');
logger.warning('Warning message');
logger.error('Error occurred', error: e);

// 开发时可以用 print (不推荐在生产环境)
debugPrint('Debug message');
```

### 性能分析

```bash
# 启动 Profile 模式
flutter run --profile

# 使用 DevTools
flutter pub global activate devtools
flutter pub global run devtools

# 性能追踪
// 在代码中添加
import 'dart:developer' as developer;

developer.Timeline.startSync('MyOperation');
// 执行操作
developer.Timeline.finishSync();
```

### 常见问题

**问题**: Hot Reload 不生效

```bash
# 解决方案
flutter clean
flutter pub get
flutter run
```

**问题**: 数据库错误

```dart
// 查看数据库文件
final dbPath = await getDatabasesPath();
print('Database path: $dbPath');

// 重置数据库
await deleteDatabase(dbPath);
```

---

## 📦 构建和发布

### Debug 构建

```bash
# Android
flutter build apk --debug

# iOS
flutter build ios --debug
```

### Release 构建

```bash
# Android
flutter build apk --release

# iOS (需要配置证书)
flutter build ios --release
flutter build ipa
```

### 版本号管理

在 `pubspec.yaml` 中：

```yaml
version: 1.0.0+1
#        │ │ │  └─ Build number
#        │ │ └──── Patch version
#        │ └────── Minor version
#        └──────── Major version
```

---

## 🔐 安全注意事项

### 敏感信息

```dart
// ❌ 不要硬编码敏感信息
const apiKey = 'sk-xxxxxxxxxxxx';

// ✅ 使用环境变量或配置文件
final apiKey = EnvConfig.apiKey;
```

### 数据加密

```dart
// 对敏感数据加密
import 'package:encrypt/encrypt.dart';

final key = Key.fromUtf8('my32lengthsupersecretnooneknows1');
final iv = IV.fromLength(16);
final encrypter = Encrypter(AES(key));

final encrypted = encrypter.encrypt(plainText, iv: iv);
final decrypted = encrypter.decrypt(encrypted, iv: iv);
```

---

## 📚 学习资源

### Flutter 官方

- [Flutter 文档](https://flutter.dev/docs)
- [Dart 文档](https://dart.dev/guides)
- [Flutter Cookbook](https://flutter.dev/docs/cookbook)

### 本项目

- [项目结构说明](PROJECT_STRUCTURE.md)
- [API 快速参考](P0_P1_P2_QUICK_REFERENCE.md)
- [功能完成报告](docs/P0_P1_P2_COMPLETION_REPORT.md)

---

## 🤝 贡献流程

### 1. Fork 项目

```bash
# 在 GitLab 上 Fork 项目
# 克隆你的 Fork
git clone https://git.woa.com/yourname/ai-agent-hub.git
```

### 2. 创建分支

```bash
git checkout -b feature/my-new-feature
```

### 3. 提交代码

```bash
git add .
git commit -m "feat: add new feature"

# Commit 格式
# feat: 新功能
# fix: 修复
# docs: 文档
# style: 格式
# refactor: 重构
# test: 测试
# chore: 构建/工具
```

### 4. 推送和 PR

```bash
git push origin feature/my-new-feature
# 在 GitLab 上创建 Merge Request
```

---

## 📞 获取帮助

- 📖 查看文档: `docs/` 目录
- 🐛 报告问题: GitLab Issues
- 💬 技术支持: edenzou@tencent.com

---

**最后更新**: 2026-02-05
