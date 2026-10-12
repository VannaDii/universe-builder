@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_configuration.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/src/configuration.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_values.dart';
import 'package:ub_store/src/revision_input.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  const secret = '\ufeffdisposable-owner';
  final hash = sha256.convert(utf8.encode(secret)).toString();
  final owner = ProfileId.generate();
  late PostgresConfiguration configuration;
  late Connection observer;
  final stores = <PostgresInstallationStore>[];
  final namespaces = <String>{};
  Future<PostgresInstallationStore> open({bool create = false}) async {
    final store = await openPostgresInstallation(configuration, create: create);
    stores.add(store);
    namespaces.add(postgresAuthorityNamespace(store.instanceId));
    return store;
  }

  Matcher failure(InstallationFailure value) => throwsA(
    isA<InstallationException>().having((e) => e.failure, 'failure', value),
  );
  Future<void> enroll(PostgresInstallationStore store) => store.transaction(
    (s) => s.authority.enroll(id: owner, credentialHash: hash),
  );
  Future<InstallationPrincipal> login(PostgresInstallationSession s) =>
      PostgresServiceAuthority(s.authority)
          .authenticate(profile: owner, credential: Credential(secret));
  group(
    'PostgreSQL configured installation ownership',
    () {
      setUp(() async {
        configuration = await BackendConfiguration.resolve(
          environment: {
            'UB_USE_POSTGRES': 'true',
            'UB_POSTGRES_ENDPOINT':
                'postgresql://postgres@127.0.0.1:$port/ub_disposable?sslmode=disable&application_name=ub-disposable-opening&connect_timeout=5',
          },
          allowLoopbackDevelopment: true,
        ) as PostgresConfiguration;
        observer = await Connection.open(
          Endpoint(
            host: '127.0.0.1',
            port: port!,
            database: 'ub_disposable',
            username: 'postgres',
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
      });
      tearDown(() async {
        for (final store in stores) {
          await store.close();
        }
        stores.clear();
        for (final name in namespaces) {
          await observer.execute('DROP SCHEMA IF EXISTS $name CASCADE');
        }
        namespaces.clear();
        await observer.close();
      });
      test(
        'explicit creation, stable reconnect, no overwrite or implicit setup',
        () async {
          await expectLater(
            open(),
            failure(InstallationFailure.identityNotInitialized),
          );
          final store = await open(create: true);
          await enroll(store);
          await store.close();
          final reopened = await open();
          expect(reopened.instanceId, store.instanceId);
          expect((await reopened.transaction(login)).id, owner);
          await expectLater(
            open(create: true),
            failure(InstallationFailure.incompatibleSchema),
          );
          expect((await reopened.transaction(login)).id, owner);
          await reopened.close();
          await expectLater(
            Future.sync(() => reopened.transaction(login)),
            failure(InstallationFailure.unavailable),
          );
        },
      );
      test('provisions full universe, authenticated publication, retry and recovery after reconnect', () async {
        final store = await open(create: true);
        await enroll(store);
        final universe = UniverseId.generate();
        namespaces.add(postgresUniverseSchema(universe));
        final continuity = ContinuityId.generate(),
            principal = PrincipalId.generate();
        final genesis = await store.transaction((s) async {
          final actor = await login(s);
          await PostgresServiceAuthority(s.authority).requireAuthor(actor);
          return s.createUniverse(
            actor: actor.id,
            universe: universe,
            name: 'Disposable cedar',
            continuity: continuity,
            principal: principal,
          );
        });
        final record = RecordId.generate();
        final version = StoredVersion.build(
          RecordVersionId.generate(),
          RecordIdentity(
            universeId: universe,
            recordId: record,
            recordKind: RecordKind.entity,
          ),
          EntityRecord(
            names: [],
            classification: null,
            classificationResolution: ClassificationResolution.unclassified,
            worldAssociations: [],
            labels: {'en': 'Disposable cedar'},
            metadata: {},
          ).toWire(),
        );
        // This internal fixture supplies already-admitted input. It does not
        // qualify the pending engine proposal/validation/approval workflow.
        final input = CommitInput(
          universe: universe,
          continuity: continuity,
          expectedHead: genesis,
          principal: principal,
          decision: 'Admitted disposable input',
          reason: 'Ownership regression',
          idempotencyKey: 'disposable-opening-publication',
          changes: [
            Assignment(recordId: record, expected: null, next: version),
          ],
        );
        Future<RevisionId> publish(PostgresInstallationStore target) =>
            target.transaction((s) async {
              final actor = await login(s);
              return PostgresServiceAuthority(s.authority)
                  .withUniverseAuthority(
                    actor,
                    universe,
                    (_) => s.kernel(universe).commit(input),
                  );
            });
        final revision = await publish(store);
        await store.close();
        final reopened = await open();
        expect(await publish(reopened), revision);
        await reopened.transaction((s) async {
          final actor = await login(s);
          await PostgresServiceAuthority(s.authority).withUniverseAuthority(
            actor,
            universe,
            (_) => s.recovery(universe).rebuild(),
          );
          expect(await s.kernel(universe).journal.head(continuity), revision);
          expect(
            (await s.kernel(universe).journal.load(version.versionId)).payload
                .toText(),
            version.payload.toText(),
          );
          expect(
            (await s.kernel(universe).search(continuity, revision, 'cedar'))
                .map((v) => v.versionId),
            [version.versionId],
          );
        });
      });
      test('failed callback and alias collision leave no partial authority or universe', () async {
        final store = await open(create: true);
        await expectLater(
          store.transaction((s) async {
            await s.authority.enroll(id: owner, credentialHash: hash);
            throw StateError('disposable abort');
          }),
          throwsStateError,
        );
        await enroll(store);
        final first = UniverseId.generate(), second = UniverseId.generate();
        namespaces.addAll([
          postgresUniverseSchema(first),
          postgresUniverseSchema(second),
        ]);
        Future<RevisionId> provision(UniverseId id) => store.transaction(
          (s) => s.createUniverse(
            actor: owner,
            universe: id,
            name: 'Alias collision',
            continuity: ContinuityId.generate(),
            principal: PrincipalId.generate(),
          ),
        );
        await provision(first);
        await expectLater(
          provision(second),
          failure(InstallationFailure.denied),
        );
        expect(
          (await observer.execute(
            'SELECT nspname FROM pg_catalog.pg_namespace WHERE nspname=\$1',
            parameters: [postgresUniverseSchema(second).replaceAll('"', '')],
          )).length,
          0,
        );
        expect(
          (await store.transaction(
            (s) => s.authority.catalog(owner, epochSeconds: BigInt.zero),
          )).map((e) => e.universeId),
          [first],
        );
      });
      test('ambiguous or incompatible control identity is preserved and refused', () async {
        final store = await open(create: true);
        final other = OperationId.generate();
        final otherSchema = postgresAuthorityNamespace(other);
        namespaces.add(otherSchema);
        await observer.runTx((tx) async {
          for (final sql in postgresAuthoritySchema(other)) {
            await tx.execute(sql);
          }
        });
        await expectLater(
          open(),
          failure(InstallationFailure.incompatibleSchema),
        );
        await observer.execute('DROP SCHEMA $otherSchema CASCADE');
        final schema = postgresAuthorityNamespace(store.instanceId);
        await observer.execute(
          "UPDATE $schema.authority SET normalization='unsupported-disposable-version'",
        );
        await expectLater(
          open(),
          failure(InstallationFailure.incompatibleSchema),
        );
        expect(
          (await observer.execute(
            'SELECT normalization FROM $schema.authority',
          )).single.single,
          'unsupported-disposable-version',
        );
        await observer.execute(
          'UPDATE $schema.authority SET normalization=\$1',
          parameters: [selectorNormalizationVersion],
        );
        await observer.execute('DROP TABLE $schema.profiles CASCADE');
        await expectLater(
          open(),
          failure(InstallationFailure.incompatibleSchema),
        );
        expect(
          (await observer.execute('SELECT instance_id FROM $schema.authority'))
              .single
              .single,
          store.instanceId.value,
        );
      });
      test(
        'competing setup connections create exactly one installation',
        () async {
          Future<bool> attempt() async {
            try {
              await open(create: true);
              return true;
            } on InstallationException catch (e) {
              expect(e.failure, InstallationFailure.incompatibleSchema);
              return false;
            }
          }

          final results = await Future.wait([attempt(), attempt()]);
          expect(results.where((v) => v).length, 1);
          final reopened = await open();
          expect(reopened.instanceId, stores.first.instanceId);
        },
      );
      test(
        'close drains admitted transaction and rejects further work',
        () async {
          final store = await open(create: true);
          final entered = Completer<void>(), release = Completer<void>();
          final writing = store.transaction((s) async {
            await s.authority.enroll(id: owner, credentialHash: hash);
            entered.complete();
            await release.future;
            return owner;
          });
          await entered.future;
          final closing = store.close();
          expect(identical(closing, store.close()), isTrue);
          await expectLater(
            store.transaction(login),
            failure(InstallationFailure.unavailable),
          );
          release.complete();
          expect(await writing, owner);
          await closing;
          expect((await (await open()).transaction(login)).id, owner);
        },
      );
      test('certificate loading errors never disclose configured paths or endpoint', () async {
        final bad = PostgresConfiguration(
          Credential(
            'postgresql://disposable:disposable@127.0.0.1:$port/ub_disposable?sslrootcert=/missing-disposable-certificate.pem',
          ),
        );
        await expectLater(
          openPostgresInstallation(bad),
          failure(InstallationFailure.unavailable),
        );
        expect(bad.toString(), isNot(contains('disposable')));
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for the owned disposable PostgreSQL fixture.'
        : false,
  );
}
