import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/inference_log_entry.dart';

/// Singleton service that collects inference log entries.
///
/// Extends [ChangeNotifier] so the UI can rebuild when new entries arrive or
/// an in-progress entry updates. In-memory only, capped at [maxEntries].
class InferenceLogService extends ChangeNotifier {
  InferenceLogService._();
  static final InferenceLogService instance = InferenceLogService._();

  static const int maxEntries = 100;
  static const int _maxToolResultChars = 2000;

  /// Master toggle — when false, all instrumentation calls are no-ops.
  bool enabled = true;

  final List<InferenceLogEntry> _entries = [];
  List<InferenceLogEntry> get entries => List.unmodifiable(_entries);

  /// Currently active session (one at a time).
  InferenceLogEntry? _active;

  // ---------------------------------------------------------------------------
  // Session lifecycle
  // ---------------------------------------------------------------------------

  /// Begin a new inference session.
  void beginSession({
    required String sessionId,
    required String agentId,
    required String agentName,
    String? channelId,
    String? provider,
    String? model,
    required String userMessage,
    String? systemPrompt,
  }) {
    if (!enabled) return;

    final entry = InferenceLogEntry(
      id: sessionId,
      startTime: DateTime.now(),
      agentId: agentId,
      agentName: agentName,
      channelId: channelId,
      provider: provider,
      model: model,
      userMessage: userMessage,
      systemPrompt: systemPrompt,
    );

    entry.timeline.add(InferenceTimelineEvent(
      timestamp: DateTime.now(),
      type: 'request',
      data: {'userMessage': userMessage},
    ));

    _active = entry;
    _entries.insert(0, entry);

    // Cap the list
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }

    notifyListeners();
  }

  /// End the current session.
  void endSession(InferenceStatus status, {String? error}) {
    if (!enabled || _active == null) return;

    _active!.endTime = DateTime.now();
    _active!.status = status;
    if (error != null) {
      _active!.errorMessage = error;
      _active!.timeline.add(InferenceTimelineEvent(
        timestamp: DateTime.now(),
        type: 'error',
        data: {'error': error},
      ));
    } else {
      _active!.timeline.add(InferenceTimelineEvent(
        timestamp: DateTime.now(),
        type: 'done',
        data: {'status': status.name},
      ));
    }

    // Finalize totals
    int textChars = 0;
    int toolCalls = 0;
    for (final round in _active!.rounds) {
      textChars += round.textBuffer.length;
      toolCalls += round.toolCalls.length;
    }
    _active!.totalTextChars = textChars;
    _active!.totalToolCalls = toolCalls;

    _active = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Round lifecycle
  // ---------------------------------------------------------------------------

  void beginRound({String? requestSummary}) {
    if (!enabled || _active == null) return;

    final round = InferenceRound(
      roundNumber: _active!.rounds.length + 1,
      startTime: DateTime.now(),
    );
    round.requestSummary = requestSummary;
    _active!.rounds.add(round);
    // No notifyListeners — too frequent
  }

  void endRound({String? stopReason}) {
    if (!enabled || _active == null || _active!.rounds.isEmpty) return;

    final round = _active!.rounds.last;
    round.endTime = DateTime.now();
    round.stopReason = stopReason;

    _active!.timeline.add(InferenceTimelineEvent(
      timestamp: DateTime.now(),
      type: 'done',
      data: {
        'round': round.roundNumber,
        'stopReason': stopReason ?? 'unknown',
      },
    ));

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Streaming events
  // ---------------------------------------------------------------------------

  /// Accumulate text — no per-chunk notifyListeners to avoid flooding.
  void onTextChunk(String text) {
    if (!enabled || _active == null || _active!.rounds.isEmpty) return;
    _active!.rounds.last.textBuffer.write(text);
  }

  void onToolCall({
    required String id,
    required String name,
    required Map<String, dynamic> arguments,
  }) {
    if (!enabled || _active == null || _active!.rounds.isEmpty) return;

    final sanitized = _redactKeys(arguments);
    _active!.rounds.last.toolCalls.add({
      'id': id,
      'name': name,
      'arguments': sanitized,
    });

    _active!.timeline.add(InferenceTimelineEvent(
      timestamp: DateTime.now(),
      type: 'tool_call',
      data: {'id': id, 'name': name},
    ));
    // No notifyListeners during streaming
  }

  void onToolResult({
    required String toolCallId,
    required String name,
    required String result,
  }) {
    if (!enabled || _active == null || _active!.rounds.isEmpty) return;

    final truncated = result.length > _maxToolResultChars
        ? '${result.substring(0, _maxToolResultChars)}... [truncated]'
        : result;

    _active!.rounds.last.toolResults.add({
      'tool_call_id': toolCallId,
      'name': name,
      'result': truncated,
    });

    _active!.timeline.add(InferenceTimelineEvent(
      timestamp: DateTime.now(),
      type: 'tool_result',
      data: {'tool_call_id': toolCallId, 'name': name},
    ));
    // No notifyListeners during streaming
  }

  // ---------------------------------------------------------------------------
  // Management
  // ---------------------------------------------------------------------------

  /// Remove all entries associated with a given channel.
  void removeByChannel(String channelId) {
    _entries.removeWhere((e) => e.channelId == channelId);
    notifyListeners();
  }

  void clearAll() {
    _entries.clear();
    _active = null;
    notifyListeners();
  }

  String exportAsJson() {
    final data = _entries.map((e) => e.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Redact any key that looks like an API key.
  static final _keyPattern = RegExp(r'(api[_-]?key|secret|token|auth|password|credential)', caseSensitive: false);

  Map<String, dynamic> _redactKeys(Map<String, dynamic> input) {
    return input.map((key, value) {
      if (_keyPattern.hasMatch(key) && value is String) {
        return MapEntry(key, '[REDACTED]');
      }
      if (value is Map<String, dynamic>) {
        return MapEntry(key, _redactKeys(value));
      }
      return MapEntry(key, value);
    });
  }
}
