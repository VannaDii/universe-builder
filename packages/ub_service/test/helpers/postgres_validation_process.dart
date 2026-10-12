import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/postgres_validation.dart';
import 'package:ub_store/postgres_installation.dart';

// Stop at the durable running boundary so the parent can terminate this peer.
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
  final universe = UniverseId.parse(args[2]);
  final operation = OperationId.parse(args[3]);
  if (!await store.acquireValidation(universe, operation)) {
    throw StateError('Validation already owned');
  }
  try {
    final task = await store.transaction((session) async {
      final authority = PostgresServiceAuthority(
        session.authority,
        epochSeconds: () => BigInt.from(100),
      );
      final principal = await authority.authenticate(
        profile: ProfileId.parse(args[1]),
        credential: const Credential('disposable-proposal-profile'),
      );
      return PostgresValidationWorkflow(
        session: session,
        universe: universe,
        authority: authority,
        principal: principal,
        epochSeconds: () => BigInt.from(100),
      ).prepareValidation(operation, isValidationActive: (_) => true);
    });
    if (task == null || task.capture == null) {
      throw StateError('No captured task');
    }
    stdout.writeln(task.capture!.toWire().toText());
    await stdout.flush();
    await stdin.drain<void>();
  } finally {
    await store.releaseValidation(universe, operation);
    await store.close();
  }
}
