import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/model_routing_config.dart';
import '../models/remote_agent.dart';

/// Configuration card for multi-modal model routing.
///
/// Allows users to optionally configure different LLM models for different
/// content types (text, image, audio, video). Unconfigured modalities
/// inherit the agent's default (fallback) model.
class ModelRoutingConfigCard extends StatefulWidget {
  /// Current routing config (from metadata['model_routing']).
  final Map<ModalityType, ModelRouteConfig> routes;

  /// Called when any route is changed.
  final ValueChanged<Map<ModalityType, ModelRouteConfig>> onChanged;

  const ModelRoutingConfigCard({
    super.key,
    required this.routes,
    required this.onChanged,
  });

  @override
  State<ModelRoutingConfigCard> createState() => _ModelRoutingConfigCardState();
}

class _ModelRoutingConfigCardState extends State<ModelRoutingConfigCard> {
  bool _isExpanded = false;

  // Per-modality controllers
  final Map<ModalityType, TextEditingController> _modelControllers = {};
  final Map<ModalityType, TextEditingController> _providerControllers = {};
  final Map<ModalityType, TextEditingController> _apiBaseControllers = {};
  final Map<ModalityType, TextEditingController> _apiKeyControllers = {};

  // Track which modalities show advanced fields
  final Map<ModalityType, bool> _showAdvanced = {};

  // Track API key visibility per modality
  final Map<ModalityType, bool> _obscureApiKey = {};

  @override
  void initState() {
    super.initState();
    for (final type in ModalityType.values) {
      final route = widget.routes[type];
      _modelControllers[type] =
          TextEditingController(text: route?.model ?? '');
      _providerControllers[type] =
          TextEditingController(text: route?.provider ?? '');
      _apiBaseControllers[type] =
          TextEditingController(text: route?.apiBase ?? '');
      _apiKeyControllers[type] =
          TextEditingController(text: route?.apiKey ?? '');
      _apiKeyControllers[type]!.addListener(() => _repairApiKeyIfGarbled(type));
      _showAdvanced[type] = false;
      _obscureApiKey[type] = true;
    }
    // Auto-expand if any route is already configured; otherwise start expanded
    // so the feature is discoverable.
    _isExpanded = true;
  }

  @override
  void dispose() {
    for (final c in _modelControllers.values) {
      c.dispose();
    }
    for (final c in _providerControllers.values) {
      c.dispose();
    }
    for (final c in _apiBaseControllers.values) {
      c.dispose();
    }
    for (final c in _apiKeyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _notifyChanged() {
    final routes = <ModalityType, ModelRouteConfig>{};
    for (final type in ModalityType.values) {
      final config = ModelRouteConfig(
        model: _modelControllers[type]!.text.trim().isEmpty
            ? null
            : _modelControllers[type]!.text.trim(),
        provider: _providerControllers[type]!.text.trim().isEmpty
            ? null
            : _providerControllers[type]!.text.trim(),
        apiBase: _apiBaseControllers[type]!.text.trim().isEmpty
            ? null
            : _apiBaseControllers[type]!.text.trim(),
        apiKey: _apiKeyControllers[type]!.text.trim().isEmpty
            ? null
            : _apiKeyControllers[type]!.text.trim(),
      );
      if (!config.isEmpty) {
        routes[type] = config;
      }
    }
    widget.onChanged(routes);
  }

  void _repairApiKeyIfGarbled(ModalityType type) {
    final controller = _apiKeyControllers[type]!;
    final text = controller.text;
    final repaired = repairUtf16Garbled(text);
    if (repaired != text) {
      controller.value = TextEditingValue(
        text: repaired,
        selection: TextSelection.collapsed(offset: repaired.length),
      );
    }
  }

  String _modalityLabel(ModalityType type, AppLocalizations l10n) {
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

  IconData _modalityIcon(ModalityType type) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final configuredCount =
        widget.routes.values.where((r) => !r.isEmpty).length;

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
            // Header — tap to expand/collapse
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Icon(Icons.route, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.modelRouting_title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  if (configuredCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$configuredCount/4',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    _isExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: colorScheme.outline,
                  ),
                ],
              ),
            ),

            if (_isExpanded) ...[
              const SizedBox(height: 8),
              Text(
                l10n.modelRouting_hint,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.outline,
                ),
              ),
              const Divider(height: 24),

              // One section per modality
              for (final type in ModalityType.values) ...[
                _buildModalitySection(type, colorScheme, l10n),
                if (type != ModalityType.video) const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModalitySection(
    ModalityType type,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final hasValue = _modelControllers[type]!.text.trim().isNotEmpty;
    final showAdv = _showAdvanced[type] ?? false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasValue
            ? colorScheme.primaryContainer.withValues(alpha: 0.15)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasValue
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Modality header
          Row(
            children: [
              Icon(_modalityIcon(type), size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                _modalityLabel(type, l10n),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (hasValue)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l10n.modelRouting_configured,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                )
              else
                Text(
                  l10n.modelRouting_usingDefault,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Model name field
          TextFormField(
            controller: _modelControllers[type],
            decoration: InputDecoration(
              hintText: l10n.modelRouting_modelHint,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.memory, size: 18),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (_) {
              setState(() {});
              _notifyChanged();
            },
          ),

          // Advanced toggle
          const SizedBox(height: 4),
          InkWell(
            onTap: () {
              setState(() {
                _showAdvanced[type] = !showAdv;
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    showAdv ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    l10n.modelRouting_advanced,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (showAdv) ...[
            const SizedBox(height: 4),
            // Provider type
            TextFormField(
              controller: _providerControllers[type],
              decoration: InputDecoration(
                hintText: l10n.modelRouting_providerHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.cloud, size: 18),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (_) => _notifyChanged(),
            ),
            const SizedBox(height: 8),
            // API Base
            TextFormField(
              controller: _apiBaseControllers[type],
              decoration: InputDecoration(
                hintText: l10n.modelRouting_apiBaseHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.language, size: 18),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (_) => _notifyChanged(),
            ),
            const SizedBox(height: 8),
            // API Key
            TextFormField(
              controller: _apiKeyControllers[type],
              decoration: InputDecoration(
                hintText: l10n.modelRouting_apiKeyHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key, size: 18),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: IconButton(
                  icon: Icon(
                    (_obscureApiKey[type] ?? true)
                        ? Icons.visibility
                        : Icons.visibility_off,
                    size: 18,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureApiKey[type] = !(_obscureApiKey[type] ?? true);
                    });
                  },
                ),
              ),
              style: const TextStyle(fontSize: 13),
              obscureText: _obscureApiKey[type] ?? true,
              onChanged: (_) => _notifyChanged(),
            ),
          ],
        ],
      ),
    );
  }
}
