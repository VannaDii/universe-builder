import 'connection.dart';

final class DeviceConnection {
  bool get supportsLocal => false;
  DeviceConnection(List<String> arguments);
  bool get available => false;
  String get unavailableMessage =>
      'Web access requires a connection to an authenticated instance.';
  Future<AppSession> connect() =>
      Future.error(StateError('Local engine unavailable'));
}
