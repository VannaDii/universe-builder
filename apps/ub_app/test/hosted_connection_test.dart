@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

import '../../../packages/ub_service/test/fixtures/tls_fixture.dart';

void main() {
  test('native hosted sessions retain scoped input without storing credentials or starting local canon', () async {
    final temporary = Directory.systemTemp.createTempSync('ub-hosted-app-');
    final tls = await generateTlsFixture(temporary);
    final serverRoot = '${temporary.path}/server',
        clientRoot = '${temporary.path}/client';
    final store = SqliteInstallationStore.create(serverRoot);
    final owner = InstallationAuthority(store).initializeAuthor();
    store.close();
    final secret = ProfileCredentialStore.read(
      root: serverRoot,
      profile: owner,
    );
    Future<LocalSqliteEngineServer> start() => LocalSqliteEngineServer.start(
      serverRoot,
      compatibilitySocket: false,
      httpsOrigin: Uri.parse('https://localhost:0'),
      bindAddress: InternetAddress.loopbackIPv4,
      tlsContext: SecurityContext()
        ..useCertificateChain(tls.certificate)
        ..usePrivateKey(tls.privateKey),
    );
    var server = await start();
    final device = DeviceConnection(
      ['--installation', clientRoot, '--engine=/nonexistent'],
      embeddedLocal: true,
      hostedSecurityContext: SecurityContext()..setTrustedCertificates(tls.ca),
    );
    HostedConnectionChoice choice() => HostedConnectionChoice(
      endpoint: server.httpsEndpoint!,
      profile: owner,
      credential: Credential(secret),
    );
    device.hosted = choice();
    AppSession? session;
    try {
      session = await device.connect();
      expect(session.principal, owner);
      expect(device.isHosted, isTrue);
      expect(device.supportsLocalSettings, isFalse);
      expect(session.pickImage, isNull);
      expect(session.backupFile, isNull);
      expect(session.pickArchiveFile, isNull);
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            name: 'Hosted memoir',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final status = InstanceLibrary.fromWire(
        await session.call(const StatusEngineRequest()),
      );
      final scope = EditorFormScope(
        instance: status.instance,
        profile: owner,
        universe: UniverseId.parse(created.string('universe_id')),
        continuity: ContinuityId.parse(created.string('continuity_id')),
        representedContext: RecordId.parse(created.string('context_id')),
      );
      final input = UnfinishedSourceForm(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        clientRef: 'hosted source',
        label: 'Firsthand memory',
        text: '\uFEFF記憶 café 😀\r\n',
      );
      await session.saveSourceForm(scope, input, BigInt.zero);
      await session.close();
      session = null;
      await server.close();
      server = await start();
      device.hosted = choice();
      session = await device.connect();
      expect(
        (await session.loadSourceForm(scope))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      await expectLater(
        session.loadSourceForm(
          EditorFormScope(
            instance: OperationId.generate(),
            profile: owner,
            universe: scope.universe,
            continuity: scope.continuity,
            representedContext: scope.representedContext,
          ),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await session.logout!();
      expect(device.hosted, isNull);
      expect(File('$clientRoot/installation.sqlite').existsSync(), isFalse);
      expect(File('$clientRoot/device-profile').existsSync(), isFalse);
      for (final file in Directory(
        clientRoot,
      ).listSync(recursive: true).whereType<File>()) {
        expect(latin1.decode(file.readAsBytesSync()).contains(secret), isFalse);
      }
    } finally {
      await session?.close();
      await server.close();
      temporary.deleteSync(recursive: true);
    }
  });
}
