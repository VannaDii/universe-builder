@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/src/postgres_authority.dart';
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_journal.dart';
import 'package:ub_store/src/postgres_kernel_schema.dart';
import 'package:ub_store/src/postgres_schema.dart';
import 'package:ub_store/src/postgres_values.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  group(
    'PostgreSQL installation authority',
    () {
      late Connection connection;
      late OperationId instance;
      late UniverseId universe;
      late ProfileId author, writer;
      late String control, namespace;
      final w1 = WorldId.generate(), w2 = WorldId.generate();
      final r1 = RecordId.generate(), r2 = RecordId.generate();
      final continuity = ContinuityId.generate();
      final now = BigInt.from(100);
      Matcher failure(InstallationFailure expected) => throwsA(
        isA<InstallationException>().having(
          (e) => e.failure,
          'failure',
          expected,
        ),
      );
      Future<Connection> open() => Connection.open(
        Endpoint(
          host: '127.0.0.1',
          port: port!,
          database: 'ub_disposable',
          username: 'postgres',
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      Future<T> authority<T>(
        Future<T> Function(PostgresInstallationAuthority) action,
      ) => connection.runTx(
        (tx) => action(PostgresInstallationAuthority(tx, instance)),
      );
      setUp(() async {
        instance = OperationId.generate();
        universe = UniverseId.generate();
        author = ProfileId.generate();
        writer = ProfileId.generate();
        control = postgresAuthorityNamespace(instance);
        namespace = postgresUniverseSchema(universe);
        connection = await open();
        await connection.runTx((tx) async {
          for (final sql in postgresAuthoritySchema(instance)) {
            await tx.execute(sql);
          }
          final store = PostgresInstallationAuthority(tx, instance);
          await store.enroll(id: author, credentialHash: '0' * 64);
          await store.enroll(
            id: writer,
            credentialHash: '1' * 64,
            actor: author,
          );
          await tx.execute('CREATE SCHEMA $namespace');
          for (final sql in [
            ...postgresBodySchema(universe),
            ...postgresKernelSchema(universe),
          ]) {
            await tx.execute(sql);
          }
          await PostgresJournal(tx, universe).initialize(
            '\uFEFFDisposable universe',
            continuity,
            PrincipalId.generate(),
          );
          await store.registerUniverse(
            actor: author,
            universe: universe,
            name: '\uFEFFDisposable universe',
          );
        });
      });
      tearDown(() async {
        try {
          await connection.execute('DROP SCHEMA IF EXISTS $control CASCADE');
          await connection.execute('DROP SCHEMA IF EXISTS $namespace CASCADE');
        } finally {
          await connection.close();
        }
      });
      GrantSpec grant({
        List<WorldId>? worlds,
        GrantLimits? limits,
        bool edit = true,
      }) => GrantSpec(
        profileId: writer,
        universeId: universe,
        worlds: worlds,
        propose: true,
        edit: edit,
        protected: false,
        limits: limits,
      );
      Future<void> put(GrantSpec grant) => authority(
        (store) =>
            store.putGrant(actor: author, grant: grant, epochSeconds: now),
      );

      test(
        'stable identity, profile hashes and typed locators survive reconnect',
        () async {
          await connection.close();
          connection = await open();
          await authority((store) async {
            expect(store.instanceId, instance);
            expect(await store.hasProfiles, isTrue);
            expect(await store.currentAuthor(), author);
            expect((await store.profile(writer))!.credentialHash, '1' * 64);
            expect(
              (await store.profile(writer)).toString(),
              isNot(contains('1' * 64)),
            );
            expect((await store.profiles(author)).length, 2);
            final catalog = await store.resolveUniverseAlias(
              actor: author,
              name: '\uFEFFDISPOSABLE UNIVERSE',
              epochSeconds: now,
            );
            expect(catalog.universeId, universe);
            expect(catalog.name, '\uFEFFDisposable universe');
            expect(catalog.namespace, 'ub_${universe.value}');
          });
          await expectLater(
            authority(
              (store) => store.resolveUniverseAlias(
                actor: writer,
                name: '\uFEFFDisposable universe',
                epochSeconds: now,
              ),
            ),
            failure(InstallationFailure.denied),
          );
          await expectLater(
            authority(
              (store) => store.enroll(
                id: ProfileId.generate(),
                credentialHash: '2' * 64,
              ),
            ),
            failure(InstallationFailure.alreadyEnrolled),
          );
          await expectLater(
            authority(
              (store) => store.enroll(
                id: ProfileId.generate(),
                credentialHash: 'invalid',
                actor: author,
              ),
            ),
            failure(InstallationFailure.incompatibleSchema),
          );
          await expectLater(
            authority((store) => store.revoke(actor: author, target: author)),
            failure(InstallationFailure.denied),
          );
          await expectLater(
            authority(
              (store) => store.enroll(
                id: ProfileId.generate(),
                credentialHash: '2' * 64,
                actor: writer,
              ),
            ),
            failure(InstallationFailure.denied),
          );
        },
      );

      test('ordered scopes and exact unsigned expiry survive replacement and reconnect', () async {
        final original = grant(
          worlds: [w2, w1, w2],
          limits: GrantLimits(
            entities: [r2, r1],
            predicates: [r1],
            continuities: [continuity],
            expiresAt: BigInt.parse('18446744073709551615'),
            delegatedCommit: true,
            allowShared: true,
          ),
        );
        await put(original);
        await connection.close();
        connection = await open();
        await authority((store) async {
          expect(
            (await store.readGrant(writer, universe)).toWire().toText(),
            original.toWire().toText(),
          );
          expect(await store.universeScope(writer, universe, now), {w1, w2});
          expect(
            (await store.grants(author)).single.toWire().toText(),
            original.toWire().toText(),
          );
          await store.authorizeWrite(
            profile: writer,
            universe: universe,
            worlds: {w1},
            shared: false,
            protected: false,
            commit: true,
            epochSeconds: now,
          );
          await expectLater(
            store.authorizeWrite(
              profile: writer,
              universe: universe,
              worlds: {w1},
              shared: true,
              protected: false,
              commit: true,
              epochSeconds: now,
            ),
            failure(InstallationFailure.denied),
          );
          await expectLater(
            store.authorizeWrite(
              profile: writer,
              universe: universe,
              worlds: {w1},
              shared: false,
              protected: true,
              commit: true,
              epochSeconds: now,
            ),
            failure(InstallationFailure.denied),
          );
        });
        await put(grant());
        await authority((store) async {
          expect(
            (await store.readGrant(writer, universe)).toWire().toText(),
            grant().toWire().toText(),
          );
          expect(await store.universeScope(writer, universe, now), isNull);
          expect((await store.limits(writer, universe, now)).entities, isNull);
        });
        for (final table in [
          'grant_worlds',
          'grant_entities',
          'grant_predicates',
          'grant_continuities',
        ]) {
          expect(
            (await connection.execute('SELECT count(*) FROM $control.$table'))
                .single
                .single,
            0,
          );
        }
      });

      test('invalid bounds, expiry and incomplete delegation leave authority unchanged', () async {
        await put(grant(worlds: [w1]));
        final count = await authority(
          (store) async => (await store.audit(author)).length,
        );
        for (final invalid in [
          grant(worlds: []),
          grant(worlds: List.filled(101, w1)),
          grant(limits: GrantLimits(entities: [])),
          grant(limits: GrantLimits(predicates: List.filled(101, r1))),
          grant(limits: GrantLimits(continuities: [])),
          grant(limits: GrantLimits(expiresAt: now)),
          grant(limits: GrantLimits(delegatedCommit: true)),
          grant(
            edit: false,
            limits: GrantLimits(
              entities: [r1],
              predicates: [r2],
              continuities: [continuity],
              expiresAt: now + BigInt.one,
              delegatedCommit: true,
            ),
          ),
        ]) {
          await expectLater(
            put(invalid),
            failure(InstallationFailure.invalidGrant),
          );
        }
        await authority((store) async {
          expect((await store.audit(author)).length, count);
          expect((await store.readGrant(writer, universe)).worlds, [w1]);
        });
        await put(grant(limits: GrantLimits(expiresAt: now + BigInt.one)));
        await expectLater(
          authority(
            (store) => store.universeScope(writer, universe, now + BigInt.one),
          ),
          failure(InstallationFailure.denied),
        );
        await expectLater(
          authority(
            (store) => store.putGrant(
              actor: writer,
              grant: grant(),
              epochSeconds: now,
            ),
          ),
          failure(InstallationFailure.denied),
        );
      });

      test('withdrawal, identical regrant and revocation advance only relevant audit sequence', () async {
        final value = grant(worlds: [w1]);
        await put(value);
        final first = await authority(
          (store) => store.validationAuthoritySequence(writer, universe),
        );
        await authority(
          (store) => store.withdrawGrant(
            actor: author,
            profile: writer,
            universe: universe,
          ),
        );
        final withdrawn = await authority(
          (store) => store.validationAuthoritySequence(writer, universe),
        );
        expect(withdrawn, greaterThan(first));
        await expectLater(
          authority((store) => store.readGrant(writer, universe)),
          failure(InstallationFailure.denied),
        );
        await put(value);
        final restored = await authority(
          (store) => store.validationAuthoritySequence(writer, universe),
        );
        expect(restored, greaterThan(withdrawn));
        await authority(
          (store) => store.withdrawGrant(
            actor: author,
            profile: writer,
            universe: UniverseId.generate(),
          ),
        );
        expect(
          await authority(
            (store) => store.validationAuthoritySequence(writer, universe),
          ),
          restored,
        );
        await authority((store) => store.revoke(actor: author, target: writer));
        expect(
          await authority(
            (store) => store.validationAuthoritySequence(writer, universe),
          ),
          greaterThan(restored),
        );
        await expectLater(
          authority((store) => store.universeScope(writer, universe, now)),
          failure(InstallationFailure.denied),
        );
      });

      test('failed audit append rolls back all grant fields and ordered children', () async {
        final original = grant(
          worlds: [w1],
          limits: GrantLimits(
            entities: [r1],
            predicates: [r2],
            continuities: [continuity],
          ),
        );
        await put(original);
        final before = await authority((store) => store.audit(author));
        await connection.execute(
          "CREATE FUNCTION $control.refuse_audit() RETURNS trigger LANGUAGE plpgsql AS 'BEGIN RAISE EXCEPTION USING ERRCODE = ''P0001'', MESSAGE = ''disposable interruption''; END'",
        );
        await connection.execute(
          'CREATE TRIGGER refuse_audit BEFORE INSERT ON $control.audit FOR EACH ROW EXECUTE FUNCTION $control.refuse_audit()',
        );
        await expectLater(
          put(grant(worlds: [w2], edit: false)),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', 'P0001'),
          ),
        );
        await connection.execute('DROP TRIGGER refuse_audit ON $control.audit');
        await authority((store) async {
          expect(
            (await store.readGrant(writer, universe)).toWire().toText(),
            original.toWire().toText(),
          );
          expect((await store.audit(author)).length, before.length);
        });
        await put(original);
        final after = await authority((store) => store.audit(author));
        expect(
          after[before.length].sequence,
          before.last.sequence + BigInt.one,
        );
      });

      test('authority lock excludes grant insertion, withdrawal, revocation and author change', () async {
        final entered = Completer<void>(), resume = Completer<void>();
        final held = authority((store) async {
          final sequence = await store.validationAuthoritySequence(
            writer,
            universe,
          );
          await expectLater(
            store.readGrant(writer, universe),
            failure(InstallationFailure.denied),
          );
          entered.complete();
          await resume.future;
          expect(
            await store.validationAuthoritySequence(writer, universe),
            sequence,
          );
          expect((await store.profile(writer))!.revoked, isFalse);
          await store.requireAuthor(author);
        });
        await entered.future;
        final contender = await open();
        try {
          for (final operation in [0, 1, 2, 3]) {
            await expectLater(
              contender.runTx((tx) async {
                await tx.execute("SET LOCAL lock_timeout='100ms'");
                final store = PostgresInstallationAuthority(tx, instance);
                switch (operation) {
                  case 0:
                    await store.putGrant(
                      actor: author,
                      grant: grant(),
                      epochSeconds: now,
                    );
                  case 1:
                    await store.withdrawGrant(
                      actor: author,
                      profile: writer,
                      universe: universe,
                    );
                  case 2:
                    await store.revoke(actor: author, target: writer);
                  case 3:
                    await store.lockAuthority();
                    await tx.execute(
                      'UPDATE $control.profiles SET author=FALSE WHERE id=\$1',
                      parameters: [author.value],
                    );
                }
              }),
              throwsA(
                isA<ServerException>().having((e) => e.code, 'code', '55P03'),
              ),
            );
          }
        } finally {
          await contender.close();
          resume.complete();
        }
        await held;
        await put(grant());
        await authority((store) => store.revoke(actor: author, target: writer));
        await expectLater(
          authority((store) => store.universeScope(writer, universe, now)),
          failure(InstallationFailure.denied),
        );
      });

      test('catalog disclosure follows grants and renames retain historical aliases', () async {
        expect(
          await authority((store) => store.catalog(writer, epochSeconds: now)),
          isEmpty,
        );
        await put(grant());
        expect(
          (await authority((store) => store.catalog(writer, epochSeconds: now)))
              .single
              .universeId,
          universe,
        );
        await expectLater(
          authority(
            (store) => store.renameUniverse(
              actor: writer,
              id: universe,
              name: 'Denied',
            ),
          ),
          failure(InstallationFailure.denied),
        );
        await authority(
          (store) => store.renameUniverse(
            actor: author,
            id: universe,
            name: '\uFEFFRenamed',
          ),
        );
        await authority((store) async {
          for (final name in ['\uFEFFDisposable universe', '\uFEFFRENAMED']) {
            final entry = await store.resolveUniverseAlias(
              actor: writer,
              name: name,
              epochSeconds: now,
            );
            expect(entry.universeId, universe);
            expect(entry.name, '\uFEFFRenamed');
            expect(entry.namespace, 'ub_${universe.value}');
          }
        });
        await authority(
          (store) => store.withdrawGrant(
            actor: author,
            profile: writer,
            universe: universe,
          ),
        );
        expect(
          await authority((store) => store.catalog(writer, epochSeconds: now)),
          isEmpty,
        );
        expect(
          (await authority((store) => store.catalog(author, epochSeconds: now)))
              .single
              .name,
          '\uFEFFRenamed',
        );
        await expectLater(
          authority(
            (store) => store.renameUniverse(
              actor: author,
              id: UniverseId.generate(),
              name: '\uFEFFDisposable universe',
            ),
          ),
          failure(InstallationFailure.denied),
        );
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for disposable ub_disposable database.'
        : false,
  );
}
