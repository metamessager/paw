import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/agent.dart';
import 'chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({Key? key}) : super(key: key);

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final Set<String> _selectedAgentIds = {};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入群聊名称')),
      );
      return;
    }

    if (_selectedAgentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个 Agent')),
      );
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    final channel = await appState.createGroup(
      name,
      _selectedAgentIds.toList(),
    );

    if (channel != null && mounted) {
      appState.selectChannel(channel);
      
      // 导航到聊天页面
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const ChatScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建群聊'),
        actions: [
          TextButton(
            onPressed: _createGroup,
            child: const Text(
              '创建',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          final agents = appState.agents;

          return Column(
            children: [
              // 群名输入
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '群聊名称',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.group),
                  ),
                ),
              ),

              // 已选择的 Agents
              if (_selectedAgentIds.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedAgentIds.length,
                    itemBuilder: (context, index) {
                      final agentId = _selectedAgentIds.elementAt(index);
                      final agent = agents.firstWhere((a) => a.id == agentId);
                      
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Chip(
                          avatar: Text(agent.avatar),
                          label: Text(agent.name),
                          onDeleted: () {
                            setState(() {
                              _selectedAgentIds.remove(agentId);
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),

              const Divider(),

              // Agent 列表
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Text(
                      '选择 Agent',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${_selectedAgentIds.length} 个)',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: agents.isEmpty
                    ? const Center(
                        child: Text('暂无 Agent'),
                      )
                    : ListView.builder(
                        itemCount: agents.length,
                        itemBuilder: (context, index) {
                          final agent = agents[index];
                          final isSelected = _selectedAgentIds.contains(agent.id);

                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedAgentIds.add(agent.id);
                                } else {
                                  _selectedAgentIds.remove(agent.id);
                                }
                              });
                            },
                            secondary: Text(
                              agent.avatar,
                              style: const TextStyle(fontSize: 28),
                            ),
                            title: Text(
                              agent.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(agent.provider.name),
                            enabled: agent.status.isOnline,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
