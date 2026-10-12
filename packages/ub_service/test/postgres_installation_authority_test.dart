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
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/src/owned_database.dart';
import 'package:ub_store/src/journal.dart';
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
  const ownerSecret = 'disposable-author',
      writerSecret = '\ufeffdisposable-writer';
  String hash(String secret) => sha256.convert(utf8.encode(secret)).toString();
  final universe = UniverseId.generate();
  final world = WorldId.generate();
  late Connection connection;
  late OperationId instance;
  late ProfileId owner, writer;
  late String control;
  final schema = postgresUniverseSchema(universe);
  var now = BigInt.from(100);
  Future<Connection> connect() => Connection.open(
    Endpoint(
      host: '127.0.0.1',
      port: port!,
      database: 'ub_disposable',
      username: 'postgres',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  Future<T> session<T>(Future<T> Function(PostgresServiceAuthority) action) =>
      connection.runTx(
        (tx) => action(
          PostgresServiceAuthority(
            PostgresInstallationAuthority(tx, instance),
            epochSeconds: () => now,
          ),
        ),
      );
  Future<InstallationPrincipal> login(ProfileId profile, String secret) =>
      session(
        (authority) => authority.authenticate(
          profile: profile,
          credential: Credential(secret),
        ),
      );
  final denied = throwsA(
    isA<InstallationException>().having(
      (e) => e.failure,
      'failure',
      InstallationFailure.denied,
    ),
  );
  GrantSpec grant({BigInt? expiry, bool propose = true}) => GrantSpec(
    profileId: writer,
    universeId: universe,
    worlds: [world],
    propose: propose,
    edit: true,
    protected: false,
    limits: GrantLimits(
      entities: [RecordId.parse('rec_000000000000000000000001')],
      expiresAt: expiry,
    ),
  );
  Future<void> put(GrantSpec grant) async {
    final actor = await login(owner, ownerSecret);
    await session((authority) => authority.putGrant(actor, grant));
  }

  group(
    'PostgreSQL service authority',
    () {
      setUp(() async {
        now = BigInt.from(100);
        instance = OperationId.generate();
        owner = ProfileId.generate();
        writer = ProfileId.generate();
        control = postgresAuthorityNamespace(instance);
        connection = await connect();
        await connection.runTx((tx) async {
          for (final sql in postgresAuthoritySchema(instance)) {
            await tx.execute(sql);
          }
          final store = PostgresInstallationAuthority(tx, instance);
          await store.enroll(id: owner, credentialHash: hash(ownerSecret));
          await store.enroll(
            id: writer,
            credentialHash: hash(writerSecret),
            actor: owner,
          );
          await tx.execute('CREATE SCHEMA $schema');
          for (final sql in [
            ...postgresBodySchema(universe),
            ...postgresKernelSchema(universe),
          ]) {
            await tx.execute(sql);
          }
          await PostgresJournal(tx, universe).initialize(
            'Disposable authority',
            ContinuityId.generate(),
            PrincipalId.generate(),
          );
          await store.registerUniverse(
            actor: owner,
            universe: universe,
            name: 'Disposable authority',
          );
        });
      });
      tearDown(() async {
        try {
          await connection.execute('DROP SCHEMA IF EXISTS $control CASCADE');
          await connection.execute('DROP SCHEMA IF EXISTS $schema CASCADE');
        } finally {
          await connection.close();
        }
      });

      test('exact BOM credentials authenticate; malformed, unknown and revoked credentials share denial', () async {
        final principal = await login(writer, writerSecret);
        expect(principal.id, writer);
        expect(principal.instanceId, instance);
        expect(principal.author, isFalse);
        for (final secret in [
          'disposable-writer',
          '\ufeff$writerSecret',
          'wrong',
          '\ud800',
        ]) {
          await expectLater(login(writer, secret), denied);
        }
        await expectLater(login(ProfileId.generate(), writerSecret), denied);
        final actor = await login(owner, ownerSecret);
        await session((authority) => authority.revoke(actor, writer));
        await expectLater(login(writer, writerSecret), denied);
        await expectLater(
          session(
            (authority) => authority.coordinate(principal, () async => true),
          ),
          denied,
        );
        final summaries = await session(
          (authority) => authority.profiles(actor),
        );
        expect(summaries.singleWhere((p) => p.id == writer).revoked, isTrue);
        expect(summaries, hasLength(2));
      });

      test('handshake checks protocol and byte bounds, and reauthenticates after revocation', () async {
        EngineHello hello({String? name, String? version}) => EngineHello(
          protocolVersion: version ?? protocolVersion,
          profileId: writer,
          credential: const Credential(writerSecret),
          clientName: name ?? 'External writer',
        );
        expect(
          (await session((authority) => authority.authenticateHello(hello())))
              .id,
          writer,
        );
        for (final message in [
          hello(version: 'unsupported'),
          hello(name: 'é' * 65),
          hello(name: '\ud800'),
        ]) {
          await expectLater(
            session((authority) => authority.authenticateHello(message)),
            throwsFormatException,
          );
        }
        final actor = await login(owner, ownerSecret);
        await session((authority) => authority.revoke(actor, writer));
        await expectLater(
          session((authority) => authority.authenticateHello(hello())),
          denied,
        );
      });

      test('SQLite and PostgreSQL produce identical live scope and validation captures', () async {
        final specification = grant(expiry: BigInt.from(1000));
        await put(specification);
        final principal = await login(writer, writerSecret);
        final current = await session(
          (authority) => authority.withUniverseAuthority(
            principal,
            universe,
            (current) async => current,
          ),
        );
        final directory = Directory.systemTemp.createTempSync(
          'universe-builder-authority-parity-',
        );
        final sqlite = SqliteInstallationStore.create(directory.path);
        try {
          sqlite.enroll(id: owner, credentialHash: hash(ownerSecret));
          sqlite.enroll(
            id: writer,
            credentialHash: hash(writerSecret),
            actor: owner,
          );
          final path = '${directory.path}/packages/universe.sqlite';
          final package = OwnedSqliteDatabase.create(path);
          try {
            package.database.execute('BEGIN IMMEDIATE');
            SqliteJournal(package.database, universe).initialize(
              'Disposable authority',
              ContinuityId.generate(),
              PrincipalId.generate(),
            );
            package.database.execute('COMMIT');
          } finally {
            package.close();
          }
          final native = InstallationAuthority(sqlite, epochSeconds: () => now);
          final author = native.authenticate(
            profile: owner,
            credential: const Credential(ownerSecret),
          );
          native.registerUniverse(
            author,
            name: 'Disposable authority',
            path: path,
          );
          native.grant(author, specification);
          final writerPrincipal = native.authenticate(
            profile: writer,
            credential: const Credential(writerSecret),
          );
          await native.withUniverseAuthority(writerPrincipal, universe, (
            other,
          ) {
            expect(current.scopeHash, other.scopeHash);
            expect(current.validationDigest, other.validationDigest);
            expect(current.sequence, other.sequence);
            expect(current.approvalAuthor, other.approvalAuthor);
            expect(current.permissions, other.permissions);
            expect(current.worldScope, other.worldScope);
            expect(
              current.limits.toWire().toText(),
              other.limits.toWire().toText(),
            );
          });
        } finally {
          sqlite.close();
          directory.deleteSync(recursive: true);
        }
      });

      test(
        'captures recheck expiry, grant replacement and base write permissions',
        () async {
          await put(grant(expiry: BigInt.from(101)));
          final principal = await login(writer, writerSecret);
          Future<CurrentUniverseAuthority> capture() => session(
            (authority) => authority.withUniverseAuthority(
              principal,
              universe,
              (current) async => current,
            ),
          );
          final first = await capture();
          await put(grant(expiry: BigInt.from(101)));
          final next = await capture();
          expect(next.validationDigest, first.validationDigest);
          expect(next.sequence, greaterThan(first.sequence));
          await session(
            (authority) => authority.authorizeWrite(
              principal,
              universe: universe,
              worlds: {world},
              shared: false,
              protected: false,
              commit: true,
            ),
          );
          await expectLater(
            session(
              (authority) => authority.authorizeWrite(
                principal,
                universe: universe,
                worlds: {},
                shared: true,
                protected: false,
                commit: true,
              ),
            ),
            denied,
          );
          now = BigInt.from(101);
          await expectLater(capture(), denied);
          await expectLater(
            session((authority) => authority.limits(principal, universe)),
            denied,
          );
          now = BigInt.from(100);
          await put(grant(propose: false));
          await expectLater(
            session(
              (authority) => authority.authorizeWrite(
                principal,
                universe: universe,
                worlds: {world},
                shared: false,
                protected: false,
                commit: false,
              ),
            ),
            denied,
          );
          final author = await login(owner, ownerSecret);
          await session(
            (authority) => authority.withdrawGrant(author, writer, universe),
          );
          await expectLater(capture(), denied);
        },
      );

      test('same restored profile cannot reuse a principal in another installation', () async {
        final principal = await login(owner, ownerSecret);
        final other = OperationId.generate();
        final otherControl = postgresAuthorityNamespace(other);
        try {
          await connection.runTx((tx) async {
            for (final sql in postgresAuthoritySchema(other)) {
              await tx.execute(sql);
            }
            final store = PostgresInstallationAuthority(tx, other);
            await store.enroll(id: owner, credentialHash: hash(ownerSecret));
            final authority = PostgresServiceAuthority(store);
            await expectLater(authority.requireAuthor(principal), denied);
            await expectLater(
              authority.coordinate(principal, () async => true),
              denied,
            );
            expect(
              (await authority.authenticate(
                profile: owner,
                credential: const Credential(ownerSecret),
              )).instanceId,
              other,
            );
          });
        } finally {
          await connection.execute(
            'DROP SCHEMA IF EXISTS $otherControl CASCADE',
          );
        }
      });

      test(
        'authority callback holds its lock against concurrent revocation',
        () async {
          await put(grant());
          final principal = await login(writer, writerSecret),
              actor = await login(owner, ownerSecret);
          final other = await connect();
          final entered = Completer<void>(), release = Completer<void>();
          final active = session(
            (authority) => authority.withUniverseAuthority(
              principal,
              universe,
              (current) async {
                entered.complete();
                await release.future;
                return current.sequence;
              },
            ),
          );
          try {
            await entered.future;
            await expectLater(
              other.runTx((tx) async {
                await tx.execute("SET LOCAL lock_timeout='100ms'");
                await PostgresServiceAuthority(
                  PostgresInstallationAuthority(tx, instance),
                ).revoke(actor, writer);
              }),
              throwsA(
                isA<ServerException>().having(
                  (e) => e.code,
                  'authority lock',
                  '55P03',
                ),
              ),
            );
          } finally {
            release.complete();
            await active;
            await other.close();
          }
          await session((authority) => authority.revoke(actor, writer));
          await expectLater(
            session(
              (authority) => authority.withUniverseAuthority(
                principal,
                universe,
                (current) async => current,
              ),
            ),
            denied,
          );
        },
      );
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for disposable ub_disposable database.'
        : false,
  );
}
