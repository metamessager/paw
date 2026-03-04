import 'package:flutter_test/flutter_test.dart';
import 'package:ai_agent_hub/models/model_routing_config.dart';

void main() {
  group('ModalityType Tests', () {
    test('should have correct labels', () {
      expect(ModalityType.text.label, 'Text');
      expect(ModalityType.image.label, 'Image');
      expect(ModalityType.audio.label, 'Audio');
      expect(ModalityType.video.label, 'Video');
    });

    test('should have correct icons', () {
      expect(ModalityType.text.icon, '\u{1F4DD}');
      expect(ModalityType.image.icon, '\u{1F5BC}');
      expect(ModalityType.audio.icon, '\u{1F3B5}');
      expect(ModalityType.video.icon, '\u{1F3AC}');
    });

    test('should have 4 values', () {
      expect(ModalityType.values.length, 4);
    });
  });

  group('ModelRouteConfig Tests', () {
    test('should create empty config', () {
      const config = ModelRouteConfig();

      expect(config.provider, isNull);
      expect(config.model, isNull);
      expect(config.apiBase, isNull);
      expect(config.apiKey, isNull);
      expect(config.isEmpty, true);
    });

    test('should create config with all fields', () {
      const config = ModelRouteConfig(
        provider: 'openai',
        model: 'gpt-4o',
        apiBase: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
      );

      expect(config.provider, 'openai');
      expect(config.model, 'gpt-4o');
      expect(config.apiBase, 'https://api.openai.com/v1');
      expect(config.apiKey, 'sk-test');
      expect(config.isEmpty, false);
    });

    test('isEmpty should return true for empty string fields', () {
      const config = ModelRouteConfig(
        provider: '',
        model: '',
        apiBase: '',
        apiKey: '',
      );
      expect(config.isEmpty, true);
    });

    test('isEmpty should return false if any field is non-empty', () {
      const config = ModelRouteConfig(model: 'gpt-4');
      expect(config.isEmpty, false);
    });

    test('toJson should only include non-empty fields', () {
      const config = ModelRouteConfig(
        provider: 'openai',
        model: 'gpt-4o',
      );

      final json = config.toJson();

      expect(json['provider'], 'openai');
      expect(json['model'], 'gpt-4o');
      expect(json.containsKey('api_base'), false);
      expect(json.containsKey('api_key'), false);
    });

    test('toJson should return empty map for empty config', () {
      const config = ModelRouteConfig();
      expect(config.toJson(), isEmpty);
    });

    test('fromJson should parse correctly', () {
      final json = {
        'provider': 'claude',
        'model': 'claude-sonnet-4-20250514',
        'api_base': 'https://api.anthropic.com/v1',
        'api_key': 'sk-ant-test',
      };

      final config = ModelRouteConfig.fromJson(json);

      expect(config.provider, 'claude');
      expect(config.model, 'claude-sonnet-4-20250514');
      expect(config.apiBase, 'https://api.anthropic.com/v1');
      expect(config.apiKey, 'sk-ant-test');
    });

    test('fromJson should handle missing fields', () {
      final config = ModelRouteConfig.fromJson({});

      expect(config.provider, isNull);
      expect(config.model, isNull);
    });
  });

  group('ResolvedModelConfig Tests', () {
    test('should create with all required fields', () {
      const config = ResolvedModelConfig(
        providerType: 'openai',
        model: 'gpt-4o',
        apiBase: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
      );

      expect(config.providerType, 'openai');
      expect(config.model, 'gpt-4o');
      expect(config.apiBase, 'https://api.openai.com/v1');
      expect(config.apiKey, 'sk-test');
    });
  });

  group('ModelRoutingConfig Tests', () {
    test('default config should be empty', () {
      const config = ModelRoutingConfig();

      expect(config.isEmpty, true);
      expect(config.routes, isEmpty);
    });

    test('isEmpty should be true when all routes are empty', () {
      final config = ModelRoutingConfig(routes: {
        ModalityType.text: const ModelRouteConfig(),
        ModalityType.image: const ModelRouteConfig(provider: ''),
      });

      expect(config.isEmpty, true);
    });

    test('isEmpty should be false when at least one route has data', () {
      final config = ModelRoutingConfig(routes: {
        ModalityType.image: const ModelRouteConfig(model: 'gpt-4o'),
      });

      expect(config.isEmpty, false);
    });

    group('resolve', () {
      test('should use route values when set', () {
        final config = ModelRoutingConfig(routes: {
          ModalityType.image: const ModelRouteConfig(
            provider: 'openai',
            model: 'gpt-4o',
            apiBase: 'https://api.openai.com/v1',
            apiKey: 'sk-image',
          ),
        });

        final resolved = config.resolve(
          ModalityType.image,
          fallbackProvider: 'claude',
          fallbackModel: 'claude-sonnet',
          fallbackApiBase: 'https://api.anthropic.com',
          fallbackApiKey: 'sk-fallback',
        );

        expect(resolved.providerType, 'openai');
        expect(resolved.model, 'gpt-4o');
        expect(resolved.apiBase, 'https://api.openai.com/v1');
        expect(resolved.apiKey, 'sk-image');
      });

      test('should fall back to defaults when route not configured', () {
        const config = ModelRoutingConfig();

        final resolved = config.resolve(
          ModalityType.text,
          fallbackProvider: 'claude',
          fallbackModel: 'claude-sonnet',
          fallbackApiBase: 'https://api.anthropic.com',
          fallbackApiKey: 'sk-fallback',
        );

        expect(resolved.providerType, 'claude');
        expect(resolved.model, 'claude-sonnet');
        expect(resolved.apiBase, 'https://api.anthropic.com');
        expect(resolved.apiKey, 'sk-fallback');
      });

      test('should fall back per-field when route has partial config', () {
        final config = ModelRoutingConfig(routes: {
          ModalityType.image: const ModelRouteConfig(
            provider: 'openai',
            model: 'gpt-4o',
            // apiBase and apiKey not set
          ),
        });

        final resolved = config.resolve(
          ModalityType.image,
          fallbackProvider: 'claude',
          fallbackModel: 'claude-sonnet',
          fallbackApiBase: 'https://api.anthropic.com/v1',
          fallbackApiKey: 'sk-ant-fallback',
        );

        expect(resolved.providerType, 'openai');
        expect(resolved.model, 'gpt-4o');
        expect(resolved.apiBase, 'https://api.anthropic.com/v1'); // fallback
        expect(resolved.apiKey, 'sk-ant-fallback'); // fallback
      });

      test('should fall back when route field is empty string', () {
        final config = ModelRoutingConfig(routes: {
          ModalityType.audio: const ModelRouteConfig(
            provider: '',
            model: '',
          ),
        });

        final resolved = config.resolve(
          ModalityType.audio,
          fallbackProvider: 'openai',
          fallbackModel: 'whisper-1',
          fallbackApiBase: 'https://api.openai.com/v1',
          fallbackApiKey: 'sk-key',
        );

        expect(resolved.providerType, 'openai');
        expect(resolved.model, 'whisper-1');
      });
    });

    group('JSON serialization', () {
      test('toJson should only include non-empty routes', () {
        final config = ModelRoutingConfig(routes: {
          ModalityType.text: const ModelRouteConfig(model: 'gpt-4o'),
          ModalityType.image: const ModelRouteConfig(), // empty, should be omitted
        });

        final json = config.toJson();

        expect(json.containsKey('text'), true);
        expect(json['text']['model'], 'gpt-4o');
        expect(json.containsKey('image'), false);
      });

      test('toJson should return empty map for empty config', () {
        const config = ModelRoutingConfig();
        expect(config.toJson(), isEmpty);
      });

      test('fromJson with null should return empty config', () {
        final config = ModelRoutingConfig.fromJson(null);
        expect(config.isEmpty, true);
      });

      test('fromJson with empty map should return empty config', () {
        final config = ModelRoutingConfig.fromJson({});
        expect(config.isEmpty, true);
      });

      test('fromJson should parse routes correctly', () {
        final json = <String, dynamic>{
          'text': <String, dynamic>{'provider': 'openai', 'model': 'gpt-4'},
          'image': <String, dynamic>{'provider': 'openai', 'model': 'gpt-4o', 'api_key': 'sk-img'},
          'video': <String, dynamic>{}, // empty route, should be skipped
        };

        final config = ModelRoutingConfig.fromJson(json);

        expect(config.routes.containsKey(ModalityType.text), true);
        expect(config.routes[ModalityType.text]!.model, 'gpt-4');
        expect(config.routes.containsKey(ModalityType.image), true);
        expect(config.routes[ModalityType.image]!.apiKey, 'sk-img');
        // Empty route should not be included
        expect(config.routes.containsKey(ModalityType.video), false);
      });

      test('roundtrip JSON serialization should preserve data', () {
        final original = ModelRoutingConfig(routes: {
          ModalityType.text: const ModelRouteConfig(
            provider: 'openai',
            model: 'gpt-4',
          ),
          ModalityType.audio: const ModelRouteConfig(
            provider: 'openai',
            model: 'whisper-1',
            apiBase: 'https://api.openai.com/v1',
          ),
        });

        final json = original.toJson();
        final restored = ModelRoutingConfig.fromJson(json);

        expect(restored.routes.length, 2);
        expect(restored.routes[ModalityType.text]!.provider, 'openai');
        expect(restored.routes[ModalityType.text]!.model, 'gpt-4');
        expect(restored.routes[ModalityType.audio]!.model, 'whisper-1');
      });
    });

    group('detectModality', () {
      test('should return text for empty attachments', () {
        expect(
          ModelRoutingConfig.detectModality([]),
          ModalityType.text,
        );
      });

      test('should detect video with highest priority', () {
        expect(
          ModelRoutingConfig.detectModality(['image', 'video', 'audio']),
          ModalityType.video,
        );
      });

      test('should detect audio when no video present', () {
        expect(
          ModelRoutingConfig.detectModality(['image', 'audio']),
          ModalityType.audio,
        );
      });

      test('should detect image when no video/audio present', () {
        expect(
          ModelRoutingConfig.detectModality(['image']),
          ModalityType.image,
        );
      });

      test('should default to text for unknown types', () {
        expect(
          ModelRoutingConfig.detectModality(['document', 'spreadsheet']),
          ModalityType.text,
        );
      });

      test('priority order: video > audio > image > text', () {
        // Only video
        expect(
          ModelRoutingConfig.detectModality(['video']),
          ModalityType.video,
        );
        // Audio + image (no video)
        expect(
          ModelRoutingConfig.detectModality(['audio', 'image']),
          ModalityType.audio,
        );
        // Only image
        expect(
          ModelRoutingConfig.detectModality(['image', 'document']),
          ModalityType.image,
        );
      });
    });
  });
}
