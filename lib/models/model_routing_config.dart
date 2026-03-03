import 'remote_agent.dart' show repairUtf16Garbled;

String? _repairNullable(String? s) =>
    s != null ? repairUtf16Garbled(s) : null;

/// Modality types for model routing.
enum ModalityType {
  text,
  image,
  audio,
  video;

  String get label {
    switch (this) {
      case ModalityType.text:
        return 'Text';
      case ModalityType.image:
        return 'Image';
      case ModalityType.audio:
        return 'Audio';
      case ModalityType.video:
        return 'Video';
    }
  }

  String get icon {
    switch (this) {
      case ModalityType.text:
        return '\u{1F4DD}'; // memo
      case ModalityType.image:
        return '\u{1F5BC}'; // framed picture
      case ModalityType.audio:
        return '\u{1F3B5}'; // musical note
      case ModalityType.video:
        return '\u{1F3AC}'; // clapper board
    }
  }
}

/// Model configuration for a single modality route.
///
/// All fields are nullable. When null, the value is inherited from the
/// agent's fallback (top-level) LLM configuration.
class ModelRouteConfig {
  final String? provider;
  final String? model;
  final String? apiBase;
  final String? apiKey;

  const ModelRouteConfig({this.provider, this.model, this.apiBase, this.apiKey});

  bool get isEmpty =>
      (provider == null || provider!.isEmpty) &&
      (model == null || model!.isEmpty) &&
      (apiBase == null || apiBase!.isEmpty) &&
      (apiKey == null || apiKey!.isEmpty);

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (provider != null && provider!.isNotEmpty) map['provider'] = provider;
    if (model != null && model!.isNotEmpty) map['model'] = model;
    if (apiBase != null && apiBase!.isNotEmpty) map['api_base'] = apiBase;
    if (apiKey != null && apiKey!.isNotEmpty) map['api_key'] = apiKey;
    return map;
  }

  factory ModelRouteConfig.fromJson(Map<String, dynamic> json) {
    return ModelRouteConfig(
      provider: json['provider'] as String?,
      model: json['model'] as String?,
      apiBase: json['api_base'] as String?,
      apiKey: _repairNullable(json['api_key'] as String?),
    );
  }
}

/// Resolved model configuration with all fields guaranteed non-null.
class ResolvedModelConfig {
  final String providerType;
  final String model;
  final String apiBase;
  final String apiKey;

  const ResolvedModelConfig({
    required this.providerType,
    required this.model,
    required this.apiBase,
    required this.apiKey,
  });
}

/// Multi-modal model routing configuration.
///
/// Stored in `RemoteAgent.metadata['model_routing']`. Each modality can
/// optionally override the agent's default (fallback) LLM configuration.
class ModelRoutingConfig {
  final Map<ModalityType, ModelRouteConfig> routes;

  const ModelRoutingConfig({this.routes = const {}});

  bool get isEmpty => routes.isEmpty || routes.values.every((r) => r.isEmpty);

  /// Resolve the effective model config for [modality], falling back to the
  /// agent's top-level LLM config for any field not set in the route.
  ResolvedModelConfig resolve(
    ModalityType modality, {
    required String fallbackProvider,
    required String fallbackModel,
    required String fallbackApiBase,
    required String fallbackApiKey,
  }) {
    final route = routes[modality];
    return ResolvedModelConfig(
      providerType: (route?.provider != null && route!.provider!.isNotEmpty)
          ? route.provider!
          : fallbackProvider,
      model: (route?.model != null && route!.model!.isNotEmpty)
          ? route.model!
          : fallbackModel,
      apiBase: (route?.apiBase != null && route!.apiBase!.isNotEmpty)
          ? route.apiBase!
          : fallbackApiBase,
      apiKey: (route?.apiKey != null && route!.apiKey!.isNotEmpty)
          ? route.apiKey!
          : fallbackApiKey,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    for (final entry in routes.entries) {
      if (!entry.value.isEmpty) {
        map[entry.key.name] = entry.value.toJson();
      }
    }
    return map;
  }

  factory ModelRoutingConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return const ModelRoutingConfig();
    }
    final routes = <ModalityType, ModelRouteConfig>{};
    for (final type in ModalityType.values) {
      final routeJson = json[type.name] as Map<String, dynamic>?;
      if (routeJson != null) {
        final config = ModelRouteConfig.fromJson(routeJson);
        if (!config.isEmpty) {
          routes[type] = config;
        }
      }
    }
    return ModelRoutingConfig(routes: routes);
  }

  /// Detect the modality of a message based on attachment semantic types.
  ///
  /// Priority: video > audio > image > text.
  static ModalityType detectModality(List<String> attachmentSemanticTypes) {
    if (attachmentSemanticTypes.isEmpty) return ModalityType.text;
    for (final t in attachmentSemanticTypes) {
      if (t == 'video') return ModalityType.video;
    }
    for (final t in attachmentSemanticTypes) {
      if (t == 'audio') return ModalityType.audio;
    }
    for (final t in attachmentSemanticTypes) {
      if (t == 'image') return ModalityType.image;
    }
    return ModalityType.text;
  }
}
