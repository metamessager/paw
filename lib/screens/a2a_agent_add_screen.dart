import 'package:flutter/material.dart';
import '../models/universal_agent.dart';
import '../services/universal_agent_service.dart';

/// 添加 A2A Agent 页面
class A2AAgentAddScreen extends StatefulWidget {
  final UniversalAgentService agentService;
  final VoidCallback onAdded;

  const A2AAgentAddScreen({
    Key? key,
    required this.agentService,
    required this.onAdded,
  }) : super(key: key);

  @override
  State<A2AAgentAddScreen> createState() => _A2AAgentAddScreenState();
}

class _A2AAgentAddScreenState extends State<A2AAgentAddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _uriController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _bioController = TextEditingController();

  bool _autoDiscover = true;
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _uriController.dispose();
    _apiKeyController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加 A2A Agent'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 说明卡片
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'A2A 协议说明',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'A2A (Agent-to-Agent) 是 Google 开源的标准协议，'
                      '用于实现不同 AI Agent 之间的互操作。\n\n'
                      '输入 Agent 的基础 URI（如 https://example.com），'
                      '系统会自动发现 Agent Card。',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 自动发现开关
            SwitchListTile(
              title: const Text('自动发现 Agent'),
              subtitle: const Text('通过标准路径 /.well-known/agent.json 发现'),
              value: _autoDiscover,
              onChanged: (value) => setState(() => _autoDiscover = value),
            ),
            const SizedBox(height: 16),

            // URI 输入
            TextFormField(
              controller: _uriController,
              decoration: const InputDecoration(
                labelText: 'Agent URI *',
                hintText: 'https://example.com',
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
                helperText: 'Agent 的基础 URL',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入 URI';
                }
                if (!value.startsWith('http://') && !value.startsWith('https://')) {
                  return '请输入有效的 HTTP(S) URL';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // API Key 输入
            TextFormField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key (可选)',
                hintText: '输入认证 Token',
                prefixIcon: Icon(Icons.key),
                border: OutlineInputBorder(),
                helperText: '如果需要认证，请输入 API Key',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),

            // 手动模式额外字段
            if (!_autoDiscover) ...[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Agent 名称 *',
                  hintText: '给 Agent 起个名字',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (!_autoDiscover && (value == null || value.isEmpty)) {
                    return '请输入名称';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(
                  labelText: '简介 (可选)',
                  hintText: 'Agent 的描述',
                  prefixIcon: Icon(Icons.description),
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
            ],

            // 添加按钮
            ElevatedButton(
              onPressed: _loading ? null : _addAgent,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _autoDiscover ? '发现并添加' : '手动添加',
                      style: const TextStyle(fontSize: 16),
                    ),
            ),

            // 示例
            const SizedBox(height: 24),
            ExpansionTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text('示例 URI'),
              children: [
                ListTile(
                  dense: true,
                  title: const Text('https://agent.example.com'),
                  subtitle: const Text('标准 A2A Agent'),
                  onTap: () {
                    _uriController.text = 'https://agent.example.com';
                  },
                ),
                ListTile(
                  dense: true,
                  title: const Text('https://api.openai.com/v1/agents/gpt-4'),
                  subtitle: const Text('OpenAI A2A Agent (假设)'),
                  onTap: () {
                    _uriController.text =
                        'https://api.openai.com/v1/agents/gpt-4';
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addAgent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      A2AAgent agent;

      if (_autoDiscover) {
        // 自动发现模式
        agent = await widget.agentService.discoverAndAddA2AAgent(
          _uriController.text.trim(),
          apiKey: _apiKeyController.text.trim().isEmpty
              ? null
              : _apiKeyController.text.trim(),
          customName: _nameController.text.trim().isEmpty
              ? null
              : _nameController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('成功添加 A2A Agent: ${agent.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // 手动添加模式
        agent = await widget.agentService.addA2AAgentManually(
          name: _nameController.text.trim(),
          baseUri: _uriController.text.trim(),
          apiKey: _apiKeyController.text.trim().isEmpty
              ? null
              : _apiKeyController.text.trim(),
          bio: _bioController.text.trim().isEmpty
              ? null
              : _bioController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('成功添加 Agent: ${agent.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      widget.onAdded();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('添加失败'),
            content: Text(
              _autoDiscover
                  ? '无法发现 A2A Agent。\n\n'
                      '错误: $e\n\n'
                      '建议:\n'
                      '1. 检查 URI 是否正确\n'
                      '2. 确认 Agent 支持 A2A 协议\n'
                      '3. 检查网络连接\n'
                      '4. 尝试"手动添加"模式'
                  : '添加 Agent 失败: $e',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
              if (_autoDiscover)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() => _autoDiscover = false);
                  },
                  child: const Text('切换手动模式'),
                ),
            ],
          ),
        );
      }
    }
  }
}
