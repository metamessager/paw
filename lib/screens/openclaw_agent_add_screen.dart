import 'package:flutter/material.dart';
import '../models/openclaw_agent.dart';
import '../services/openclaw_agent_service.dart';

/// 添加 OpenClaw Agent 页面
class OpenClawAgentAddScreen extends StatefulWidget {
  final OpenClawAgentService agentService;
  final VoidCallback onAdded;

  const OpenClawAgentAddScreen({
    Key? key,
    required this.agentService,
    required this.onAdded,
  }) : super(key: key);

  @override
  State<OpenClawAgentAddScreen> createState() => _OpenClawAgentAddScreenState();
}

class _OpenClawAgentAddScreenState extends State<OpenClawAgentAddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _workspaceIdController = TextEditingController();
  final _modelController = TextEditingController();
  final _bioController = TextEditingController();

  bool _loading = false;
  bool _showAdvanced = false;

  // 高级配置
  final List<String> _selectedTools = [];
  final List<String> _selectedKnowledgeBases = [];

  @override
  void initState() {
    super.initState();
    // 设置默认值
    _baseUrlController.text = 'https://knot.example.com';
    _modelController.text = 'gpt-4';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _tokenController.dispose();
    _workspaceIdController.dispose();
    _modelController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加 OpenClaw Agent'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // OpenClaw 说明卡片
            Card(
              color: Colors.purple.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🦅', style: TextStyle(fontSize: 32)),
                        const SizedBox(width: 12),
                        Text(
                          'OpenClaw (Knot Platform)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'OpenClaw 是基于 Knot 平台的智能体系统，支持：\n'
                      '• MCP 工具集成\n'
                      '• Rules 规则引擎\n'
                      '• 知识库检索\n'
                      '• 多模型支持',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 基本配置
            Text(
              '基本配置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.purple.shade700,
              ),
            ),
            const SizedBox(height: 16),

            // Agent 名称
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Agent 名称 *',
                hintText: '例: 我的 OpenClaw 助手',
                prefixIcon: Icon(Icons.badge),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入名称';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Knot Base URL
            TextFormField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Knot Base URL *',
                hintText: 'https://knot.example.com',
                prefixIcon: Icon(Icons.cloud),
                border: OutlineInputBorder(),
                helperText: 'Knot 平台的基础 URL',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入 Base URL';
                }
                if (!value.startsWith('http://') && !value.startsWith('https://')) {
                  return '请输入有效的 URL';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Knot Token
            TextFormField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Knot Token *',
                hintText: '输入你的 Knot API Token',
                prefixIcon: Icon(Icons.key),
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入 Token';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Workspace ID
            TextFormField(
              controller: _workspaceIdController,
              decoration: const InputDecoration(
                labelText: 'Workspace ID *',
                hintText: '例: workspace-123',
                prefixIcon: Icon(Icons.workspaces),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入 Workspace ID';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 模型选择
            TextFormField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: '模型 (可选)',
                hintText: 'gpt-4, claude-3, 等',
                prefixIcon: Icon(Icons.psychology),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 简介
            TextFormField(
              controller: _bioController,
              decoration: const InputDecoration(
                labelText: '简介 (可选)',
                hintText: 'Agent 的描述',
                prefixIcon: Icon(Icons.description),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            // 高级配置折叠
            ExpansionTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('高级配置'),
              initiallyExpanded: _showAdvanced,
              onExpansionChanged: (expanded) {
                setState(() => _showAdvanced = expanded);
              },
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // MCP 工具配置
                      const Text(
                        'MCP 工具',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          'weather',
                          'web_search',
                          'file_system',
                          'database',
                        ].map((tool) {
                          final isSelected = _selectedTools.contains(tool);
                          return FilterChip(
                            label: Text(tool),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedTools.add(tool);
                                } else {
                                  _selectedTools.remove(tool);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // 知识库配置
                      const Text(
                        '知识库',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '示例知识库 UUID:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const Text(
                        'bed6837500624aa6b2d3f3551f8590be (Knot)',
                        style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _addKnowledgeBase,
                        icon: const Icon(Icons.add),
                        label: const Text('添加知识库'),
                      ),
                      if (_selectedKnowledgeBases.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ..._selectedKnowledgeBases.map((kb) {
                          return Chip(
                            label: Text(kb.substring(0, 20) + '...'),
                            onDeleted: () {
                              setState(() {
                                _selectedKnowledgeBases.remove(kb);
                              });
                            },
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 添加按钮
            ElevatedButton(
              onPressed: _loading ? null : _addAgent,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.purple,
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '添加 OpenClaw Agent',
                      style: TextStyle(fontSize: 16),
                    ),
            ),

            // 测试连接按钮
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loading ? null : _testConnection,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('测试连接'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addKnowledgeBase() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加知识库'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '知识库 UUID',
            hintText: 'bed6837500624aa6b2d3f3551f8590be',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _selectedKnowledgeBases.add(result);
      });
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      // 创建临时 Agent 测试连接
      final testAgent = OpenClawAgent(
        id: 'test',
        name: _nameController.text,
        avatar: '🦅',
        knotBaseUrl: _baseUrlController.text.trim(),
        knotToken: _tokenController.text.trim(),
        knotWorkspaceId: _workspaceIdController.text.trim(),
      );

      final success = await widget.agentService.testConnection(testAgent);

      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '✅ 连接成功！' : '❌ 连接失败'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addAgent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final agent = await widget.agentService.addAgent(
        name: _nameController.text.trim(),
        knotBaseUrl: _baseUrlController.text.trim(),
        knotToken: _tokenController.text.trim(),
        knotWorkspaceId: _workspaceIdController.text.trim(),
        knotModel: _modelController.text.trim().isEmpty
            ? null
            : _modelController.text.trim(),
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        tools: _selectedTools.isEmpty ? null : _selectedTools,
        knowledgeBases:
            _selectedKnowledgeBases.isEmpty ? null : _selectedKnowledgeBases,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 成功添加: ${agent.name}'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onAdded();
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('添加失败'),
            content: Text('错误: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }
}
