import 'package:flutter/material.dart';
import 'change_password_screen.dart';
import 'agent_list_screen.dart';
import 'channel_list_screen.dart';

/// 应用主页
class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Agent Hub'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 欢迎卡片
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.smart_toy,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '欢迎使用 AI Agent Hub',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '管理您的 AI Agent 和通信频道',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[700],
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 功能菜单标题
            Text(
              '功能菜单',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),

            // Agent 管理
            _buildFeatureCard(
              context,
              icon: Icons.smart_toy,
              title: 'Agent 管理',
              subtitle: '查看、添加和管理您的 AI Agent',
              color: Colors.blue,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AgentListScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 频道管理
            _buildFeatureCard(
              context,
              icon: Icons.forum,
              title: '频道管理',
              subtitle: '管理消息频道和会话',
              color: Colors.purple,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ChannelListScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 修改密码
            _buildFeatureCard(
              context,
              icon: Icons.lock_reset,
              title: '修改密码',
              subtitle: '更改您的登录密码',
              color: Colors.orange,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ChangePasswordScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 设置
            _buildFeatureCard(
              context,
              icon: Icons.settings,
              title: '设置',
              subtitle: '应用设置和偏好',
              color: Colors.green,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: color,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置页面
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          
          // 安全设置分组
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '安全设置',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('修改密码'),
            subtitle: const Text('更改登录密码'),
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
            title: const Text('生物识别'),
            subtitle: const Text('使用指纹或面部识别'),
            trailing: Switch(
              value: false,
              onChanged: (value) {
                // TODO: 实现生物识别
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('生物识别功能即将推出')),
                );
              },
            ),
          ),
          
          const Divider(height: 32),
          
          // 账户设置分组
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '账户设置',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('个人信息'),
            subtitle: const Text('管理您的个人信息'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('功能开发中')),
              );
            },
          ),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('通知设置'),
            subtitle: const Text('管理推送通知'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('功能开发中')),
              );
            },
          ),
          
          const Divider(height: 32),
          
          // 关于分组
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '关于',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('关于应用'),
            subtitle: const Text('版本 1.0.0'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'AI Agent Hub',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.android, size: 48),
                children: [
                  const Text('安全的 AI Agent 管理平台'),
                ],
              );
            },
          ),
          
          const Divider(),
          
          // 退出登录
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              '退出登录',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('确认退出'),
                  content: const Text('确定要退出登录吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          '/login',
                          (route) => false,
                        );
                      },
                      child: const Text(
                        '确定',
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
}
