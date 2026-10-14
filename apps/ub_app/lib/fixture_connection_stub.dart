import 'fixture_workspace.dart';

final class FixtureDevice {
  FixtureDevice(List<String> arguments);
  Future<FixtureTransport> start() => Future.error(
    UnsupportedError(
      'The disposable fixture is a desktop mode. Connect to an instance to use the author workspace.',
    ),
  );
}
