import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/agent.dart';
import 'chat_screen.dart';

class AgentListScreen extends StatelessWidget {
  const AgentListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择 Agent'),
      ),
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          final agents = appState.agents;

          if (agents.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.smart_toy_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('暂无 Agent'),
                  SizedBox(height: 8),
                  Text(
                    '请先在平台注册 Agent',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: agents.length,
            itemBuilder: (context, index) {
              final agent = agents[index];
              return _AgentListItem(
                agent: agent,
                onTap: () async {
                  // 创建私聊
                  final channel = await appState.createDMWithAgent(agent.id);
                  
                  if (channel != null && context.mounted) {
                    appState.selectChannel(channel);
                    
                    // 导航到聊天页面
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const ChatScreen(),
                      ),
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _AgentListItem extends StatelessWidget {
  final Agent agent;
  final VoidCallback onTap;

  const _AgentListItem({
    required this.agent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: agent.status.isOnline
            ? Colors.green.withOpacity(0.2)
            : Colors.grey.withOpacity(0.2),
        child: Text(
          agent.avatar,
          style: const TextStyle(fontSize: 24),
        ),
      ),
      title: Text(
        agent.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (agent.bio != null) ...[
            Text(agent.bio!),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: agent.status.isOnline ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                agent.status.isOnline ? '在线' : '离线',
                style: TextStyle(
                  color: agent.status.isOnline ? Colors.green : Colors.grey,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                agent.provider.name,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
      trailing: const Icon(Icons.chat_bubble_outline),
      onTap: onTap,
    );
  }
}
