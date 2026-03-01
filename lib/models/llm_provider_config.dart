/// LLM 服务商配置
class LLMProviderConfig {
  final String name;
  final String providerType; // openai / claude / glm
  final String defaultApiBase;
  final String defaultModel;
  final List<String> models;
  final bool requiresApiKey;
  final String icon;

  const LLMProviderConfig({
    required this.name,
    required this.providerType,
    required this.defaultApiBase,
    required this.defaultModel,
    required this.models,
    required this.requiresApiKey,
    required this.icon,
  });
}

/// 预定义的 LLM 服务商列表
const List<LLMProviderConfig> llmProviders = [
  LLMProviderConfig(
    name: 'OpenAI',
    providerType: 'openai',
    defaultApiBase: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4o',
    models: [],
    requiresApiKey: true,
    icon: '🟢',
  ),
  LLMProviderConfig(
    name: 'Claude',
    providerType: 'claude',
    defaultApiBase: 'https://api.anthropic.com/v1',
    defaultModel: 'claude-sonnet-4-20250514',
    models: [],
    requiresApiKey: true,
    icon: '🟠',
  ),
  LLMProviderConfig(
    name: 'Gemini',
    providerType: 'openai',
    defaultApiBase: 'https://generativelanguage.googleapis.com/v1beta/openai',
    defaultModel: 'gemini-2.0-flash',
    models: [],
    requiresApiKey: true,
    icon: '🔷',
  ),
  LLMProviderConfig(
    name: 'Grok',
    providerType: 'openai',
    defaultApiBase: 'https://api.x.ai/v1',
    defaultModel: 'grok-3',
    models: [],
    requiresApiKey: true,
    icon: '⚫',
  ),
  LLMProviderConfig(
    name: 'DeepSeek',
    providerType: 'openai',
    defaultApiBase: 'https://api.deepseek.com/v1',
    defaultModel: 'deepseek-chat',
    models: [],
    requiresApiKey: true,
    icon: '🔵',
  ),
  LLMProviderConfig(
    name: 'Qwen',
    providerType: 'openai',
    defaultApiBase: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: 'qwen-plus',
    models: [],
    requiresApiKey: true,
    icon: '🟣',
  ),
  LLMProviderConfig(
    name: 'GLM',
    providerType: 'glm',
    defaultApiBase: 'https://open.bigmodel.cn/api/paas/v4',
    defaultModel: 'glm-4.7',
    models: [],
    requiresApiKey: true,
    icon: '🔴',
  ),
  LLMProviderConfig(
    name: 'Kimi',
    providerType: 'openai',
    defaultApiBase: 'https://api.moonshot.cn/v1',
    defaultModel: 'moonshot-v1-8k',
    models: [],
    requiresApiKey: true,
    icon: '🌙',
  ),
  LLMProviderConfig(
    name: 'Hunyuan',
    providerType: 'openai',
    defaultApiBase: 'https://api.hunyuan.cloud.tencent.com/v1',
    defaultModel: 'hunyuan-lite',
    models: [],
    requiresApiKey: true,
    icon: '💜',
  ),
  LLMProviderConfig(
    name: 'Ollama',
    providerType: 'openai',
    defaultApiBase: 'http://localhost:11434/v1',
    defaultModel: 'llama3',
    models: [],
    requiresApiKey: false,
    icon: '⚪',
  ),
];
