import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'services/password_service.dart';
import 'services/local_database_service.dart';
import 'services/local_api_service.dart';
import 'services/local_storage_service.dart';
import 'services/permission_service.dart';
import 'services/acp_server_service.dart';
import 'services/remote_agent_service.dart';
import 'services/token_service.dart';
import 'providers/app_state.dart';
import 'screens/password_setup_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
// 全局 ACP Server 实例
late ACPServerService globalACPServer;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Web平台初始化FFI数据库工厂
  if (kIsWeb) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiWeb;
  }
  
  // 初始化本地数据库
  await _initializeLocalStorage();
  
  // 检查远端 Agent 健康状态
  await _checkRemoteAgentsHealth();
  
  // 初始化 ACP Server
  await _initializeACPServer();
  
  runApp(const MyApp());
}
/// 初始化本地存储
Future<void> _initializeLocalStorage() async {
  try {
    print('🚀 初始化本地存储...');

    // 初始化数据库
    final db = LocalDatabaseService();
    await db.database; // 触发数据库初始化

    // 初始化示例数据（仅首次启动）
    final api = LocalApiService();
    await api.initializeSampleData();

    print('✅ 本地存储初始化完成');
  } catch (e) {
    print('❌ 本地存储初始化失败: $e');
  }
}

/// 检查远端 Agent 健康状态
Future<void> _checkRemoteAgentsHealth() async {
  try {
    print('🚀 检查远端 Agent 健康状态...');
    
    final databaseService = LocalDatabaseService();
    final tokenService = TokenService(databaseService);
    final remoteAgentService = RemoteAgentService(databaseService, tokenService);
    
    // 检查所有 Agent 的健康状态
    final onlineCount = await remoteAgentService.checkAllAgentsHealth(
      timeout: const Duration(seconds: 3),
    );
    
    print('✅ 远端 Agent 健康检查完成，在线: $onlineCount');
  } catch (e) {
    print('❌ 远端 Agent 健康检查失败: $e');
  }
}

/// 初始化 ACP Server
Future<void> _initializeACPServer() async {
  try {
    print('🚀 初始化 ACP Server...');
    
    // 创建服务实例
    final storageService = LocalStorageService();
    final permissionService = PermissionService(storageService);
    final apiService = LocalApiService();
    
    // 初始化权限数据库
    await permissionService.initialize();
    
    // 创建 ACP Server
    globalACPServer = ACPServerService(
      config: ACPServerConfig(
        host: '0.0.0.0',
        port: 18790,
        heartbeatInterval: 30,
      ),
      permissionService: permissionService,
      apiService: apiService,
    );
    
    // 启动服务器
    await globalACPServer.start();
    
    print('✅ ACP Server 启动成功 (端口: 18790)');
  } catch (e) {
    print('❌ ACP Server 初始化失败: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppState(),
        ),
      ],
      child: MaterialApp(
        title: 'AI Agent Hub',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
        ),
        home: const SplashScreen(),
        routes: {
          '/setup': (context) => const PasswordSetupScreen(),
          '/login': (context) => const LoginScreen(),
          '/home': (context) => const HomeScreen(),
        },
      ),
    );
  }
}

/// 启动页 - 检查密码状态并导航到相应页面
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _passwordService = PasswordService();

  @override
  void initState() {
    super.initState();
    _checkPasswordStatus();
  }

  Future<void> _checkPasswordStatus() async {
    // 初始化服务
    await _passwordService.init();
    
    // 短暂延迟，显示启动画面
    await Future.delayed(const Duration(seconds: 1));
    
    if (!mounted) return;
    
    // 检查是否已设置密码
    final isPasswordSet = await _passwordService.isPasswordSet();
    
    if (isPasswordSet) {
      // 已设置密码，跳转到登录页
      Navigator.of(context).pushReplacementNamed('/login');
    } else {
      // 未设置密码，跳转到设置页
      Navigator.of(context).pushReplacementNamed('/setup');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(
                Icons.smart_toy,
                size: 80,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 32),
            
            // 应用名称
            const Text(
              'AI Agent Hub',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            
            // 加载指示器
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 16),
            
            const Text(
              '正在加载...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
