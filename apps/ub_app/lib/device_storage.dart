import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Mobile runners choose their app-private, backup-excluded installation root.
Future<String?> mobileInstallationRoot() =>
    const MethodChannel('universe_builder/device')
        .invokeMethod<String>('installationRoot');

/// The native runner retains one shared text file in private cache until an
/// author explicitly chooses it in Import source. No service call is made here.
final mobileSharedSources = MobileSharedSources();

final class MobileSharedSources extends ChangeNotifier
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('universe_builder/shared_sources');
  bool _started = false;
  bool pending = false;
  String? error;
  bool get enabled =>
      !kIsWeb &&
      {
        TargetPlatform.iOS,
        TargetPlatform.android,
      }.contains(defaultTargetPlatform);

  void start() {
    if (_started || !enabled) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') await refresh();
    });
    refresh();
  }

  void stop() {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    if (!enabled) return;
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('status');
      final wasPending = pending;
      pending = status?['pending'] == true;
      if (pending != wasPending) error = null;
      if (status?['error'] is String) error = status!['error'] as String;
      notifyListeners();
    } on Object {
      // Source editing and ordinary file picking remain usable if the OS
      // cannot supply its private shared-file status.
    }
  }

  Future<String?> pendingPath() async {
    final path = await _channel.invokeMethod<String>('pendingPath');
    if (path == null) {
      throw const FormatException(
        'No shared text file is waiting. Share a .txt or .md file to Universe Builder first.',
      );
    }
    return path;
  }

  void dismissError() {
    error = null;
    notifyListeners();
  }
}
