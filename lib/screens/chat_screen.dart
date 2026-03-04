import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/channel.dart';
import '../models/pending_attachment.dart';
import '../models/remote_agent.dart';
import '../services/audio_recording_service.dart';
import '../utils/layout_utils.dart';
import '../l10n/app_localizations.dart';
import '../controllers/chat_controller.dart';
import '../widgets/chat/chat_app_bar.dart';
import '../widgets/chat/chat_menu.dart';
import '../widgets/chat/chat_input_area.dart';
import '../widgets/chat/chat_message_list.dart';
import '../widgets/chat/chat_reply_preview.dart';
import '../widgets/chat/session_list_panel.dart';
import '../widgets/chat/group_session_list_panel.dart';
import '../widgets/message_search_delegate.dart';
import '../widgets/voice_record_overlay.dart';
import 'remote_agent_detail_screen.dart';
import 'group_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  final String? agentId;
  final String? agentName;
  final String? agentAvatar;
  final String? channelId;
  final bool embedded;
  final VoidCallback? onClose;
  final ValueChanged<String>? onSwitchChannel;

  /// When set, scroll to and highlight this message after loading.
  final String? highlightMessageId;

  /// When true, show a back arrow in the app bar (e.g. returning to search).
  final bool showBackButton;

  const ChatScreen({
    Key? key,
    this.agentId,
    this.agentName,
    this.agentAvatar,
    this.channelId,
    this.embedded = false,
    this.onClose,
    this.onSwitchChannel,
    this.highlightMessageId,
    this.showBackButton = false,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late final ChatController _controller;
  StreamSubscription<ChatEvent>? _eventSubscription;

  // UI-only state (bound to widget tree)
  final _messageController = TextEditingController();
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  final _textFieldFocusNode = FocusNode();
  final _chatInputKey = GlobalKey<ChatInputAreaState>();

  // Voice recording (UI-bound)
  late AudioRecordingService _audioRecordingService;
  StreamSubscription<RecordingState>? _recordingSubscription;
  bool _isRecording = false;
  bool _isCancelZone = false;
  Duration _recordingElapsed = Duration.zero;
  double _recordingAmplitude = 0.0;

  // Pending attachments (UI-bound)
  List<PendingAttachment> _pendingAttachments = [];
  static const int _maxPendingAttachments = 9;

  // Emoji picker (UI-bound)
  bool _showEmojiPicker = false;

  // Scroll state (UI-bound)
  bool _isUserScrolledUp = false;
  int _unreadMessageCount = 0;

  // Pending highlight from search navigation
  String? _pendingHighlightMessageId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = ChatController(
      agentId: widget.agentId,
      initialAgentName: widget.agentName,
      initialAgentAvatar: widget.agentAvatar,
      initialChannelId: widget.channelId,
      embedded: widget.embedded,
      onClose: widget.onClose,
      onSwitchChannel: widget.onSwitchChannel,
      getUserId: () => Provider.of<AppState>(context, listen: false).currentUser?.id ?? 'user',
      getUserName: () => Provider.of<AppState>(context, listen: false).currentUser?.username ?? 'User',
    );

    _controller.addListener(_onControllerChanged);
    _eventSubscription = _controller.events.listen(_handleControllerEvent);

    _audioRecordingService = AudioRecordingService();
    _recordingSubscription = _audioRecordingService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isRecording = state.isRecording;
          _recordingElapsed = state.elapsed;
          _recordingAmplitude = state.amplitude;
        });
      }
    });

    _messageController.addListener(_onTextChanged);
    _itemPositionsListener.itemPositions.addListener(_onScroll);
    _textFieldFocusNode.addListener(_onFocusChanged);

    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    }

    _controller.init();
    _audioRecordingService.requestPermission();
    _pendingHighlightMessageId = widget.highlightMessageId;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    }
    _eventSubscription?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _recordingSubscription?.cancel();
    _audioRecordingService.dispose();
    _messageController.dispose();
    _textFieldFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.onAppLifecycleChanged(state == AppLifecycleState.resumed);

    // If the app loses focus while recording (e.g. Samsung edge panel, app
    // switch, incoming call), stop the recording so it doesn't run forever.
    if (state != AppLifecycleState.resumed &&
        _audioRecordingService.currentState.isRecording) {
      _audioRecordingService.cancelRecording();
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Event handling
  // ---------------------------------------------------------------------------

  void _handleControllerEvent(ChatEvent event) {
    if (!mounted) return;

    switch (event) {
      case ShowSnackBarEvent(:final message):
        _showLocalizedSnackBar(message);
      case ShowErrorSnackBarEvent(:final message):
        _showLocalizedSnackBar(message, isError: true);
      case ShowRetrySnackBarEvent(:final interruptedInfo):
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.chat_connectionInterrupted),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: l10n.chat_connectionInterruptedRetry,
              onPressed: () => _controller.retryLastUserMessage(interruptedInfo),
            ),
          ),
        );
      case NavigateToSessionEvent(:final channelId, :final agentId, :final agentName, :final agentAvatar, :final embedded):
        if (embedded && widget.onSwitchChannel != null) {
          widget.onSwitchChannel!(channelId);
        } else {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
                agentId: agentId ?? widget.agentId,
                agentName: agentName ?? _controller.agentName,
                agentAvatar: agentAvatar ?? _controller.agentAvatar,
                channelId: channelId,
                embedded: widget.embedded,
                onClose: widget.onClose,
                onSwitchChannel: widget.onSwitchChannel,
              ),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.05),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                    child: child,
                  ),
                );
              },
              transitionDuration: const Duration(milliseconds: 350),
            ),
          );
        }
      case ShowLoadingOverlayEvent(:final message):
        _showClearingOverlay(message);
      case DismissOverlayEvent():
        Navigator.of(context).pop();
      case RequestScrollToBottomEvent(:final force):
        if (_pendingHighlightMessageId != null) {
          final mid = _pendingHighlightMessageId!;
          _pendingHighlightMessageId = null;
          // Wait a frame so the list has laid out, then scroll to the message.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToMessage(mid);
          });
        } else {
          _scrollToBottom(force: force);
        }
      case ShowHistoryRequestDialogEvent(:final reason, :final result):
        _showHistoryRequestDialog(reason).then((approved) {
          if (!result.isCompleted) result.complete(approved);
        });
      case ShowOsToolConfirmationEvent(:final toolName, :final args, :final risk, :final result):
        _showOsToolConfirmation(toolName, args, risk).then((approved) {
          if (!result.isCompleted) result.complete(approved);
        });
      case CloseScreenEvent():
        if (widget.embedded) {
          widget.onClose?.call();
        } else {
          Navigator.pop(context);
        }
      case AgentInfoUpdatedEvent():
        // Already handled via notifyListeners
        break;
    }
  }

  void _showLocalizedSnackBar(String key, {bool isError = false}) {
    if (!mounted) return;
    // Simple approach: show the key as message. In production, use l10n lookup.
    final text = key.contains(':') ? key.split(':').last : key;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red[400] : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Text / scroll / focus callbacks
  // ---------------------------------------------------------------------------

  void _onTextChanged() {
    // Mention detection is handled inside ChatInputArea
  }

  void _onFocusChanged() {
    if (_textFieldFocusNode.hasFocus && _showEmojiPicker) {
      setState(() { _showEmojiPicker = false; });
    }
  }

  void _onScroll() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || _controller.messages.isEmpty) return;
    // In reverse mode, index 0 is the newest (bottom) message.
    final isAtBottom = positions.any((pos) => pos.index == 0);
    if (_isUserScrolledUp && isAtBottom) {
      setState(() {
        _isUserScrolledUp = false;
        _unreadMessageCount = 0;
      });
      _controller.isUserScrolledUp = false;
      _controller.markMessagesAsReadIfAtBottom();
    } else if (!_isUserScrolledUp && !isAtBottom) {
      setState(() { _isUserScrolledUp = true; });
      _controller.isUserScrolledUp = true;
    }
  }

  void _scrollToBottom({bool force = false, bool isNewMessage = false}) {
    if (_controller.messages.isEmpty) return;
    if (!force && _isUserScrolledUp) {
      if (isNewMessage) {
        setState(() { _unreadMessageCount++; });
      }
      return;
    }
    if (isNewMessage) {
      _controller.markMessagesAsReadIfAtBottom();
    }
    // In reverse mode, index 0 is the newest (bottom) message.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller.messages.isEmpty) return;
      if (force) {
        _itemScrollController.jumpTo(index: 0, alignment: 0.0);
      } else {
        _itemScrollController.scrollTo(
          index: 0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _jumpToBottom() {
    setState(() {
      _isUserScrolledUp = false;
      _unreadMessageCount = 0;
    });
    _controller.isUserScrolledUp = false;
    _controller.markMessagesAsReadIfAtBottom();
    if (_controller.messages.isNotEmpty) {
      // In reverse mode, index 0 is the newest (bottom) message.
      _itemScrollController.jumpTo(index: 0, alignment: 0.0);
    }
  }

  void _scrollToMessage(String messageId) {
    final idx = _controller.messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      // Convert chronological index to reversed index.
      final reversedIdx = _controller.messages.length - 1 - idx;
      _itemScrollController.scrollTo(
        index: reversedIdx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.3,
      );
      setState(() { _controller.highlightedMessageId = messageId; });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() { _controller.highlightedMessageId = null; });
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Emoji
  // ---------------------------------------------------------------------------

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() { _showEmojiPicker = false; });
      _textFieldFocusNode.requestFocus();
    } else {
      _textFieldFocusNode.unfocus();
      setState(() { _showEmojiPicker = true; });
    }
  }

  void _onEmojiSelected(Category? category, Emoji emoji) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursorPos = selection.baseOffset;
    if (cursorPos < 0) {
      _messageController.text = text + emoji.emoji;
      _messageController.selection = TextSelection.collapsed(offset: _messageController.text.length);
    } else {
      final newText = text.substring(0, cursorPos) + emoji.emoji + text.substring(cursorPos);
      _messageController.text = newText;
      _messageController.selection = TextSelection.collapsed(offset: cursorPos + emoji.emoji.length);
    }
  }

  void _onBackspacePressed() {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursorPos = selection.baseOffset;
    if (cursorPos > 0 && text.isNotEmpty) {
      final newText = text.substring(0, cursorPos - 1) + text.substring(cursorPos);
      _messageController.text = newText;
      _messageController.selection = TextSelection.collapsed(offset: cursorPos - 1);
    }
  }

  // ---------------------------------------------------------------------------
  // Clipboard paste (desktop)
  // ---------------------------------------------------------------------------

  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!_textFieldFocusNode.hasFocus) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
      _handleDesktopPaste();
      return false;
    }
    return false;
  }

  Future<void> _handleDesktopPaste() async {
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes == null || imageBytes.isEmpty) return;
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/paste_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(imageBytes);
      await _addPendingAttachment(tempFile, isFromClipboard: true);
    } catch (e) {
      debugPrint('Error pasting image from clipboard: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Attachments
  // ---------------------------------------------------------------------------

  Future<void> _addPendingAttachment(File file, {bool isFromClipboard = false}) async {
    if (_pendingAttachments.length >= _maxPendingAttachments) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_maxAttachments(_maxPendingAttachments))),
        );
      }
      return;
    }
    try {
      final attachment = await PendingAttachment.fromFile(file, isFromClipboard: isFromClipboard);
      if (mounted) {
        setState(() { _pendingAttachments.add(attachment); });
      }
    } catch (e) {
      debugPrint('Error staging attachment: $e');
    }
  }

  void _removePendingAttachment(PendingAttachment att) {
    setState(() {
      _pendingAttachments.remove(att);
      if (att.isFromClipboard) {
        try { att.file.deleteSync(); } catch (_) {}
      }
    });
  }

  void _showAttachmentOptions() {
    debugPrint('[ChatScreen] _showAttachmentOptions called, isDesktop=${LayoutUtils.isDesktopLayout(context)}');
    if (LayoutUtils.isDesktopLayout(context)) {
      _pickAndStageFile();
      return;
    }
    final l10n = AppLocalizations.of(context);
    LayoutUtils.showAdaptivePanel(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: Text(l10n.chat_photoLibrary),
            onTap: () { Navigator.pop(context); _pickAndStageImage(); },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: Text(l10n.chat_camera),
            onTap: () { Navigator.pop(context); _pickAndStageImage(); },
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file),
            title: Text(l10n.chat_file),
            onTap: () { Navigator.pop(context); _pickAndStageFile(); },
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndStageFile() async {
    debugPrint('[ChatScreen] _pickAndStageFile called');
    try {
      final file = await _controller.attachmentService.pickFile();
      debugPrint('[ChatScreen] pickFile returned: $file');
      if (file == null) return;
      await _addPendingAttachment(file);
    } catch (e) {
      debugPrint('[ChatScreen] _pickAndStageFile error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_sendFileError('$e'))),
        );
      }
    }
  }

  Future<void> _pickAndStageImage() async {
    try {
      final image = await _controller.attachmentService.pickImage();
      if (image == null) return;
      await _addPendingAttachment(image);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_sendImageError('$e'))),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Voice recording
  // ---------------------------------------------------------------------------

  Future<void> _sendVoiceMessage() async {
    final result = await _audioRecordingService.stopRecording();
    if (result == null) return;

    if (result.durationMs < 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).chat_voiceTooShort)),
      );
      try { await File(result.filePath).delete(); } catch (_) {}
      return;
    }

    final userId = _controller.getUserId();
    final userName = _controller.getUserName();

    final message = await _controller.attachmentService.saveVoiceMessage(
      filePath: result.filePath,
      durationMs: result.durationMs,
      waveform: result.waveform,
      channelId: _controller.currentChannelId ?? '',
      userId: userId,
      userName: userName,
      agentId: widget.agentId ?? '',
    );

    if (message != null) {
      _controller.addLocalMessage(message);
      _scrollToBottom(force: true);
      _controller.sendAttachmentToAgent(message);
    }
  }

  // ---------------------------------------------------------------------------
  // Send message
  // ---------------------------------------------------------------------------

  void _sendMessage() {
    final content = _messageController.text.trim();
    _controller.sendMessage(
      content: content,
      pendingAttachments: _pendingAttachments,
      clearMessageController: () {
        _messageController.clear();
        setState(() { _pendingAttachments.clear(); });
      },
      replyToId: _controller.replyingToMessage?.id,
    );
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  Future<void> _navigateToAgentDetail() async {
    if (widget.agentId == null) return;
    await _navigateToAgentDetailById(widget.agentId!);
  }

  Future<void> _navigateToAgentDetailById(String agentId) async {
    final remoteAgent = await _controller.localDatabaseService.getRemoteAgentById(agentId);
    if (remoteAgent != null && mounted) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RemoteAgentDetailScreen(agent: remoteAgent),
        ),
      );
      if (result == 'deleted' && mounted) {
        if (_controller.isGroupMode) {
          await _controller.refreshGroupMembers();
        } else {
          if (widget.embedded) {
            widget.onClose?.call();
          } else {
            Navigator.pop(context);
          }
        }
      } else if (mounted) {
        final updated = await _controller.localDatabaseService.getRemoteAgentById(agentId);
        if (updated != null) {
          _controller.updateAgentInfo(updated.name, updated.avatar);
        }
      }
    }
  }

  Future<void> _navigateToGroupDetail() async {
    final channel = _controller.groupChannel;
    if (channel == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupDetailScreen(channel: channel),
      ),
    );
    if (result == true && mounted) {
      // Group was deleted
      if (widget.embedded) {
        widget.onClose?.call();
      } else {
        Navigator.pop(context);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Session list
  // ---------------------------------------------------------------------------

  Future<void> _showSessionList() async {
    if (widget.agentId == null) return;
    try {
      final sessions = await _controller.chatService.getAgentSessions(agentId: widget.agentId!);
      if (!mounted) return;

      final content = SessionListPanel(
        sessions: sessions,
        currentChannelId: _controller.currentChannelId,
        controller: _controller,
        onNewSession: () => _controller.createNewSession(),
        onSwitchSession: (channelId) async {
          await _controller.localDatabaseService.touchChannelUpdatedAt(channelId);
          if (!mounted) return;
          if (widget.embedded) {
            widget.onSwitchChannel?.call(channelId);
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(
                  agentId: widget.agentId,
                  agentName: _controller.agentName,
                  agentAvatar: _controller.agentAvatar,
                  channelId: channelId,
                ),
              ),
            );
          }
        },
        onBatchDelete: (ids) => _controller.batchDeleteSessions(ids, isGroup: false),
      );

      if (LayoutUtils.isDesktopLayout(context)) {
        LayoutUtils.showRightDrawer(context: context, builder: (_) => content);
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(title: Text(AppLocalizations.of(context).chat_sessionList), elevation: 1),
              body: content,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_loadSessionsFailed('$e'))),
        );
      }
    }
  }

  Future<void> _showGroupSessionList() async {
    if (_controller.groupChannel == null) return;
    try {
      final parentGroupId = _controller.groupChannel!.groupFamilyId;
      final sessions = await _controller.chatService.getGroupSessions(parentGroupId: parentGroupId);
      if (!mounted) return;

      final content = GroupSessionListPanel(
        sessions: sessions,
        currentChannelId: _controller.currentChannelId,
        controller: _controller,
        onNewSession: () => _controller.createNewGroupSession(),
        onSwitchSession: (channelId) async {
          await _controller.localDatabaseService.touchChannelUpdatedAt(channelId);
          if (!mounted) return;
          if (widget.embedded) {
            widget.onSwitchChannel?.call(channelId);
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(channelId: channelId),
              ),
            );
          }
        },
        onBatchDelete: (ids) => _controller.batchDeleteSessions(ids, isGroup: true),
      );

      if (LayoutUtils.isDesktopLayout(context)) {
        LayoutUtils.showRightDrawer(context: context, builder: (_) => content);
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(title: Text(AppLocalizations.of(context).chat_sessionList), elevation: 1),
              body: content,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).chat_loadGroupSessionsFailed('$e'))),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  void _showSearchDialog() async {
    List<String>? agentChannelIds;
    if (_controller.isGroupMode && _controller.currentChannelId != null) {
      agentChannelIds = [_controller.currentChannelId!];
    } else if (widget.agentId != null) {
      try {
        final channels = await _controller.localDatabaseService.getChannelsForAgent(widget.agentId!);
        agentChannelIds = channels.map((c) => c.id).toList();
      } catch (_) {}
    }

    if (!mounted) return;

    showSearch(
      context: context,
      delegate: MessageSearchDelegate(
        searchService: _controller.searchService,
        channelIds: agentChannelIds,
        onResultTap: (message, channelId) {
          if (channelId != null && channelId != _controller.currentChannelId) {
            if (widget.embedded) {
              widget.onSwitchChannel?.call(channelId);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    agentId: widget.agentId,
                    agentName: _controller.agentName,
                    agentAvatar: _controller.agentAvatar,
                    channelId: channelId,
                  ),
                ),
              );
            }
          } else {
            _scrollToMessage(message.id);
          }
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Group management (UI-bound dialogs)
  // ---------------------------------------------------------------------------

  Future<void> _editGroupInfo() async {
    if (LayoutUtils.isDesktopLayout(context)) {
      _editGroupInfoDesktop();
    } else {
      _editGroupInfoDialog();
    }
  }

  void _editGroupInfoDesktop() {
    final nameController = TextEditingController(text: _controller.groupChannel?.name ?? '');
    final descController = TextEditingController(text: _controller.groupChannel?.description ?? '');
    final systemPromptController = TextEditingController(text: _controller.groupChannel?.systemPrompt ?? '');

    LayoutUtils.showRightDrawer(
      context: context,
      builder: (ctx) {
        final panelL10n = AppLocalizations.of(ctx);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Expanded(child: Text(panelL10n.chat_editGroupInfo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(controller: nameController, decoration: InputDecoration(labelText: panelL10n.chat_groupName, border: const OutlineInputBorder()), autofocus: true),
                    const SizedBox(height: 16),
                    TextField(controller: descController, decoration: InputDecoration(labelText: panelL10n.chat_groupDescriptionOptional, border: const OutlineInputBorder()), maxLines: 2),
                    const SizedBox(height: 16),
                    TextField(controller: systemPromptController, decoration: InputDecoration(labelText: panelL10n.chat_groupSystemPrompt, hintText: panelL10n.chat_groupSystemPromptHint, border: const OutlineInputBorder()), maxLines: 4),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(panelL10n.common_cancel)),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () async {
                            final newName = nameController.text.trim();
                            if (newName.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(panelL10n.chat_groupNameEmpty)));
                              return;
                            }
                            final old = _controller.groupChannel!;
                            final newSystemPrompt = systemPromptController.text.trim();
                            final updated = Channel(
                              id: old.id, name: newName, type: old.type, members: old.members,
                              createdBy: old.createdBy, createdAt: old.createdAt,
                              description: descController.text.trim().isNotEmpty ? descController.text.trim() : null,
                              systemPrompt: newSystemPrompt.isNotEmpty ? newSystemPrompt : null,
                              avatar: old.avatar, isPrivate: old.isPrivate,
                              maxLoopRounds: old.maxLoopRounds,
                            );
                            await _controller.localDatabaseService.updateChannel(updated);
                            if (mounted) { _controller.updateGroupChannelInfo(updated); }
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: Text(panelL10n.common_save),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editGroupInfoDialog() async {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController(text: _controller.groupChannel?.name ?? '');
    final descController = TextEditingController(text: _controller.groupChannel?.description ?? '');
    final systemPromptController = TextEditingController(text: _controller.groupChannel?.systemPrompt ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogL10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(dialogL10n.chat_editGroupInfo),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: InputDecoration(labelText: dialogL10n.chat_groupName, border: const OutlineInputBorder()), autofocus: true),
                const SizedBox(height: 12),
                TextField(controller: descController, decoration: InputDecoration(labelText: dialogL10n.chat_groupDescriptionOptional, border: const OutlineInputBorder()), maxLines: 2),
                const SizedBox(height: 12),
                TextField(controller: systemPromptController, decoration: InputDecoration(labelText: dialogL10n.chat_groupSystemPrompt, hintText: dialogL10n.chat_groupSystemPromptHint, border: const OutlineInputBorder()), maxLines: 3),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(dialogL10n.common_cancel)),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(dialogL10n.common_save)),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    final newName = nameController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.chat_groupNameEmpty)));
      return;
    }
    final old = _controller.groupChannel!;
    final newSystemPrompt = systemPromptController.text.trim();
    final updated = Channel(
      id: old.id, name: newName, type: old.type, members: old.members,
      createdBy: old.createdBy, createdAt: old.createdAt,
      description: descController.text.trim().isNotEmpty ? descController.text.trim() : null,
      systemPrompt: newSystemPrompt.isNotEmpty ? newSystemPrompt : null,
      avatar: old.avatar, isPrivate: old.isPrivate,
      maxLoopRounds: old.maxLoopRounds,
    );
    await _controller.localDatabaseService.updateChannel(updated);
    if (mounted) { _controller.updateGroupChannelInfo(updated); }
  }

  void _showGroupMembersPanel() {
    LayoutUtils.showAdaptivePanel(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => _GroupMembersSheet(
        groupAgents: _controller.groupAgents,
        channelId: _controller.currentChannelId!,
        adminAgentId: _controller.groupAdminAgentId,
        channelMembers: _controller.groupChannel?.members ?? [],
        onAddMember: () => _addGroupMember(),
        onRemoveMember: (agent) => _removeGroupMember(agent),
        onSaveGroupBio: (agent, bio) => _controller.saveMemberGroupBio(agent, bio),
        onChangeAdmin: (agent) async {
          if (agent.id == _controller.groupAdminAgentId) return;
          final parentGroupId = _controller.groupChannel?.groupFamilyId ?? _controller.currentChannelId!;
          final sessions = await _controller.localDatabaseService.getGroupSessions(parentGroupId);
          for (final session in sessions) {
            if (_controller.groupAdminAgentId != null) {
              await _controller.localDatabaseService.updateChannelMemberRole(session.id, _controller.groupAdminAgentId!, 'member');
            }
            await _controller.localDatabaseService.updateChannelMemberRole(session.id, agent.id, 'admin');
          }
          await _controller.refreshGroupMembers();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context).chat_adminChanged(agent.name))),
            );
          }
        },
        onMentionAgent: (agent) {
          Navigator.pop(sheetContext);
          _chatInputKey.currentState?.insertMentionForAgent(agent);
        },
      ),
    );
  }

  Future<void> _addGroupMember() async {
    final l10n = AppLocalizations.of(context);
    final allAgents = await _controller.localDatabaseService.getAllRemoteAgents();
    final currentIds = _controller.groupAgents.map((a) => a.id).toSet();
    final available = allAgents.where((a) => !currentIds.contains(a.id)).toList();

    if (!mounted) return;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.chat_noMoreAgents)));
      return;
    }

    final selected = await LayoutUtils.showAdaptivePanel<RemoteAgent>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(l10n.chat_addMember, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            const Divider(height: 1),
            ...available.map((agent) => ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: Colors.blue[100], borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Text(agent.name.isNotEmpty ? agent.name[0].toUpperCase() : '?', style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold)),
              ),
              title: Text(agent.name),
              subtitle: agent.bio != null && agent.bio!.isNotEmpty ? Text(agent.bio!, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
              onTap: () => Navigator.pop(ctx, agent),
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;
    await _controller.addGroupMember(selected);
    if (mounted) _showGroupMembersPanel();
  }

  Future<void> _removeGroupMember(RemoteAgent agent) async {
    final l10n = AppLocalizations.of(context);
    if (_controller.groupAgents.length <= 1) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.chat_cannotRemoveLast)));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogL10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(dialogL10n.chat_removeMember),
          content: Text(dialogL10n.chat_removeMemberContent(agent.name)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(dialogL10n.common_cancel)),
            TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: Text(dialogL10n.chat_removeButton)),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await _controller.removeGroupMember(agent);
    if (mounted) _showGroupMembersPanel();
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------

  Future<bool> _showHistoryRequestDialog(String reason) async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.chat_historyRequestTitle),
        content: Text(reason),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.chat_historyIgnore)),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.chat_historyApprove)),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _showOsToolConfirmation(String toolName, Map<String, dynamic> args, dynamic risk) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('OS Tool: $toolName'),
        content: Text('Allow execution?\nArgs: $args'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Deny')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Allow')),
        ],
      ),
    );
    return result ?? false;
  }

  void _showClearingOverlay(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = _controller;

    return Scaffold(
      appBar: AppBar(
        elevation: 1,
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.showBackButton && widget.onClose != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onClose,
              )
            : null,
        title: c.isGroupMode
            ? ChatGroupAppBarTitle(
                groupChannel: c.groupChannel,
                groupAgents: c.groupAgents,
                isProcessing: c.isProcessing,
                respondingAgentNames: c.respondingAgentNames,
                mentionOnlyMode: c.mentionOnlyMode,
                currentChannelId: c.currentChannelId,
                onAvatarTap: _navigateToGroupDetail,
                onStopGenerating: c.isProcessing
                    ? () => c.stopGroupStreaming()
                    : null,
              )
            : ChatDMAppBarTitle(
                agentName: c.agentName,
                agentAvatar: c.agentAvatar,
                isProcessing: c.isProcessing,
                isCheckingHealth: c.isCheckingHealth,
                isAgentOnline: c.isAgentOnline,
                currentChannelId: c.currentChannelId,
                onAvatarTap: _navigateToAgentDetail,
                onStopGenerating: c.isProcessing
                    ? () => c.stopStreaming()
                    : null,
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, size: 20),
            tooltip: AppLocalizations.of(context).chat_sessionList,
            onPressed: c.isGroupMode ? _showGroupSessionList : _showSessionList,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              if (c.isGroupMode) {
                ChatMenuHelper.showGroupMenu(
                  context,
                  onEditGroup: _editGroupInfo,
                  onShowMembers: _showGroupMembersPanel,
                  onAddMember: _addGroupMember,
                  onSearch: _showSearchDialog,
                );
              } else {
                ChatMenuHelper.showAgentMenu(
                  context,
                  onReset: () {
                    _messageController.text = '/reset';
                    _sendMessage();
                  },
                  onViewDetails: _navigateToAgentDetail,
                  onSearch: _showSearchDialog,
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Message list
          Expanded(
            child: Stack(
              children: [
                c.messages.isEmpty && !c.isLoading
                    ? _buildEmptyState()
                    : ChatMessageList(
                        messages: c.messages,
                        messageIdMap: c.messageIdMap,
                        streamingMessageId: c.streamingMessageId,
                        groupStreamingMessageIds: c.groupStreamingMessageIds,
                        isGroupMode: c.isGroupMode,
                        itemScrollController: _itemScrollController,
                        itemPositionsListener: _itemPositionsListener,
                        onStopStreaming: () => c.stopStreaming(),
                        onActionSelected: (msg, cid, aid, alabel, {confirmationContext}) {
                          c.handleActionSelected(msg, cid, aid, alabel, confirmationContext: confirmationContext);
                        },
                        onSingleSelectSubmitted: (msg, sid, oid, olabel) {
                          c.handleSingleSelectSubmitted(msg, sid, oid, olabel);
                        },
                        onMultiSelectSubmitted: (msg, sid, oids, summary) {
                          c.handleMultiSelectSubmitted(msg, sid, oids, summary);
                        },
                        onFileUploadSubmitted: (msg, uid, files, summary) {
                          c.handleFileUploadSubmitted(msg, uid, files, summary);
                        },
                        onFormSubmitted: (msg, fid, values, summary) {
                          c.handleFormSubmitted(msg, fid, values, summary);
                        },
                        onReply: (msg) => c.startReply(msg),
                        onRollback: (msg) => c.rollbackMessage(msg),
                        onRollbackReEdit: (msg, {bool reEdit = false}) => c.rollbackMessage(msg, reEdit: reEdit),
                        onDelete: (msg) => c.deleteMessage(msg),
                        onAgentAvatarTap: _navigateToAgentDetailById,
                        onScrollToMessage: _scrollToMessage,
                        highlightedMessageId: c.highlightedMessageId,
                      ),
                if (_isUserScrolledUp)
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: _buildScrollToBottomButton(),
                  ),
              ],
            ),
          ),

          // Voice record overlay
          if (_isRecording)
            VoiceRecordOverlay(
              elapsed: _recordingElapsed,
              amplitude: _recordingAmplitude,
              isCancelZone: _isCancelZone,
            ),

          // Reply preview bar
          if (c.replyingToMessage != null)
            ChatReplyPreview(
              replyingTo: c.replyingToMessage!,
              onCancel: () => c.cancelReply(),
            ),

          // Queue indicator
          _buildQueueIndicator(),

          // Mention picker overlay (group mode)
          Offstage(
            offstage: !(_chatInputKey.currentState?.showMentionPicker ?? false),
            child: _chatInputKey.currentState?.buildMentionPicker() ?? const SizedBox.shrink(),
          ),

          // Input area
          ChatInputArea(
            key: _chatInputKey,
            messageController: _messageController,
            textFieldFocusNode: _textFieldFocusNode,
            isLoading: c.isLoading,
            isGroupMode: c.isGroupMode,
            pendingAttachments: _pendingAttachments,
            groupAgents: c.groupAgents,
            audioRecordingService: _audioRecordingService,
            isRecording: _isRecording,
            isCancelZone: _isCancelZone,
            onSend: _sendMessage,
            onToggleEmojiPicker: _toggleEmojiPicker,
            onShowAttachmentOptions: _showAttachmentOptions,
            onSendVoice: _sendVoiceMessage,
            showEmojiPicker: _showEmojiPicker,
            onRemoveAttachment: _removePendingAttachment,
            onMentionPickerChanged: () {
              if (mounted) setState(() {});
            },
          ),

          // Emoji picker panel
          if (_showEmojiPicker)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                onEmojiSelected: _onEmojiSelected,
                onBackspacePressed: _onBackspacePressed,
                config: Config(
                  height: 250,
                  emojiViewConfig: EmojiViewConfig(
                    emojiSizeMax: 28 * (Platform.isIOS ? 1.30 : 1.0),
                    backgroundColor: Colors.white,
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    indicatorColor: Theme.of(context).primaryColor,
                    iconColorSelected: Theme.of(context).primaryColor,
                    backgroundColor: Colors.white,
                  ),
                  searchViewConfig: const SearchViewConfig(),
                  bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: _controller.agentAvatar != null && _controller.agentAvatar!.length > 2
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _controller.agentAvatar!.startsWith('/') && !_controller.agentAvatar!.startsWith('http')
                        ? Image.file(
                            File(_controller.agentAvatar!),
                            width: 80, height: 80, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Text(
                              _controller.agentName?.isNotEmpty == true ? _controller.agentName![0] : 'A',
                              style: const TextStyle(fontSize: 56),
                            ),
                          )
                        : Image.network(
                            _controller.agentAvatar!,
                            width: 80, height: 80, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Text(
                              _controller.agentName?.isNotEmpty == true ? _controller.agentName![0] : 'A',
                              style: const TextStyle(fontSize: 56),
                            ),
                          ),
                  )
                : Text(
                    _controller.agentAvatar ??
                    (_controller.agentName?.isNotEmpty == true ? _controller.agentName![0] : 'A'),
                    style: const TextStyle(fontSize: 56),
                  ),
          ),
          const SizedBox(height: 16),
          Text(_controller.agentName ?? 'AI Agent', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Send a message to start chatting', style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildScrollToBottomButton() {
    return GestureDetector(
      onTap: _jumpToBottom,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_unreadMessageCount > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  _unreadMessageCount > 99 ? '99+' : '$_unreadMessageCount',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.grey[700]),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueIndicator() {
    if (_controller.messageQueue.isEmpty) return const SizedBox.shrink();

    final count = _controller.messageQueue.length;
    final preview = _controller.messageQueue.first.length > 40
        ? '${_controller.messageQueue.first.substring(0, 40)}...'
        : _controller.messageQueue.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border(top: BorderSide(color: Colors.blue[100]!, width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.queue, size: 16, color: Colors.blue[400]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count == 1 ? '1 message queued' : '$count messages queued',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.blue[700]),
                ),
                Text(preview, style: TextStyle(fontSize: 11, color: Colors.blue[400]), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (count > 1)
            GestureDetector(
              onTap: () { setState(() { _controller.messageQueue.clear(); }); },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text('Clear', style: TextStyle(fontSize: 12, color: Colors.red[400], fontWeight: FontWeight.w500)),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _GroupMembersSheet — kept in this file as it's tightly coupled with UI.
// ---------------------------------------------------------------------------

class _GroupMembersSheet extends StatefulWidget {
  final List<RemoteAgent> groupAgents;
  final String channelId;
  final String? adminAgentId;
  final List<ChannelMember> channelMembers;
  final Future<void> Function() onAddMember;
  final Future<void> Function(RemoteAgent agent) onRemoveMember;
  final Future<List<ChannelMember>> Function(RemoteAgent agent, String? newGroupBio) onSaveGroupBio;
  final Future<void> Function(RemoteAgent agent) onChangeAdmin;
  final void Function(RemoteAgent agent) onMentionAgent;

  const _GroupMembersSheet({
    required this.groupAgents,
    required this.channelId,
    this.adminAgentId,
    this.channelMembers = const [],
    required this.onAddMember,
    required this.onRemoveMember,
    required this.onSaveGroupBio,
    required this.onChangeAdmin,
    required this.onMentionAgent,
  });

  @override
  State<_GroupMembersSheet> createState() => _GroupMembersSheetState();
}

class _GroupMembersSheetState extends State<_GroupMembersSheet> {
  String? _editingAgentId;
  late TextEditingController _editController;
  late List<ChannelMember> _channelMembers;
  bool _editingIsAdmin = false;
  late String? _currentAdminAgentId;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _channelMembers = List.of(widget.channelMembers);
    _currentAdminAgentId = widget.adminAgentId;
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _startEditing(RemoteAgent agent) {
    final member = _channelMembers.where((m) => m.id == agent.id).firstOrNull;
    _editController.text = member?.groupBio ?? '';
    setState(() {
      _editingAgentId = agent.id;
      _editingIsAdmin = _currentAdminAgentId == agent.id;
    });
  }

  void _cancelEditing() {
    setState(() { _editingAgentId = null; });
  }

  Future<void> _saveEditing(RemoteAgent agent) async {
    final text = _editController.text.trim();
    final newGroupBio = text.isEmpty ? null : text;
    final updatedMembers = await widget.onSaveGroupBio(agent, newGroupBio);
    final wasAdmin = _currentAdminAgentId == agent.id;
    if (_editingIsAdmin && !wasAdmin) {
      await widget.onChangeAdmin(agent);
      if (mounted) setState(() { _currentAdminAgentId = agent.id; });
    }
    if (mounted) setState(() { _channelMembers = updatedMembers; _editingAgentId = null; });
  }

  Future<void> _resetGroupBio(RemoteAgent agent) async {
    final updatedMembers = await widget.onSaveGroupBio(agent, null);
    if (mounted) setState(() { _channelMembers = updatedMembers; _editingAgentId = null; });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(child: Text('Group Members (${widget.groupAgents.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                TextButton.icon(
                  onPressed: () { Navigator.pop(context); widget.onAddMember(); },
                  icon: const Icon(Icons.person_add, size: 20),
                  label: Text(l10n.chat_add),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...widget.groupAgents.map((agent) {
            final member = _channelMembers.where((m) => m.id == agent.id).firstOrNull;
            final groupBio = member?.groupBio;
            final displayBio = groupBio ?? agent.bio;
            final hasGroupBio = groupBio != null && groupBio.isNotEmpty;
            final isEditing = _editingAgentId == agent.id;

            if (isEditing) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(color: Colors.blue[100], borderRadius: BorderRadius.circular(8)),
                          alignment: Alignment.center,
                          child: Text(agent.name.isNotEmpty ? agent.name[0].toUpperCase() : '?', style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(l10n.chat_groupRoleTitle(agent.name), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                      ],
                    ),
                    if (agent.bio != null && agent.bio!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Default: ${agent.bio}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      ),
                    const SizedBox(height: 8),
                    TextField(controller: _editController, maxLines: 3, autofocus: true, decoration: InputDecoration(labelText: l10n.chat_groupCapabilityLabel, hintText: l10n.chat_groupCapabilityHint, border: const OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () { setState(() { _editingIsAdmin = !_editingIsAdmin; }); },
                      child: Row(
                        children: [
                          SizedBox(height: 32, width: 40, child: FittedBox(fit: BoxFit.scaleDown, child: Switch(value: _editingIsAdmin, onChanged: (v) { setState(() { _editingIsAdmin = v; }); }, activeTrackColor: Colors.orange[200], activeThumbColor: Colors.orange[700]))),
                          const SizedBox(width: 4),
                          Icon(Icons.admin_panel_settings, size: 18, color: _editingIsAdmin ? Colors.orange[700] : Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(l10n.createGroup_setAsAdmin, style: TextStyle(fontSize: 13, color: _editingIsAdmin ? Colors.orange[700] : Colors.grey[600], fontWeight: _editingIsAdmin ? FontWeight.w600 : FontWeight.normal)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: _cancelEditing, child: Text(l10n.common_cancel)),
                        if (hasGroupBio) TextButton(onPressed: () => _resetGroupBio(agent), child: Text(l10n.chat_resetButton, style: TextStyle(color: Colors.orange[700]))),
                        TextButton(onPressed: () => _saveEditing(agent), child: Text(l10n.common_save)),
                      ],
                    ),
                    const Divider(height: 1),
                  ],
                ),
              );
            }

            return ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: Colors.blue[100], borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Text(agent.name.isNotEmpty ? agent.name[0].toUpperCase() : '?', style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold)),
              ),
              title: Row(
                children: [
                  Flexible(child: Text(agent.name, overflow: TextOverflow.ellipsis)),
                  if (_currentAdminAgentId == agent.id) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(12)),
                      child: Text('Admin', style: TextStyle(fontSize: 11, color: Colors.orange[800], fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
              subtitle: displayBio != null && displayBio.isNotEmpty
                  ? Text(displayBio, maxLines: 1, overflow: TextOverflow.ellipsis, style: hasGroupBio ? TextStyle(color: Colors.blue[600], fontStyle: FontStyle.italic) : null)
                  : Text('Set group role...', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: Icon(Icons.edit_note, size: 20, color: Colors.blue[300]), tooltip: 'Edit group role', onPressed: () => _startEditing(agent)),
                  IconButton(icon: Icon(Icons.remove_circle_outline, color: Colors.red[300]), onPressed: () { Navigator.pop(context); widget.onRemoveMember(agent); }),
                ],
              ),
              onTap: () => widget.onMentionAgent(agent),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
