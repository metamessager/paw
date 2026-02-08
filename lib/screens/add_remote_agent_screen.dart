import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/remote_agent.dart';
import '../services/remote_agent_service.dart';
import '../services/local_database_service.dart';
import '../services/token_service.dart';
import 'agent_token_display_screen.dart';

/// 添加远端助手界面
class AddRemoteAgentScreen extends StatefulWidget {
  const AddRemoteAgentScreen({super.key});

  @override
  State<AddRemoteAgentScreen> createState() => _AddRemoteAgentScreenState();
}

enum AgentCreationMode {
  create, // 创建本地配置，生成 Token
  connect, // 连接到远端 Agent，输入 Token
}

class _AddRemoteAgentScreenState extends State<AddRemoteAgentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _endpointController = TextEditingController();
  final _tokenController = TextEditingController();

  AgentCreationMode _mode = AgentCreationMode.connect; // 默认为连接模式
  ProtocolType _selectedProtocol = ProtocolType.a2a;
  ConnectionType _selectedConnectionType = ConnectionType.http;
  String _selectedAvatar = '🤖';
  bool _isCreating = false;

  late RemoteAgentService _agentService;

  @override
  void initState() {
    super.initState();
    final dbService = LocalDatabaseService();
    final tokenService = TokenService(dbService);
    _agentService = RemoteAgentService(dbService, tokenService);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _endpointController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _createAgent() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final agent = await _agentService.createAgent(
        name: _nameController.text.trim(),
        protocol: _selectedProtocol,
        connectionType: _selectedConnectionType,
        endpoint: _endpointController.text.trim(),
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        avatar: _selectedAvatar,
      );

      if (!mounted) return;

      // 导航到 Token 展示界面
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AgentTokenDisplayScreen(agent: agent),
        ),
      );
    } on AgentDuplicateException catch (e) {
      if (!mounted) return;

      await _showDuplicateAgentDialog(e);

      setState(() {
        _isCreating = false;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('创建失败: $e'),
          backgroundColor: Colors.red,
        ),
      );

      setState(() {
        _isCreating = false;
      });
    }
  }

  Future<void> _connectToAgent() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      // 1. 先创建临时 Agent 用于测试连接
      final tempAgent = await _agentService.createAgentWithToken(
        name: _nameController.text.trim(),
        protocol: _selectedProtocol,
        connectionType: _selectedConnectionType,
        endpoint: _endpointController.text.trim(),
        token: _tokenController.text.trim(),
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        avatar: _selectedAvatar,
      );

      if (!mounted) return;

      // 2. 显示测试连接提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('正在测试 Agent 连接...'),
            ],
          ),
          duration: Duration(seconds: 5),
        ),
      );

      // 3. 测试 Agent 连接
      final isHealthy = await _agentService.checkAgentHealth(
        tempAgent.id,
        timeout: const Duration(seconds: 10),
      );

      if (!mounted) return;

      if (isHealthy) {
        // 连接成功
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接成功！Agent 在线可用'),
            backgroundColor: Colors.green,
          ),
        );

        // 返回到列表页
        Navigator.pop(context, true);
      } else {
        // 连接失败，询问是否保留
        final shouldKeep = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('连接测试失败'),
            content: const Text(
              'Agent 健康检查失败，无法建立连接。\n\n'
              '可能的原因：\n'
              '• Endpoint URL 不正确\n'
              '• Token 无效\n'
              '• Agent 服务未运行\n'
              '• 网络连接问题\n\n'
              '是否仍要保留此 Agent 配置？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('删除配置'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保留配置'),
              ),
            ],
          ),
        );

        if (shouldKeep != true) {
          // 用户选择删除配置
          await _agentService.deleteAgent(tempAgent.id);

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已删除 Agent 配置'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          // 用户选择保留配置
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已保留 Agent 配置（离线状态）'),
              backgroundColor: Colors.orange,
            ),
          );
        }

        // 返回到列表页
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } on AgentDuplicateException catch (e) {
      if (!mounted) return;

      await _showDuplicateAgentDialog(e);

      setState(() {
        _isCreating = false;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('操作失败: $e'),
          backgroundColor: Colors.red,
        ),
      );

      setState(() {
        _isCreating = false;
      });
    }
  }

  Future<void> _showDuplicateAgentDialog(AgentDuplicateException e) async {
    final existingAgent = e.existingAgent;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agent 已存在'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.message),
            const SizedBox(height: 12),
            Text(
              '已有 Agent 信息：',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text('名称: ${existingAgent.name}'),
            if (existingAgent.endpoint.isNotEmpty)
              Text('Endpoint: ${existingAgent.endpoint}'),
            Text('协议: ${existingAgent.protocol.name}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_mode == AgentCreationMode.connect ? '连接远端助手' : '创建助手配置'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 模式切换
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('连接远端 Agent'),
                          selected: _mode == AgentCreationMode.connect,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _mode = AgentCreationMode.connect;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('创建本地配置'),
                          selected: _mode == AgentCreationMode.create,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _mode = AgentCreationMode.create;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 头像选择
              Center(
                child: GestureDetector(
                  onTap: _showAvatarPicker,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _selectedAvatar,
                        style: const TextStyle(fontSize: 48),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _showAvatarPicker,
                  icon: const Icon(Icons.edit),
                  label: const Text('更换头像'),
                ),
              ),
              const SizedBox(height: 24),

              // 助手名称
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '助手名称',
                  hintText: '例如：我的 AI 助手',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入助手名称';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 助手描述
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(
                  labelText: '助手描述（可选）',
                  hintText: '简单描述这个助手的功能',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // Token 输入字段（仅连接模式显示）
              if (_mode == AgentCreationMode.connect) ...[
                TextFormField(
                  controller: _tokenController,
                  decoration: InputDecoration(
                    labelText: '远端 Token',
                    hintText: '输入远端 Agent 的认证 Token',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.vpn_key),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          _tokenController.text = data!.text!;
                        }
                      },
                      tooltip: '从剪贴板粘贴',
                    ),
                  ),
                  validator: (value) {
                    if (_mode == AgentCreationMode.connect) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入远端 Token';
                      }
                    }
                    return null;
                  },
                  obscureText: false,
                  enableSuggestions: false,
                  autocorrect: false,
                ),
                const SizedBox(height: 16),
              ],

              // 端点 URL
              TextFormField(
                controller: _endpointController,
                decoration: InputDecoration(
                  labelText: _mode == AgentCreationMode.connect
                      ? '端点 URL'
                      : '端点 URL（可选）',
                  hintText: _selectedConnectionType == ConnectionType.websocket
                      ? 'ws://example.com/agent'
                      : 'https://example.com/agent',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.language),
                  helperText: _mode == AgentCreationMode.connect
                      ? '远端 Agent 的服务地址'
                      : '可以稍后配置',
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (_mode == AgentCreationMode.connect) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入端点 URL';
                    }
                    // 简单的 URL 格式验证
                    if (!value.startsWith('http://') &&
                        !value.startsWith('https://') &&
                        !value.startsWith('ws://') &&
                        !value.startsWith('wss://')) {
                      return '请输入有效的 URL（http://, https://, ws://, wss://）';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 协议类型
              DropdownButtonFormField<ProtocolType>(
                value: _selectedProtocol,
                decoration: const InputDecoration(
                  labelText: '协议类型',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.settings_ethernet),
                ),
                items: const [
                  DropdownMenuItem(
                    value: ProtocolType.a2a,
                    child: Text('A2A (Agent-to-Agent)'),
                  ),
                  DropdownMenuItem(
                    value: ProtocolType.acp,
                    child: Text('ACP (Agent Communication Protocol)'),
                  ),
                  DropdownMenuItem(
                    value: ProtocolType.custom,
                    child: Text('自定义协议'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedProtocol = value!;
                  });
                },
              ),
              const SizedBox(height: 16),

              // 连接类型
              DropdownButtonFormField<ConnectionType>(
                value: _selectedConnectionType,
                decoration: const InputDecoration(
                  labelText: '连接类型',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
                items: const [
                  DropdownMenuItem(
                    value: ConnectionType.http,
                    child: Text('HTTP/HTTPS'),
                  ),
                  DropdownMenuItem(
                    value: ConnectionType.websocket,
                    child: Text('WebSocket'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedConnectionType = value!;
                    // 根据连接类型更新端点提示
                    if (_endpointController.text.isEmpty) {
                      return;
                    }
                  });
                },
              ),
              const SizedBox(height: 24),

              // 说明文本
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _mode == AgentCreationMode.connect
                              ? '连接说明'
                              : '创建说明',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _mode == AgentCreationMode.connect
                          ? '1. 输入远端 Agent 提供的 Token\n'
                            '2. 填写远端 Agent 的服务地址\n'
                            '3. 选择正确的协议和连接类型\n'
                            '4. 连接成功后可以开始对话'
                          : '1. 创建后将生成唯一的 Token\n'
                            '2. 使用 Token 在远端助手配置中进行认证\n'
                            '3. 远端助手连接成功后将显示在线状态',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 操作按钮
              ElevatedButton(
                onPressed: _isCreating ? null : (_mode == AgentCreationMode.connect ? _connectToAgent : _createAgent),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isCreating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_mode == AgentCreationMode.connect ? '连接远端助手' : '创建助手配置'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAvatarPicker() {
    final avatars = [
      '🤖', '🦾', '🧠', '💡', '🌟', '⚡', '🔮', '🎯',
      '🚀', '🛸', '🌈', '🔥', '💎', '🎨', '🎭', '🎪',
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择头像'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: avatars.length,
            itemBuilder: (context, index) {
              final avatar = avatars[index];
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedAvatar = avatar;
                  });
                  Navigator.pop(context);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: _selectedAvatar == avatar
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      avatar,
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}
