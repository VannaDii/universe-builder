import 'package:flutter/services.dart';

/// Mobile runners choose their app-private, backup-excluded installation root.
Future<String?> mobileInstallationRoot() =>
    const MethodChannel('universe_builder/device')
        .invokeMethod<String>('installationRoot');
