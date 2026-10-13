@TestOn('vm && mac-os')
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_configuration.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/native_credentials.dart';
import 'package:ub_service/ub_service.dart';
import 'package:ub_store/local_settings.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  final certificate = Platform.environment['UB_TEST_POSTGRES_TLS_ROOT_CERT'];
  test(
    'device tests PostgreSQL author access without saving and explicitly saves and reconnects to the same instance',
    () async {
      final root = Directory('/tmp').createTempSync('ub-app-postgres-');
      final database =
          'ub_app_${OperationId.generate().value.replaceAll('-', '')}';
      final observer = await Connection.open(
        Endpoint(
          host: '127.0.0.1',
          port: port!,
          database: 'ub_disposable',
          username: 'postgres',
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      var created = false;
      String? reference;
      LocalPostgresEngineServer? server;
      AppSession? session;
      try {
        await observer.execute('CREATE DATABASE $database');
        created = true;
        final endpoint =
            'postgresql://postgres@127.0.0.1:$port/$database?sslmode=verify-full&sslrootcert=${Uri.encodeQueryComponent(certificate!)}';
        final configuration = PostgresConfiguration(Credential(endpoint));
        final store = await openPostgresInstallation(
          configuration,
          create: true,
        );
        final instance = store.instanceId;
        late ProfileId author;
        try {
          author = await store.transaction(
            (s) =>
                PostgresServiceAuthority(s.authority)
                    .initializeAuthor(profileRoot: root.path),
          );
        } finally {
          await store.close();
        }
        final device = DeviceConnection([
          '--installation',
          root.path,
          '--engine=/nonexistent/universe-engine',
        ]);
        final tested = await device.testPostgres(endpoint);
        expect(tested.instance, instance);
        expect(tested.profile, author);
        expect(tested.toString(), isNot(contains(endpoint)));
        expect(File('${root.path}/settings.sqlite').existsSync(), isFalse);
        expect(DeviceProfileStore.read(root.path), isNull);
        await device.savePostgres(tested);
        expect(DeviceProfileStore.read(root.path), author);
        final settings = LocalSettingsStore.openExisting(
          '${root.path}/settings.sqlite',
        );
        try {
          reference = settings.read().endpoint!.keyReference;
          final saved = await LocalBackendConfiguration.resolve(
            environment: {},
            settings: settings,
          );
          expect((saved as PostgresConfiguration).endpoint.expose(), endpoint);
        } finally {
          settings.close();
        }
        server = await LocalPostgresEngineServer.start(
          root.path,
          configuration,
        );
        session = await device.connect();
        expect(session.author, isTrue);
        expect(session.principal, author);
        final library = InstanceLibrary.fromWire(
          await session.call(const StatusEngineRequest()),
        );
        expect(library.instance, instance);
        expect(library.backend, ConnectedBackend.postgres);
        await session.call(const ShutdownEngineRequest());
        await session.close();
        session = null;
        await server.done;
        await server.close();
        server = null;
        File('${root.path}/profiles/${author.value}.sqlite').deleteSync();
        await expectLater(
          device.testPostgres(endpoint),
          throwsA(isA<ProfileCredentialException>()),
        );
        expect(DeviceProfileStore.read(root.path), author);
        expect(File('${root.path}/installation.sqlite').existsSync(), isFalse);
      } finally {
        try {
          await session?.close();
          await server?.close();
        } finally {
          try {
            if (reference != null) {
              await const NativeInstallationKeyStore().remove(reference);
            }
          } finally {
            try {
              if (created) await observer.execute('DROP DATABASE $database');
            } finally {
              await observer.close();
              root.deleteSync(recursive: true);
            }
          }
        }
      }
    },
    skip: port == null || certificate == null
        ? 'Requires disposable PostgreSQL with UB_TEST_POSTGRES_TLS_ROOT_CERT'
        : false,
  );
}
