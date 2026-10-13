import 'connection.dart';

final class DeviceConnection {
  bool get supportsLocal => false;
  DeviceConnection(List<String> arguments);
  bool get available => false;
  String get unavailableMessage =>
      'Web access requires a connection to an authenticated instance.';
  Future<AppSession> connect() =>
      Future.error(StateError('Local engine unavailable'));
  Future<TestedPostgresConnection> testPostgres(String endpoint) =>
      Future.error(StateError('Local setup unavailable'));
  Future<void> savePostgres(TestedPostgresConnection choice) =>
      Future.error(StateError('Local setup unavailable'));
  Future<TestedSqliteConnection> testSqlite() =>
      Future.error(StateError('Local setup unavailable'));
  Future<void> saveSqlite(TestedSqliteConnection choice) =>
      Future.error(StateError('Local setup unavailable'));
}
