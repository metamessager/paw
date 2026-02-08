import 'dart:async';
import 'package:flutter/material.dart';
import '../models/agent.dart';
import '../services/local_api_service.dart';
import '../services/local_database_service.dart';
import '../services/remote_agent_service.dart';
import '../services/token_service.dart';
import '../utils/logger.dart';
import 'remote_agent_list_screen.dart';
import 'channel_list_screen.dart';
import 'add_remote_agent_screen.dart';
import 'create_group_screen.dart';
import 'chat_screen.dart';
import 'agent_detail_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import '../widgets/agent_search_delegate.dart';
import '../services/message_search_service.dart';
/// 应用主页 - Telegram风格设计
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final LocalApiService _apiService = LocalApiService();
  List<Agent> _agents = [];
  List<Agent> _filteredAgents = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  // FAB 动画控制
  late AnimationController _buttonAnimatedIcon;

  // 定期健康检查定时器
  Timer? _healthCheckTimer;

  // TODO: Use _isFabMenuOpen if implementing FAB menu toggle
  // bool _isFabMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _loadAgents();
    _searchController.addListener(_onSearchChanged);

    // 初始化动画控制器
    _buttonAnimatedIcon = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // 启动定期健康检查（每30秒）
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshAgentStatus();
    });
  }

  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    _searchController.dispose();
    _buttonAnimatedIcon.dispose();
    super.dispose();
  }

  // TODO: Implement _toggleFabMenu if needed
  // /// 切换 FAB 菜单
  // void _toggleFabMenu() {
  //   setState(() {
  //     _isFabMenuOpen = !_isFabMenuOpen;
  //     if (_isFabMenuOpen) {
  //       _buttonAnimatedIcon.forward();
  //     } else {
  //       _buttonAnimatedIcon.reverse();
  //     }
  //   });
  // }

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
        color: statusColor.withValues(alpha: 0.1),
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
                    builder: (context) => AgentDetailScreen(agent: agent),
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

  /// 加载Agent列表
  Future<void> _loadAgents() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 先执行所有 Agent 的健康检查，更新数据库中的状态
      final databaseService = LocalDatabaseService();
      final tokenService = TokenService(databaseService);
      final remoteAgentService = RemoteAgentService(databaseService, tokenService);
      await remoteAgentService.checkAllAgentsHealth(
        timeout: const Duration(seconds: 3),
      );

      // 然后加载最新的 Agent 列表
      final agents = await _apiService.getAgents();
      if (mounted) {
        setState(() {
          _agents = agents;
          _filteredAgents = _applySearchFilter(agents);
          _isLoading = false;
        });
      }
      AppLogger.info('Loaded ${agents.length} agents');
    } catch (e) {
      AppLogger.error('Failed to load agents', e);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 静默刷新 Agent 状态（不显示 loading 状态）
  Future<void> _refreshAgentStatus() async {
    try {
      final databaseService = LocalDatabaseService();
      final tokenService = TokenService(databaseService);
      final remoteAgentService = RemoteAgentService(databaseService, tokenService);
      await remoteAgentService.checkAllAgentsHealth(
        timeout: const Duration(seconds: 3),
      );

      final agents = await _apiService.getAgents();
      if (mounted) {
        setState(() {
          _agents = agents;
          _filteredAgents = _applySearchFilter(agents);
        });
      }
    } catch (e) {
      AppLogger.error('Failed to refresh agent status', e);
    }
  }

  /// 根据当前搜索关键字过滤 Agent 列表
  List<Agent> _applySearchFilter(List<Agent> agents) {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) return agents;
    return agents.where((agent) {
      return agent.name.toLowerCase().contains(query) ||
             (agent.type?.toLowerCase().contains(query) ?? false) ||
             (agent.description?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  /// 搜索过滤
  void _onSearchChanged() {
    setState(() {
      _filteredAgents = _applySearchFilter(_agents);
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
              final databaseService = LocalDatabaseService();
              final messageSearchService = MessageSearchService(databaseService);
              showSearch(
                context: context,
                delegate: AgentSearchDelegate(
                  agents: _agents,
                  databaseService: databaseService,
                  messageSearchService: messageSearchService,
                ),
              );
            },
          ),
        ],
      ),
      // 左侧抽屉菜单
      drawer: _buildDrawer(),
      body: _buildBody(),
      floatingActionButton: _buildFloatingActionButton(),
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
                      ).then((_) => _loadAgents());
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

  /// 构建功能卡片
  
  
  // TODO: Implement _buildFeatureCard if needed
  // Widget _buildFeatureCard(
  //   BuildContext context, {
  //   required IconData icon,
  //   required String title,
  //   required String subtitle,
  //   required Color color,
  //   required VoidCallback onTap,
  // }) {
  //   return Card(
  //     elevation: 2,
  //     child: InkWell(
  //       onTap: onTap,
  //       child: Padding(
  //         padding: const EdgeInsets.all(16),
  //         child: Row(
  //           children: [
  //             Container(
  //               padding: const EdgeInsets.all(12),
  //               decoration: BoxDecoration(
  //                 color: color.withValues(alpha: 0.1),
  //                 borderRadius: BorderRadius.circular(12),
  //               ),
  //               child: Icon(
  //                 icon,
  //                 color: color,
  //                 size: 32,
  //               ),
  //             ),
  //             const SizedBox(width: 16),
  //             Expanded(
  //               child: Column(
  //                 crossAxisAlignment: CrossAxisAlignment.start,
  //                 children: [
  //                   Text(
  //                     title,
  //                     style: const TextStyle(
  //                       fontSize: 16,
  //                       fontWeight: FontWeight.bold,
  //                     ),
  //                   ),
  //                   const SizedBox(height: 4),
  //                   Text(
  //                     subtitle,
  //                     style: TextStyle(
  //                       fontSize: 14,
  //                       color: Colors.grey[600],
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //             Icon(
  //               Icons.chevron_right,
  //               color: Colors.grey[400],
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }

  /// 构建浮动操作按钮
  Widget _buildFloatingActionButton() {
    return FloatingActionButton(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          builder: (context) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.smart_toy),
                  title: const Text('添加 Agent'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AddRemoteAgentScreen(),
                      ),
                    ).then((_) => _loadAgents());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.group_add),
                  title: const Text('创建群组'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateGroupScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
      child: const Icon(Icons.add),
    );
  }
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
    );
  }
}
