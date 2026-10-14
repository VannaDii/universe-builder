import 'package:flutter/services.dart';

const _channel = MethodChannel('universe_builder/backup_files');
Future<String?> saveBackupFile(String source) =>
    _channel.invokeMethod<String>('saveBackup', {'source': source});
Future<bool> openBackupFile(String destination) async =>
    await _channel.invokeMethod<bool>('openBackup', {
      'destination': destination,
    }) ??
    false;
