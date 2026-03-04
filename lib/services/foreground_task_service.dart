import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Manages an Android foreground service to keep the app alive while agent
/// tasks are running. Uses reference counting so the service stays active as
/// long as at least one agent task is in progress.
///
/// On non-Android platforms this is a silent no-op.
class ForegroundTaskService {
  ForegroundTaskService._();
  static final ForegroundTaskService _instance = ForegroundTaskService._();
  factory ForegroundTaskService() => _instance;

  /// Per-agent reference counts. A single agent may have concurrent tasks
  /// across multiple channels.
  final Map<String, int> _activeAgentCounts = {};

  bool _initialized = false;
  bool _running = false;

  /// Whether the foreground service is currently active.
  bool get isRunning => _running;

  /// True only on Android (not web).
  bool get _isSupported => !kIsWeb && Platform.isAndroid;

  /// Call once during app startup (after [WidgetsFlutterBinding.ensureInitialized]).
  void init() {
    if (!_isSupported || _initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'paw_foreground_service',
        channelName: 'Agent Processing',
        channelDescription: 'Keeps the connection alive while an agent is working',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Increment the reference count for [agentName] and start the foreground
  /// service if it is not already running.
  Future<void> acquireTask(String agentName) async {
    if (!_isSupported) return;

    _activeAgentCounts[agentName] = (_activeAgentCounts[agentName] ?? 0) + 1;
    print('[ForegroundTask] acquire "$agentName" (count: ${_activeAgentCounts[agentName]}, total agents: ${_activeAgentCounts.length})');

    if (!_running) {
      await _startService();
    }
  }

  /// Decrement the reference count for [agentName]. When all counts reach zero
  /// the foreground service is stopped.
  Future<void> releaseTask(String agentName) async {
    if (!_isSupported) return;

    final current = _activeAgentCounts[agentName] ?? 0;
    if (current <= 1) {
      _activeAgentCounts.remove(agentName);
    } else {
      _activeAgentCounts[agentName] = current - 1;
    }

    print('[ForegroundTask] release "$agentName" (count: ${_activeAgentCounts[agentName] ?? 0}, total agents: ${_activeAgentCounts.length})');

    if (_activeAgentCounts.isEmpty && _running) {
      await _stopService();
    }
  }

  /// Emergency cleanup — release all tasks and stop the service immediately.
  Future<void> releaseAllTasks() async {
    if (!_isSupported) return;

    _activeAgentCounts.clear();
    if (_running) {
      await _stopService();
    }
  }

  Future<void> _startService() async {
    try {
      _running = true;
      await FlutterForegroundTask.startService(
        notificationTitle: 'Paw - Agent Processing',
        notificationText: 'An agent task is in progress',
        callback: _foregroundTaskCallback,
      );
      print('[ForegroundTask] Service started');
    } catch (e) {
      print('[ForegroundTask] Failed to start service: $e');
      _running = false;
    }
  }

  Future<void> _stopService() async {
    try {
      await FlutterForegroundTask.stopService();
      _running = false;
      print('[ForegroundTask] Service stopped');
    } catch (e) {
      print('[ForegroundTask] Failed to stop service: $e');
    }
  }
}

// Top-level callback required by flutter_foreground_task.
// We don't need to run any Dart code in the service isolate — the sole
// purpose of the foreground service is to keep the process alive.
@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_NoOpTaskHandler());
}

class _NoOpTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
