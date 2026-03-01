import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_localizations.dart';
import '../models/remote_agent.dart';
import '../models/llm_provider_config.dart';
import '../services/remote_agent_service.dart';
import '../services/local_database_service.dart';
import '../services/token_service.dart';
import '../widgets/os_tool_config_card.dart';
import '../widgets/skill_config_card.dart';

/// 添加远端助手界面
class AddRemoteAgentScreen extends StatefulWidget {
  /// Optional callback used in desktop embedded mode.
  /// When provided, called instead of Navigator.pop after completion.
  final VoidCallback? onDone;

  const AddRemoteAgentScreen({super.key, this.onDone});

  @override
  State<AddRemoteAgentScreen> createState() => _AddRemoteAgentScreenState();
}

enum AgentCreationMode {
  create, // 创建本地配置，生成 Token
  connect, // 连接到远端 Agent，输入 Token
}

class _AddRemoteAgentScreenState extends State<AddRemoteAgentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _endpointController = TextEditingController();
  final _tokenController = TextEditingController();

  // LLM 配置相关控制器
  final _apiKeyController = TextEditingController();
  final _apiBaseController = TextEditingController();
  final _modelController = TextEditingController();
  final _systemPromptController = TextEditingController();

  AgentCreationMode _mode = AgentCreationMode.create;
  String _selectedAvatar = '🤖';
  bool _isCreating = false;
  bool _obscureApiKey = true;

  // LLM 服务商选择
  int _selectedProviderIndex = -1; // -1 表示未选择

  // 用户自定义的模型名称（按服务商名称分组）
  Map<String, List<String>> _customModels = {};

  // OS 工具配置
  Set<String> _enabledOsTools = {};

  // Skills 配置
  Set<String> _enabledSkills = {};

  late RemoteAgentService _agentService;

  void _finish() {
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  void initState() {
    super.initState();
    final dbService = LocalDatabaseService();
    final tokenService = TokenService(dbService);
    _agentService = RemoteAgentService(dbService, tokenService);
    _loadCustomModels();
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

  /// 获取指定服务商的完整模型列表（预置 + 用户自定义）
  List<String> _getModelsForProvider(LLMProviderConfig provider) {
    final builtIn = provider.models;
    final custom = _customModels[provider.name] ?? [];
    // 去重：custom 中可能和 builtIn 重复
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
    _nameController.dispose();
    _bioController.dispose();
    _endpointController.dispose();
    _tokenController.dispose();
    _apiKeyController.dispose();
    _apiBaseController.dispose();
    _modelController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  void _selectProvider(int index) {
    setState(() {
      _selectedProviderIndex = index;
      final provider = llmProviders[index];
      _apiBaseController.text = provider.defaultApiBase;
      _modelController.text = provider.defaultModel;
      if (!provider.requiresApiKey) {
        _apiKeyController.clear();
      }
    });
  }

  void _generateRandomToken() {
    setState(() {
      _tokenController.text = const Uuid().v4();
    });
  }

  Future<void> _createAgent() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      // 构建 metadata（包含 LLM 配置）
      final Map<String, dynamic> metadata = {};
      AgentStatus? initialStatus;
      if (_selectedProviderIndex >= 0) {
        final provider = llmProviders[_selectedProviderIndex];
        metadata['llm_provider'] = provider.providerType;
        metadata['llm_model'] = _modelController.text.trim();
        metadata['llm_api_base'] = _apiBaseController.text.trim();
        if (_apiKeyController.text.trim().isNotEmpty) {
          metadata['llm_api_key'] = _apiKeyController.text.trim();
        }
        // Local LLM agents are always available
        initialStatus = AgentStatus.online;

        // Save enabled OS tools
        if (_enabledOsTools.isNotEmpty) {
          metadata['enabled_os_tools'] = _enabledOsTools.toList();
        }

        // Save enabled skills
        if (_enabledSkills.isNotEmpty) {
          metadata['enabled_skills'] = _enabledSkills.toList();
        }

        // 保存用户手动输入的模型名称供下次选择
        final inputModel = _modelController.text.trim();
        if (inputModel.isNotEmpty && !provider.models.contains(inputModel)) {
          await _saveCustomModel(provider.name, inputModel);
        }
      }
      // system_prompt is a general agent config, independent of LLM provider
      if (_systemPromptController.text.trim().isNotEmpty) {
        metadata['system_prompt'] = _systemPromptController.text.trim();
      }

      final agent = await _agentService.createAgent(
        name: _nameController.text.trim(),
        protocol: ProtocolType.acp,
        connectionType: ConnectionType.websocket,
        endpoint: _endpointController.text.trim(),
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        avatar: _selectedAvatar,
        metadata: metadata,
        initialStatus: initialStatus,
      );

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.addAgent_createSuccess),
          backgroundColor: Colors.green,
        ),
      );
      _finish();
    } on AgentDuplicateException catch (e) {
      if (!mounted) return;

      await _showDuplicateAgentDialog(e);

      setState(() {
        _isCreating = false;
      });
    } catch (e) {
      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.addAgent_createFailed(e.toString())),
          backgroundColor: Colors.red,
        ),
      );

      setState(() {
        _isCreating = false;
      });
    }
  }

  Future<void> _connectToAgent() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final tempAgent = await _agentService.createAgentWithToken(
        name: _nameController.text.trim(),
        protocol: ProtocolType.acp,
        connectionType: ConnectionType.websocket,
        endpoint: _endpointController.text.trim(),
        token: _tokenController.text.trim(),
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        avatar: _selectedAvatar,
      );

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Text(l10n.addAgent_testingConnection),
            ],
          ),
          duration: const Duration(seconds: 5),
        ),
      );

      final isHealthy = await _agentService.checkAgentHealth(
        tempAgent.id,
        timeout: const Duration(seconds: 10),
      );

      if (!mounted) return;

      if (isHealthy) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.addAgent_connectSuccess),
            backgroundColor: Colors.green,
          ),
        );
        _finish();
      } else {
        final shouldKeep = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.addAgent_connectFailTitle),
            content: Text(l10n.addAgent_connectFailContent),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.addAgent_deleteConfig),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.addAgent_keepConfig),
              ),
            ],
          ),
        );

        if (shouldKeep != true) {
          await _agentService.deleteAgent(tempAgent.id);

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.addAgent_configDeleted),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.addAgent_configKeptOffline),
              backgroundColor: Colors.orange,
            ),
          );
        }

        if (mounted) {
          _finish();
        }
      }
    } on AgentDuplicateException catch (e) {
      if (!mounted) return;

      await _showDuplicateAgentDialog(e);

      setState(() {
        _isCreating = false;
      });
    } catch (e) {
      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.addAgent_operationFailed(e.toString())),
          backgroundColor: Colors.red,
        ),
      );

      setState(() {
        _isCreating = false;
      });
    }
  }

  Future<void> _showDuplicateAgentDialog(AgentDuplicateException e) async {
    final existingAgent = e.existingAgent;
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.addAgent_duplicateTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.message),
            const SizedBox(height: 12),
            Text(
              l10n.addAgent_existingInfo,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(l10n.addAgent_existingName(existingAgent.name)),
            if (existingAgent.endpoint.isNotEmpty)
              Text('Endpoint: ${existingAgent.endpoint}'),
            Text(l10n.addAgent_existingProtocol(existingAgent.protocol.name)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_ok),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_mode == AgentCreationMode.connect ? l10n.addAgent_connectTitle : l10n.addAgent_createTitle),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 模式切换 - SegmentedButton
              _buildModeSwitch(colorScheme),
              const SizedBox(height: 20),

              // 头像区域 - 渐变背景
              _buildAvatarSection(colorScheme),
              const SizedBox(height: 20),

              // 基本信息卡片
              _buildBasicInfoCard(colorScheme),
              const SizedBox(height: 16),

              // 连接配置卡片
              if (_mode == AgentCreationMode.connect)
                _buildConnectConfigCard(colorScheme),

              // 创建模式 - LLM 配置卡片
              if (_mode == AgentCreationMode.create)
                _buildLLMConfigCard(colorScheme),

              // 创建模式 - OS 工具配置（仅在选择了 LLM provider 时显示）
              if (_mode == AgentCreationMode.create && _selectedProviderIndex >= 0) ...[
                const SizedBox(height: 16),
                OsToolConfigCard(
                  enabledTools: _enabledOsTools,
                  onChanged: (tools) {
                    setState(() {
                      _enabledOsTools = tools;
                    });
                  },
                ),
                const SizedBox(height: 16),
                SkillConfigCard(
                  enabledSkills: _enabledSkills,
                  onChanged: (skills) {
                    setState(() {
                      _enabledSkills = skills;
                    });
                  },
                ),
              ],

              const SizedBox(height: 16),

              // 说明步骤卡片（仅连接模式显示）
              if (_mode == AgentCreationMode.connect) ...[
                _buildInstructionCard(colorScheme),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 24),

              // 操作按钮 - 渐变圆角
              _buildActionButton(colorScheme),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// 模式切换 - SegmentedButton
  Widget _buildModeSwitch(ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<AgentCreationMode>(
        segments: [
          ButtonSegment<AgentCreationMode>(
            value: AgentCreationMode.create,
            icon: const Icon(Icons.add_circle_outline),
            label: Text(l10n.addAgent_modeCreate),
          ),
          ButtonSegment<AgentCreationMode>(
            value: AgentCreationMode.connect,
            icon: const Icon(Icons.link),
            label: Text(l10n.addAgent_modeConnect),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (Set<AgentCreationMode> selected) {
          setState(() {
            _mode = selected.first;
          });
        },
      ),
    );
  }

  /// 头像区域 - 渐变背景装饰
  Widget _buildAvatarSection(ColorScheme colorScheme) {
    return Center(
      child: GestureDetector(
        onTap: _showAvatarPicker,
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primaryContainer,
                colorScheme.secondaryContainer,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                _selectedAvatar,
                style: const TextStyle(fontSize: 52),
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.edit,
                    size: 14,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 基本信息卡片
  Widget _buildBasicInfoCard(ColorScheme colorScheme) {
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
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.addAgent_agentNameRequired;
                }
                return null;
              },
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

  /// 连接配置卡片（连接模式）
  Widget _buildConnectConfigCard(ColorScheme colorScheme) {
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

            // Token 输入 - 特殊样式
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
                        l10n.addAgent_tokenAuth,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.tertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _tokenController,
                    decoration: InputDecoration(
                      hintText: l10n.addAgent_tokenHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.casino),
                        onPressed: _generateRandomToken,
                        tooltip: l10n.addAgent_generateToken,
                      ),
                    ),
                    validator: (value) {
                      if (_mode == AgentCreationMode.connect) {
                        if (value == null || value.trim().isEmpty) {
                          return l10n.addAgent_tokenRequired;
                        }
                      }
                      return null;
                    },
                    enableSuggestions: false,
                    autocorrect: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 端点 URL
            TextFormField(
              controller: _endpointController,
              decoration: InputDecoration(
                labelText: l10n.addAgent_endpointUrl,
                hintText: l10n.addAgent_endpointUrlHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.language),
                helperText: l10n.addAgent_endpointHelper,
              ),
              keyboardType: TextInputType.url,
              validator: (value) {
                if (_mode == AgentCreationMode.connect) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.addAgent_endpointRequired;
                  }
                  if (!value.startsWith('http://') &&
                      !value.startsWith('https://') &&
                      !value.startsWith('ws://') &&
                      !value.startsWith('wss://')) {
                    return l10n.addAgent_endpointInvalid;
                  }
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 端点 URL 卡片（创建模式）
  Widget _buildEndpointCard(ColorScheme colorScheme) {
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
                Icon(Icons.language, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.addAgent_endpointConfigTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _endpointController,
              decoration: InputDecoration(
                labelText: l10n.addAgent_endpointOptional,
                hintText: l10n.addAgent_endpointUrlHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.language),
                helperText: l10n.addAgent_endpointOptionalHelper,
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
      ),
    );
  }

  /// LLM 配置卡片（创建模式）
  Widget _buildLLMConfigCard(ColorScheme colorScheme) {
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

            // 服务商选择网格
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
                      _selectProvider(index);
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

            // 选择服务商后显示配置字段
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

              // API Key（根据服务商是否需要）
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
                        _obscureApiKey
                            ? Icons.visibility_off
                            : Icons.visibility,
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
                      Icon(Icons.info_outline,
                          size: 16, color: colorScheme.tertiary),
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

  /// 说明步骤卡片（仅连接模式）
  Widget _buildInstructionCard(ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context);
    final steps = [
      (l10n.addAgent_connectStep1, Icons.vpn_key),
      (l10n.addAgent_connectStep2, Icons.language),
      (l10n.addAgent_connectStep3, Icons.chat),
    ];

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cable,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.addAgent_connectSteps,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(steps.length, (index) {
              final (text, icon) = steps[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(icon, size: 18, color: colorScheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
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

  /// 操作按钮 - 渐变色 + 圆角
  Widget _buildActionButton(ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.tertiary,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isCreating
              ? null
              : (_mode == AgentCreationMode.connect
                  ? _connectToAgent
                  : _createAgent),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: _isCreating
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _mode == AgentCreationMode.connect
                              ? Icons.link
                              : Icons.add_circle,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _mode == AgentCreationMode.connect
                              ? l10n.addAgent_connectButton
                              : l10n.addAgent_createButton,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAvatarPicker() {
    final l10n = AppLocalizations.of(context);
    final avatars = [
      '🤖', '🦾', '🧠', '💡', '🌟', '⚡', '🔮', '🎯',
      '🚀', '🛸', '🌈', '🔥', '💎', '🎨', '🎭', '🎪',
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                    _selectedAvatar = avatar;
                  });
                  Navigator.pop(context);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: _selectedAvatar == avatar
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
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
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_cancel),
          ),
        ],
      ),
    );
  }
}
