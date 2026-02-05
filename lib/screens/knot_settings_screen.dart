import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/local_knot_agent_service.dart';

/// Knot 设置页面
class KnotSettingsScreen extends StatefulWidget {
  const KnotSettingsScreen({Key? key}) : super(key: key);

  @override
  State<KnotSettingsScreen> createState() => _KnotSettingsScreenState();
}

class _KnotSettingsScreenState extends State<KnotSettingsScreen> {
  final _knotApiService = LocalKnotAgentService();
  final _tokenController = TextEditingController();
  
  bool _isLoading = false;
  bool _isTokenVisible = false;
  bool _hasToken = false;
  bool _connectionTested = false;
  bool _connectionSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _knotApiService.dispose();
    super.dispose();
  }

  Future<void> _loadToken() async {
    setState(() => _isLoading = true);
    
    final token = await _knotApiService.getToken();
    setState(() {
      _hasToken = token != null && token.isNotEmpty;
      if (_hasToken) {
        _tokenController.text = token!;
      }
      _isLoading = false;
    });
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 API Token')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _knotApiService.saveToken(token);
      setState(() {
        _hasToken = true;
        _connectionTested = false;
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteToken() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除 API Token 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await _knotApiService.deleteToken();
      _tokenController.clear();
      setState(() {
        _hasToken = false;
        _connectionTested = false;
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除成功')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isLoading = true);

    try {
      final success = await _knotApiService.testConnection();
      setState(() {
        _connectionTested = true;
        _connectionSuccess = success;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '连接成功' : '连接失败'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _connectionTested = true;
        _connectionSuccess = false;
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('测试失败: $e')),
        );
      }
    }
  }

  void _openKnotDocs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('获取 API Token'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('请按照以下步骤获取 API Token：'),
            SizedBox(height: 12),
            Text('1. 访问 Knot 平台'),
            Text('2. 进入个人设置页面'),
            Text('3. 找到 API Token 管理'),
            Text('4. 创建或复制现有 Token'),
            SizedBox(height: 12),
            Text(
              '注意：请妥善保管您的 Token，不要泄露给他人',
              style: TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knot 配置'),
        actions: [
          if (_hasToken)
            IconButton(
              onPressed: _isLoading ? null : _deleteToken,
              icon: const Icon(Icons.delete),
              tooltip: '删除 Token',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline),
                            const SizedBox(width: 8),
                            const Text(
                              '关于 Knot API',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Knot 是腾讯内部的 AI Agent 平台，提供 OpenClaw 风格的智能体服务。通过配置 API Token，您可以在 AI Agent Hub 中管理和使用 Knot Agent。',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _openKnotDocs,
                          icon: const Icon(Icons.help_outline),
                          label: const Text('如何获取 API Token'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'API Token',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenController,
                  decoration: InputDecoration(
                    labelText: 'Knot API Token',
                    hintText: '粘贴您的 API Token',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.key),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _isTokenVisible = !_isTokenVisible;
                            });
                          },
                          icon: Icon(
                            _isTokenVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          tooltip: _isTokenVisible ? '隐藏' : '显示',
                        ),
                        if (_tokenController.text.isNotEmpty)
                          IconButton(
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _tokenController.text),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制到剪贴板')),
                              );
                            },
                            icon: const Icon(Icons.copy),
                            tooltip: '复制',
                          ),
                      ],
                    ),
                  ),
                  obscureText: !_isTokenVisible,
                  maxLines: _isTokenVisible ? null : 1,
                  onChanged: (value) {
                    setState(() {
                      _connectionTested = false;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveToken,
                        icon: const Icon(Icons.save),
                        label: const Text('保存'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _hasToken ? _testConnection : null,
                        icon: const Icon(Icons.wifi_tethering),
                        label: const Text('测试连接'),
                      ),
                    ),
                  ],
                ),
                if (_connectionTested) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _connectionSuccess
                          ? Colors.green[50]
                          : Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _connectionSuccess
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _connectionSuccess ? Icons.check_circle : Icons.error,
                          color: _connectionSuccess
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _connectionSuccess
                                ? '连接成功！可以开始使用 Knot Agent'
                                : '连接失败，请检查 Token 是否正确',
                            style: TextStyle(
                              color: _connectionSuccess
                                  ? Colors.green[800]
                                  : Colors.red[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'API 基础 URL',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.link),
                    title: const Text('https://knot.woa.com'),
                    subtitle: const Text('Knot 平台 API 地址'),
                    trailing: IconButton(
                      onPressed: () {
                        Clipboard.setData(
                          const ClipboardData(text: 'https://knot.woa.com'),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制到剪贴板')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
