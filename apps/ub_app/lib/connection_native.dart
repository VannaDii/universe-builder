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
  }
  String? root, profile, helper;
  bool get supportsLocal => true;
  bool get available => root?.isNotEmpty == true && profile?.isNotEmpty == true;
  String get unavailableMessage =>
      'Open Universe Builder from a configured local installation.';
  Future<AppSession> connect() async {
    if (!available) throw StateError('Local connection not configured');
    final client = await LoopbackEngineClient.ensureRunning(
      root: root!,
      profile: ProfileId.parse(profile!),
      helper: helper ?? await LocalEngineClient.siblingEngine(),
      clientName: 'universe-builder-app',
    );
    return AppSession(
      call: client.call,
      close: client.close,
      author: client.welcome.author,
    );
  }
}
