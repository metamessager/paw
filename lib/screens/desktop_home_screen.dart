import 'package:flutter/material.dart';
import '../models/conversation_selection.dart';
import '../l10n/app_localizations.dart';
import '../services/local_database_service.dart';
import '../services/message_search_service.dart';
import '../widgets/agent_search_delegate.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'add_remote_agent_screen.dart';
import 'create_group_screen.dart';
import 'settings_screen.dart';
import '../utils/layout_utils.dart';
import '../services/native_window_service.dart';

/// Desktop split-panel layout similar to WeChat desktop.
/// Left: icon sidebar + conversation list (HomeScreen embedded).
/// Right: chat view (ChatScreen embedded) or empty state.
class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({Key? key}) : super(key: key);

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

/// Tracks what the right panel is currently displaying.
enum _RightPanelView {
  empty,
  chat,
  settings,
  addAgent,
  createGroup,
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  @override
  void dispose() {
    FloatingPanelManager.instance.closeAll();
    NativeWindowService.instance.closeAll();
    super.dispose();
  }

  ConversationSelection? _selected;
  double _leftPanelWidth = 320;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  /// A separate navigator key for the right panel so that pages pushed
  /// inside it (e.g. sub-pages of Settings) stay within the right panel
  /// and never cover the sidebar or conversation list.
  final GlobalKey<NavigatorState> _rightNavKey = GlobalKey<NavigatorState>();

  _RightPanelView _rightPanel = _RightPanelView.empty;

  /// Monotonic counter appended to the Navigator's ValueKey so that
  /// each conversation switch creates a fresh Navigator (and therefore a
  /// fresh initial route).  This avoids the problem where
  /// `onGenerateRoute` only fires once for a given Navigator instance.
  int _navGeneration = 0;

  static const double _minLeftPanelWidth = 240;
  static const double _maxLeftPanelWidth = 480;
  static const double _sidebarWidth = 56;

  void _onConversationSelected(ConversationSelection selection) {
    setState(() {
      _selected = selection;
      _rightPanel = _RightPanelView.chat;
      _navGeneration++;
    });
  }

  void _onChatClose() {
    setState(() {
      _selected = null;
      _rightPanel = _RightPanelView.empty;
      _navGeneration++;
    });
  }

  void _onSwitchChannel(String channelId) {
    if (_selected == null) return;
    setState(() {
      _selected = ConversationSelection(
        agentId: _selected!.agentId,
        agentName: _selected!.agentName,
        agentAvatar: _selected!.agentAvatar,
        channelId: channelId,
      );
      _navGeneration++;
    });
  }

  void _reloadAgents() {
    _homeKey.currentState?.reloadAgents();
  }

  void _showPanel(_RightPanelView panel) {
    setState(() {
      _rightPanel = panel;
      if (panel != _RightPanelView.chat) {
        _selected = null;
      }
      _navGeneration++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // WeChat-style icon sidebar
          _buildSidebar(),

          // Conversation list panel
          SizedBox(
            width: _leftPanelWidth,
            child: HomeScreen(
              key: _homeKey,
              embedded: true,
              selectedConversation: _selected,
              onConversationSelected: _onConversationSelected,
            ),
          ),

          // Resizable divider
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                _leftPanelWidth = (_leftPanelWidth + details.delta.dx)
                    .clamp(_minLeftPanelWidth, _maxLeftPanelWidth);
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: Container(
                width: 1,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),

          // Right panel — uses a nested Navigator so that pages pushed
          // inside it (e.g. Settings sub-pages) stay within this panel.
          // The ValueKey includes _navGeneration so that switching
          // conversations creates a fresh Navigator with a new initial
          // route, rather than trying to mutate the old one.
          Expanded(
            child: ClipRect(
              child: Navigator(
                key: ValueKey('nav_$_navGeneration'),
                onGenerateRoute: (_) {
                  return MaterialPageRoute(
                    builder: (_) => _buildRightPanelRoot(),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The root widget of the right-panel navigator.
  Widget _buildRightPanelRoot() {
    switch (_rightPanel) {
      case _RightPanelView.chat:
        if (_selected != null) {
          return ChatScreen(
            key: ValueKey(_selected!.key),
            agentId: _selected!.agentId,
            agentName: _selected!.agentName,
            agentAvatar: _selected!.agentAvatar,
            channelId: _selected!.channelId,
            embedded: true,
            onClose: _onChatClose,
            onSwitchChannel: _onSwitchChannel,
          );
        }
        return _buildEmptyState();

      case _RightPanelView.settings:
        return const SettingsScreen();

      case _RightPanelView.addAgent:
        return AddRemoteAgentScreen(
          onDone: () {
            _reloadAgents();
            _showPanel(_RightPanelView.empty);
          },
        );

      case _RightPanelView.createGroup:
        return CreateGroupScreen(
          onGroupCreated: (channelId) {
            _reloadAgents();
            // After creating a group, switch to the group chat.
            _onConversationSelected(ConversationSelection(
              channelId: channelId,
            ));
          },
        );

      case _RightPanelView.empty:
        return _buildEmptyState();
    }
  }

  /// WeChat-style narrow icon sidebar on the far left.
  Widget _buildSidebar() {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final sidebarBg = colorScheme.surfaceContainerHighest;
    final iconColor = colorScheme.onSurfaceVariant;
    final activeColor = colorScheme.primary;

    return Container(
      width: _sidebarWidth,
      color: sidebarBg,
      child: Column(
        children: [
          const SizedBox(height: 12),
          // App avatar / brand
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/images/paw_icon.png',
                width: 36,
                height: 36,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Chat (current view indicator)
          _SidebarIcon(
            icon: Icons.chat_bubble,
            tooltip: l10n.drawer_myProfile,
            color: _rightPanel == _RightPanelView.chat ||
                    _rightPanel == _RightPanelView.empty
                ? activeColor
                : iconColor,
            onTap: () => _showPanel(_RightPanelView.empty),
          ),

          // Search
          _SidebarIcon(
            icon: Icons.search,
            tooltip: l10n.common_search,
            color: iconColor,
            onTap: () => _openSearch(),
          ),

          const Spacer(),

          // New Agent
          _SidebarIcon(
            icon: Icons.person_add_outlined,
            tooltip: l10n.drawer_newAgent,
            color: _rightPanel == _RightPanelView.addAgent
                ? activeColor
                : iconColor,
            onTap: () => _showPanel(_RightPanelView.addAgent),
          ),

          // New Group
          _SidebarIcon(
            icon: Icons.group_add_outlined,
            tooltip: l10n.drawer_newGroup,
            color: _rightPanel == _RightPanelView.createGroup
                ? activeColor
                : iconColor,
            onTap: () => _showPanel(_RightPanelView.createGroup),
          ),

          const Divider(indent: 12, endIndent: 12, height: 1),

          // Settings
          _SidebarIcon(
            icon: Icons.settings_outlined,
            tooltip: l10n.drawer_settings,
            color: _rightPanel == _RightPanelView.settings
                ? activeColor
                : iconColor,
            onTap: () => _showPanel(_RightPanelView.settings),
          ),

          // Logout
          _SidebarIcon(
            icon: Icons.logout,
            tooltip: l10n.drawer_logout,
            color: Colors.red,
            onTap: _showLogoutDialog,
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _openSearch() {
    final agents = _homeKey.currentState?.agents ?? [];
    final databaseService = LocalDatabaseService();
    final messageSearchService = MessageSearchService(databaseService);
    // Use the right-panel navigator context so the search overlay
    // only covers the right panel, not the sidebar.
    final navContext = _rightNavKey.currentContext;
    if (navContext != null) {
      showSearch(
        context: navContext,
        delegate: AgentSearchDelegate(
          agents: agents,
          databaseService: databaseService,
          messageSearchService: messageSearchService,
        ),
      );
    }
  }

  void _showLogoutDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.logout_confirmTitle),
        content: Text(l10n.logout_confirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
                '/login',
                (route) => false,
              );
            },
            child: Text(
              l10n.common_confirm,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.home_noMessages,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single icon button in the sidebar.
class _SidebarIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _SidebarIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}
