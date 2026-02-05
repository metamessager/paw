# P0/P1/P2 集成检查清单

> 📋 用于验证所有功能是否正确集成

---

## 📦 1. 依赖安装

### 1.1 检查 pubspec.yaml

```bash
cat pubspec.yaml | grep -A 10 "dependencies:"
```

应包含以下依赖：

```yaml
dependencies:
  flutter:
    sdk: flutter
  sqflite: ^2.3.0
  path_provider: ^2.1.1       # ✓ 已有
  path: ^1.8.3
  shared_preferences: ^2.2.2   # ⚠️ 需要添加
  intl: ^0.18.1               # ⚠️ 需要添加
  archive: ^3.4.9             # ⚠️ 需要添加
  share_plus: ^7.2.1          # ⚠️ 需要添加
  web_socket_channel: ^2.4.0
  http: ^1.1.0
```

### 1.2 安装缺失的依赖

```bash
cd /data/workspace/clawd/ai-agent-hub
flutter pub add shared_preferences intl archive share_plus
flutter pub get
```

**预期输出**:
```
✓ shared_preferences 2.2.2 added
✓ intl 0.18.1 added
✓ archive 3.4.9 added
✓ share_plus 7.2.1 added
```

---

## 🔍 2. 文件检查

### 2.1 验证新增文件存在

```bash
cd /data/workspace/clawd/ai-agent-hub

# 检查服务文件
ls -lh lib/services/error_handler_service.dart
ls -lh lib/services/logger_service.dart
ls -lh lib/services/onboarding_service.dart
ls -lh lib/services/agent_collaboration_service.dart
ls -lh lib/services/data_export_import_service.dart

# 检查界面文件
ls -lh lib/screens/log_viewer_screen.dart
ls -lh lib/screens/agent_collaboration_screen.dart

# 检查文档
ls -lh docs/P0_P1_P2_COMPLETION_REPORT.md
ls -lh P0_P1_P2_QUICK_REFERENCE.md
```

**预期**: 所有文件都存在且大小合理（> 0 字节）

### 2.2 验证数据库索引已添加

```bash
grep -n "CREATE INDEX" lib/services/local_database_service.dart | wc -l
```

**预期**: 至少 20 行（包含所有索引）

---

## 🔧 3. 代码集成

### 3.1 更新 main.dart

检查 `lib/main.dart` 是否已初始化日志服务：

```dart
// 应该包含以下代码
import 'services/logger_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化日志服务
  await LoggerService().initialize();
  
  runApp(const MyApp());
}
```

**检查命令**:
```bash
grep -A 5 "void main()" lib/main.dart
```

### 3.2 添加引导页面检查

在 `MyApp` 的 `build` 方法中：

```dart
home: FutureBuilder<bool>(
  future: OnboardingService().isOnboardingCompleted(),
  builder: (context, snapshot) {
    if (!snapshot.hasData) {
      return const CircularProgressIndicator();
    }
    if (snapshot.data == false) {
      // 显示引导页面
      return const OnboardingScreen();
    }
    return const HomeScreen(); // 你的主页面
  },
),
```

### 3.3 添加日志查看器入口

在设置页面 (例如 `SettingsScreen`) 添加：

```dart
ListTile(
  leading: const Icon(Icons.article),
  title: const Text('系统日志'),
  subtitle: const Text('查看应用日志'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LogViewerScreen(),
      ),
    );
  },
),
```

### 3.4 添加协作功能入口

在主界面或 Agent 列表页面添加：

```dart
FloatingActionButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AgentCollaborationScreen(
          apiService: widget.apiService,
        ),
      ),
    );
  },
  tooltip: 'Agent 协作',
  child: const Icon(Icons.groups),
),
```

### 3.5 添加备份/恢复功能

在设置页面添加：

```dart
ListTile(
  leading: const Icon(Icons.backup),
  title: const Text('备份数据'),
  subtitle: const Text('导出所有数据'),
  onTap: () async {
    final service = DataExportImportService(
      LocalDatabaseService(),
      LocalFileStorageService(),
      LoggerService(),
    );
    
    final path = await service.exportAllData();
    if (path != null) {
      await Share.shareXFiles([XFile(path)]);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备份已创建: $path')),
      );
    }
  },
),

ListTile(
  leading: const Icon(Icons.restore),
  title: const Text('恢复数据'),
  subtitle: const Text('从备份文件恢复'),
  onTap: () async {
    // TODO: 实现文件选择和恢复
  },
),
```

---

## 🧪 4. 功能测试

### 4.1 P0 功能测试

#### 错误处理测试

```dart
// 在任意界面添加测试按钮
ElevatedButton(
  onPressed: () {
    final errorHandler = ErrorHandlerService(LoggerService());
    
    // 测试错误提示
    errorHandler.handleError(
      context,
      Exception('这是一个测试错误'),
      title: '测试错误处理',
      onRetry: () => print('重试'),
    );
  },
  child: Text('测试错误处理'),
),
```

**预期**: 显示友好的错误对话框，包含"重试"按钮

#### 性能测试

```bash
# 启动应用
flutter run --profile

# 使用 DevTools 检查性能
flutter pub global activate devtools
flutter pub global run devtools
```

**检查项**:
- [ ] 消息列表滚动流畅 (60 FPS)
- [ ] Agent 列表加载快速 (< 100ms)
- [ ] 数据库查询优化生效

### 4.2 P1 功能测试

#### 日志系统测试

```dart
// 添加测试按钮
ElevatedButton(
  onPressed: () {
    final logger = LoggerService();
    logger.debug('这是 Debug 日志');
    logger.info('这是 Info 日志');
    logger.warning('这是 Warning 日志');
    logger.error('这是 Error 日志', error: Exception('测试错误'));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('日志已写入，请查看日志查看器')),
    );
  },
  child: Text('生成测试日志'),
),
```

**检查项**:
- [ ] 日志文件已创建
- [ ] 日志查看器能看到所有日志
- [ ] 级别筛选正常工作
- [ ] 日志导出功能正常

**验证日志文件**:
```bash
# Android
adb shell ls /data/user/0/your.package.name/app_flutter/logs/

# iOS
xcrun simctl get_app_container booted your.bundle.id data
```

#### 引导系统测试

```dart
// 重置引导状态
await OnboardingService().resetOnboarding();

// 重启应用，应该看到引导页面
```

**检查项**:
- [ ] 首次启动显示引导
- [ ] 5 个引导页面都正常显示
- [ ] 跳过按钮正常工作
- [ ] 完成后不再显示

### 4.3 P2 功能测试

#### Agent 协作测试

1. 打开 Agent 协作界面
2. 输入任务信息
3. 选择 2-3 个 Agent
4. 选择协作策略 (测试每一种)
5. 执行任务
6. 查看结果

**检查项**:
- [ ] 顺序执行策略正常
- [ ] 并行执行策略正常
- [ ] 投票机制正常
- [ ] 流水线策略正常
- [ ] 结果展示正确

#### 数据导入导出测试

```dart
// 测试导出
final service = DataExportImportService(
  LocalDatabaseService(),
  LocalFileStorageService(),
  LoggerService(),
);

// 1. 导出所有数据
final exportPath = await service.exportAllData();
print('导出文件: $exportPath');

// 2. 验证 ZIP 文件存在
final file = File(exportPath!);
print('文件大小: ${await file.length()} bytes');

// 3. 测试导入（谨慎！会覆盖数据）
// final success = await service.importData(exportPath);
// print('导入结果: $success');
```

**检查项**:
- [ ] 导出创建 ZIP 文件
- [ ] ZIP 文件包含所有必要数据
- [ ] 导入功能正常（使用测试数据）
- [ ] Channel 单独导出正常

---

## ✅ 5. 代码质量检查

### 5.1 运行代码分析

```bash
flutter analyze
```

**预期**: 无错误，警告 < 5 个

### 5.2 格式化代码

```bash
flutter format lib/
```

**预期**: 所有文件格式正确

### 5.3 检查导入语句

```bash
# 检查是否有未使用的导入
flutter analyze --no-congratulate | grep "unused_import"
```

**预期**: 无未使用的导入

---

## 📱 6. 平台测试

### 6.1 Android 测试

```bash
flutter run -d android
```

**检查项**:
- [ ] 应用正常启动
- [ ] 所有功能正常工作
- [ ] 文件权限正常
- [ ] 分享功能正常

### 6.2 iOS 测试

```bash
flutter run -d ios
```

**检查项**:
- [ ] 应用正常启动
- [ ] 所有功能正常工作
- [ ] 文件权限正常
- [ ] 分享功能正常

### 6.3 Web 测试 (可选)

```bash
flutter run -d chrome
```

**注意**: 某些功能可能在 Web 上不可用（如文件系统）

---

## 🚀 7. 构建测试

### 7.1 Debug 构建

```bash
flutter build apk --debug
```

**预期**: 构建成功，无错误

### 7.2 Release 构建

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

**预期**: 构建成功，应用可安装运行

---

## 📊 8. 性能验证

### 8.1 启动时间

使用 Stopwatch 测量：

```dart
final stopwatch = Stopwatch()..start();
await LoggerService().initialize();
stopwatch.stop();
print('Logger init time: ${stopwatch.elapsedMilliseconds}ms');
```

**预期**: < 100ms

### 8.2 内存使用

使用 DevTools Memory 面板：

```bash
flutter pub global run devtools
```

**检查项**:
- [ ] 应用内存占用合理 (< 200MB)
- [ ] 无明显内存泄漏
- [ ] GC 频率正常

### 8.3 数据库查询速度

```dart
final stopwatch = Stopwatch()..start();
await db.query('messages', limit: 100);
stopwatch.stop();
print('Query time: ${stopwatch.elapsedMilliseconds}ms');
```

**预期**: < 10ms (有索引后)

---

## ✅ 9. 最终检查清单

### 代码完整性

- [ ] 所有新增文件已添加
- [ ] 数据库索引已添加
- [ ] 依赖已安装
- [ ] 代码已格式化
- [ ] 无编译错误

### 功能完整性

- [ ] P0: 错误处理正常
- [ ] P0: 性能优化生效
- [ ] P1: 日志系统正常
- [ ] P1: 用户引导正常
- [ ] P2: Agent 协作正常
- [ ] P2: 数据导入导出正常

### 文档完整性

- [ ] 完成报告已创建
- [ ] 快速参考已创建
- [ ] 代码注释充分
- [ ] API 文档完整

### 测试完整性

- [ ] 单元测试通过
- [ ] 集成测试通过
- [ ] UI 测试通过
- [ ] 性能测试通过

### 构建完整性

- [ ] Debug 构建成功
- [ ] Release 构建成功
- [ ] Android 构建成功
- [ ] iOS 构建成功

---

## 🎉 完成标志

当以上所有检查项都打勾 (✓) 后，项目即可上线！

```
┌────────────────────────────────────┐
│                                    │
│   🎉 恭喜！所有任务已完成！        │
│                                    │
│   ✅ P0: 100%                      │
│   ✅ P1: 100%                      │
│   ✅ P2: 100%                      │
│                                    │
│   🚀 项目已就绪，可立即上线！      │
│                                    │
└────────────────────────────────────┘
```

---

## 📞 问题排查

如果遇到问题，请检查：

1. **编译错误**: 确认所有依赖已安装
2. **运行时错误**: 查看日志文件 (`logs/`)
3. **性能问题**: 使用 DevTools 分析
4. **功能异常**: 检查日志查看器

---

**最后更新**: 2026-02-05  
**文档版本**: 1.0
