import 'dart:io';

import 'package:ub_client/local_engine.dart';
import 'package:ub_client/loopback_engine.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

final class DeviceConnection {
  DeviceConnection(List<String> arguments) {
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      final equal = argument.indexOf('=');
      final key = equal < 0 ? argument : argument.substring(0, equal);
      if (!{'--installation', '--profile', '--engine'}.contains(key)) continue;
      final value = equal < 0
          ? (++i < arguments.length ? arguments[i] : '')
          : argument.substring(equal + 1);
      if (key == '--installation') root = value;
      if (key == '--profile') profile = value;
      if (key == '--engine') helper = value;
    }
    if (root == null && profile == null && Platform.isLinux) {
      final data = Platform.environment['XDG_DATA_HOME'];
      final home = Platform.environment['HOME'];
      if (data?.startsWith('/') == true) {
        root = '$data/universe-builder/installation';
      } else if (home?.startsWith('/') == true) {
        root = '$home/.local/share/universe-builder/installation';
      }
    }
  }
  String? root, profile, helper;
  bool get supportsLocal => true;
  bool get available => root?.isNotEmpty == true;
  String get unavailableMessage =>
      'Open Universe Builder from a configured local installation.';
  Future<AppSession> connect() async {
    if (!available) throw StateError('Local connection not configured');
    final engine = helper ?? await LocalEngineClient.siblingEngine();
    if (profile == null) {
      final initialized = await Process.run(engine, [
        '--installation',
        root!,
        '--device-profile',
      ]);
      if (initialized.exitCode != 0) {
        throw StateError('Device setup unavailable');
      }
      profile = ProfileId.parse((initialized.stdout as String).trim()).value;
    }
    final client = await LoopbackEngineClient.ensureRunning(
      root: root!,
      profile: ProfileId.parse(profile!),
      helper: engine,
      clientName: 'universe-builder-app',
      compatibilitySocket: false,
    );
    return AppSession(
      call: client.call,
      close: client.close,
      author: client.welcome.author,
    );
  }
}
