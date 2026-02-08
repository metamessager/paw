import 'package:flutter/material.dart';
import 'change_password_screen.dart';
import 'profile_screen.dart';
import '../services/local_database_service.dart';

/// Settings screen
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          
          // Security settings section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Security',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('Change Password'),
            subtitle: const Text('Change your login password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChangePasswordScreen(),
                ),
              );
            },
          ),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Biometric Authentication'),
            subtitle: const Text('Use fingerprint or face ID'),
            trailing: Switch(
              value: false,
              onChanged: (value) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Biometric authentication coming soon')),
                );
              },
            ),
          ),
          
          const Divider(height: 32),
          
          // Account settings section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Account',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile'),
            subtitle: const Text('Manage your profile information'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(),
                ),
              );
            },
          ),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Notifications'),
            subtitle: const Text('Manage push notifications'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Feature coming soon')),
              );
            },
          ),
          
          const Divider(height: 32),

          // Data management section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Data Management',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.delete_sweep, color: Colors.orange),
            title: const Text('Clear Sample Data'),
            subtitle: const Text('Remove demo agents and channels'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showClearDataDialog(context),
          ),

          const Divider(height: 32),

          // About section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'About',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('About'),
            subtitle: const Text('Version 1.0.0'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'AI Agent Hub',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.android, size: 48),
                children: const [
                  Text('Secure AI Agent Management Platform'),
                ],
              );
            },
          ),
          
          const Divider(),
          
          // Logout
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'Logout',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Confirm Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          '/login',
                          (route) => false,
                        );
                      },
                      child: const Text(
                        'Logout',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 显示清理数据确认对话框
  void _showClearDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理示例数据'),
        content: const Text(
          '这将删除所有示例 Agent 和相关的 Channel、消息。\n\n'
          '注意：这不会删除您手动添加的远端 Agent。\n\n'
          '是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearSampleData(context);
            },
            child: const Text(
              '清理',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  /// 清理示例数据
  Future<void> _clearSampleData(BuildContext context) async {
    try {
      // 显示进度提示
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
              Text('正在清理数据...'),
            ],
          ),
          duration: Duration(seconds: 5),
        ),
      );

      final db = LocalDatabaseService();

      // 获取所有 Agent
      final agents = await db.getAllAgents();

      // 筛选出示例 Agent（根据名称判断）
      final sampleAgents = agents.where((agent) =>
        agent.name == 'GPT-4 助手' || agent.name == 'Claude 助手'
      ).toList();

      if (sampleAgents.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('未找到示例数据'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // 删除示例 Agent（会自动级联删除相关的 Channel、消息等）
      for (final agent in sampleAgents) {
        await db.deleteAgent(agent.id);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已删除 ${sampleAgents.length} 个示例 Agent'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('清理失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
