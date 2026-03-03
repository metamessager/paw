import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/channel.dart';
import '../models/agent.dart';
import '../services/local_api_service.dart';
import '../services/local_database_service.dart';
import '../utils/logger.dart';
import 'chat_screen.dart';

/// Group detail screen, similar to RemoteAgentDetailScreen but for groups.
class GroupDetailScreen extends StatefulWidget {
  final Channel channel;

  const GroupDetailScreen({
    super.key,
    required this.channel,
  });

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late Channel _channel;
  final LocalApiService _apiService = LocalApiService();
  final LocalDatabaseService _databaseService = LocalDatabaseService();
  Map<String, Agent> _agentMap = {};
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    _loadAgents();
  }

  Future<void> _loadAgents() async {
    try {
      final agents = await _apiService.getAgents();
      final map = <String, Agent>{};
      for (final agent in agents) {
        map[agent.id] = agent;
      }
      if (mounted) {
        setState(() {
          _agentMap = map;
        });
      }
    } catch (e) {
      AppLogger.error('Failed to load agents for group detail', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final memberCount = _channel.members.where((m) => m.id != 'user').length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.groupDetail_title),
        elevation: 1,
      ),
      body: ListView(
        children: [
          // Header section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.group, size: 40, color: Colors.blue),
                ),
                const SizedBox(height: 16),
                Text(
                  _channel.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_channel.description != null &&
                    _channel.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _channel.description!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  l10n.contacts_memberCount(memberCount),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // System prompt section
          if (_channel.systemPrompt != null &&
              _channel.systemPrompt!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.groupDetail_systemPrompt,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _channel.systemPrompt!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],

          // Members section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.groupDetail_members,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
          ..._channel.members
              .where((m) => m.id != 'user')
              .map((member) => _buildMemberTile(member)),

          const SizedBox(height: 24),

          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: () => _startChat(),
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(l10n.groupDetail_startChat),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _isDeleting ? null : () => _showDeleteDialog(),
              icon: _isDeleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, color: Colors.red),
              label: Text(
                l10n.groupDetail_deleteGroup,
                style: const TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMemberTile(ChannelMember member) {
    final l10n = AppLocalizations.of(context);
    final agent = _agentMap[member.id];
    final isAdmin = member.role == 'admin';

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: agent != null && agent.avatar.length <= 2
            ? Text(agent.avatar, style: const TextStyle(fontSize: 18))
            : Text(
                agent?.name.isNotEmpty == true ? agent!.name[0] : '?',
                style: const TextStyle(fontSize: 18),
              ),
      ),
      title: Text(
        agent?.name ?? member.id,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: member.groupBio != null && member.groupBio!.isNotEmpty
          ? Text(
              member.groupBio!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            )
          : (agent?.bio != null && agent!.bio!.isNotEmpty
              ? Text(
                  agent.bio!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                )
              : null),
      trailing: isAdmin
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Text(
                l10n.groupDetail_admin,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          : Text(
              l10n.groupDetail_member,
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
    );
  }

  Future<void> _startChat() async {
    final latestChannelId = await _databaseService
        .getLatestActiveGroupChannel(_channel.groupFamilyId);
    final targetChannelId = latestChannelId ?? _channel.id;

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(channelId: targetChannelId),
      ),
    );
  }

  void _showDeleteDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.groupDetail_confirmDelete),
        content: Text(l10n.groupDetail_deleteContent(_channel.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteGroup();
            },
            child: Text(
              l10n.common_delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGroup() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _isDeleting = true);

    try {
      // Delete all sessions in this group family
      final sessions =
          await _databaseService.getGroupSessions(_channel.groupFamilyId);
      for (final session in sessions) {
        await _databaseService.deleteChannelMessages(session.id);
        await _databaseService.deleteChannel(session.id);
      }
      // Delete the parent group itself
      await _databaseService.deleteChannelMessages(_channel.id);
      await _databaseService.deleteChannel(_channel.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.groupDetail_deleted(_channel.name))),
      );
      Navigator.pop(context, true); // return true to indicate deletion
    } catch (e) {
      AppLogger.error('Failed to delete group', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l10n.groupDetail_deleteFailed(e.toString()))),
      );
      setState(() => _isDeleting = false);
    }
  }
}
