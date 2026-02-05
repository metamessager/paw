import 'package:flutter/material.dart';
import '../models/knot_agent.dart';
import '../services/local_knot_agent_service.dart';

/// Knot Agent 详情/编辑页面
class KnotAgentDetailScreen extends StatefulWidget {
  final KnotAgent? agent;

  const KnotAgentDetailScreen({Key? key, this.agent}) : super(key: key);

  @override
  State<KnotAgentDetailScreen> createState() => _KnotAgentDetailScreenState();
}

class _KnotAgentDetailScreenState extends State<KnotAgentDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _knotApiService = LocalKnotAgentService();
  
  late TextEditingController _nameController;
  late TextEditingController _avatarController;
  late TextEditingController _bioController;
  late TextEditingController _systemPromptController;
  
  String _selectedModel = 'deepseek-v3.1-Terminus';
  List<String> _mcpServers = [];
  String? _selectedWorkspace;
  List<KnotWorkspace> _workspaces = [];
  
  bool _isLoading = false;
  bool _isLoadingWorkspaces = false;

  final List<String> _availableModels = [
    'deepseek-v3.1-Terminus',
    'deepseek-v3.2',
    'deepseek-r1-0528',
    'kimi-k2-instruct',
    'glm-4.6',
    'glm-4.7',
  ];

  @override
  void initState() {
    super.initState();
    
    _nameController = TextEditingController(text: widget.agent?.name ?? '');
    _avatarController = TextEditingController(text: widget.agent?.avatar ?? '🌐');
    _bioController = TextEditingController(text: widget.agent?.bio ?? '');
    _systemPromptController = TextEditingController(
      text: widget.agent?.config.systemPrompt ?? '',
    );
    
    if (widget.agent != null) {
      _selectedModel = widget.agent!.config.model;
      _mcpServers = List.from(widget.agent!.config.mcpServers);
      _selectedWorkspace = widget.agent!.workspaceId;
    }
    
    _loadWorkspaces();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _avatarController.dispose();
    _bioController.dispose();
    _systemPromptController.dispose();
    _knotApiService.dispose();
    super.dispose();
  }

  Future<void> _loadWorkspaces() async {
    setState(() => _isLoadingWorkspaces = true);
    
    try {
      final workspaces = await _knotApiService.getWorkspaces();
      setState(() {
        _workspaces = workspaces;
        _isLoadingWorkspaces = false;
      });
    } catch (e) {
      setState(() => _isLoadingWorkspaces = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载工作区失败: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (widget.agent == null) {
        // 创建新 Agent
        await _knotApiService.createKnotAgent(
          name: _nameController.text,
          avatar: _avatarController.text,
          bio: _bioController.text.isEmpty ? null : _bioController.text,
          model: _selectedModel,
          systemPrompt: _systemPromptController.text.isEmpty 
              ? null 
              : _systemPromptController.text,
          mcpServers: _mcpServers,
          workspaceId: _selectedWorkspace,
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('创建成功')),
          );
          Navigator.pop(context, true);
        }
      } else {
        // 更新现有 Agent
        await _knotApiService.updateKnotAgent(
          agentId: widget.agent!.knotAgentId,
          name: _nameController.text,
          avatar: _avatarController.text,
          bio: _bioController.text.isEmpty ? null : _bioController.text,
          model: _selectedModel,
          systemPrompt: _systemPromptController.text.isEmpty 
              ? null 
              : _systemPromptController.text,
          mcpServers: _mcpServers,
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('更新成功')),
          );
          Navigator.pop(context, true);
        }
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

  void _addMcpServer() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加 MCP 服务'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入 MCP 服务名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _mcpServers.add(result);
      });
    }
  }

  void _removeMcpServer(int index) {
    setState(() {
      _mcpServers.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.agent != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑 Agent' : '创建 Agent'),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.check),
              tooltip: '保存',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Agent 名称',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label),
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
              controller: _avatarController,
              decoration: const InputDecoration(
                labelText: 'Avatar (Emoji)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.emoji_emotions),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入 Avatar';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bioController,
              decoration: const InputDecoration(
                labelText: '简介（可选）',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            const Text(
              '配置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedModel,
              decoration: const InputDecoration(
                labelText: '模型',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.computer),
              ),
              items: _availableModels.map((model) {
                return DropdownMenuItem(
                  value: model,
                  child: Text(model),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedModel = value);
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _systemPromptController,
              decoration: const InputDecoration(
                labelText: '系统提示词（可选）',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.chat),
                hintText: '输入自定义系统提示词',
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 16),
            if (!isEdit) ...[
              DropdownButtonFormField<String>(
                value: _selectedWorkspace,
                decoration: const InputDecoration(
                  labelText: '工作区（可选）',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.folder),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('不指定工作区'),
                  ),
                  ..._workspaces.map((workspace) {
                    return DropdownMenuItem(
                      value: workspace.id,
                      child: Text('${workspace.name} (${workspace.type})'),
                    );
                  }),
                ],
                onChanged: _isLoadingWorkspaces
                    ? null
                    : (value) {
                        setState(() => _selectedWorkspace = value);
                      },
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                const Text(
                  'MCP 服务',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addMcpServer,
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
              ],
            ),
            if (_mcpServers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '暂无 MCP 服务',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ..._mcpServers.asMap().entries.map((entry) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.extension),
                    title: Text(entry.value),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _removeMcpServer(entry.key),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
