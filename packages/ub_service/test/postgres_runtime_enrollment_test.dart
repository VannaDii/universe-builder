@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/postgres_runtime.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/src/postgres_authority_schema.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  group(
    'PostgreSQL protected local enrollment',
    () {
      late Directory directory;
      late PostgresInstallationStore store;
      late NativePostgresRuntime runtime;
      late Connection observer;
      late ProfileId authorId;
      Endpoint endpoint() => Endpoint(
        host: '127.0.0.1',
        port: port!,
        database: 'ub_disposable',
        username: 'postgres',
      );
      const settings = ConnectionSettings(sslMode: SslMode.disable);
      String control() => postgresAuthorityNamespace(store.instanceId);
      Credential credential(ProfileId id) => Credential(
        ProfileCredentialStore.read(root: directory.path, profile: id),
      );
      EngineHello hello(ProfileId id) => EngineHello(
        protocolVersion: protocolVersion,
        profileId: id,
        credential: credential(id),
        clientName: 'Disposable enrollment client',
      );
      Set<String> files() =>
          Directory('${directory.path}/profiles')
              .listSync()
              .map((f) => f.path)
              .toSet();
      Future<ProfileId> enroll(NativePostgresConnection author) async {
        final result = WireFields(
          await author.execute(const EnrollEngineRequest()),
          {'profile_id'},
        );
        return ProfileId.parse(result.string('profile_id'));
      }

      setUp(() async {
        directory = Directory.systemTemp.createTempSync(
          'universe-builder-enrollment-',
        );
        observer = await Connection.open(endpoint(), settings: settings);
        store = await PostgresInstallationStore.create(
          endpoint(),
          settings: settings,
        );
        authorId = await store.transaction(
          (session) =>
              PostgresServiceAuthority(session.authority)
                  .initializeAuthor(profileRoot: directory.path),
        );
        runtime = NativePostgresRuntime(
          store: store,
          profileRoot: directory.path,
        );
      });
      tearDown(() async {
        await runtime.close();
        await store.close();
        try {
          await observer.execute('DROP SCHEMA IF EXISTS ${control()} CASCADE');
        } finally {
          await observer.close();
          directory.deleteSync(recursive: true);
        }
      });

      test('explicit author setup and enrollment publish hashes after durable private secrets without disclosing them', () async {
        final author = await runtime.connect(hello(authorId));
        expect(author.welcome.author, isTrue);
        final id = await enroll(author);
        final secret = credential(id);
        expect(secret.expose().length, 64);
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(secret.expose()), isTrue);
        expect(secret.toString(), '[redacted]');
        final writer = await runtime.connect(hello(id));
        expect(writer.welcome.author, isFalse);
        expect(writer.welcome.principal, id);
        await store.transaction((session) async {
          final profile = (await session.authority.profile(id))!;
          expect(
            profile.credentialHash,
            sha256.convert(utf8.encode(secret.expose())).toString(),
          );
          expect(profile.author, isFalse);
          expect(profile.revoked, isFalse);
          expect(await session.authority.grants(authorId), isEmpty);
        });
        final summaries = (await author.execute(const ProfilesEngineRequest()))
            .toText();
        expect(summaries.contains(secret.expose()), isFalse);
        expect(
          summaries.contains(
            sha256.convert(utf8.encode(secret.expose())).toString(),
          ),
          isFalse,
        );
        expect(files(), hasLength(2));
        for (final path in files()) {
          expect(File(path).statSync().mode & 0x3f, 0);
        }
        final before = files();
        await expectLater(
          store.transaction(
            (session) =>
                PostgresServiceAuthority(session.authority)
                    .initializeAuthor(profileRoot: directory.path),
          ),
          throwsA(
            isA<InstallationException>().having(
              (e) => e.failure,
              'failure',
              InstallationFailure.alreadyEnrolled,
            ),
          ),
        );
        expect(files(), before);
      });

      test('writer enrollment is denied and enrolled credentials retain current revocation through restart', () async {
        var author = await runtime.connect(hello(authorId));
        final id = await enroll(author);
        final writer = await runtime.connect(hello(id));
        final before = files();
        await expectLater(
          enroll(writer),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        expect(files(), before);
        await author.execute(RevokeEngineRequest(profileId: id));
        await expectLater(
          writer.execute(const StatusEngineRequest()),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final instance = store.instanceId;
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(
          store: store,
          profileRoot: directory.path,
        );
        expect(store.instanceId, instance);
        author = await runtime.connect(hello(authorId));
        expect(author.welcome.author, isTrue);
        await expectLater(
          runtime.connect(hello(id)),
          throwsA(
            isA<InstallationException>().having(
              (e) => e.failure,
              'failure',
              InstallationFailure.denied,
            ),
          ),
        );
        expect(files(), before);
      });

      test('missing or invalid configured profile storage cannot publish a credential hash', () async {
        await runtime.close();
        runtime = NativePostgresRuntime(store: store);
        var author = await runtime.connect(hello(authorId));
        final before = files();
        await expectLater(
          enroll(author),
          throwsA(
            isA<InstallationException>().having(
              (e) => e.failure,
              'failure',
              InstallationFailure.unavailable,
            ),
          ),
        );
        final blocked = File('${directory.path}/blocked');
        blocked.writeAsStringSync('disposable regular file');
        await runtime.close();
        runtime = NativePostgresRuntime(
          store: store,
          profileRoot: blocked.path,
        );
        author = await runtime.connect(hello(authorId));
        await expectLater(
          enroll(author),
          throwsA(
            isA<ProfileCredentialException>().having(
              (e) => e.failure,
              'failure',
              ProfileCredentialFailure.unavailable,
            ),
          ),
        );
        expect(files(), before);
        expect(blocked.readAsStringSync(), 'disposable regular file');
        expect(
          (await observer.execute('SELECT count(*) FROM ${control()}.profiles'))
              .single
              .single,
          1,
        );
        expect(
          (await observer.execute('SELECT count(*) FROM ${control()}.audit'))
              .single
              .single,
          1,
        );
      });

      test('failed registry enrollment retains its durable secret without authenticating an unpublished profile', () async {
        final author = await runtime.connect(hello(authorId));
        final before = files();
        await observer.execute(
          'CREATE FUNCTION ${control()}.reject_enrollment() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN IF NEW.action=\'enroll\' THEN RAISE EXCEPTION \'Disposable enrollment failure\'; END IF; RETURN NEW; END \$\$',
        );
        await observer.execute(
          'CREATE TRIGGER reject_enrollment BEFORE INSERT ON ${control()}.audit FOR EACH ROW EXECUTE FUNCTION ${control()}.reject_enrollment()',
        );
        await expectLater(enroll(author), throwsA(isA<ServerException>()));
        final retained = files().difference(before).single;
        final fileName = retained.split(Platform.pathSeparator).last;
        final unpublished = ProfileId.parse(
          fileName.substring(0, fileName.length - '.sqlite'.length),
        );
        expect(credential(unpublished).expose().length, 64);
        expect(
          (await observer.execute('SELECT count(*) FROM ${control()}.profiles'))
              .single
              .single,
          1,
        );
        await expectLater(
          runtime.connect(hello(unpublished)),
          throwsA(
            isA<InstallationException>().having(
              (e) => e.failure,
              'failure',
              InstallationFailure.denied,
            ),
          ),
        );
        await observer.execute(
          'DROP TRIGGER reject_enrollment ON ${control()}.audit',
        );
        await observer.execute(
          'DROP FUNCTION ${control()}.reject_enrollment()',
        );
        final enrolled = await enroll(author);
        expect(
          (await runtime.connect(hello(enrolled))).welcome.author,
          isFalse,
        );
        expect(files(), contains(retained));
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT to a disposable PostgreSQL instance'
        : false,
  );
}
