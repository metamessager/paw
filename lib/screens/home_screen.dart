import 'package:flutter/material.dart';
import '../models/agent.dart';
import '../services/local_api_service.dart';
import '../utils/logger.dart';
import 'remote_agent_list_screen.dart';
import 'channel_list_screen.dart';
import 'change_password_screen.dart';
import 'chat_screen.dart';

/// 应用主页 - Telegram风格设计
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LocalApiService _apiService = LocalApiService();
  List<Agent> _agents = [];
  List<Agent> _filteredAgents = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _loadAgents();
    _searchController.addListener(_onSearchChanged);
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 加载Agent列表
  Future<void> _loadAgents() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final agents = await _apiService.getAgents();
      setState(() {
        _agents = agents;
        _filteredAgents = agents;
        _isLoading = false;
      });
      AppLogger.info('Loaded ${agents.length} agents');
    } catch (e) {
      AppLogger.error('Failed to load agents', e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 搜索过滤
  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredAgents = _agents.where((agent) {
        return agent.name.toLowerCase().contains(query) ||
               (agent.type?.toLowerCase().contains(query) ?? false) ||
               (agent.description?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Agent Hub'),
        elevation: 1,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          // 搜索按钮（展开搜索）
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              showSearch(
                context: context,
                delegate: AgentSearchDelegate(agents: _agents),
              );
            },
          ),
          // 更多菜单
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'agents':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RemoteAgentListScreen(),
                    ),
                  );
                  break;
                case 'channels':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChannelListScreen(),
                    ),
                  );
                  break;
                case 'settings':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'agents',
                child: ListTile(
                  leading: Icon(Icons.smart_toy),
                  title: Text('Agent管理'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'channels',
                child: ListTile(
                  leading: Icon(Icons.forum),
                  title: Text('频道管理'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('设置'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      // 左侧抽屉菜单
      drawer: _buildDrawer(),
      body: _buildBody(),
    );
  }

  /// 构建左侧抽屉菜单
  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // 用户信息头部
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
              ),
              accountName: const Text('User'),
              accountEmail: const Text('user@ai-agent-hub.com'),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Text(
                  'U',
                  style: TextStyle(
                    fontSize: 24,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
            ),
            
            // 菜单列表
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('My Profile'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfileScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.smart_toy_outlined),
                    title: const Text('New Agent'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RemoteAgentListScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.group_add_outlined),
                    title: const Text('New Group'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ChannelListScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Settings'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text(
                      'Logout',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _showLogoutDialog();
                    },
                  ),
                ],
              ),
            ),
            
            // 版本信息
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'AI Agent Hub v1.0.0',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示退出登录确认对话框
  void _showLogoutDialog() {
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
  }

  /// 构建主页body内容
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_agents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Agents',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the menu to add agents',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAgents,
      child: ListView.builder(
        itemCount: _filteredAgents.length,
        itemBuilder: (context, index) {
          return _buildAgentTile(_filteredAgents[index]);
        },
      ),
    );
  }

  /// Agent列表项 - Telegram风格
  Widget _buildAgentTile(Agent agent) {
    return InkWell(
      onTap: () {
        // 点击进入聊天
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              agentId: agent.id,
              agentName: agent.name,
              agentAvatar: agent.avatar,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Agent头像
            _buildAgentAvatar(agent),
            const SizedBox(width: 12),
            // Agent信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 名称行
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          agent.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 状态指示器
                      _buildStatusIndicator(agent),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 描述或类型
                  Text(
                    agent.description ?? agent.type ?? 'AI Agent',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 更多操作
            IconButton(
              icon: const Icon(Icons.more_horiz, size: 20),
              color: Colors.grey,
              onPressed: () {
                _showAgentOptions(agent);
              },
            ),
          ],
        ),
      ),
      // 浮动操作按钮：快速添加
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 添加 Agent 按钮
          AnimatedBuilder(
            animation: _translateButton,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(
                  0,
                  -(_translateButton.value * 140),
                ),
                child: Opacity(
                  opacity: _translateButton.value,
                  child: _buildFabMenuItem(
                    icon: Icons.smart_toy,
                    label: '添加 Agent',
                    backgroundColor: Colors.blue,
                    onTap: () {
                      _toggleFabMenu();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AgentListScreen(),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          // 创建群组按钮
          AnimatedBuilder(
            animation: _translateButton,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(
                  0,
                  -(_translateButton.value * 70),
                ),
                child: Opacity(
                  opacity: _translateButton.value,
                  child: _buildFabMenuItem(
                    icon: Icons.group_add,
                    label: '创建群组',
                    backgroundColor: Colors.purple,
                    onTap: () {
                      _toggleFabMenu();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CreateGroupScreen(),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // 主 FAB 按钮
          FloatingActionButton(
            onPressed: _toggleFabMenu,
            child: AnimatedIcon(
              icon: AnimatedIcons.menu_close,
              progress: _buttonAnimatedIcon,
            ),
          ),
        ],
      ),
      // 背景遮罩
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Stack(
        children: [
          // 原有内容
          SingleChildScrollView(
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

                // Knot Agent 管理
                _buildFeatureCard(
                  context,
                  icon: Icons.cloud,
                  title: 'Knot Agent',
                  subtitle: '管理 Knot 平台的 OpenClaw 风格 Agent',
                  color: Colors.teal,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const KnotAgentScreen(),
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
          // 背景遮罩（当菜单打开时）
          if (_isFabMenuOpen)
            GestureDetector(
              onTap: _toggleFabMenu,
              child: Container(
                color: Colors.black54,
              ),
            ),
        ],
      ),
    );
  }

  /// 构建 FAB 菜单项
  Widget _buildFabMenuItem({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required VoidCallback onTap,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标签
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 按钮
        FloatingActionButton(
          heroTag: label,
          mini: true,
          backgroundColor: backgroundColor,
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }

  /// Agent头像
  Widget _buildAgentAvatar(Agent agent) {
    final isOnline = agent.status.isOnline;
    
    return Stack(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Colors.grey[200],
          child: agent.avatar.length <= 2
              ? Text(
                  agent.avatar,
                  style: const TextStyle(fontSize: 24),
                )
              : ClipOval(
                  child: Image.network(
                    agent.avatar,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Text(
                        agent.name.isNotEmpty ? agent.name[0] : 'A',
                        style: const TextStyle(fontSize: 24),
                      );
                    },
                  ),
                ),
        ),
        // 在线状态点
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 状态指示器
  Widget _buildStatusIndicator(Agent agent) {
    String statusText;
    Color statusColor;
    
    if (agent.status.isOnline) {
      statusText = '在线';
      statusColor = Colors.green;
    } else {
      statusText = '离线';
      statusColor = Colors.grey;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          fontSize: 11,
          color: statusColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 显示Agent操作菜单
  void _showAgentOptions(Agent agent) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Start Chat'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ChatScreen(
                      agentId: agent.id,
                      agentName: agent.name,
                      agentAvatar: agent.avatar,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('View Details'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RemoteAgentListScreen(),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.red),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// 个人资料页面
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 32),
            
            // 头像
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    child: Icon(
                      Icons.person,
                      size: 60,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 用户名
            const Text(
              'User',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // 邮箱
            Text(
              'user@ai-agent-hub.com',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // 信息卡片
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: const Text('Email'),
                    subtitle: const Text('user@ai-agent-hub.com'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Feature coming soon')),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: const Text('Phone'),
                    subtitle: const Text('Not set'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Feature coming soon')),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cake_outlined),
                    title: const Text('Birthday'),
                    subtitle: const Text('Not set'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Feature coming soon')),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: const Text('Location'),
                    subtitle: const Text('Not set'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Feature coming soon')),
                      );
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 统计信息
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('Agents', '5'),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.grey[300],
                    ),
                    _buildStatItem('Groups', '3'),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.grey[300],
                    ),
                    _buildStatItem('Messages', '128'),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 编辑资料按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Feature coming soon')),
                    );
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit Profile'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 统计项
  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

/// Agent搜索委托
class AgentSearchDelegate extends SearchDelegate<Agent?> {
  final List<Agent> agents;

  AgentSearchDelegate({required this.agents});

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    final results = query.isEmpty
        ? agents
        : agents.where((agent) {
            return agent.name.toLowerCase().contains(query.toLowerCase()) ||
                   (agent.type?.toLowerCase().contains(query.toLowerCase()) ?? false) ||
                   (agent.description?.toLowerCase().contains(query.toLowerCase()) ?? false);
          }).toList();

    if (results.isEmpty) {
      return const Center(
        child: Text('No agents found'),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final agent = results[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey[200],
            child: agent.avatar.length <= 2
                ? Text(agent.avatar, style: const TextStyle(fontSize: 20))
                : ClipOval(
                    child: Image.network(
                      agent.avatar,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Text(
                          agent.name.isNotEmpty ? agent.name[0] : 'A',
                          style: const TextStyle(fontSize: 20),
                        );
                      },
                    ),
                  ),
          ),
          title: Text(agent.name),
          subtitle: Text(agent.description ?? agent.type ?? 'AI Agent'),
          onTap: () {
            close(context, agent);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(
                  agentId: agent.id,
                  agentName: agent.name,
                  agentAvatar: agent.avatar,
                ),
              ),
            );
          },
        );
      },
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
                // TODO: 实现生物识别
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Biometric authentication coming soon')),
                );
              },
            ),
          ),
          
          const Divider(height: 32),
          
          // 账户设置分组
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
                  builder: (context) => const ProfileScreen(),
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
          
          // 关于分组
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
          
          // 退出登录
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
}
