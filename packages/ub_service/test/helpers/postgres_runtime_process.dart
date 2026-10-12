import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/postgres_runtime.dart';
import 'package:ub_store/postgres_installation.dart';

// Disposable functional-test peer. Production transport is exercised separately.
Future<void> main(List<String> args) async {
  final store = await PostgresInstallationStore.openExisting(
    Endpoint(
      host: '127.0.0.1',
      port: int.parse(args[0]),
      database: 'ub_disposable',
      username: 'postgres',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  final runtime = NativePostgresRuntime(store: store);
  try {
    final connection = await runtime.connect(
      EngineHello(
        protocolVersion: protocolVersion,
        profileId: ProfileId.parse(args[1]),
        credential: const Credential('disposable-process-profile'),
        clientName: 'Disposable process peer',
      ),
    );
    stdout.writeln('ready');
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      try {
        final result = await connection.execute(
          EngineRequest.fromWire(CanonicalValue.parseJson(line)),
        );
        stdout.writeln(jsonEncode({'result': result.toText()}));
      } on Object catch (error) {
        stdout.writeln(jsonEncode({'error': error.runtimeType.toString()}));
      }
    }
  } finally {
    await runtime.close();
    await store.close();
  }
}
