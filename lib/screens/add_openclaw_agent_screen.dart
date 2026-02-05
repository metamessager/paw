/// OpenClaw Agent 添加/编辑页面
/// 用于配置 OpenClaw Gateway 连接

import 'package:flutter/material.dart';
import '../models/openclaw_agent.dart';
import '../services/acp_service.dart';
import '../services/local_database_service.dart';

class AddOpenClawAgentScreen extends StatefulWidget {
  final OpenClawAgent? agent; // null = 添加模式, 非null = 编辑模式

  const AddOpenClawAgentScreen({super.key, this.agent});

  @override
  State<AddOpenClawAgentScreen> createState() => _AddOpenClawAgentScreenState();
}

class _AddOpenClawAgentScreenState extends State<AddOpenClawAgentScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _gatewayUrlController;
  late final TextEditingController _authTokenController;
  late final TextEditingController _bioController;
  late final TextEditingController _modelController;
  late final TextEditingController _systemPromptController;

  String _selectedAvatar = '🦅';
  final List<String> _selectedTools = [];
  bool _isLoading = false;
  bool _isTesting = false;
  String? _testResult;

  late final ACPService _acpService;

  @override
  void initState() {
    super.initState();
    _acpService = ACPService(LocalDatabaseService().database);

    // 初始化控制器
    _nameController = TextEditingController(text: widget.agent?.name ?? '');
    _gatewayUrlController = TextEditingController(
      text: widget.agent?.gatewayUrl ?? 'ws://localhost:18789',
    );
    _authTokenController =
        TextEditingController(text: widget.agent?.authToken ?? '');
    _bioController = TextEditingController(text: widget.agent?.bio ?? '');
    _modelController = TextEditingController(
      text: widget.agent?.model ?? 'claude-3-5-sonnet',
    );
    _systemPromptController =
        TextEditingController(text: widget.agent?.systemPrompt ?? '');

    // 初始化已选工具
    if (widget.agent?.tools != null) {
      _selectedTools.addAll(widget.agent!.tools!);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _gatewayUrlController.dispose();
    _authTokenController.dispose();
    _bioController.dispose();
    _modelController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.agent != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditMode ? '编辑 OpenClaw Agent' : '添加 OpenClaw Agent'),
        actions: [
          if (!isEditMode)
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: _showHelp,
              tooltip: '帮助',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 基本信息
            _buildSection(
              title: '基本信息',
              children: [
                _buildAvatarSelector(),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Agent 名称 *',
                    hintText: '例如: My OpenClaw Assistant',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入 Agent 名称';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bioController,
                  decoration: const InputDecoration(
                    labelText: 'Agent 简介',
                    hintText: '描述这个 Agent 的功能...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Gateway 配置
            _buildSection(
              title: 'Gateway 配置',
              children: [
                TextFormField(
                  controller: _gatewayUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Gateway URL *',
                    hintText: 'ws://localhost:18789',
                    border: OutlineInputBorder(),
                    helperText: 'OpenClaw Gateway 的 WebSocket 地址',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入 Gateway URL';
                    }
                    if (!value.startsWith('ws://') &&
                        !value.startsWith('wss://')) {
                      return 'URL 必须以 ws:// 或 wss:// 开头';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _authTokenController,
                  decoration: const InputDecoration(
                    labelText: '认证 Token（可选）',
                    hintText: '如果 Gateway 需要认证...',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                _buildTestConnectionButton(),
                if (_testResult != null) ...[
                  const SizedBox(height: 8),
                  _buildTestResult(),
                ],
              ],
            ),

            const SizedBox(height: 24),

            // 模型配置
            _buildSection(
              title: '模型配置',
              children: [
                TextFormField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: '模型名称',
                    hintText: 'claude-3-5-sonnet, gpt-4, 等',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _systemPromptController,
                  decoration: const InputDecoration(
                    labelText: '系统提示词（可选）',
                    hintText: '自定义 Agent 的行为...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 工具配置
            _buildSection(
              title: '可用工具',
              children: [
                _buildToolsSelector(),
              ],
            ),

            const SizedBox(height: 32),

            // 保存按钮
            FilledButton(
              onPressed: _isLoading ? null : _saveAgent,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEditMode ? '保存更改' : '添加 Agent'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildAvatarSelector() {
    final avatars = ['🦅', '🤖', '🦾', '🧠', '💡', '⚡', '🔧', '🎯'];

    return Wrap(
      spacing: 12,
      children: avatars.map((avatar) {
        final isSelected = _selectedAvatar == avatar;
        return GestureDetector(
          onTap: () => setState(() => _selectedAvatar = avatar),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade300,
                width: isSelected ? 3 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                avatar,
                style: const TextStyle(fontSize: 32),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildToolsSelector() {
    return Column(
      children: OpenClawTool.all.map((tool) {
        final isSelected = _selectedTools.contains(tool);
        return CheckboxListTile(
          value: isSelected,
          onChanged: (checked) {
            setState(() {
              if (checked == true) {
                _selectedTools.add(tool);
              } else {
                _selectedTools.remove(tool);
              }
            });
          },
          title: Text(
            '${OpenClawTool.icons[tool]} ${OpenClawTool.displayNames[tool]}',
          ),
          subtitle: Text(_getToolDescription(tool)),
        );
      }).toList(),
    );
  }

  String _getToolDescription(String tool) {
    switch (tool) {
      case OpenClawTool.bash:
        return '执行 Shell 命令';
      case OpenClawTool.fileSystem:
        return '读写文件系统';
      case OpenClawTool.webSearch:
        return '搜索互联网';
      case OpenClawTool.codeExecutor:
        return '执行代码';
      case OpenClawTool.screenshot:
        return '截取屏幕';
      case OpenClawTool.browser:
        return '控制浏览器';
      default:
        return '';
    }
  }

  Widget _buildTestConnectionButton() {
    return OutlinedButton.icon(
      onPressed: _isTesting ? null : _testConnection,
      icon: _isTesting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cable),
      label: const Text('测试连接'),
    );
  }

  Widget _buildTestResult() {
    final isSuccess = _testResult == 'success';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSuccess ? Colors.green : Colors.red,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle : Icons.error,
            color: isSuccess ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isSuccess ? '连接成功！Gateway 可用。' : '连接失败：$_testResult',
              style: TextStyle(
                color: isSuccess ? Colors.green.shade900 : Colors.red.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final testAgent = OpenClawAgent(
        id: 'test',
        name: 'test',
        avatar: '🦅',
        gatewayUrl: _gatewayUrlController.text.trim(),
        authToken: _authTokenController.text.trim().isEmpty
            ? null
            : _authTokenController.text.trim(),
      );

      final success = await _acpService.testConnection(testAgent);

      setState(() {
        _testResult = success ? 'success' : '无法连接到 Gateway';
      });
    } catch (e) {
      setState(() {
        _testResult = e.toString();
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _saveAgent() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (widget.agent == null) {
        // 添加模式
        await _acpService.addAgent(
          name: _nameController.text.trim(),
          gatewayUrl: _gatewayUrlController.text.trim(),
          authToken: _authTokenController.text.trim().isEmpty
              ? null
              : _authTokenController.text.trim(),
          bio: _bioController.text.trim().isEmpty
              ? null
              : _bioController.text.trim(),
          avatar: _selectedAvatar,
          tools: _selectedTools.isEmpty ? null : _selectedTools,
          model: _modelController.text.trim().isEmpty
              ? null
              : _modelController.text.trim(),
          systemPrompt: _systemPromptController.text.trim().isEmpty
              ? null
              : _systemPromptController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OpenClaw Agent 添加成功！')),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        // 编辑模式
        final updatedAgent = widget.agent!.copyWith(
          name: _nameController.text.trim(),
          gatewayUrl: _gatewayUrlController.text.trim(),
          authToken: _authTokenController.text.trim().isEmpty
              ? null
              : _authTokenController.text.trim(),
          bio: _bioController.text.trim().isEmpty
              ? null
              : _bioController.text.trim(),
          avatar: _selectedAvatar,
          tools: _selectedTools.isEmpty ? null : _selectedTools,
          model: _modelController.text.trim().isEmpty
              ? null
              : _modelController.text.trim(),
          systemPrompt: _systemPromptController.text.trim().isEmpty
              ? null
              : _systemPromptController.text.trim(),
        );

        await _acpService.updateAgent(updatedAgent);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OpenClaw Agent 更新成功！')),
          );
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OpenClaw Agent 帮助'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '什么是 OpenClaw？',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'OpenClaw (Moltbot) 是一个工业级 AI Agent Gateway，'
                '可以连接大型语言模型（如 Claude、GPT-4）并提供工具调用能力。',
              ),
              SizedBox(height: 16),
              Text(
                '如何配置？',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('1. 确保 OpenClaw Gateway 已启动'),
              Text('2. 输入 Gateway URL（通常是 ws://localhost:18789）'),
              Text('3. 如需认证，输入 Token'),
              Text('4. 选择需要的工具'),
              Text('5. 点击"测试连接"验证配置'),
              SizedBox(height: 16),
              Text(
                '可用工具说明：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Bash 命令：执行 Shell 命令'),
              Text('• 文件系统：读写文件'),
              Text('• Web 搜索：搜索互联网'),
              Text('• 代码执行：运行代码'),
              Text('• 屏幕截图：截取屏幕'),
              Text('• 浏览器控制：自动化浏览器'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
