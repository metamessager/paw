import 'package:flutter/material.dart';
import '../services/password_service.dart';

/// 登录页面
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _passwordController = TextEditingController();
  final _passwordService = PasswordService();
  
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String _errorMessage = '';
  int _failedAttempts = 0;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    await _passwordService.init();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  /// 提交登录
  Future<void> _submitLogin() async {
    setState(() {
      _errorMessage = '';
    });

    final password = _passwordController.text;

    if (password.isEmpty) {
      setState(() {
        _errorMessage = '请输入密码';
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _passwordService.verifyPassword(password);
      
      if (success) {
        // 登录成功，跳转到主页
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        setState(() {
          _failedAttempts++;
          if (_failedAttempts >= 3) {
            _errorMessage = '密码错误次数过多，请稍后再试';
          } else {
            _errorMessage = '密码错误，请重试 (${_failedAttempts}/3)';
          }
        });
        
        // 清空输入
        _passwordController.clear();
      }
    } catch (e) {
      setState(() {
        _errorMessage = '登录失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 80),
              
              // Logo
              Icon(
                Icons.lock_person,
                size: 100,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 32),
              
              Text(
                'AI Agent Hub',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              
              Text(
                '请输入密码解锁',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              
              // 密码输入框
              TextField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                autofocus: true,
                onSubmitted: (_) => _submitLogin(),
                decoration: InputDecoration(
                  labelText: '密码',
                  hintText: '请输入您的密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible 
                        ? Icons.visibility 
                        : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // 错误提示
              if (_errorMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      ),
                    ],
                  ),
                ),
              
              if (_errorMessage.isNotEmpty)
                const SizedBox(height: 24),
              
              // 登录按钮
              ElevatedButton(
                onPressed: (_isLoading || _failedAttempts >= 3) 
                  ? null 
                  : _submitLogin,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      '登录',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
              ),
              const SizedBox(height: 16),
              
              // 忘记密码提示
              TextButton(
                onPressed: () {
                  _showResetPasswordDialog();
                },
                child: const Text('忘记密码？'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示重置密码对话框
  void _showResetPasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置密码'),
        content: const Text(
          '重置密码将清除所有本地数据。\n\n'
          '如果需要重置密码，请联系管理员或重新安装应用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await _passwordService.resetPassword();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/setup');
              }
            },
            child: const Text(
              '确认重置',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
