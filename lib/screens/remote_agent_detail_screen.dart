import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../models/remote_agent.dart';
import '../models/llm_provider_config.dart';
import '../services/remote_agent_service.dart';
import '../services/local_database_service.dart';
import '../services/local_file_storage_service.dart';
import '../services/token_service.dart';
import '../services/os_tool_registry.dart';
import '../models/model_routing_config.dart';
import '../services/skill_registry.dart';
import 'os_tool_select_screen.dart';
import 'skill_select_screen.dart';
import 'model_routing_config_screen.dart';
import 'chat_screen.dart';
import '../utils/layout_utils.dart';

/// 远端 Agent 详情页面（从聊天页进入）
class RemoteAgentDetailScreen extends StatefulWidget {
  final RemoteAgent agent;

  const RemoteAgentDetailScreen({
    super.key,
    required this.agent,
  });

  @override
  State<RemoteAgentDetailScreen> createState() =>
      _RemoteAgentDetailScreenState();
}

class _RemoteAgentDetailScreenState extends State<RemoteAgentDetailScreen> {
  late RemoteAgent _agent;
  bool _isDeleting = false;
  bool _isEditing = false;
  bool _isSaving = false;

  // 编辑用的控制器
  late TextEditingController _nameController;
  late TextEditingController _bioController;
  late TextEditingController _endpointController;
  late TextEditingController _systemPromptController;
  late TextEditingController _apiBaseController;
  late TextEditingController _modelController;
  late TextEditingController _apiKeyController;
  String _editingAvatar = '';

  // LLM 编辑状态
  int _selectedProviderIndex = -1;
  bool _obscureApiKey = true;
  ProtocolType _editingProtocol = ProtocolType.acp;
  ConnectionType _editingConnectionType = ConnectionType.websocket;
  Map<String, List<String>> _customModels = {};

  // OS 工具配置
  Set<String> _enabledOsTools = {};

  // Skills 配置
  Set<String> _enabledSkills = {};

  // Model routing 配置
  Map<ModalityType, ModelRouteConfig> _modelRoutes = {};

  // 本地上传的头像文件路径（相对路径）
  String? _localAvatarPath;

  final ImagePicker _imagePicker = ImagePicker();
  final LocalFileStorageService _fileStorage = LocalFileStorageService();

  @override
  void initState() {
    super.initState();
    _agent = widget.agent;
    _initEditingControllers();
    _loadCustomModels();
  }

  void _initEditingControllers() {
    _nameController = TextEditingController(text: _agent.name);
    _bioController = TextEditingController(text: _agent.bio ?? '');
    _endpointController = TextEditingController(text: _agent.endpoint);
    _systemPromptController = TextEditingController(
      text: _agent.metadata['system_prompt'] as String? ?? '',
    );
    _apiBaseController = TextEditingController(
      text: _agent.metadata['llm_api_base'] as String? ?? '',
    );
    _modelController = TextEditingController(
      text: _agent.metadata['llm_model'] as String? ?? '',
    );
    _apiKeyController = TextEditingController(
      text: _agent.metadata['llm_api_key'] as String? ?? '',
    );
    _apiKeyController.addListener(_repairApiKeyIfGarbled);
    _editingAvatar = _agent.avatar;
    _localAvatarPath = null;
    _editingProtocol = _agent.protocol;
    _editingConnectionType = _agent.connectionType;
    _obscureApiKey = true;

    // Load OS tools from metadata
    _enabledOsTools = _agent.enabledOsTools;

    // Load skills from metadata
    _enabledSkills = _agent.enabledSkills;

    // Load model routing from metadata
    _modelRoutes = Map<ModalityType, ModelRouteConfig>.from(_agent.modelRouting.routes);

    // Match provider index from metadata
    _selectedProviderIndex = -1;
    final savedProvider = _agent.metadata['llm_provider'] as String?;
    if (savedProvider != null) {
      for (int i = 0; i < llmProviders.length; i++) {
        if (llmProviders[i].providerType == savedProvider) {
          // Also check api_base to distinguish providers with same providerType
          final savedBase = _agent.metadata['llm_api_base'] as String?;
          if (savedBase == null || savedBase == llmProviders[i].defaultApiBase) {
            _selectedProviderIndex = i;
            break;
          }
          // If no exact match yet, keep as fallback
          if (_selectedProviderIndex == -1) {
            _selectedProviderIndex = i;
          }
        }
      }
    }
  }

  void _repairApiKeyIfGarbled() {
    final text = _apiKeyController.text;
    final repaired = repairUtf16Garbled(text);
    if (repaired != text) {
      _apiKeyController.value = TextEditingValue(
        text: repaired,
        selection: TextSelection.collapsed(offset: repaired.length),
      );
    }
  }

  Future<void> _loadCustomModels() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, List<String>>{};
    for (final provider in llmProviders) {
      final key = 'custom_models_${provider.name}';
      final list = prefs.getStringList(key);
      if (list != null && list.isNotEmpty) {
        map[provider.name] = list;
      }
    }
    if (mounted) {
      setState(() {
        _customModels = map;
      });
    }
  }

  Future<void> _saveCustomModel(String providerName, String model) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'custom_models_$providerName';
    final list = List<String>.from(_customModels[providerName] ?? []);
    if (!list.contains(model)) {
      list.add(model);
      await prefs.setStringList(key, list);
      _customModels[providerName] = list;
    }
  }

  List<String> _getModelsForProvider(LLMProviderConfig provider) {
    final builtIn = provider.models;
    final custom = _customModels[provider.name] ?? [];
    final merged = [...builtIn];
    for (final m in custom) {
      if (!merged.contains(m)) {
        merged.add(m);
      }
    }
    return merged;
  }

  @override
  void dispose() {
    _apiKeyController.removeListener(_repairApiKeyIfGarbled);
    _nameController.dispose();
    _bioController.dispose();
    _endpointController.dispose();
    _systemPromptController.dispose();
    _apiBaseController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _enterEditMode() {
    setState(() {
      _isEditing = true;
      _initEditingControllers();
    });
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      _initEditingControllers();
    });
  }

  Future<void> _saveEdit() async {
    final l10n = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.agentDetail_nameRequired),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 如果有本地上传的图片，先解析出完整路径存储
      String avatar = _editingAvatar;
      if (_localAvatarPath != null) {
        final fullPath = await _fileStorage.getFullPath(_localAvatarPath!);
        avatar = fullPath;
      }

      // Build updated metadata
      final Map<String, dynamic> metadata = Map<String, dynamic>.from(_agent.metadata);

      // System prompt
      final systemPrompt = _systemPromptController.text.trim();
      if (systemPrompt.isNotEmpty) {
        metadata['system_prompt'] = systemPrompt;
      } else {
        metadata.remove('system_prompt');
      }

      // LLM config
      if (_selectedProviderIndex >= 0) {
        final provider = llmProviders[_selectedProviderIndex];
        metadata['llm_provider'] = provider.providerType;
        metadata['llm_model'] = _modelController.text.trim();
        metadata['llm_api_base'] = _apiBaseController.text.trim();
        if (_apiKeyController.text.trim().isNotEmpty) {
          metadata['llm_api_key'] =
              repairUtf16Garbled(_apiKeyController.text.trim());
        } else {
          metadata.remove('llm_api_key');
        }

        // Save custom model name
        final inputModel = _modelController.text.trim();
        if (inputModel.isNotEmpty && !provider.models.contains(inputModel)) {
          await _saveCustomModel(provider.name, inputModel);
        }

        // Save OS tools
        if (_enabledOsTools.isNotEmpty) {
          metadata['enabled_os_tools'] = _enabledOsTools.toList();
        } else {
          metadata.remove('enabled_os_tools');
        }

        // Save skills
        if (_enabledSkills.isNotEmpty) {
          metadata['enabled_skills'] = _enabledSkills.toList();
        } else {
          metadata.remove('enabled_skills');
        }

        // Save model routing
        if (_modelRoutes.isNotEmpty) {
          final routingConfig = ModelRoutingConfig(routes: _modelRoutes);
          if (!routingConfig.isEmpty) {
            metadata['model_routing'] = routingConfig.toJson();
          } else {
            metadata.remove('model_routing');
          }
        } else {
          metadata.remove('model_routing');
        }
      } else {
        // No provider selected — clear LLM config
        metadata.remove('llm_provider');
        metadata.remove('llm_model');
        metadata.remove('llm_api_base');
        metadata.remove('llm_api_key');
        metadata.remove('enabled_os_tools');
      }

      final updatedAgent = _agent.copyWith(
        name: name,
        bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
        avatar: avatar,
        endpoint: _endpointController.text.trim(),
        protocol: _editingProtocol,
        connectionType: _editingConnectionType,
        metadata: metadata,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      final dbService = LocalDatabaseService();
      final tokenService = TokenService(dbService);
      final agentService = RemoteAgentService(dbService, tokenService);
      await agentService.updateAgent(updatedAgent);

      setState(() {
        _agent = updatedAgent;
        _isEditing = false;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.agentDetail_saveSuccess)),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.agentDetail_saveFailed('$e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getStatusColor(AgentStatus status) {
    switch (status) {
      case AgentStatus.online:
        return Colors.green;
      case AgentStatus.offline:
        return Colors.orange;
      case AgentStatus.error:
        return Colors.red;
    }
  }

  Future<void> _deleteAgent() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.agentDetail_confirmDelete),
        content: Text(
          l10n.agentDetail_deleteContent(_agent.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.agentDetail_deleteAgent),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      final dbService = LocalDatabaseService();
      final tokenService = TokenService(dbService);
      final agentService = RemoteAgentService(dbService, tokenService);
      await agentService.deleteAgent(_agent.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.agentDetail_deleted(_agent.name))),
        );
        Navigator.pop(context, 'deleted');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.agentDetail_deleteFailed('$e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startConversation() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          agentId: _agent.id,
          agentName: _agent.name,
          agentAvatar: _agent.avatar,
        ),
      ),
    );
  }

  // ==================== 头像选择 ====================

  void _showAvatarPicker() {
    final l10n = AppLocalizations.of(context);
    LayoutUtils.showAdaptivePanel(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.emoji_emotions_outlined),
            title: Text(l10n.agentDetail_selectBuiltinAvatar),
            onTap: () {
              Navigator.pop(ctx);
              _showBuiltinAvatarPicker();
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l10n.agentDetail_selectFromGallery),
            onTap: () {
              Navigator.pop(ctx);
              _pickImageFromGallery();
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: Text(l10n.agentDetail_takePhoto),
            onTap: () {
              Navigator.pop(ctx);
              _pickImageFromCamera();
            },
          ),
        ],
      ),
    );
  }

  void _showBuiltinAvatarPicker() {
    final l10n = AppLocalizations.of(context);
    final avatars = [
      '🤖', '🦾', '🧠', '💡', '🌟', '⚡', '🔮', '🎯',
      '🚀', '🛸', '🌈', '🔥', '💎', '🎨', '🎭', '🎪',
      '🐱', '🐶', '🦊', '🐼', '🦉', '🦋', '🐝', '🐙',
      '👤', '👩‍💻', '🧑‍🔬', '🧑‍🚀', '🧙', '🥷', '🦸', '🤹',
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.addAgent_selectAvatar),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: avatars.length,
            itemBuilder: (context, index) {
              final avatar = avatars[index];
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _editingAvatar = avatar;
                    _localAvatarPath = null;
                  });
                  Navigator.pop(ctx);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: _editingAvatar == avatar && _localAvatarPath == null
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      avatar,
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.common_cancel),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImageFromGallery() async {
    final l10n = AppLocalizations.of(context);
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image == null) return;
      await _savePickedImage(File(image.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.agentDetail_galleryFailed('$e')), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickImageFromCamera() async {
    final l10n = AppLocalizations.of(context);
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image == null) return;
      await _savePickedImage(File(image.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.agentDetail_cameraFailed('$e')), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _savePickedImage(File imageFile) async {
    final l10n = AppLocalizations.of(context);
    try {
      final relativePath = await _fileStorage.saveImage(
        imageFile,
        type: ResourceType.avatars,
      );
      final fullPath = await _fileStorage.getFullPath(relativePath);
      setState(() {
        _localAvatarPath = relativePath;
        _editingAvatar = fullPath;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.agentDetail_saveImageFailed('$e')), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==================== 头像展示 ====================

  /// 判断 avatar 是否为本地文件路径
  bool _isLocalFilePath(String avatar) {
    return avatar.startsWith('/') && !avatar.startsWith('http');
  }

  /// 判断 avatar 是否为网络 URL
  bool _isNetworkUrl(String avatar) {
    return avatar.startsWith('http://') || avatar.startsWith('https://');
  }

  Widget _buildAvatarWidget(String avatar, double size) {
    final borderRadius = BorderRadius.circular(size * 0.25);
    if (_isLocalFilePath(avatar)) {
      final file = File(avatar);
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Icon(Icons.smart_toy, size: size * 0.6);
          },
        ),
      );
    } else if (_isNetworkUrl(avatar)) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.network(
          avatar,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Icon(Icons.smart_toy, size: size * 0.6);
          },
        ),
      );
    } else {
      // Emoji
      return Text(
        avatar,
        style: TextStyle(fontSize: size * 0.4),
      );
    }
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l10n.agentDetail_editTitle : l10n.agentDetail_title),
        centerTitle: true,
        actions: [
          if (!_isEditing && !_isDeleting)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10n.agentDetail_editTooltip,
              onPressed: _enterEditMode,
            ),
        ],
      ),
      body: _isDeleting
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _isEditing ? _buildEditBody() : _buildDetailBody(),
            ),
    );
  }

  // ==================== 详情模式 ====================

  Widget _buildDetailBody() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 24),
        _buildInfoCard(),
        if (_agent.metadata['llm_provider'] != null) ...[
          const SizedBox(height: 16),
          _buildOsToolsCard(),
          const SizedBox(height: 16),
          _buildSkillsCard(),
          if (_agent.hasModelRouting) ...[
            const SizedBox(height: 16),
            _buildModelRoutingCard(),
          ],
        ],
        // Token 卡片（仅远端 agent 显示）
        if (_agent.metadata['llm_provider'] == null) ...[
          const SizedBox(height: 16),
          _buildTokenCard(),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _startConversation,
            icon: const Icon(Icons.chat),
            label: Text(l10n.agentDetail_startConversation),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _deleteAgent,
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: Text(l10n.agentDetail_deleteAgent),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(25),
          ),
          alignment: Alignment.center,
          child: _buildAvatarWidget(_agent.avatar, 100),
        ),
        const SizedBox(height: 16),
        Text(
          _agent.name,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
        ),
        if (_agent.bio != null && _agent.bio!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _agent.bio!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _getStatusColor(_agent.status).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_agent.statusIcon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                _agent.statusText,
                style: TextStyle(
                  fontSize: 14,
                  color: _getStatusColor(_agent.status),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    final l10n = AppLocalizations.of(context);
    final systemPrompt = _agent.metadata['system_prompt'] as String?;
    final llmProvider = _agent.metadata['llm_provider'] as String?;
    final llmModel = _agent.metadata['llm_model'] as String?;
    final llmApiBase = _agent.metadata['llm_api_base'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.agentDetail_connectionInfo,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Divider(height: 24),
            _buildInfoRow(l10n.agentDetail_protocol, _agent.protocolName),
            const SizedBox(height: 8),
            _buildInfoRow(l10n.agentDetail_connectionType, _agent.connectionTypeName),
            if (_agent.endpoint.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(l10n.agentDetail_endpoint, _agent.endpoint),
            ],
            const SizedBox(height: 8),
            _buildInfoRow('Agent ID', _agent.id),
            if (_agent.capabilities.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(l10n.agentDetail_capabilities, _agent.capabilities.join(', ')),
            ],
            if (systemPrompt != null && systemPrompt.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(l10n.agentDetail_systemPrompt, systemPrompt),
            ],
            if (llmProvider != null) ...[
              const Divider(height: 24),
              Text(
                l10n.agentDetail_llmConfig,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              _buildInfoRow(l10n.agentDetail_provider, llmProvider),
              if (llmModel != null && llmModel.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildInfoRow(l10n.agentDetail_model, llmModel),
              ],
              if (llmApiBase != null && llmApiBase.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildInfoRow('API Base', llmApiBase),
              ],
            ],
            if (_agent.lastHeartbeat != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(l10n.agentDetail_lastActive, _formatTimestamp(_agent.lastHeartbeat!)),
            ],
            const SizedBox(height: 8),
            _buildInfoRow(l10n.agentDetail_createdAt, _formatTimestamp(_agent.createdAt)),
          ],
        ),
      ),
    );
  }

  Widget _buildOsToolsCard() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final registry = OsToolRegistry.instance;
    final enabledTools = _agent.enabledOsTools;

    // Group all platform tools by category.
    final grouped = registry.toolsByCategory;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build_circle, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.osTool_configTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: enabledTools.isNotEmpty
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${enabledTools.length}/${registry.tools.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: enabledTools.isNotEmpty
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (enabledTools.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.agentDetail_noOsToolsEnabled,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ...grouped.entries.map((entry) {
                final category = entry.key;
                final tools = entry.value;
                // Only show categories that have at least one enabled tool
                final enabledInCategory = tools.where((t) => enabledTools.contains(t.name)).toList();
                if (enabledInCategory.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Text(
                        _osCategoryLabel(category, l10n),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    ...enabledInCategory.map((tool) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            _osToolIcon(tool.name),
                            size: 16,
                            color: colorScheme.onSurface,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tool.name,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  tool.description.split('.').first.trim(),
                                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _osRiskBadge(tool.defaultRiskLevel, colorScheme),
                        ],
                      ),
                    )),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillsCard() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final skillRegistry = SkillRegistry.instance;
    final enabledSkills = _agent.enabledSkills;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_stories, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.skill_configTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: enabledSkills.isNotEmpty
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${enabledSkills.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: enabledSkills.isNotEmpty
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (enabledSkills.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.agentDetail_noSkillsEnabled,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ...enabledSkills.map((skillName) {
                final def = skillRegistry.getDefinition(skillName);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.article,
                        size: 16,
                        color: colorScheme.onSurface,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              def?.displayName ?? skillName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            if (def != null)
                              Text(
                                def.description,
                                style: TextStyle(fontSize: 11, color: colorScheme.outline),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildModelRoutingCard() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final routing = _agent.modelRouting;

    String modalityLabel(ModalityType type) {
      switch (type) {
        case ModalityType.text:
          return l10n.modelRouting_text;
        case ModalityType.image:
          return l10n.modelRouting_image;
        case ModalityType.audio:
          return l10n.modelRouting_audio;
        case ModalityType.video:
          return l10n.modelRouting_video;
      }
    }

    IconData modalityIcon(ModalityType type) {
      switch (type) {
        case ModalityType.text:
          return Icons.text_fields;
        case ModalityType.image:
          return Icons.image;
        case ModalityType.audio:
          return Icons.audiotrack;
        case ModalityType.video:
          return Icons.videocam;
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.modelRouting_title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...ModalityType.values
                .where((t) => routing.routes.containsKey(t) && !routing.routes[t]!.isEmpty)
                .map((type) {
              final route = routing.routes[type]!;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(modalityIcon(type), size: 16, color: colorScheme.onSurface),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            modalityLabel(type),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            route.model ?? l10n.modelRouting_usingDefault,
                            style: TextStyle(fontSize: 11, color: colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l10n.modelRouting_configured,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _osRiskBadge(String riskLevel, ColorScheme colorScheme) {
    final Color bgColor;
    final Color fgColor;
    final String label;
    switch (riskLevel) {
      case 'safe':
        bgColor = Colors.green.withValues(alpha: 0.1);
        fgColor = Colors.green;
        label = 'SAFE';
        break;
      case 'highRisk':
        bgColor = colorScheme.errorContainer;
        fgColor = colorScheme.error;
        label = 'HIGH';
        break;
      default:
        bgColor = Colors.orange.withValues(alpha: 0.1);
        fgColor = Colors.orange;
        label = 'LOW';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: fgColor),
      ),
    );
  }

  String _osCategoryLabel(String category, AppLocalizations l10n) {
    switch (category) {
      case 'command':
        return l10n.osTool_catCommand;
      case 'file':
        return l10n.osTool_catFile;
      case 'app':
        return l10n.osTool_catApp;
      case 'clipboard':
        return l10n.osTool_catClipboard;
      case 'macos':
        return l10n.osTool_catMacos;
      case 'process':
        return l10n.osTool_catProcess;
      default:
        return category;
    }
  }

  IconData _osToolIcon(String name) {
    switch (name) {
      case 'shell_exec':
        return Icons.terminal;
      case 'file_read':
        return Icons.description;
      case 'file_write':
        return Icons.edit_document;
      case 'file_delete':
        return Icons.delete_forever;
      case 'file_move':
        return Icons.drive_file_move;
      case 'file_list':
        return Icons.folder_open;
      case 'app_open':
        return Icons.launch;
      case 'url_open':
        return Icons.open_in_browser;
      case 'screenshot':
        return Icons.screenshot;
      case 'clipboard_read':
        return Icons.content_paste;
      case 'clipboard_write':
        return Icons.content_copy;
      case 'system_info':
        return Icons.info_outline;
      case 'applescript_exec':
        return Icons.code;
      case 'process_list':
        return Icons.list_alt;
      case 'process_kill':
        return Icons.dangerous;
      case 'process_detail':
        return Icons.analytics;
      case 'network_connections':
        return Icons.lan;
      default:
        return Icons.build;
    }
  }

  Widget _buildTokenCard() {
    final l10n = AppLocalizations.of(context);
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.key,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.agentDetail_authToken,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _agent.token,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  color: Colors.greenAccent,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _agent.token));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.agentDetail_tokenCopied),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy),
                label: Text(l10n.agentDetail_copyToken),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ==================== 编辑模式 ====================

  Widget _buildEditBody() {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 头像编辑
        Center(
          child: GestureDetector(
            onTap: _showAvatarPicker,
            child: Stack(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(25),
                  ),
                  alignment: Alignment.center,
                  child: _buildAvatarWidget(_editingAvatar, 100),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _showAvatarPicker,
            icon: const Icon(Icons.edit, size: 16),
            label: Text(l10n.agentDetail_changeAvatar),
          ),
        ),
        const SizedBox(height: 16),

        // 卡片 1: 基本信息
        _buildEditBasicInfoCard(colorScheme),
        const SizedBox(height: 16),

        // 卡片 2: 连接配置（仅远端 agent 显示）
        if (_agent.metadata['llm_provider'] == null) ...[
          _buildEditConnectionCard(colorScheme),
          const SizedBox(height: 16),
        ],

        // 卡片 3: 模型配置（仅本地 agent 显示）
        if (_agent.metadata['llm_provider'] != null)
          _buildEditLLMConfigCard(colorScheme),

        // 卡片 4: OS 工具 / 技能 / 模型路由导航入口（仅在选择了 LLM provider 时显示）
        if (_selectedProviderIndex >= 0) ...[
          const SizedBox(height: 16),
          _buildEditConfigNavigationTiles(colorScheme),
        ],
        const SizedBox(height: 16),

        // Agent ID（只读）
        TextFormField(
          initialValue: _agent.id,
          decoration: const InputDecoration(
            labelText: 'Agent ID',
            prefixIcon: Icon(Icons.fingerprint),
            border: OutlineInputBorder(),
          ),
          enabled: false,
        ),
        const SizedBox(height: 32),

        // 保存 / 取消按钮
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isSaving ? null : _cancelEdit,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(l10n.common_cancel),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveEdit,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(l10n.common_save),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditBasicInfoCard(ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.addAgent_basicInfo,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.addAgent_agentName,
                hintText: l10n.addAgent_agentNameHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bioController,
              decoration: InputDecoration(
                labelText: l10n.addAgent_agentBio,
                hintText: l10n.addAgent_agentBioHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.description),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _systemPromptController,
              decoration: InputDecoration(
                labelText: l10n.addAgent_systemPrompt,
                hintText: l10n.addAgent_systemPromptHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.tune),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
              minLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditConnectionCard(ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.addAgent_connectConfig,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 端点 URL
            TextFormField(
              controller: _endpointController,
              decoration: InputDecoration(
                labelText: l10n.addAgent_endpointUrl,
                hintText: l10n.addAgent_endpointUrlHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.language),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),

            // Token（只读显示 + 复制）
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.vpn_key, size: 16, color: colorScheme.tertiary),
                      const SizedBox(width: 6),
                      Text(
                        'Token',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.tertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _agent.token,
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: l10n.agentDetail_copyTokenTooltip,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _agent.token));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.agentDetail_tokenCopied),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  /// Navigation tiles for OS Tools, Skills, and Model Routing sub-pages (edit mode).
  Widget _buildEditConfigNavigationTiles(ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context);
    final configuredRouteCount =
        _modelRoutes.values.where((r) => !r.isEmpty).length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.build_circle, color: colorScheme.primary),
            title: Text(l10n.osTool_configTitle),
            subtitle: Text(
              _enabledOsTools.isEmpty
                  ? l10n.addAgent_noOsTools
                  : l10n.addAgent_osToolsCount(_enabledOsTools.length),
              style: TextStyle(
                color: _enabledOsTools.isEmpty
                    ? colorScheme.outline
                    : colorScheme.primary,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final result = await Navigator.push<Set<String>>(
                context,
                MaterialPageRoute(
                  builder: (_) => OsToolSelectScreen(
                    enabledTools: _enabledOsTools,
                  ),
                ),
              );
              if (result != null) {
                setState(() {
                  _enabledOsTools = result;
                });
              }
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.auto_stories, color: colorScheme.primary),
            title: Text(l10n.skill_configTitle),
            subtitle: Text(
              _enabledSkills.isEmpty
                  ? l10n.addAgent_noSkills
                  : l10n.addAgent_skillsCount(_enabledSkills.length),
              style: TextStyle(
                color: _enabledSkills.isEmpty
                    ? colorScheme.outline
                    : colorScheme.primary,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final result = await Navigator.push<Set<String>>(
                context,
                MaterialPageRoute(
                  builder: (_) => SkillSelectScreen(
                    enabledSkills: _enabledSkills,
                  ),
                ),
              );
              if (result != null) {
                setState(() {
                  _enabledSkills = result;
                });
              }
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.route, color: colorScheme.primary),
            title: Text(l10n.modelRouting_title),
            subtitle: Text(
              configuredRouteCount == 0
                  ? l10n.addAgent_noModelRouting
                  : l10n.addAgent_modelRoutingCount(configuredRouteCount),
              style: TextStyle(
                color: configuredRouteCount == 0
                    ? colorScheme.outline
                    : colorScheme.primary,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final result =
                  await Navigator.push<Map<ModalityType, ModelRouteConfig>>(
                context,
                MaterialPageRoute(
                  builder: (_) => ModelRoutingConfigScreen(
                    routes: _modelRoutes,
                  ),
                ),
              );
              if (result != null) {
                setState(() {
                  _modelRoutes = result;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEditLLMConfigCard(ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.addAgent_modelConfig,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.common_optional,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.addAgent_modelConfigHint,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),

            // 服务商选择
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(llmProviders.length, (index) {
                final provider = llmProviders[index];
                final isSelected = _selectedProviderIndex == index;
                return ChoiceChip(
                  label: Text('${provider.icon} ${provider.name}'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedProviderIndex = index;
                        _apiBaseController.text = provider.defaultApiBase;
                        _modelController.text = provider.defaultModel;
                        if (!provider.requiresApiKey) {
                          _apiKeyController.clear();
                        }
                      });
                    } else {
                      setState(() {
                        _selectedProviderIndex = -1;
                        _apiBaseController.clear();
                        _modelController.clear();
                        _apiKeyController.clear();
                      });
                    }
                  },
                  selectedColor: colorScheme.primaryContainer,
                  showCheckmark: false,
                  avatar: isSelected
                      ? Icon(Icons.check_circle, size: 18, color: colorScheme.primary)
                      : null,
                );
              }),
            ),

            if (_selectedProviderIndex >= 0) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // API Base URL
              TextFormField(
                controller: _apiBaseController,
                decoration: const InputDecoration(
                  labelText: 'API Base URL',
                  hintText: 'https://api.openai.com/v1',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cloud),
                  isDense: true,
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),

              // 模型名称
              TextFormField(
                controller: _modelController,
                decoration: InputDecoration(
                  labelText: l10n.addAgent_modelName,
                  hintText: l10n.addAgent_modelNameHint,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.memory),
                  isDense: true,
                  suffixIcon: _getModelsForProvider(llmProviders[_selectedProviderIndex]).isNotEmpty
                      ? PopupMenuButton<String>(
                          icon: const Icon(Icons.arrow_drop_down),
                          tooltip: l10n.addAgent_selectModel,
                          onSelected: (model) {
                            setState(() {
                              _modelController.text = model;
                            });
                          },
                          itemBuilder: (context) {
                            final provider = llmProviders[_selectedProviderIndex];
                            final models = _getModelsForProvider(provider);
                            return models
                                .map((m) => PopupMenuItem(
                                      value: m,
                                      child: Text(m),
                                    ))
                                .toList();
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),

              // API Key
              if (llmProviders[_selectedProviderIndex].requiresApiKey)
                TextFormField(
                  controller: _apiKeyController,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: l10n.addAgent_apiKeyHint,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.key),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureApiKey ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureApiKey = !_obscureApiKey;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureApiKey,
                  enableSuggestions: false,
                  autocorrect: false,
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: colorScheme.tertiary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.addAgent_apiKeyNotRequired,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ==================== 工具方法 ====================

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(int timestampMs) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final time = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return l10n.agentDetail_justNow;
    } else if (diff.inMinutes < 60) {
      return l10n.agentDetail_minutesAgo(diff.inMinutes);
    } else if (diff.inHours < 24) {
      return l10n.agentDetail_hoursAgo(diff.inHours);
    } else {
      return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}
