@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_client/loopback_engine.dart';
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
    String? selectedImage;
    var saveSelection = true;
    final selectedArchive = '${temporary.path}/selected-archive.sqlite';
    final device = DeviceConnection(
      ['--installation', clientRoot, '--engine=/nonexistent'],
      embeddedLocal: true,
      hostedSecurityContext: SecurityContext()..setTrustedCertificates(tls.ca),
      pickImagePath: () async => selectedImage,
      releasePickedPath: (path) async => File(path).deleteSync(),
      saveBackupFile: (path) async {
        if (!saveSelection) return null;
        await File(path).copy(selectedArchive);
        return selectedArchive;
      },
      openBackupFile: (path) async {
        await File(selectedArchive).copy(path);
        return true;
      },
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
      expect(session.pickImage, isNotNull);
      expect(session.backupFile, isNull);
      expect(session.pickArchiveFile, isNotNull);
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            realWorld: false,
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
      expect(await session.pickImage!(const Selector('Hosted memoir')), isNull);
      final image = File('${temporary.path}/portrait.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwHwQBEPgD/U6VwW8AAAAASUVORK5CYII=',
          ),
        );
      selectedImage = image.path;
      final staged = (await session.pickImage!(
        const Selector('Hosted memoir'),
      ))!;
      expect(staged.asset.originalName, 'portrait.png');
      expect(staged.asset.width, 2);
      expect(image.existsSync(), isFalse);
      final invalid = File('${temporary.path}/invalid.png')
        ..writeAsStringSync('invalid image');
      selectedImage = invalid.path;
      await expectLater(
        session.pickImage!(const Selector('Hosted memoir')),
        throwsA(isA<ProtocolError>()),
      );
      expect(invalid.existsSync(), isFalse);
      final oversized = File('${temporary.path}/large.png')
          .openSync(mode: FileMode.write);
      oversized.truncateSync(10 * 1024 * 1024 + 1);
      oversized.closeSync();
      selectedImage = '${temporary.path}/large.png';
      await expectLater(
        session.pickImage!(const Selector('Hosted memoir')),
        throwsA(
          isA<LocalEngineException>().having(
            (e) => e.failure,
            'failure',
            LocalEngineFailure.invalidRequest,
          ),
        ),
      );
      expect(File(selectedImage).existsSync(), isFalse);
      expect(
        await session.saveArchiveFile!(
          LibraryEntry(scope.universe, 'Hosted memoir'),
        ),
        selectedArchive,
      );
      expect(File(selectedArchive).lengthSync(), greaterThan(0));
      saveSelection = false;
      expect(
        await session.saveArchiveFile!(
          LibraryEntry(scope.universe, 'Hosted memoir'),
        ),
        isNull,
      );
      expect(Directory('$clientRoot/client-files').listSync(), isEmpty);
      final importInput = PackageImportDraft(
        operation: OperationId.generate(),
        name: 'Hosted clone',
      );
      final selected = (await session.pickArchiveFile!())!;
      final review = await session.reviewArchiveFile!(
        selected,
        importInput,
      ) as CanonicalObject;
      await selected.release!();
      expect(Directory('$clientRoot/client-files').listSync(), isEmpty);
      expect(
        InstanceLibrary.fromWire(
          await session.call(const StatusEngineRequest()),
        ).universes,
        hasLength(1),
      );
      await session.savePackageImport!(
        importInput.copyWith(phase: PackageImportPhase.review, review: review),
        BigInt.zero,
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
      final recoveredImport = (await session.loadPackageImport!())!.form;
      expect(recoveredImport.review!.toText(), review.toText());
      final imported = Map.fromEntries(
        (await session.call(
          recoveredImport.admission(),
        ) as CanonicalObject).fields,
      );
      expect((imported['imported'] as CanonicalBool).value, isTrue);
      expect(wireString(imported['universe_id']!), isNot(scope.universe.value));
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
