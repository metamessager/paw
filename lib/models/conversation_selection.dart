/// Immutable data class representing a selected conversation in the desktop
/// split-panel layout.
class ConversationSelection {
  final String? agentId;
  final String? agentName;
  final String? agentAvatar;
  final String? channelId;

  const ConversationSelection({
    this.agentId,
    this.agentName,
    this.agentAvatar,
    this.channelId,
  });

  /// Unique key used to force ChatScreen recreation via ValueKey.
  String get key => channelId ?? agentId ?? '';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationSelection &&
          agentId == other.agentId &&
          channelId == other.channelId;

  @override
  int get hashCode => Object.hash(agentId, channelId);
}
