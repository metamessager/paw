/// OpenClaw Agent 数据模型
/// 代表通过 ACP 协议连接的 OpenClaw Agent

import 'agent.dart';
import 'universal_agent.dart';
import 'a2a/task.dart';
import 'a2a/agent_card.dart';
/// OpenClaw Agent
class OpenClawAgent extends UniversalAgent {
  /// OpenClaw Gateway URL (例如: ws://localhost:18789)
  final String gatewayUrl;

  /// 认证 Token（可选）
  final String? authToken;

  /// 会话 ID（用于保持对话上下文）
  final String? sessionId;

  /// 可用工具列表
  /// 常见工具: bash, file-system, web-search, code-executor
  final List<String>? tools;

  /// Agent 配置
  final Map<String, dynamic>? config;

  /// 模型名称（例如: claude-3-5-sonnet, gpt-4）
  final String? model;

  /// 系统提示词
  final String? systemPrompt;

  OpenClawAgent({
    required super.id,
    required super.name,
    required super.avatar,
    super.bio,
    required this.gatewayUrl,
    this.authToken,
    this.sessionId,
    this.tools,
    this.config,
    this.model,
    this.systemPrompt,
    super.status = const AgentStatus(state: 'offline'),
  }) : super(
          type: 'openclaw',
          provider: AgentProvider(
            name: 'OpenClaw',
            platform: 'Moltbot ACP Gateway',
            type: 'openclaw',
            logo: '🦅',
          ),
        );

  @override
  Future<String> sendMessage(String message) async {
    // 实际实现在 ACPService 中
    throw UnimplementedError('Use ACPService.sendMessage()');
  }

  @override
  Future<A2ATaskResponse> submitTask(A2ATask task) async {
    // 实际实现在 ACPService 中
    throw UnimplementedError('Use ACPService.submitTask()');
  }

  @override
  Future<A2AAgentCard?> getAgentCard() async {
    return A2AAgentCard(
      name: name,
      description: bio ?? 'OpenClaw Agent via ACP Protocol',
      version: '1.0.0',
      endpoints: A2AEndpoints(
        tasks: '$gatewayUrl/tasks',
        stream: '$gatewayUrl/stream',
        status: '$gatewayUrl/status',
      ),
      capabilities: [
        'chat',
        'task_execution',
        'streaming',
        if (tools != null && tools!.isNotEmpty) 'tool_calling',
        'session_management',
      ],
      authentication: authToken != null
          ? A2AAuthentication(
              schemes: ['bearer'],
              config: {'header': 'Authorization'},
            )
          : null,
      metadata: {
        'protocol': 'ACP',
        'platform': 'OpenClaw (Moltbot)',
        'gateway_url': gatewayUrl,
        'tools': tools,
        'model': model,
        'session_id': sessionId,
      },
    );
  }

  /// 转换为 JSON
  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'bio': bio,
      'type': type,
      'gateway_url': gatewayUrl,
      'auth_token': authToken,
      'session_id': sessionId,
      'tools': tools,
      'config': config,
      'model': model,
      'system_prompt': systemPrompt,
      'provider': provider.toJson(),
      'status': status.toJson(),
    };
  }

  /// 从 JSON 创建
  factory OpenClawAgent.fromJson(Map<String, dynamic> json) {
    return OpenClawAgent(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      avatar: json['avatar'] ?? '🦅',
      bio: json['bio'],
      gatewayUrl: json['gateway_url'] ?? '',
      authToken: json['auth_token'],
      sessionId: json['session_id'],
      tools: json['tools'] != null ? List<String>.from(json['tools']) : null,
      config: json['config'],
      model: json['model'],
      systemPrompt: json['system_prompt'],
      status: json['status'] != null
          ? AgentStatus.fromJson(json['status'])
          : const AgentStatus(state: 'offline'),
    );
  }

  /// 复制并修改
  OpenClawAgent copyWith({
    String? id,
    String? name,
    String? avatar,
    String? bio,
    String? gatewayUrl,
    String? authToken,
    String? sessionId,
    List<String>? tools,
    Map<String, dynamic>? config,
    String? model,
    String? systemPrompt,
    AgentStatus? status,
  }) {
    return OpenClawAgent(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      bio: bio ?? this.bio,
      gatewayUrl: gatewayUrl ?? this.gatewayUrl,
      authToken: authToken ?? this.authToken,
      sessionId: sessionId ?? this.sessionId,
      tools: tools ?? this.tools,
      config: config ?? this.config,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      status: status ?? this.status,
    );
  }
}

/// OpenClaw 工具枚举
class OpenClawTool {
  /// Bash 命令执行
  static const String bash = 'bash';

  /// 文件系统操作
  static const String fileSystem = 'file-system';

  /// Web 搜索
  static const String webSearch = 'web-search';

  /// 代码执行
  static const String codeExecutor = 'code-executor';

  /// 屏幕截图
  static const String screenshot = 'screenshot';

  /// 浏览器控制
  static const String browser = 'browser';

  /// 所有可用工具
  static const List<String> all = [
    bash,
    fileSystem,
    webSearch,
    codeExecutor,
    screenshot,
    browser,
  ];

  /// 工具名称映射
  static const Map<String, String> displayNames = {
    bash: 'Bash 命令',
    fileSystem: '文件系统',
    webSearch: 'Web 搜索',
    codeExecutor: '代码执行',
    screenshot: '屏幕截图',
    browser: '浏览器控制',
  };

  /// 工具图标
  static const Map<String, String> icons = {
    bash: '💻',
    fileSystem: '📁',
    webSearch: '🔍',
    codeExecutor: '⚙️',
    screenshot: '📷',
    browser: '🌐',
  };
}
