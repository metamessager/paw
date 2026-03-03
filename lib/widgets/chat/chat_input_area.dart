import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/pending_attachment.dart';
import '../../models/remote_agent.dart';
import '../../services/audio_recording_service.dart';
import '../../utils/layout_utils.dart';
import '../../l10n/app_localizations.dart';

/// The chat input area widget (supports both desktop and mobile layouts).
///
/// Handles:
/// - Text input with desktop/mobile layouts
/// - Voice recording (mobile: hold to talk)
/// - Pending attachment previews
/// - @mention picker for group mode
/// - Emoji picker toggle
/// - Enter key handling (send / mention confirm)
class ChatInputArea extends StatefulWidget {
  final TextEditingController messageController;
  final FocusNode textFieldFocusNode;
  final bool isLoading;
  final bool isProcessing;
  final bool isGroupMode;
  final List<PendingAttachment> pendingAttachments;
  final List<RemoteAgent> groupAgents;
  final AudioRecordingService audioRecordingService;
  final bool isRecording;
  final bool isCancelZone;
  final VoidCallback onSend;
  final VoidCallback onToggleEmojiPicker;
  final VoidCallback onShowAttachmentOptions;
  final VoidCallback? onSendVoice;
  final bool showEmojiPicker;
  final ValueChanged<PendingAttachment> onRemoveAttachment;

  const ChatInputArea({
    super.key,
    required this.messageController,
    required this.textFieldFocusNode,
    required this.isLoading,
    required this.isProcessing,
    required this.isGroupMode,
    required this.pendingAttachments,
    required this.groupAgents,
    required this.audioRecordingService,
    required this.isRecording,
    required this.isCancelZone,
    required this.onSend,
    required this.onToggleEmojiPicker,
    required this.onShowAttachmentOptions,
    this.onSendVoice,
    required this.showEmojiPicker,
    required this.onRemoveAttachment,
  });

  @override
  State<ChatInputArea> createState() => ChatInputAreaState();
}

class ChatInputAreaState extends State<ChatInputArea> {
  bool _isVoiceMode = false;
  bool _hasText = false;

  // Mention picker state
  bool _showMentionPicker = false;
  String _mentionQuery = '';
  int _mentionTriggerOffset = -1;
  int _mentionSelectedIndex = 0;

  bool get showMentionPicker => _showMentionPicker;

  @override
  void initState() {
    super.initState();
    _hasText = widget.messageController.text.isNotEmpty;
    widget.messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.messageController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final newHasText = widget.messageController.text.isNotEmpty;
    if (newHasText != _hasText) {
      setState(() {
        _hasText = newHasText;
      });
    }
    if (widget.isGroupMode) {
      _detectMentionTrigger();
    }
  }

  bool get _canSend => _hasText || widget.pendingAttachments.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isDesktop = LayoutUtils.isDesktopLayout(context);
    if (isDesktop) {
      return _buildDesktopInputArea();
    }
    return _buildMobileInputArea();
  }

  /// Build the mention picker overlay widget.
  Widget buildMentionPicker() {
    final showAll = _mentionAllMatches(_mentionQuery.toLowerCase());
    final filtered = _getFilteredMentionAgents();
    final totalCount = (showAll ? 1 : 0) + filtered.length;

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: totalCount,
        itemBuilder: (context, index) {
          if (showAll && index == 0) {
            final isSelected = _mentionSelectedIndex == 0;
            return ListTile(
              dense: true,
              selected: isSelected,
              selectedTileColor: Colors.blue.withOpacity(0.1),
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.orange[200] : Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.group, size: 16, color: Colors.orange[800]),
              ),
              title: Text(
                AppLocalizations.of(context).chat_mentionAll,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                AppLocalizations.of(context).chat_mentionAllSub(widget.groupAgents.length),
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              onTap: _insertMentionAll,
            );
          }

          final agentIndex = showAll ? index - 1 : index;
          final agent = filtered[agentIndex];
          final isSelected = index == _mentionSelectedIndex;
          return ListTile(
            dense: true,
            selected: isSelected,
            selectedTileColor: Colors.blue.withOpacity(0.1),
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue[200] : Colors.blue[100],
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                agent.name.isNotEmpty ? agent.name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            title: Text(
              agent.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            onTap: () => _insertMentionAtCursor(agent),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Desktop input area
  // ---------------------------------------------------------------------------

  Widget _buildDesktopInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    widget.showEmojiPicker
                        ? Icons.keyboard
                        : Icons.emoji_emotions_outlined,
                    size: 22,
                  ),
                  color: Colors.grey[600],
                  onPressed: widget.onToggleEmojiPicker,
                  tooltip: 'Emoji',
                  splashRadius: 18,
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file, size: 22),
                  color: Colors.grey[600],
                  onPressed: widget.onShowAttachmentOptions,
                  tooltip: 'Attachment',
                  splashRadius: 18,
                ),
              ],
            ),
          ),
          _buildPendingAttachmentsPreview(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleInputKeyEvent,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 80,
                        maxHeight: 200,
                      ),
                      child: TextField(
                        controller: widget.messageController,
                        focusNode: widget.textFieldFocusNode,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context).chat_messageHint,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        enabled: !widget.isLoading,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: widget.isLoading
                      ? Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send),
                          color: _canSend
                              ? Theme.of(context).primaryColor
                              : Colors.grey[400],
                          onPressed: _canSend ? widget.onSend : null,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile input area
  // ---------------------------------------------------------------------------

  Widget _buildMobileInputArea() {
    final hasPendingAttachments = widget.pendingAttachments.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPendingAttachmentsPreview(),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isVoiceMode ? Icons.keyboard_alt_outlined : Icons.mic_none,
                  ),
                  color: Colors.grey[600],
                  onPressed: () {
                    setState(() {
                      _isVoiceMode = !_isVoiceMode;
                    });
                    if (!_isVoiceMode) {
                      widget.textFieldFocusNode.requestFocus();
                    }
                  },
                ),
                IconButton(
                  icon: Icon(
                    widget.showEmojiPicker
                        ? Icons.keyboard
                        : Icons.emoji_emotions_outlined,
                  ),
                  color: Colors.grey[600],
                  onPressed: widget.onToggleEmojiPicker,
                ),
                Expanded(
                  child: _isVoiceMode
                      ? _buildHoldToTalkButton()
                      : Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Focus(
                            onKeyEvent: _handleInputKeyEvent,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 150),
                              child: TextField(
                                controller: widget.messageController,
                                focusNode: widget.textFieldFocusNode,
                                decoration: InputDecoration(
                                  hintText: AppLocalizations.of(context).chat_messageHint,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                maxLines: null,
                                textInputAction: TextInputAction.newline,
                                enabled: !widget.isLoading,
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  color: Colors.grey[600],
                  onPressed: widget.onShowAttachmentOptions,
                ),
                if (!_isVoiceMode)
                  widget.isLoading
                      ? Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        )
                      : (_hasText || hasPendingAttachments || widget.isProcessing)
                          ? IconButton(
                              icon: const Icon(Icons.send),
                              color: Theme.of(context).primaryColor,
                              onPressed: (_hasText || hasPendingAttachments) ? widget.onSend : null,
                            )
                          : const SizedBox.shrink(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Hold to talk button
  // ---------------------------------------------------------------------------

  Widget _buildHoldToTalkButton() {
    return GestureDetector(
      onLongPressStart: (_) {
        widget.audioRecordingService.startRecording().then((success) {
          if (!success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).chat_micNotAvailable),
              ),
            );
          }
        });
      },
      onLongPressMoveUpdate: (details) {
        // Cancel zone is handled by parent widget
      },
      onLongPressEnd: (_) async {
        if (widget.isCancelZone) {
          await widget.audioRecordingService.cancelRecording();
        } else {
          widget.onSendVoice?.call();
        }
      },
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: widget.isRecording ? Colors.grey[300] : Colors.grey[100],
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.grey[300]!,
            width: 0.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.isRecording
              ? (widget.isCancelZone
                  ? AppLocalizations.of(context).chat_releaseToCancel
                  : AppLocalizations.of(context).chat_releaseToSend)
              : AppLocalizations.of(context).chat_holdToTalk,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pending attachments preview
  // ---------------------------------------------------------------------------

  Widget _buildPendingAttachmentsPreview() {
    if (widget.pendingAttachments.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
        ),
      ),
      child: SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: widget.pendingAttachments.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final att = widget.pendingAttachments[index];
            if (att.type == PendingAttachmentType.image) {
              return _buildImagePreviewItem(att);
            } else {
              return _buildFilePreviewItem(att);
            }
          },
        ),
      ),
    );
  }

  Widget _buildImagePreviewItem(PendingAttachment att) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: att.thumbnailBytes != null
              ? Image.memory(
                  att.thumbnailBytes!,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                )
              : Container(
                  width: 80,
                  height: 80,
                  color: Colors.grey[200],
                  child: const Icon(Icons.image, color: Colors.grey),
                ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => widget.onRemoveAttachment(att),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilePreviewItem(PendingAttachment att) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 160,
          height: 80,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              Icon(Icons.insert_drive_file, size: 32, color: Colors.blue[400]),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      att.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      PendingAttachment.formatFileSize(att.fileSize),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => widget.onRemoveAttachment(att),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Key event handling
  // ---------------------------------------------------------------------------

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (widget.messageController.value.composing != TextRange.empty) {
        return KeyEventResult.ignored;
      }
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      if (_showMentionPicker) {
        final showAll = _mentionAllMatches(_mentionQuery.toLowerCase());
        if (showAll && _mentionSelectedIndex == 0) {
          _insertMentionAll();
        } else {
          final filtered = _getFilteredMentionAgents();
          final agentIndex = showAll ? _mentionSelectedIndex - 1 : _mentionSelectedIndex;
          if (agentIndex >= 0 && agentIndex < filtered.length) {
            _insertMentionAtCursor(filtered[agentIndex]);
          }
        }
        return KeyEventResult.handled;
      }
      widget.onSend();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp && _showMentionPicker) {
      final totalCount = _getMentionPickerItemCount(_mentionQuery);
      if (totalCount > 0) {
        setState(() {
          _mentionSelectedIndex = (_mentionSelectedIndex - 1).clamp(0, totalCount - 1);
        });
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && _showMentionPicker) {
      final totalCount = _getMentionPickerItemCount(_mentionQuery);
      if (totalCount > 0) {
        setState(() {
          _mentionSelectedIndex = (_mentionSelectedIndex + 1).clamp(0, totalCount - 1);
        });
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // Mention picker logic
  // ---------------------------------------------------------------------------

  void _detectMentionTrigger() {
    final text = widget.messageController.text;
    final selection = widget.messageController.selection;
    final cursorPos = selection.baseOffset;

    if (cursorPos < 0 || cursorPos > text.length) {
      if (_showMentionPicker) {
        setState(() { _showMentionPicker = false; });
      }
      return;
    }

    int atPos = -1;
    for (int i = cursorPos - 1; i >= 0; i--) {
      final char = text[i];
      if (char == '@') {
        if (i == 0 || text[i - 1] == ' ' || text[i - 1] == '\n') {
          atPos = i;
        }
        break;
      }
      if (char == ' ' || char == '\n') break;
    }

    if (atPos >= 0) {
      final query = text.substring(atPos + 1, cursorPos).toLowerCase();
      final totalCount = _getMentionPickerItemCount(query);

      if (totalCount > 0) {
        final queryChanged = query != _mentionQuery;
        setState(() {
          _showMentionPicker = true;
          _mentionQuery = query;
          _mentionTriggerOffset = atPos;
          if (queryChanged) { _mentionSelectedIndex = 0; }
          if (_mentionSelectedIndex >= totalCount) {
            _mentionSelectedIndex = totalCount - 1;
          }
        });
        return;
      }
    }

    if (_showMentionPicker) {
      setState(() { _showMentionPicker = false; });
    }
  }

  bool _mentionAllMatches(String query) {
    return 'all'.contains(query);
  }

  int _getMentionPickerItemCount(String query) {
    final q = query.toLowerCase();
    final agentCount = widget.groupAgents.where(
      (a) => a.name.toLowerCase().contains(q),
    ).length;
    final allCount = _mentionAllMatches(q) ? 1 : 0;
    return allCount + agentCount;
  }

  List<RemoteAgent> _getFilteredMentionAgents() {
    return widget.groupAgents.where(
      (a) => a.name.toLowerCase().contains(_mentionQuery.toLowerCase()),
    ).toList();
  }

  void _insertMentionAtCursor(RemoteAgent agent) {
    _insertMentionText('@${agent.name} ');
  }

  void _insertMentionAll() {
    _insertMentionText('@all ');
  }

  void _insertMentionText(String mentionText) {
    final text = widget.messageController.text;
    final selection = widget.messageController.selection;
    final cursorPos = selection.baseOffset;

    if (_mentionTriggerOffset >= 0 && cursorPos >= 0) {
      final newText = text.substring(0, _mentionTriggerOffset) +
          mentionText +
          text.substring(cursorPos);
      widget.messageController.text = newText;
      final newCursorPos = _mentionTriggerOffset + mentionText.length;
      widget.messageController.selection = TextSelection.collapsed(offset: newCursorPos);
    } else {
      widget.messageController.text = text + mentionText;
      widget.messageController.selection = TextSelection.collapsed(
        offset: widget.messageController.text.length,
      );
    }

    setState(() {
      _showMentionPicker = false;
      _mentionTriggerOffset = -1;
      _mentionQuery = '';
      _mentionSelectedIndex = 0;
    });

    widget.textFieldFocusNode.requestFocus();
  }

  /// Public method to insert a mention for a specific agent (called from parent).
  void insertMentionForAgent(RemoteAgent agent) {
    _insertMentionAtCursor(agent);
    widget.textFieldFocusNode.requestFocus();
  }
}
