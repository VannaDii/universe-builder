@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart' hide Description;
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/postgres_runtime.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/loopback_engine.dart';
import 'package:ub_service/ub_service.dart' show PostgresConfiguration;
import 'package:ub_store/installation.dart';
import 'package:ub_store/local_http_endpoint.dart';
import 'package:ub_store/ub_store.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/sqlite.dart' as local;
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_values.dart';

import 'operation_compilation_test.dart' as f;
import 'effective_objects_test.dart' as objects;
import 'writing_units_test.dart' as units;
import 'writing_event_edits_test.dart' as event_edits;

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  late PostgresInstallationStore store;
  late NativePostgresRuntime runtime;
  late Connection observer;
  late ProfileId authorId, writerId;
  final universes = <UniverseId>[];
  const secret = 'disposable-engine-profile';
  const selector = Selector('Disposable engine universe');
  Endpoint endpoint() => Endpoint(
    host: '127.0.0.1',
    port: port!,
    database: 'ub_disposable',
    username: 'postgres',
  );
  const settings = ConnectionSettings(sslMode: SslMode.disable);
  EngineHello hello(
    ProfileId id, {
    String version = protocolVersion,
    String credential = secret,
  }) => EngineHello(
    protocolVersion: version,
    profileId: id,
    credential: Credential(credential),
    clientName: 'Disposable PostgreSQL engine client',
  );
  Future<T> tool<T>(
    NativePostgresConnection connection,
    Request request,
    T Function(CanonicalValue) decode,
  ) async => Envelope.fromWire(
    await connection.execute(ToolEngineRequest(request: request)),
    decode,
  ).result;

  group(
    'PostgreSQL engine integration',
    () {
      setUp(() async {
        universes.clear();
        observer = await Connection.open(endpoint(), settings: settings);
        store = await PostgresInstallationStore.create(
          endpoint(),
          settings: settings,
        );
        authorId = ProfileId.generate();
        writerId = ProfileId.generate();
        await store.transaction((s) async {
          final hash = sha256.convert(utf8.encode(secret)).toString();
          await s.authority.enroll(id: authorId, credentialHash: hash);
          await s.authority.enroll(
            id: writerId,
            credentialHash: hash,
            actor: authorId,
          );
        });
        runtime = NativePostgresRuntime(store: store);
      });
      tearDown(() async {
        await runtime.close();
        await store.close();
        try {
          for (final universe in universes) {
            await observer.execute(
              'DROP SCHEMA IF EXISTS ${postgresUniverseSchema(universe)} CASCADE',
            );
          }
          await observer.execute(
            'DROP SCHEMA IF EXISTS ${postgresAuthorityNamespace(store.instanceId)} CASCADE',
          );
        } finally {
          await observer.close();
        }
      });
      test('local PostgreSQL server owns discovery and drains on author shutdown without SQLite fallback', () async {
      await runtime.close();
      await store.close();
      final root = Directory('/tmp').createTempSync('ub-pg-http-');
      final configuration = PostgresConfiguration(
        Credential(
          'postgresql://postgres@127.0.0.1:$port/ub_disposable?sslmode=disable',
        ),
        allowLoopbackDevelopment: true,
      );
      LocalPostgresEngineServer? server;
      final http = HttpClient();
      var next = BigInt.one;
      Future<EngineResult> call(
        ProfileId profile,
        EngineRequest command,
      ) async {
        final id = next;
        next += BigInt.one;
        final request = await http.postUrl(
          server!.httpEndpoint.resolve('/engine/call'),
        );
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'UB ${base64Encode(hello(profile).toWire().toBytes())}',
        );
        request.add(EngineCall(id: id, request: command).toWire().toBytes());
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          bytes.add(chunk);
        }
        final reply = EngineReply.decode(bytes.takeBytes());
        expect(reply.id, id);
        return reply.result;
      }

      try {
        server = await LocalPostgresEngineServer.start(
          root.path,
          configuration,
        );
        expect(readLocalHttpEndpoint(root.path), server.httpEndpoint);
        await expectLater(
          LocalPostgresEngineServer.start(root.path, configuration),
          throwsA(isA<LocalEngineServerException>()),
        );
        expect(readLocalHttpEndpoint(root.path), server.httpEndpoint);
        final status = (await call(
          authorId,
          const StatusEngineRequest(),
        ) as EngineSuccess).value;
        expect(
          wireString(
            (status as CanonicalObject).fields
                .singleWhere((entry) => entry.key == 'backend').value,
          ),
          'postgres',
        );
        expect(
          WireFields(status, {
            'instance_id',
            'service_instance',
            'universes',
            'canonical_commit',
            'backend',
            'max_requests_per_principal',
            'universe_queue_capacity',
          }).string('instance_id'),
          store.instanceId.value,
        );
        final created = WireFields(
          (await call(
            authorId,
            const CreateUniverseEngineRequest(
              name: 'PostgreSQL local server universe',
              start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
            ),
          ) as EngineSuccess).value,
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        universes.add(UniverseId.parse(created.string('universe_id')));
        expect(
          await call(writerId, const ShutdownEngineRequest()),
          isA<EngineFailure>(),
        );
        expect(readLocalHttpEndpoint(root.path), server.httpEndpoint);
        expect(
          await call(authorId, const ShutdownEngineRequest()),
          isA<EngineSuccess>(),
        );
        await server.done.timeout(const Duration(seconds: 10));
        expect(File('${root.path}/engine-http.json').existsSync(), isFalse);
        expect(File('${root.path}/installation.sqlite').existsSync(), isFalse);
        server = await LocalPostgresEngineServer.start(
          root.path,
          configuration,
        );
        final reopened = (await call(
          authorId,
          const StatusEngineRequest(),
        ) as EngineSuccess).value;
        expect(reopened.toText(), contains(created.string('universe_id')));
      } finally {
        http.close(force: true);
        await server?.close();
        root.deleteSync(recursive: true);
      }
    });
    test('PostgreSQL logical export streams multiple pages and preserves filtered typed dependencies without workflow authority', () async {
        final author = await runtime.connect(hello(authorId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final continuity = ContinuityId.parse(created.string('continuity_id'));
        final base = RevisionId.parse(created.string('revision'));
        final represented = RecordId.parse(created.string('context_id'));
        final worldId = f.id(60), typeId = f.id(61);
        final world = recordWorld(worldId);
        final payloads = <RecordId, RecordPayload>{
          worldId: WorldRecord(selector: 'Campaign é😀'),
          typeId: f.type(61),
          for (var n = 100; n < 170; n++)
            f.id(n): EntityRecord(
              names: [],
              classification: typeId,
              classificationResolution: ClassificationResolution.resolved,
              worldAssociations: [
                WorldAssociation(
                  world: world,
                  role: 'setting',
                  validity: const UnspecifiedValidity(),
                  qualifiers: {},
                ),
              ],
              labels: {'en': 'Mara $n é😀'},
              metadata: {},
            ),
        };
        final rows = [
          for (final entry in payloads.entries)
            StoredVersion.build(
              RecordVersionId.generate(),
              RecordIdentity(
                universeId: universe,
                recordId: entry.key,
                recordKind: entry.value.recordKind,
              ),
              entry.value.toWire(),
            ),
        ];
        final head = await store.transaction(
          (s) => s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: continuity,
                  expectedHead: base,
                  principal: PrincipalId.generate(),
                  decision: 'Disposable setup',
                  reason: 'Paged transfer fixture',
                  idempotencyKey: 'paged-export-fixture',
                  changes: [
                    for (final row in rows)
                      Assignment(
                        recordId: row.identity.recordId,
                        expected: null,
                        next: row,
                      ),
                  ],
                ),
              ),
        );
        final directory = Directory.systemTemp.createTempSync(
          'ub-postgres-filtered-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final draft = DraftContent(
          baseRevision: head,
          representedContext: represented,
          operations: [],
          rationale: 'Private draft not included in canon-only export',
          proposal: null,
        );
        await author.execute(
          SaveDraftEngineRequest(
            universe: selector,
            continuityId: continuity,
            expectedVersion: BigInt.zero,
            content: draft,
          ),
        );
        final complete = '${directory.path}/complete.sqlite';
        await author.execute(
          ExportLogicalEngineRequest(
            universe: selector,
            destination: complete,
            recordIds: [],
            completeHistory: true,
          ),
        );
        final full = local.OwnedSqliteDatabase.stageLogicalArchive(
          complete,
          directory.path,
        );
        try {
          final journal = local.SqliteJournal(full.package.database, universe);
          expect(journal.head(continuity), head);
          expect(journal.snapshot(continuity, head), hasLength(74));
          for (final row in rows) {
            expect(
              journal.load(row.versionId).toCanonical().toText(),
              row.toCanonical().toText(),
            );
          }
          expect(
            local.WorkflowStorage(full.package.database).keys('draft:'),
            hasLength(1),
          );
          expect(
            full.package.database
                .select('SELECT name FROM type_definition')
                .single['name'],
            (payloads[typeId] as EntityTypeRecord).name,
          );
          final clone = UniverseId.generate();
          universes.add(clone);
          await store.transaction((session) async {
            expect(
              await session.importUniverse(
                actor: authorId,
                archive: full,
                scratch: directory.path,
                name: 'Imported campaign',
                clone: clone,
              ),
              clone,
            );
          });
          final expected = full.reconstruct(
            directory.path,
            target: clone,
            name: 'Imported campaign',
          );
          try {
            await store.transaction((session) async {
              await session.verifyUniverse(clone, complete: true);
              final targetJournal = session.kernel(clone).journal;
              final expectedJournal = local.SqliteJournal(
                expected.package.database,
                clone,
              );
              expect(await targetJournal.heads(), expectedJournal.heads());
              for (final row in expected.package.database.select(
                'SELECT id FROM record_versions',
              )) {
                final id = RecordVersionId.parse(row['id'] as String);
                expect(
                  (await targetJournal.load(id)).toCanonical().toText(),
                  expectedJournal.load(id).toCanonical().toText(),
                );
              }
              final expectedWorkflow = local.WorkflowStorage(
                expected.package.database,
              );
              for (final row in expected.package.database.select(
                'SELECT key FROM workflow_index',
              )) {
                final key = row['key'] as String;
                expect(
                  (await session.workflows(clone).evidence(key))!.toText(),
                  expectedWorkflow.evidence(key)!.toText(),
                );
              }
            });
          } finally {
            expected.close();
          }
        } finally {
          full.close();
        }
        final destination = '${directory.path}/filtered.sqlite';
        final manifest = WireFields(
          await author.execute(
            ExportLogicalEngineRequest(
              universe: selector,
              destination: destination,
              recordIds: [f.id(100)],
              completeHistory: false,
            ),
          ),
          {
            'format',
            'universe',
            'name',
            'complete',
            'omitted_records',
            'includes_history',
            'includes_workflow',
          },
        );
        expect(manifest.boolean('complete'), isFalse);
        expect(manifest.boolean('includes_workflow'), isFalse);
        final filtered = local.OwnedSqliteDatabase.stageLogicalArchive(
          destination,
          directory.path,
        );
        try {
          final journal = local.SqliteJournal(
            filtered.package.database,
            universe,
          );
          final ids = filtered.package.database
              .select('SELECT id FROM record_identities')
              .map((r) => r['id'] as String)
              .toSet();
          expect(
            ids,
            containsAll([f.id(100).value, worldId.value, typeId.value]),
          );
          expect(ids, isNot(contains(f.id(101).value)));
          expect(journal.head(continuity), head);
          expect(
            local.WorkflowStorage(filtered.package.database).keys('draft:'),
            isEmpty,
          );
          await expectLater(
            store.transaction(
              (session) => session.importUniverse(
                actor: authorId,
                archive: filtered,
                scratch: directory.path,
                name: 'Refused filtered identity',
              ),
            ),
            throwsA(isA<FormatException>()),
          );
          final postgresFiltered = UniverseId.generate();
          universes.add(postgresFiltered);
          await store.transaction((session) async {
            await session.importUniverse(
              actor: authorId,
              archive: filtered,
              scratch: directory.path,
              name: 'PostgreSQL filtered campaign',
              clone: postgresFiltered,
            );
            await session.verifyUniverse(postgresFiltered, complete: true);
            expect(
              await session.workflows(postgresFiltered).keys('draft:'),
              isEmpty,
            );
          });
          expect(
            (await observer.execute(
              'SELECT id FROM ${postgresUniverseSchema(postgresFiltered)}.record_identities',
            )).map((r) => r.single).toSet(),
            ids,
          );
          final clone = filtered.reconstruct(
            directory.path,
            target: UniverseId.generate(),
            name: 'Filtered campaign',
          );
          try {
            expect(
              clone.package.database
                  .select('SELECT count(*) AS n FROM record_versions')
                  .single['n'],
              ids.length,
            );
          } finally {
            clone.close();
          }
        } finally {
          filtered.close();
        }
        final refused = '${directory.path}/invalid.sqlite';
        await expectLater(
          author.execute(
            ExportLogicalEngineRequest(
              universe: selector,
              destination: refused,
              recordIds: [f.id(100)],
              completeHistory: true,
            ),
          ),
          throwsA(isA<FormatException>()),
        );
        expect(File(refused).existsSync(), isFalse);
        await expectLater(
          author.execute(
            ExportLogicalEngineRequest(
              universe: selector,
              destination: refused,
              recordIds: [RecordId.generate()],
              completeHistory: false,
            ),
          ),
          throwsA(isA<FormatException>()),
        );
        expect(File(refused).existsSync(), isFalse);
        expect(directory.listSync().whereType<Directory>(), isEmpty);
        await store.transaction((s) async {
          expect(await s.kernel(universe).journal.head(continuity), head);
          expect(await s.workflows(universe).keys('draft:'), hasLength(1));
        });
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('health recovery isolates damaged universes and maintenance collects only disposable caches', () async {
        final author = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
        Future<WireFields> create(String name) async {
          final fields = WireFields(
            await author.execute(
              CreateUniverseEngineRequest(
                name: name,
                start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
              ),
            ),
            {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
          );
          universes.add(UniverseId.parse(fields.string('universe_id')));
          return fields;
        }

        final damaged = await create(selector.value);
        final healthy = await create('Healthy disposable universe');
        final universe = UniverseId.parse(damaged.string('universe_id'));
        final healthyId = UniverseId.parse(healthy.string('universe_id'));
        final schema = postgresUniverseSchema(universe);
        final healthySchema = postgresUniverseSchema(healthyId);
        final original = (await observer.execute(
          'SELECT id,digest FROM $schema.record_versions ORDER BY id LIMIT 1',
        )).single;
        Future<void> replaceDigest(String digest) async {
          await observer.runTx((tx) async {
            await tx.execute(
              'ALTER TABLE $schema.record_versions DISABLE TRIGGER immutable_history',
            );
            await tx.execute(
              'UPDATE $schema.record_versions SET digest=\$1 WHERE id=\$2',
              parameters: [digest, original[0]],
            );
            await tx.execute(
              'ALTER TABLE $schema.record_versions ENABLE TRIGGER immutable_history',
            );
          });
        }

        await replaceDigest('0' * 64);
        const doctor = DoctorEngineRequest();
        await expectLater(
          writer.execute(doctor),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final report = WireFields(await author.execute(doctor), {
          'service_instance',
          'packages',
          'profile_storage',
          'recovery',
          'admission',
        });
        expect(
          report.string('profile_storage'),
          'installation database authority',
        );
        final packages = report.array('packages');
        final failure = packages
            .map((v) => (Map.fromEntries((v as CanonicalObject).fields)))
            .singleWhere((v) => wireString(v['id']!) == universe.value);
        expect(failure.keys.toSet(), {'id', 'error'});
        expect(
          wireString(failure['error']!),
          'universe unavailable: check schema version and retained-content integrity',
        );
        expect(
          (await observer.execute(
            'SELECT generation FROM $schema.projection_state',
          )).single.single,
          0,
        );
        expect(
          (await observer.execute(
            'SELECT generation FROM $healthySchema.projection_state',
          )).single.single,
          1,
        );
        await expectLater(
          author.execute(const LibraryEngineRequest(universe: selector)),
          throwsA(isA<FormatException>()),
        );
        await replaceDigest(original[1] as String);
        final recovered = WireFields(await author.execute(doctor), {
          'service_instance',
          'packages',
          'profile_storage',
          'recovery',
          'admission',
        });
        expect(
          recovered
              .array('packages')
              .map(
                (v) =>
                    (Map.fromEntries((v as CanonicalObject).fields)).keys.toSet(),
              ),
          everyElement({'id', 'storage'}),
        );
        final continuity = ContinuityId.parse(damaged.string('continuity_id'));
        final revision = RevisionId.parse(damaged.string('revision'));
        final represented = RecordId.parse(damaged.string('context_id'));
        final content = DraftContent(
          baseRevision: revision,
          representedContext: represented,
          operations: [],
          rationale: 'Retained unfinished text é😀',
          proposal: null,
        );
        final draft = await author.execute(
          SaveDraftEngineRequest(
            universe: selector,
            continuityId: continuity,
            expectedVersion: BigInt.zero,
            content: content,
          ),
        );
        const source = StageSourceEngineRequest(
          universe: selector,
          label: 'Retained source',
          text: '\uFEFFExact author text é😀\r\n',
        );
        await author.execute(source);
        final membership = await store.transaction(
          (s) => s.kernel(universe).journal.snapshot(continuity, revision),
        );
        final checksum = canonicalDigest(
          CanonicalObject([
            for (final entry in membership.entries)
              MapEntry(entry.key.value, CanonicalString(entry.value.value)),
          ]),
        );
        await observer.runTx((tx) async {
          await tx.execute(
            'INSERT INTO $schema.snapshot_membership VALUES(\$1,\$2,\$3)',
            parameters: [universe.value, revision.value, checksum],
          );
          for (final entry in membership.entries) {
            await tx.execute(
              'INSERT INTO $schema.snapshot_member VALUES(\$1,\$2,\$3,\$4)',
              parameters: [
                universe.value,
                revision.value,
                entry.key.value,
                entry.value.value,
              ],
            );
          }
        });
        const preview = MaintainEngineRequest(universe: selector, collect: false);
        const collect = MaintainEngineRequest(universe: selector, collect: true);
        await expectLater(
          writer.execute(collect),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        WireFields maintenance(CanonicalValue value) => WireFields(value, {
          'retention_policy',
          'retained_record_versions',
          'retained_revisions',
          'retained_commit_receipts',
          'retained_workflow_entries',
          'retained_source_assets',
          'eligible_snapshot_caches',
          'collected_snapshot_caches',
          'source_assets_collected',
          'backup_pins',
          'canonical',
        });
        final before = maintenance(await author.execute(preview));
        expect(before.require('eligible_snapshot_caches').toText(), '1');
        expect(before.require('collected_snapshot_caches').toText(), '0');
        final after = maintenance(await author.execute(collect));
        expect(after.require('collected_snapshot_caches').toText(), '1');
        expect(after.require('source_assets_collected').toText(), '0');
        expect(after.boolean('canonical'), isFalse);
        for (final field in [
          'retained_record_versions',
          'retained_revisions',
          'retained_commit_receipts',
          'retained_workflow_entries',
          'retained_source_assets',
        ]) {
          expect(after.require(field).toText(), before.require(field).toText());
        }
        expect(
          (await author.execute(
            LoadDraftEngineRequest(universe: selector, continuityId: continuity),
          )).toText(),
          draft.toText(),
        );
        await store.transaction((s) async {
          expect(await s.kernel(universe).journal.head(continuity), revision);
          expect(
            await s.kernel(universe).journal.snapshot(continuity, revision),
            membership,
          );
          expect(
            wireString(
              (await s
                  .workflows(universe)
                  .get('source:${sha256.convert(utf8.encode(source.text))}'))!,
            ),
            source.text,
          );
          await s.verifyUniverse(universe, complete: true);
        });
        expect(
          (await observer.execute(
            'SELECT count(*) FROM $schema.snapshot_membership',
          )).single.single,
          0,
        );
        expect(
          (await observer.execute('SELECT count(*) FROM $schema.snapshot_member'))
              .single
              .single,
          0,
        );
      });

      test('continuity dispatch pins branch history and publishes explicit adoption only with exact approval', () async {
        var author = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-03-15T12:30:00+02:00'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final parent = ContinuityId.parse(created.string('continuity_id'));
        final represented = RecordId.parse(created.string('context_id'));
        final branch = ContinuityId.generate();
        EntityRecord entity(String label) => EntityRecord(
          names: [],
          classificationResolution: ClassificationResolution.unclassified,
          worldAssociations: [],
          labels: {'en': label},
          metadata: {},
        );
        StoredVersion row(int n, String label) => StoredVersion.build(
          RecordVersionId.generate(),
          RecordIdentity(
            universeId: universe,
            recordId: f.id(n),
            recordKind: RecordKind.entity,
          ),
          entity(label).toWire(),
        );
        final original = row(20, 'Original'), removed = row(21, 'Removed');
        Future<RevisionId> seed(
          String key,
          RevisionId head,
          List<Assignment> changes,
        ) => store.transaction(
          (s) => s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: parent,
                  expectedHead: head,
                  principal: PrincipalId.generate(),
                  decision: 'Disposable setup',
                  reason: 'Continuity edits',
                  idempotencyKey: key,
                  changes: changes,
                ),
              ),
        );
        final base = await seed(
          'continuity-base',
          RevisionId.parse(created.string('revision')),
          [
            Assignment(
              recordId: original.identity.recordId,
              expected: null,
              next: original,
            ),
            Assignment(
              recordId: removed.identity.recordId,
              expected: null,
              next: removed,
            ),
          ],
        );
        final fork = ForkContinuityEngineRequest(
          universe: selector,
          name: 'Alternate campaign',
          continuityId: branch,
          source: parent,
          revision: base,
        );
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: null,
              propose: true,
              edit: true,
              protected: true,
            ),
          ),
        );
        const profilesRequest = ProfilesEngineRequest();
        await expectLater(
          writer.execute(profilesRequest),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final management = WireFields(await author.execute(profilesRequest), {
          'profiles',
          'grants',
        });
        final identities = management
            .array('profiles')
            .map(
              (value) => WireFields(value, {'profile_id', 'author', 'revoked'}),
            )
            .toList();
        expect(identities.map((value) => value.string('profile_id')).toSet(), {
          authorId.value,
          writerId.value,
        });
        expect(
          identities
              .singleWhere(
                (value) => value.string('profile_id') == authorId.value,
              )
              .boolean('author'),
          isTrue,
        );
        expect(
          identities
              .singleWhere(
                (value) => value.string('profile_id') == writerId.value,
              )
              .boolean('author'),
          isFalse,
        );
        expect(identities.every((value) => !value.boolean('revoked')), isTrue);
        final granted = GrantSpec.fromWire(management.array('grants').single);
        expect(granted.profileId, writerId);
        expect(granted.universeId, universe);
        expect(granted.propose && granted.edit && granted.protected, isTrue);
        await expectLater(
          writer.execute(fork),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final forked = await author.execute(fork);
        final forkRevision = RevisionId.parse(
          WireFields(forked, {'continuity_id', 'revision'}).string('revision'),
        );
        expect((await author.execute(fork)).toText(), forked.toText());
        final changed = row(20, 'Changed'), added = row(22, 'Added');
        final advanced = await seed('continuity-edits', base, [
          Assignment(
            recordId: original.identity.recordId,
            expected: original.versionId,
            next: changed,
          ),
          Assignment(
            recordId: removed.identity.recordId,
            expected: removed.versionId,
            next: null,
          ),
          Assignment(
            recordId: added.identity.recordId,
            expected: null,
            next: added,
          ),
        ]);
        await expectLater(
          author.execute(
            ForkContinuityEngineRequest(
              universe: selector,
              name: fork.name,
              continuityId: branch,
              source: parent,
              revision: advanced,
            ),
          ),
          throwsA(isA<FormatException>()),
        );
        final comparison = CompareContinuitiesEngineRequest(
          universe: selector,
          target: branch,
          targetRevision: forkRevision,
          source: parent,
          sourceRevision: advanced,
        );
        final compared = await author.execute(comparison);
        final differences = WireFields(compared, {
          'differences',
          'target_revision',
          'source_revision',
        }).array('differences');
        expect(
          differences.map(
            (v) => WireFields(v, {
              'record_id',
              'kind',
              'label',
              'target_version',
              'source_version',
            }).string('record_id'),
          ),
          [f.id(20).value, f.id(21).value, f.id(22).value],
        );
        final selection = PrepareAdoptionEngineRequest(
          universe: selector,
          target: branch,
          targetRevision: forkRevision,
          source: parent,
          sourceRevision: advanced,
          recordIds: [f.id(22), f.id(20), f.id(21), represented],
        );
        await expectLater(
          writer.execute(comparison),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          writer.execute(selection),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final prepared = await author.execute(selection);
        final operations = WireFields(prepared, {
          'operations',
          'target_revision',
          'source_revision',
        }).array('operations').map(DomainOperation.fromWire).toList();
        expect(operations, hasLength(3));
        expect(
          (operations[0] as AdoptRecordVersionOperation).expectedVersion,
          isNull,
        );
        expect(
          (operations[1] as AdoptRecordVersionOperation).source.recordVersionId,
          changed.versionId,
        );
        expect(
          (operations[1] as AdoptRecordVersionOperation).expectedVersion,
          original.versionId,
        );
        expect(
          (operations[2] as TombstoneRecordOperation).expectedVersion,
          removed.versionId,
        );
        await store.transaction((s) async {
          expect(await s.kernel(universe).journal.head(branch), forkRevision);
          expect(await s.kernel(universe).journal.head(parent), advanced);
          expect(await s.workflows(universe).keys('proposal:'), isEmpty);
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
        });
        final opened = await tool(
          author,
          OpenContextRequest(
            universe: selector,
            continuityId: branch,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(represented),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        final candidate = await tool(
          author,
          CreateProposalRequest(
            universe: selector,
            contextId: opened.contextId,
            operations: operations,
            submission: Submission.submitted,
            rationale: 'Explicit campaign adoption',
            idempotencyKey: 'adoption-create',
          ),
          Proposal.fromWire,
        );
        final ref = ProposalRef(
          proposalId: candidate.proposalId,
          version: candidate.version,
          digest: candidate.digest,
        );
        final checked = await tool(
          author,
          ProposalValidationRequest(
            universe: selector,
            contextId: opened.contextId,
            proposalReference: ref,
            checkScope: CheckScope.candidate,
          ),
          ValidationV3.fromWire,
        ) as EvaluatedValidation;
        final publish = CommitRequest(
          universe: selector,
          proposalReference: ref,
          expectedBaseRevision: forkRevision,
          validationRun: checked.execution.runId,
          idempotencyKey: 'adoption-publish',
        );
        await expectLater(
          tool(author, publish, CommitReceipt.fromWire),
          throwsA(isA<ApprovalRequiredError>()),
        );
        await author.execute(
          ApproveEngineRequest(
            universe: selector,
            proposalReference: ref,
            validationRun: checked.execution.runId,
          ),
        );
        final receipt = await tool(author, publish, CommitReceipt.fromWire);
        final equal = WireFields(
          await author.execute(
            CompareContinuitiesEngineRequest(
              universe: selector,
              target: branch,
              targetRevision: receipt.revision,
              source: parent,
              sourceRevision: advanced,
            ),
          ),
          {'differences', 'target_revision', 'source_revision'},
        );
        expect(equal.array('differences'), isEmpty);
        await store.transaction((s) async {
          expect(await s.kernel(universe).journal.head(parent), advanced);
        });
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        expect(
          (await tool(
            author,
            publish,
            CommitReceipt.fromWire,
          )).toWire().toText(),
          receipt.toWire().toText(),
        );
        expect((await author.execute(fork)).toText(), forked.toText());
        expect((await author.execute(comparison)).toText(), compared.toText());
        expect((await author.execute(selection)).toText(), prepared.toText());
      });

      test('continuity dispatch enforces UTF-8 names pinned revisions selection limits and atomic fork names', () async {
        final author = await runtime.connect(hello(authorId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-03-15T12:30:00+02:00'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final parent = ContinuityId.parse(created.string('continuity_id'));
        final base = RevisionId.parse(created.string('revision'));
        final context = RecordId.parse(created.string('context_id'));
        final branch = ContinuityId.generate();
        ForkContinuityEngineRequest fork(String name, {RevisionId? revision}) =>
            ForkContinuityEngineRequest(
              universe: selector,
              name: name,
              continuityId: branch,
              source: parent,
              revision: revision ?? base,
            );
        for (final name in ['   ', '😀' * 33]) {
          await expectLater(
            author.execute(fork(name)),
            throwsA(isA<InvalidArgumentError>()),
          );
        }
        await expectLater(
          author.execute(
            fork('Missing source', revision: RevisionId.generate()),
          ),
          throwsA(isA<FormatException>()),
        );
        await store.transaction((s) async {
          final journal = s.kernel(universe).journal;
          await journal.lockUniverse();
          // Conflicting retained name forces failure after the branch was staged.
          await s.workflows(universe).compareAppend({}, [
            MapEntry(
              'continuity-name:${branch.value}',
              CanonicalString('Retained name'),
            ),
          ]);
        });
        await expectLater(
          author.execute(fork('Conflicting name')),
          throwsA(isA<FormatException>()),
        );
        await store.transaction((s) async {
          expect(await s.kernel(universe).journal.heads(), hasLength(1));
        });
        final saved = await author.execute(fork('Retained name'));
        expect(
          (await author.execute(fork('Retained name'))).toText(),
          saved.toText(),
        );
        PrepareAdoptionEngineRequest prepare(List<RecordId> ids) =>
            PrepareAdoptionEngineRequest(
              universe: selector,
              target: parent,
              targetRevision: base,
              source: parent,
              sourceRevision: base,
              recordIds: ids,
            );
        for (final ids in [<RecordId>[], List.filled(101, context)]) {
          await expectLater(
            author.execute(prepare(ids)),
            throwsA(isA<InvalidArgumentError>()),
          );
        }
        await expectLater(
          author.execute(prepare([RecordId.generate()])),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final unchanged = WireFields(
          await author.execute(prepare(List.filled(100, context))),
          {'operations', 'target_revision', 'source_revision'},
        );
        expect(unchanged.array('operations'), isEmpty);
        final invalidPin = CompareContinuitiesEngineRequest(
          universe: selector,
          target: parent,
          targetRevision: RevisionId.generate(),
          source: parent,
          sourceRevision: base,
        );
        await expectLater(
          author.execute(invalidPin),
          throwsA(isA<FormatException>()),
        );
        await store.transaction((s) async {
          expect(await s.kernel(universe).journal.head(parent), base);
          expect(await s.workflows(universe).keys('proposal:'), isEmpty);
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
        });
      });

      test('continuity comparison omits generated assertions and adoption preserves duplicate selection order', () async {
        final author = await runtime.connect(hello(authorId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-03-15T12:30:00+02:00'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final parent = ContinuityId.parse(created.string('continuity_id'));
        var head = RevisionId.parse(created.string('revision'));
        StoredVersion stored(RecordVersion row) => StoredVersion.build(
          row.recordVersionId,
          RecordIdentity(
            universeId: universe,
            recordId: row.identity.recordId,
            recordKind: row.identity.recordKind,
          ),
          CanonicalValue.parseWireJson(
            row.payload.toWire().toText().replaceAll(f.u.value, universe.value),
          ),
        );
        Future<void> seed(String key, List<RecordVersion> rows) async {
          head = await store.transaction(
            (s) => s
                .kernel(universe)
                .commit(
                  CommitInput(
                    universe: universe,
                    continuity: parent,
                    expectedHead: head,
                    principal: PrincipalId.generate(),
                    decision: 'Disposable setup',
                    reason: 'Occurred event history',
                    idempotencyKey: key,
                    changes: [
                      for (final row in rows)
                        Assignment(
                          recordId: row.identity.recordId,
                          expected: null,
                          next: stored(row),
                        ),
                    ],
                  ),
                ),
          );
        }

        final rows = event_edits.base();
        await seed('before-event', rows);
        final branch = ContinuityId.generate();
        final forked = await author.execute(
          ForkContinuityEngineRequest(
            universe: selector,
            name: 'Before event',
            continuityId: branch,
            source: parent,
            revision: head,
          ),
        );
        final revision = RevisionId.parse(
          WireFields(forked, {'continuity_id', 'revision'}).string('revision'),
        );
        final added = event_edits
            .occurred(rows)
            .where(
              (r) => !rows.any(
                (old) => old.identity.recordId == r.identity.recordId,
              ),
            )
            .toList();
        final generated = added
            .where(
              (r) =>
                  r.payload is AssertionRecord &&
                  (r.payload as AssertionRecord).establishedBy != null,
            )
            .single;
        await seed('after-event', added);
        final compared = WireFields(
          await author.execute(
            CompareContinuitiesEngineRequest(
              universe: selector,
              target: branch,
              targetRevision: revision,
              source: parent,
              sourceRevision: head,
            ),
          ),
          {'differences', 'target_revision', 'source_revision'},
        );
        final changedIds = compared
            .array('differences')
            .map(
              (v) => WireFields(v, {
                'record_id',
                'kind',
                'label',
                'target_version',
                'source_version',
              }).string('record_id'),
            )
            .toList();
        expect(changedIds, isNot(contains(generated.identity.recordId.value)));
        expect(
          changedIds,
          containsAll(
            added
                .where((r) => r.payload is! AssertionRecord)
                .map((r) => r.identity.recordId.value),
          ),
        );
        final selected = added
            .firstWhere((r) => r.payload is EventRecord)
            .identity
            .recordId;
        final prepared = WireFields(
          await author.execute(
            PrepareAdoptionEngineRequest(
              universe: selector,
              target: branch,
              targetRevision: revision,
              source: parent,
              sourceRevision: head,
              recordIds: [selected, selected],
            ),
          ),
          {'operations', 'target_revision', 'source_revision'},
        );
        expect(prepared.array('operations'), hasLength(2));
        expect(
          prepared.array('operations').first.toText(),
          prepared.array('operations').last.toText(),
        );
        await store.transaction((s) async {
          expect(await s.kernel(universe).journal.head(branch), revision);
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
        });
      });

      test('continuity comparison accepts one thousand differences and refuses larger results', () async {
        final author = await runtime.connect(hello(authorId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-03-15T12:30:00+02:00'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final parent = ContinuityId.parse(created.string('continuity_id'));
        final originalBase = RevisionId.parse(created.string('revision'));
        var head = originalBase;
        final rows = [
          for (var n = 200; n <= 1200; n++)
            StoredVersion.build(
              RecordVersionId.generate(),
              RecordIdentity(
                universeId: universe,
                recordId: f.id(n),
                recordKind: RecordKind.entity,
              ),
              f.entity().toWire(),
            ),
        ];
        for (var offset = 0; offset < rows.length; offset += 100) {
          head = await store.transaction(
            (s) => s
                .kernel(universe)
                .commit(
                  CommitInput(
                    universe: universe,
                    continuity: parent,
                    expectedHead: head,
                    principal: PrincipalId.generate(),
                    decision: 'Disposable setup',
                    reason: 'Comparison boundary',
                    idempotencyKey: 'comparison-fixture-$offset',
                    changes: [
                      for (final row in rows.skip(offset).take(100))
                        Assignment(
                          recordId: row.identity.recordId,
                          expected: null,
                          next: row,
                        ),
                    ],
                  ),
                ),
          );
        }
        final branch = ContinuityId.generate();
        final forked = await author.execute(
          ForkContinuityEngineRequest(
            universe: selector,
            name: 'Comparison target',
            continuityId: branch,
            source: parent,
            revision: originalBase,
          ),
        );
        final initial = RevisionId.parse(
          WireFields(forked, {'continuity_id', 'revision'}).string('revision'),
        );
        CompareContinuitiesEngineRequest compare(RevisionId target) =>
            CompareContinuitiesEngineRequest(
              universe: selector,
              target: branch,
              targetRevision: target,
              source: parent,
              sourceRevision: head,
            );
        await expectLater(
          author.execute(compare(initial)),
          throwsA(isA<EvaluationLimitReachedError>()),
        );
        final target = await store.transaction(
          (s) => s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: branch,
                  expectedHead: initial,
                  principal: PrincipalId.generate(),
                  decision: 'Disposable setup',
                  reason: 'One common record',
                  idempotencyKey: 'comparison-boundary',
                  changes: [
                    Assignment(
                      recordId: rows.first.identity.recordId,
                      expected: null,
                      next: StoredVersion.build(
                        RecordVersionId.generate(),
                        rows.first.identity,
                        rows.first.payload,
                      ),
                    ),
                  ],
                ),
              ),
        );
        final compared = WireFields(await author.execute(compare(target)), {
          'differences',
          'target_revision',
          'source_revision',
        });
        expect(compared.array('differences'), hasLength(1000));
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('private image routes preserve originals and preview only admitted pinned assets after reviewed publication', () async {
        final directory = Directory.systemTemp.createTempSync(
          'ub-postgres-images-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final bytes = base64.decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwHwQBEPgD/U6VwW8AAAAASUVORK5CYII=',
        );
        final source = File('${directory.path}/Portrait é.png')
          ..writeAsBytesSync(bytes);
        var author = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-03-15T12:30:00+02:00'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final continuity = ContinuityId.parse(created.string('continuity_id'));
        final represented = RecordId.parse(created.string('context_id'));
        final revision = RevisionId.parse(created.string('revision'));
        Future<OpenedContext> open() => tool(
          author,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(represented),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        StageImageEngineRequest stage(String path) =>
            StageImageEngineRequest(universe: selector, source: path);
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: null,
              propose: true,
              edit: true,
              protected: true,
            ),
          ),
        );
        await expectLater(
          writer.execute(stage('/unreadable/never-opened')),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final invalid = File('${directory.path}/invalid.png')
          ..writeAsStringSync('not an image');
        final link = Link('${directory.path}/linked.png')
          ..createSync(source.path);
        await expectLater(
          author.execute(stage(invalid.path)),
          throwsA(isA<FormatException>()),
        );
        await expectLater(
          author.execute(stage(link.path)),
          throwsA(isA<FileSystemException>()),
        );
        await expectLater(
          author.execute(stage(directory.path)),
          throwsA(isA<FileSystemException>()),
        );
        await expectLater(
          store.transaction((s) async {
            await s
                .kernel(universe)
                .stageImageBytes(bytes, 'Interrupted import.png');
            throw StateError('Disposable interrupted staging');
          }),
          throwsA(isA<StateError>()),
        );
        await store.transaction((s) async {
          expect(await s.workflows(universe).keys('image-asset:'), isEmpty);
          expect(await s.workflows(universe).keys('image-bytes:'), isEmpty);
        });
        final old = await open();
        final browserServer = await LoopbackEngineServer.postgres(runtime);
        final browserHttp = HttpClient();
        late CanonicalValue uploaded;
        try {
          final grantRequest = await browserHttp.postUrl(
            browserServer.endpoint.resolve('/engine/browser-grant'),
          );
          grantRequest.headers.set(
            'authorization',
            'UB ${base64Encode(hello(authorId).toWire().toBytes())}',
          );
          grantRequest.contentLength = 0;
          final grantResponse = await grantRequest.close();
          expect(grantResponse.statusCode, HttpStatus.ok);
          final grant = WireFields(
            CanonicalValue.parseWireJson(
              await grantResponse.transform(utf8.decoder).join(),
            ),
            {'enrollment_token', 'expires_at'},
          );
          final exchange = await browserHttp.postUrl(
            browserServer.endpoint.resolve('/engine/browser/exchange'),
          );
          exchange.headers.set('origin', browserServer.endpoint.origin);
          exchange.headers.contentType = ContentType.json;
          exchange.add(
            CanonicalObject([
              MapEntry(
                'token',
                CanonicalString(grant.string('enrollment_token')),
              ),
            ]).toBytes(),
          );
          final exchangeResponse = await exchange.close();
          expect(exchangeResponse.statusCode, HttpStatus.ok);
          final cookie = exchangeResponse.cookies.single;
          final session = WireFields(
            CanonicalValue.parseWireJson(
              await exchangeResponse.transform(utf8.decoder).join(),
            ),
            {'welcome', 'csrf', 'expires_at'},
          );
          final imageRequest = await browserHttp.postUrl(
            browserServer.endpoint.resolve('/engine/browser/image-file'),
          );
          imageRequest.headers.set('origin', browserServer.endpoint.origin);
          imageRequest.headers.contentType = ContentType.binary;
          imageRequest.headers.set('cookie', '${cookie.name}=${cookie.value}');
          imageRequest.headers.set('x-ub-csrf', session.string('csrf'));
          imageRequest.headers.set(
            'x-ub-image',
            base64Encode(
              CanonicalObject([
                MapEntry('universe', selector.toWire()),
                MapEntry(
                  'original_name',
                  CanonicalString(source.uri.pathSegments.last),
                ),
              ]).toBytes(),
            ),
          );
          imageRequest.contentLength = bytes.length;
          imageRequest.add(bytes);
          final imageResponse = await imageRequest.close();
          expect(imageResponse.statusCode, HttpStatus.ok);
          final result = EngineResult.fromWire(
            CanonicalValue.parseWireJson(
              await imageResponse.transform(utf8.decoder).join(),
            ),
          );
          expect(result, isA<EngineSuccess>());
          uploaded = (result as EngineSuccess).value;
        } finally {
          browserHttp.close(force: true);
          await browserServer.close();
        }
        final imported = WireFields(uploaded, {
          'canonical',
          'asset_id',
          'preview',
          'metadata',
          'operations',
        });
        expect(imported.boolean('canonical'), isFalse);
        expect(imported.string('preview'), startsWith('data:image/jpeg;base64,'));
        final operation = DomainOperation.fromWire(
          imported.array('operations').single,
        ) as AddImageAssetOperation;
        final asset = operation.record;
        final id = RecordId.parse(imported.string('asset_id'));
        expect(operation.clientRef, id.value);
        expect(asset.originalName, 'Portrait é.png');
        expect(asset.mediaType, 'image/png');
        expect(asset.byteSize, BigInt.from(bytes.length));
        expect(
          imported.require('metadata').toText(),
          CanonicalObject(
            asset.toWire().fields.where((f) => f.key != 'record_kind'),
          ).toText(),
        );
        ImagePreviewEngineRequest preview(
          ContextId context, {
          RecordId? record,
        }) => ImagePreviewEngineRequest(
          universe: selector,
          contextId: context,
          asset: record ?? id,
        );
        await expectLater(
          author.execute(preview(old.contextId)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await store.transaction((s) async {
          expect(
            await s.kernel(universe).imageBytes(asset),
            orderedEquals(bytes),
          );
          expect(await s.kernel(universe).journal.head(continuity), revision);
          expect(await s.kernel(universe).journal.identityExists(id), isFalse);
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
        });
        final candidate = await tool(
          author,
          CreateProposalRequest(
            universe: selector,
            contextId: old.contextId,
            operations: [operation],
            submission: Submission.submitted,
            rationale: 'Reviewed portrait asset',
            idempotencyKey: 'image-candidate',
          ),
          Proposal.fromWire,
        );
        final reference = ProposalRef(
          proposalId: candidate.proposalId,
          version: candidate.version,
          digest: candidate.digest,
        );
        final checked = await tool(
          author,
          ProposalValidationRequest(
            universe: selector,
            contextId: old.contextId,
            proposalReference: reference,
            checkScope: CheckScope.candidate,
          ),
          ValidationV3.fromWire,
        ) as EvaluatedValidation;
        await author.execute(
          ApproveEngineRequest(
            universe: selector,
            proposalReference: reference,
            validationRun: checked.execution.runId,
          ),
        );
        final published = await tool(
          author,
          CommitRequest(
            universe: selector,
            proposalReference: reference,
            expectedBaseRevision: revision,
            validationRun: checked.execution.runId,
            idempotencyKey: 'publish-image',
          ),
          CommitReceipt.fromWire,
        );
        expect(published.revision, isNot(revision));
        await expectLater(
          author.execute(preview(old.contextId)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final current = await open();
        await expectLater(
          author.execute(preview(current.contextId, record: represented)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          writer.execute(preview(current.contextId)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final result = await author.execute(preview(current.contextId));
        expect(
          WireFields(result, {
            'asset_id',
            'metadata',
            'preview',
          }).string('preview'),
          imported.string('preview'),
        );
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        expect(
          (await author.execute(preview(current.contextId))).toText(),
          result.toText(),
        );
        await store.transaction((s) async {
          expect(
            await s.kernel(universe).imageBytes(asset),
            orderedEquals(bytes),
          );
        });
        final destination = '${directory.path}/portrait-export.sqlite';
        await author.execute(
          ExportLogicalEngineRequest(
            universe: selector,
            destination: destination,
            recordIds: [],
            completeHistory: true,
          ),
        );
        final archived = local.OwnedSqliteDatabase.stageLogicalArchive(
          destination,
          directory.path,
        );
        try {
          expect(
            local.SqliteKernel(
              archived.package.database,
              universe,
            ).imageBytes(asset),
            orderedEquals(bytes),
          );
          expect(
            local.SqliteKernel(
              archived.package.database,
              universe,
            ).imagePreview(asset),
            imported.string('preview'),
          );
          final postgresClone = UniverseId.generate();
          universes.add(postgresClone);
          await store.transaction((session) async {
            await session.importUniverse(
              actor: authorId,
              archive: archived,
              scratch: directory.path,
              name: 'PostgreSQL portrait',
              clone: postgresClone,
            );
            expect(
              await session.kernel(postgresClone).imageBytes(asset),
              orderedEquals(bytes),
            );
            expect(
              await session.kernel(postgresClone).imagePreview(asset),
              imported.string('preview'),
            );
            await session.verifyUniverse(postgresClone, complete: true);
          });
          final restored = archived.stageRestore(
            directory.path,
            name: 'Restored portrait',
          );
          try {
            expect(
              local.SqliteKernel(
                restored.package.database,
                universe,
              ).imageBytes(asset),
              orderedEquals(bytes),
            );
            expect(
              local.SqliteJournal(
                restored.package.database,
                universe,
              ).head(continuity),
              published.revision,
            );
          } finally {
            restored.close();
          }
        } finally {
          archived.close();
        }
        final backup = '${directory.path}/portrait-backup.sqlite';
        await author.execute(
          BackupEngineRequest(universe: selector, destination: backup),
        );
        final retained = await store.transaction((session) async {
          final workflow = session.workflows(universe);
          return {
            for (final key in await workflow.keys(''))
              key: (await workflow.evidence(key))!.toText(),
          };
        });
        final reviewed = WireFields(
          await author.execute(
            const PreviewPurgeEngineRequest(universe: selector),
          ),
          {'digest', 'impact'},
        );
        await author.execute(
          PurgeEngineRequest(
            universe: selector,
            digest: reviewed.string('digest'),
            confirmation: 'PURGE Disposable engine universe',
          ),
        );
        await author.execute(
          RestoreEngineRequest(
            source: backup,
            name: 'Disposable engine universe',
          ),
        );
        await store.transaction((session) async {
          await session.verifyUniverse(universe, complete: true);
          expect(
            await session.kernel(universe).journal.head(continuity),
            published.revision,
          );
          expect(
            await session.kernel(universe).imageBytes(asset),
            orderedEquals(bytes),
          );
          expect(
            await session.kernel(universe).imagePreview(asset),
            imported.string('preview'),
          );
          for (final entry in retained.entries) {
            expect(
              (await session.workflows(universe).evidence(entry.key))!.toText(),
              entry.value,
            );
            if (entry.key.startsWith('approval:') ||
                entry.key.startsWith('context:')) {
              expect(await session.workflows(universe).get(entry.key), isNull);
            }
          }
        });
        expect(
          (await observer.execute(
            'SELECT count(*) FROM ${postgresUniverseSchema(universe)}.historical_receipt',
          )).single.single,
          greaterThan(0),
        );
      });

      test('private library shows current heads and latest named writing while retaining immutable revisions', () async {
        final author = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-03-15T12:30:00+02:00'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final continuity = ContinuityId.parse(created.string('continuity_id'));
        final context = RecordId.parse(created.string('context_id'));
        final revision = RevisionId.parse(created.string('revision'));
        const request = LibraryEngineRequest(universe: selector);
        Future<WireFields> library() async => WireFields(
          await author.execute(request),
          {'storage', 'worlds', 'contexts', 'continuities', 'writing'},
        );
        List<WireFields> pending(WireFields value) =>
            WireFields(value.require('writing'), {'proposals', 'approved'})
                .array('proposals')
                .map(
                  (v) => WireFields(v, {
                    'candidate',
                    'label',
                    'submission',
                    'base_revision',
                    'continuity',
                  }),
                )
                .toList();
        final initial = await library();
        final storage = WireFields(initial.require('storage'), {
          'universe',
          'backend',
          'postgres_version',
          'synchronous_commit',
          'heads',
        });
        expect(storage.string('universe'), universe.value);
        expect(storage.string('backend'), 'postgres');
        expect(storage.string('postgres_version'), isNotEmpty);
        expect(storage.string('synchronous_commit'), 'on');
        expect(
          storage.array('heads').single.toText(),
          CanonicalArray([
            CanonicalString(continuity.value),
            CanonicalString(revision.value),
          ]).toText(),
        );
        expect(initial.array('contexts').map(wireString), [context.value]);
        expect(initial.array('worlds'), isEmpty);
        expect(
          WireFields(initial.array('continuities').single, {
            'id',
            'revision',
            'name',
          }).string('name'),
          'Original continuity',
        );
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: null,
              propose: true,
              edit: true,
              protected: true,
            ),
          ),
        );
        await expectLater(
          writer.execute(request),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final opened = await tool(
          author,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(context),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        EntityRecord person(String name) => EntityRecord(
          names: [
            ContextualName(text: name, validity: const UnspecifiedValidity()),
          ],
          classificationResolution: ClassificationResolution.unclassified,
          worldAssociations: [],
          labels: {'en': 'Display label'},
          metadata: {},
        );
        ProposalRef reference(Proposal p) => ProposalRef(
          proposalId: p.proposalId,
          version: p.version,
          digest: p.digest,
        );
        final proposal = await tool(
          author,
          CreateProposalRequest(
            universe: selector,
            contextId: opened.contextId,
            operations: [
              CreateEntityOperation(
                clientRef: f.id(20).value,
                record: person('Mara'),
              ),
            ],
            submission: Submission.draft,
            rationale: 'Named authoring',
            idempotencyKey: 'library-create',
          ),
          Proposal.fromWire,
        );
        expect(pending(await library()).single.string('label'), 'Mara');
        final revised = await tool(
          author,
          ReviseProposalRequest(
            universe: selector,
            contextId: opened.contextId,
            proposalReference: reference(proposal),
            operations: [
              CreateEntityOperation(
                clientRef: f.id(20).value,
                record: person('Mara corrected'),
              ),
            ],
            submission: Submission.draft,
            rationale: 'Corrected identity',
            idempotencyKey: 'library-revise',
          ),
          Proposal.fromWire,
        );
        final latest = pending(await library());
        expect(latest, hasLength(1));
        expect(latest.single.string('label'), 'Mara corrected');
        expect(
          ProposalRef.fromWire(latest.single.require('candidate')),
          reference(revised),
        );
        await tool(
          author,
          WithdrawProposalRequest(
            universe: selector,
            contextId: opened.contextId,
            proposalReference: reference(revised),
            idempotencyKey: 'library-withdraw',
          ),
          Proposal.fromWire,
        );
        expect(pending(await library()), isEmpty);
        await store.transaction((s) async {
          expect(await s.workflows(universe).keys('proposal:'), hasLength(3));
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
          expect(await s.kernel(universe).journal.head(continuity), revision);
          final world = StoredVersion.build(
            RecordVersionId.generate(),
            RecordIdentity(
              universeId: universe,
              recordId: f.id(50),
              recordKind: RecordKind.world,
            ),
            WorldRecord(selector: 'Campaign').toWire(),
          );
          await s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: continuity,
                  expectedHead: revision,
                  principal: PrincipalId.generate(),
                  decision: 'Disposable setup',
                  reason: 'Library world',
                  idempotencyKey: 'library-world',
                  changes: [
                    Assignment(
                      recordId: world.identity.recordId,
                      expected: null,
                      next: world,
                    ),
                  ],
                ),
              );
          await s.workflows(universe).compareAppend({}, [
            MapEntry(
              'continuity-name:${continuity.value}',
              CanonicalString('Campaign edition'),
            ),
          ]);
        });
        final current = await library();
        final world = WireFields(current.array('worlds').single, {
          'id',
          'name',
          'continuity_id',
        });
        expect(world.string('id'), recordWorld(f.id(50)).value);
        expect(world.string('name'), 'Campaign');
        expect(world.string('continuity_id'), continuity.value);
        final edition = WireFields(current.array('continuities').single, {
          'id',
          'revision',
          'name',
        });
        expect(edition.string('name'), 'Campaign edition');
        expect(edition.string('revision'), isNot(revision.value));
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: [recordWorld(f.id(50))],
              propose: false,
              edit: false,
              protected: false,
            ),
          ),
        );
        await expectLater(
          writer.execute(request),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await runtime.close();
        runtime = NativePostgresRuntime(store: store);
        final reopened = await runtime.connect(hello(authorId));
        final recovered = WireFields(await reopened.execute(request), {
          'storage',
          'worlds',
          'contexts',
          'continuities',
          'writing',
        });
        expect(
          recovered.require('writing').toText(),
          current.require('writing').toText(),
        );
        expect(
          recovered.require('continuities').toText(),
          current.require('continuities').toText(),
        );
        expect(
          recovered.require('worlds').toText(),
          current.require('worlds').toText(),
        );
        await store.transaction((s) => s.verifyUniverse(universe, complete: true));
      });

      test('private drafts recover exact saves across reconnect and keep old bases without publication', () async {
        var author = await runtime.connect(hello(authorId));
        final other = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-03-15T12:30:00+02:00'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final continuity = ContinuityId.parse(created.string('continuity_id'));
        final context = RecordId.parse(created.string('context_id'));
        final revision = RevisionId.parse(created.string('revision'));
        DraftContent content(
          String text, {
          RecordId? represented,
          List<DomainOperation> operations = const [],
        }) => DraftContent(
          baseRevision: revision,
          representedContext: represented ?? context,
          operations: operations,
          rationale: text,
          proposal: null,
        );
        SaveDraftEngineRequest save(DraftContent draft, BigInt version) =>
            SaveDraftEngineRequest(
              universe: selector,
              continuityId: continuity,
              expectedVersion: version,
              content: draft,
            );
        final load = LoadDraftEngineRequest(
          universe: selector,
          continuityId: continuity,
        );
        expect(await author.execute(load), isA<CanonicalNull>());
        await expectLater(
          author.execute(save(content('😀' * 4001), BigInt.zero)),
          throwsA(isA<InvalidArgumentError>()),
        );
        final oversized = content(
          'Too many operations',
          operations: List.generate(
            2000,
            (_) => DefineUnitOperation(
              clientRef: 'unfinished-unit',
              record: units.unit(),
            ),
          ),
        );
        expect(
          CanonicalArray(oversized.operations.map((op) => op.toWire()))
              .toBytes()
              .length,
          greaterThan(128000),
        );
        await expectLater(
          author.execute(save(oversized, BigInt.zero)),
          throwsA(isA<InvalidArgumentError>()),
        );
        await expectLater(
          author.execute(
            save(
              content('Unknown context', represented: f.id(999)),
              BigInt.zero,
            ),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        expect(await author.execute(load), isA<CanonicalNull>());
        final request = save(
          content(
            'Unfinished text é😀',
            operations: [
              DefineUnitOperation(
                clientRef: 'unfinished-unit',
                record: units.unit(),
              ),
            ],
          ),
          BigInt.zero,
        );
        final saved = await author.execute(request);
        expect(SavedDraft.fromWire(saved).version, BigInt.one);
        expect(
          SavedDraft.fromWire(saved).content.toWire().toText(),
          request.content.toWire().toText(),
        );
        expect((await other.execute(request)).toText(), saved.toText());
        await expectLater(
          other.execute(save(content('Competing text'), BigInt.zero)),
          throwsA(
            isA<BaseRevisionConflictError>().having(
              (e) => e.actual,
              'actual',
              'draft:1',
            ),
          ),
        );
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: null,
              propose: true,
              edit: true,
              protected: true,
            ),
          ),
        );
        await expectLater(
          writer.execute(load),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          writer.execute(request),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await store.transaction((s) async {
          final journal = s.kernel(universe).journal;
          expect(await journal.head(continuity), revision);
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
          final row = f.row(20, f.entity());
          await s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: continuity,
                  expectedHead: revision,
                  principal: PrincipalId.generate(),
                  decision: 'Disposable setup',
                  reason: 'Advance after draft',
                  idempotencyKey: 'draft-fixture',
                  changes: [
                    Assignment(
                      recordId: row.identity.recordId,
                      expected: null,
                      next: StoredVersion.build(
                        row.recordVersionId,
                        RecordIdentity(
                          universeId: universe,
                          recordId: row.identity.recordId,
                          recordKind: row.identity.recordKind,
                        ),
                        row.payload.toWire(),
                      ),
                    ),
                  ],
                ),
              );
        });
        await runtime.close();
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        expect((await author.execute(request)).toText(), saved.toText());
        expect((await author.execute(load)).toText(), saved.toText());
        final revised = await author.execute(
          save(content('😀' * 4000), BigInt.one),
        );
        expect(SavedDraft.fromWire(revised).version, BigInt.two);
        expect(SavedDraft.fromWire(revised).content.baseRevision, revision);
        await store.transaction((s) async {
          final workflow = s.workflows(universe);
          final keys = await workflow.keys(
            'draft:${authorId.value}:${continuity.value}:',
          );
          expect(keys, hasLength(2));
          expect((await workflow.get(keys.first))!.toText(), saved.toText());
          expect((await workflow.get(keys.last))!.toText(), revised.toText());
          expect(await workflow.keys('approval:'), isEmpty);
          expect(await workflow.keys('proposal:'), isEmpty);
          expect(
            await s.kernel(universe).journal.head(continuity),
            isNot(revision),
          );
        });
      });

      test('inline research dispatch works without writing rights and never retains publication authority', () async {
        final author = await runtime.connect(hello(authorId));
        final writer = await runtime.connect(hello(writerId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-03-15T12:30:00+02:00'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final continuity = ContinuityId.parse(created.string('continuity_id'));
        final represented = RecordId.parse(created.string('context_id'));
        final revision = RevisionId.parse(created.string('revision'));
        Future<void> grant(List<WorldId>? worlds) async {
          await author.execute(
            GrantEngineRequest(
              grant: GrantSpec(
                profileId: writerId,
                universeId: universe,
                worlds: worlds,
                propose: false,
                edit: false,
                protected: false,
              ),
            ),
          );
        }

        Future<OpenedContext> open() => tool(
          writer,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(represented),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        InlineValidationRequest check(
          ContextId context, {
          Selector? world,
          List<DomainOperation>? operations,
        }) => InlineValidationRequest(
          universe: selector,
          contextId: context,
          world: world,
          operations:
              operations ??
              [
                CreateEntityOperation(
                  clientRef: f.id(20).value,
                  record: f.entity(),
                ),
              ],
          checkScope: CheckScope.universe,
        );
        await grant(null);
        final opened = await open();
        final request = check(opened.contextId);
        final report = await tool(
          writer,
          request,
          ValidationV3.fromWire,
        ) as EvaluatedValidation;
        expect((report.submittedInput as QueryInput).frame, opened.frame);
        expect(report.finalBindingDigest, isNull);
        expect(report.assessment, isA<AbsentAssessment>());
        expect(report.execution.operationId, isNull);
        expect(report.execution.inputDigest, canonicalDigest(request.toArgs()));
        await store.transaction((s) async {
          final workflow = s.workflows(universe);
          expect(await workflow.keys('validation:'), hasLength(1));
          final retained = WireFields(
            (await workflow.get('validation:${report.execution.runId.value}'))!,
            {
              'proposal_digest',
              'validation',
              'admissible',
              'report',
              'capture',
            },
          );
          expect(retained.boolean('admissible'), isTrue);
          expect(retained.optional('capture', (value) => value), isNull);
          expect(retained.require('report').toText(), report.toWire().toText());
          for (final prefix in [
            'proposal:',
            'operation:',
            'reserved-record:',
            'approval:',
          ]) {
            expect(await workflow.keys(prefix), isEmpty);
          }
          expect(await s.kernel(universe).journal.head(continuity), revision);
          expect(
            await s.kernel(universe).journal.identityExists(f.id(20)),
            isFalse,
          );
        });
        await expectLater(
          tool(
            writer,
            check(
              opened.contextId,
              operations: [
                CreateEntityOperation(
                  clientRef: f.id(21).value,
                  record: f.entity(classification: f.id(999)),
                ),
              ],
            ),
            ValidationV3.fromWire,
          ),
          throwsA(isA<FormatException>()),
        );
        await store.transaction((s) async {
          final row = f.row(50, WorldRecord(selector: 'Campaign'));
          await s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: continuity,
                  expectedHead: revision,
                  principal: PrincipalId.generate(),
                  decision: 'Disposable world',
                  reason: 'Scoped research',
                  idempotencyKey: 'inline-world',
                  changes: [
                    Assignment(
                      recordId: row.identity.recordId,
                      expected: null,
                      next: StoredVersion.build(
                        row.recordVersionId,
                        RecordIdentity(
                          universeId: universe,
                          recordId: row.identity.recordId,
                          recordKind: row.identity.recordKind,
                        ),
                        row.payload.toWire(),
                      ),
                    ),
                  ],
                ),
              );
        });
        final unscoped = await open();
        await expectLater(
          tool(
            writer,
            check(unscoped.contextId, world: const Selector('Campaign')),
            ValidationV3.fromWire,
          ),
          throwsA(isA<WorldScopeConflictError>()),
        );
        await grant([recordWorld(f.id(50))]);
        final scoped = await open();
        final invalid = [
          CreateEntityOperation(clientRef: '', record: f.entity()),
        ];
        expect(
          await tool(
            writer,
            check(
              scoped.contextId,
              world: const Selector('Campaign'),
              operations: invalid,
            ),
            ValidationV3.fromWire,
          ),
          isA<RestrictedValidation>(),
        );
        await expectLater(
          tool(
            writer,
            check(
              scoped.contextId,
              world: const Selector('Hidden'),
              operations: invalid,
            ),
            ValidationV3.fromWire,
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await store.transaction((s) async {
          expect(await s.workflows(universe).keys('validation:'), hasLength(1));
          expect(await s.workflows(universe).keys('proposal:'), isEmpty);
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
        });
      });

      test('creates, validates, reviews, approves and publishes through dispatch with durable retries and current access', () async {
        var author = await runtime.connect(hello(authorId));
        var writer = await runtime.connect(hello(writerId));
        expect(author.welcome.author, isTrue);
        expect(writer.welcome.author, isFalse);
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-03-15T12:30:00+02:00'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final continuity = ContinuityId.parse(created.string('continuity_id'));
        final represented = RecordId.parse(created.string('context_id'));
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: null,
              propose: true,
              edit: true,
              protected: false,
            ),
          ),
        );
        const sourceText = '\uFEFFExact notes: é😀\r\n';
        const sourceRequest = StageSourceEngineRequest(
          universe: selector,
          label: 'Disposable notes',
          text: sourceText,
        );
        await expectLater(
          writer.execute(sourceRequest),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final staged = WireFields(await author.execute(sourceRequest), {
          'canonical',
          'operations',
        });
        expect(staged.boolean('canonical'), isFalse);
        final sourceVersion = (staged.require('operations') as CanonicalArray)
            .items
            .map(DomainOperation.fromWire)
            .cast<RecordNarrativeReferenceOperation>()
            .map((op) => op.payload)
            .whereType<SourceVersionRecord>()
            .single;
        final digest = sha256.convert(utf8.encode(sourceText)).toString();
        expect(sourceVersion.contentDigest, digest);
        expect(
          sourceVersion.byteSize,
          BigInt.from(utf8.encode(sourceText).length),
        );
        await store.transaction((s) async {
          expect(
            wireString((await s.workflows(universe).get('source:$digest'))!),
            sourceText,
          );
          expect(
            await s
                .kernel(universe)
                .journal
                .snapshot(
                  continuity,
                  RevisionId.parse(created.string('revision')),
                ),
            hasLength(2),
          );
        });
        final opened = await tool(
          writer,
          OpenContextRequest(
            universe: selector,
            universeId: universe,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(represented),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        expect(opened.frame.revision.value, created.string('revision'));
        final proposal = await tool(
          writer,
          CreateProposalRequest(
            universe: selector,
            universeId: universe,
            contextId: opened.contextId,
            operations: [
              CreateEntityOperation(
                clientRef: RecordId.generate().value,
                record: EntityRecord(
                  names: [],
                  classification: null,
                  classificationResolution: ClassificationResolution.unclassified,
                  worldAssociations: [],
                  labels: {},
                  metadata: {},
                ),
              ),
            ],
            submission: Submission.submitted,
            rationale: 'Disposable engine authoring',
            idempotencyKey: 'create',
          ),
          Proposal.fromWire,
        );
        final reference = ProposalRef(
          proposalId: proposal.proposalId,
          version: proposal.version,
          digest: proposal.digest,
        );
        var status = await tool(
          writer,
          QueuedProposalValidationRequest(
            universe: selector,
            universeId: universe,
            contextId: opened.contextId,
            proposalReference: reference,
            checkScope: CheckScope.candidate,
            idempotencyKey: 'queue',
          ),
          OperationStatusV3.fromWire,
        );
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!{
              OperationState.succeeded,
              OperationState.failed,
              OperationState.cancelled,
            }.contains(status.state) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          status = await tool(
            writer,
            GetOperationIdRequest(
              universe: selector,
              universeId: universe,
              operationId: status.operationId,
            ),
            OperationStatusV3.fromWire,
          );
        }
        expect(status.state, OperationState.succeeded, reason: status.failure);
        final report = status.validation as EvaluatedValidation;
        final approve = ApproveEngineRequest(
          universe: selector,
          proposalReference: reference,
          validationRun: report.execution.runId,
        );
        await expectLater(
          writer.execute(approve),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          writer.execute(
            ReviewEngineRequest(universe: selector, proposalReference: reference),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final review = WireFields(
          await author.execute(
            ReviewEngineRequest(universe: selector, proposalReference: reference),
          ),
          {
            'proposal',
            'changes',
            'diff',
            'footprint',
            'latest',
            'assessment_review',
          },
        );
        expect(
          Proposal.fromWire(review.require('proposal')).digest,
          proposal.digest,
        );
        expect((review.require('diff') as CanonicalArray).items, hasLength(1));
        const libraryRequest = LibraryEngineRequest(universe: selector);
        WireFields writing(CanonicalValue value) => WireFields(
          WireFields(value, {
            'storage',
            'worlds',
            'contexts',
            'continuities',
            'writing',
          }).require('writing'),
          {'proposals', 'approved'},
        );
        final beforeApproval = writing(await author.execute(libraryRequest));
        expect(beforeApproval.array('proposals'), hasLength(1));
        expect(beforeApproval.array('approved'), isEmpty);
        await author.execute(approve);
        final approvedWriting = writing(await author.execute(libraryRequest));
        expect(approvedWriting.array('proposals'), hasLength(1));
        expect(approvedWriting.array('approved'), hasLength(1));
        final historical = WireFields(approvedWriting.array('approved').single, {
          'candidate',
          'validation_run',
          'label',
        });
        expect(ProposalRef.fromWire(historical.require('candidate')), reference);
        expect(historical.string('validation_run'), report.execution.runId.value);
        final commit = CommitRequest(
          universe: selector,
          universeId: universe,
          proposalReference: reference,
          expectedBaseRevision: opened.frame.revision,
          validationRun: report.execution.runId,
          idempotencyKey: 'publish',
        );
        final receipt = await tool(writer, commit, CommitReceipt.fromWire);
        final publishedLibrary = writing(await author.execute(libraryRequest));
        expect(publishedLibrary.array('proposals'), isEmpty);
        expect(
          publishedLibrary.require('approved').toText(),
          approvedWriting.require('approved').toText(),
        );
        final directory = Directory.systemTemp.createTempSync(
          'ub-postgres-export-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final destination = '${directory.path}/complete.sqlite';
        final export = ExportLogicalEngineRequest(
          universe: selector,
          destination: destination,
          recordIds: [],
          completeHistory: true,
        );
        await expectLater(
          writer.execute(export),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        expect(File(destination).existsSync(), isFalse);
        final manifest = await author.execute(export);
        final archived = local.OwnedSqliteDatabase.stageLogicalArchive(
          destination,
          directory.path,
        );
        try {
          expect(archived.manifest.toText(), manifest.toText());
          final source = await store.transaction((s) async {
            final workflow = s.workflows(universe);
            final rows = <String, String>{};
            for (final key in await workflow.keys('')) {
              rows[key] = (await workflow.evidence(key))!.toText();
            }
            return rows;
          });
          final evidence = local.WorkflowStorage(archived.package.database);
          for (final entry in source.entries) {
            expect(evidence.evidence(entry.key)!.toText(), entry.value);
          }
          expect(archived.package.universeId, universe);
          expect(
            local.SqliteJournal(
              archived.package.database,
              universe,
            ).head(continuity),
            receipt.revision,
          );
          expect(wireString(evidence.evidence('source:$digest')!), sourceText);
          final records = await observer.execute(
            'SELECT id FROM ${postgresUniverseSchema(universe)}.record_versions ORDER BY id',
          );
          await store.transaction((s) async {
            for (final row in records) {
              final id = RecordVersionId.parse(row.single as String);
              expect(
                local.SqliteJournal(
                  archived.package.database,
                  universe,
                ).load(id).toCanonical().toText(),
                (await s.kernel(universe).journal.load(id))
                    .toCanonical()
                    .toText(),
              );
            }
          });
          final postgresClone = UniverseId.generate();
          universes.add(postgresClone);
          await store.transaction((session) async {
            await session.importUniverse(
              actor: authorId,
              archive: archived,
              scratch: directory.path,
              name: 'PostgreSQL retained writing',
              clone: postgresClone,
            );
            final workflow = session.workflows(postgresClone);
            for (final entry in source.entries) {
              expect((await workflow.evidence(entry.key))!.toText(), entry.value);
            }
            for (final key in source.keys.where(
              (key) => key.startsWith('approval:') || key.startsWith('context:'),
            )) {
              expect(await workflow.get(key), isNull);
            }
            expect(
              await session.kernel(postgresClone).journal.head(continuity),
              receipt.revision,
            );
            await session.verifyUniverse(postgresClone, complete: true);
          });
          expect(
            (await observer.execute(
              'SELECT count(*) FROM ${postgresUniverseSchema(postgresClone)}.historical_receipt',
            )).single.single,
            greaterThan(0),
          );
          final restored = archived.stageRestore(
            directory.path,
            name: 'Restored PostgreSQL export',
          );
          try {
            expect(
              local.SqliteJournal(
                restored.package.database,
                universe,
              ).head(continuity),
              receipt.revision,
            );
            final restoredWorkflow = local.WorkflowStorage(
              restored.package.database,
            );
            for (final entry in source.entries) {
              expect(restoredWorkflow.evidence(entry.key)!.toText(), entry.value);
            }
            for (final key in source.keys.where(
              (key) => key.startsWith('approval:') || key.startsWith('context:'),
            )) {
              expect(restoredWorkflow.get(key), isNull);
            }
            expect(
              restored.package.database.select(
                'SELECT revision_id FROM operation_receipts WHERE revision_id=?',
                [receipt.revision.value],
              ),
              isNotEmpty,
            );
            expect(
              restored.package.database.select(
                'SELECT * FROM historical_receipt',
              ),
              isNotEmpty,
            );
          } finally {
            restored.close();
          }
        } finally {
          archived.close();
        }
        final before = File(destination).readAsBytesSync();
        await expectLater(
          author.execute(export),
          throwsA(isA<FileSystemException>()),
        );
        expect(File(destination).readAsBytesSync(), orderedEquals(before));
        final oldInstance = runtime.instance;
        final installation = store.instanceId;
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        expect(store.instanceId, installation);
        expect(runtime.instance, isNot(oldInstance));
        author = await runtime.connect(hello(authorId));
        writer = await runtime.connect(hello(writerId));
        final recoveredLibrary = writing(await author.execute(libraryRequest));
        expect(
          recoveredLibrary.require('proposals').toText(),
          publishedLibrary.require('proposals').toText(),
        );
        expect(
          recoveredLibrary.require('approved').toText(),
          publishedLibrary.require('approved').toText(),
        );
        expect(
          (await tool(writer, commit, CommitReceipt.fromWire)).toWire().toText(),
          receipt.toWire().toText(),
        );
        await author.execute(
          RenameUniverseEngineRequest(
            universeId: universe,
            name: 'Renamed engine universe',
          ),
        );
        final retried = Envelope.fromWire(
          await writer.execute(ToolEngineRequest(request: commit)),
          CommitReceipt.fromWire,
        );
        expect(retried.aliasMatched, isTrue);
        expect(retried.universe.value, 'Renamed engine universe');
        expect(retried.result.toWire().toText(), receipt.toWire().toText());
        await author.execute(
          WithdrawGrantEngineRequest(profileId: writerId, universeId: universe),
        );
        await expectLater(
          writer.execute(ToolEngineRequest(request: commit)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final hidden = WireFields(
          await writer.execute(const StatusEngineRequest()),
          {
            'instance_id',
            'service_instance',
            'universes',
            'canonical_commit',
            'backend',
            'max_requests_per_principal',
            'universe_queue_capacity',
          },
        );
        expect((hidden.require('universes') as CanonicalArray).items, isEmpty);
      });
      test('pinned discovery, record history and paged research survive reopen while current world scope remains closed', () async {
        var author = await runtime.connect(hello(authorId));
        var writer = await runtime.connect(hello(writerId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final continuity = ContinuityId.parse(created.string('continuity_id'));
        final context = RecordId.parse(created.string('context_id'));
        final publicWorld = RecordId.generate(),
            privateWorld = RecordId.generate();
        final publicWorldId = recordWorld(publicWorld),
            privateWorldId = recordWorld(privateWorld);
        final ids = List.generate(4, (_) => RecordId.generate())
          ..sort((a, b) => a.value.compareTo(b.value));
        final hidden = RecordId.generate();
        EntityRecord entity(String label, WorldId world) => EntityRecord(
          names: [],
          classificationResolution: ClassificationResolution.unclassified,
          worldAssociations: [
            WorldAssociation(
              world: world,
              role: 'setting',
              validity: const UnspecifiedValidity(),
              qualifiers: {},
            ),
          ],
          labels: {'en': label},
          metadata: {},
        );
        final payloads = <RecordId, RecordPayload>{
          publicWorld: WorldRecord(selector: 'Campaign', aliases: ['Play']),
          privateWorld: WorldRecord(selector: 'Private'),
          for (var i = 0; i < ids.length; i++)
            ids[i]: entity('Alpha $i é😀', publicWorldId),
          hidden: entity('Alpha hidden', privateWorldId),
        };
        final rows = [
          for (final entry in payloads.entries)
            StoredVersion.build(
              RecordVersionId.generate(),
              RecordIdentity(
                universeId: universe,
                recordId: entry.key,
                recordKind: entry.value.recordKind,
              ),
              entry.value.toWire(),
            ),
        ];
        final revision = await store.transaction(
          (s) => s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: continuity,
                  expectedHead: RevisionId.parse(created.string('revision')),
                  principal: PrincipalId.generate(),
                  decision: 'Disposable read setup',
                  reason: 'Disposable read setup',
                  idempotencyKey: 'read-fixture',
                  changes: [
                    for (final row in rows)
                      Assignment(recordId: row.identity.recordId, next: row),
                  ],
                ),
              ),
        );
        Future<OpenedContext> openContext(
          NativePostgresConnection connection,
        ) => tool(
          connection,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(context),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        final opened = await openContext(author);
        final summary = await tool(
          author,
          DescribeSummaryRequest(universe: selector),
          Description.fromWire,
        );
        expect(summary.continuities.single.revisionId, revision);
        expect(
          (await tool(
            author,
            DescribeCapabilitiesRequest(universe: selector),
            Description.fromWire,
          )).capabilities,
          isNotEmpty,
        );
        expect(
          (await tool(
            author,
            DescribeWorldsRequest(
              universe: selector,
              contextId: opened.contextId,
            ),
            Description.fromWire,
          )).worlds,
          hasLength(2),
        );
        await tool(
          author,
          DescribeDefinitionsRequest(
            universe: selector,
            contextId: opened.contextId,
          ),
          Description.fromWire,
        );
        GetRequest get(ContextId retained, RecordId id) => GetRequest(
          universe: selector,
          contextId: retained,
          recordIds: [id],
          fieldGroups: [FieldGroup.payload, FieldGroup.history],
        );
        final oldRecord = await tool(
          author,
          get(opened.contextId, ids.first),
          Records.fromWire,
        );
        expect(
          oldRecord.records.single.payload.toWire().toText(),
          payloads[ids.first]!.toWire().toText(),
        );
        expect(oldRecord.history, hasLength(1));
        final newer = StoredVersion.build(
          RecordVersionId.generate(),
          rows.firstWhere((r) => r.identity.recordId == ids.first).identity,
          entity('Changed', publicWorldId).toWire(),
        );
        await store.transaction(
          (s) => s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: continuity,
                  expectedHead: revision,
                  principal: PrincipalId.generate(),
                  decision: 'Disposable update',
                  reason: 'Disposable update',
                  idempotencyKey: 'read-update',
                  changes: [
                    Assignment(
                      recordId: ids.first,
                      expected: rows
                          .firstWhere((r) => r.identity.recordId == ids.first)
                          .versionId,
                      next: newer,
                    ),
                  ],
                ),
              ),
        );
        SearchRequest search({String? cursor, String query = 'Alpha'}) =>
            SearchRequest(
              universe: selector,
              contextId: opened.contextId,
              query: query,
              typedFilters: Filters(recordKinds: [RecordKind.entity]),
              limit: 1,
              cursor: cursor,
              world: const Selector('Play'),
            );
        Future<Envelope<SearchResults>> searchPage(
          SearchRequest request,
        ) async => Envelope.fromWire(
          await author.execute(ToolEngineRequest(request: request)),
          SearchResults.fromWire,
        );
        final first = await searchPage(search());
        expect(first.result.hits.single.recordId, ids.first);
        expect(first.delivery.complete, isFalse);
        final record = RecordVersion.fromWire(
          rows
              .firstWhere((r) => r.identity.recordId == ids.first)
              .toCanonical(),
        );
        final budget =
            ContextBrief(
              records: [record],
              requiredDependencies: [],
              coverage: Coverage.partial,
            ).toWire().toBytes().length +
            30;
        GetContextRequest brief({
          String? cursor,
          String purpose = 'Research',
        }) => GetContextRequest(
          universe: selector,
          contextId: opened.contextId,
          focusIds: ids,
          purpose: purpose,
          byteBudget: budget,
          cursor: cursor,
        );
        Future<Envelope<ContextBrief>> briefPage(
          GetContextRequest request,
        ) async => Envelope.fromWire(
          await author.execute(ToolEngineRequest(request: request)),
          ContextBrief.fromWire,
        );
        final firstBrief = await briefPage(brief());
        expect(firstBrief.delivery.complete, isFalse);
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        writer = await runtime.connect(hello(writerId));
        await expectLater(
          searchPage(search(cursor: first.delivery.cursor, query: 'Changed')),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          briefPage(
            brief(cursor: firstBrief.delivery.cursor, purpose: 'Changed'),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final collected = [first.result.hits.single.recordId];
        var cursor = first.delivery.cursor;
        while (cursor != null) {
          final page = await searchPage(search(cursor: cursor));
          expect(page.frame!.revision, revision);
          collected.addAll(page.result.hits.map((h) => h.recordId));
          cursor = page.delivery.cursor;
        }
        expect(collected, ids);
        final briefIds = [
          ...firstBrief.result.records.map((r) => r.identity.recordId),
        ];
        final dependencies = [...firstBrief.result.requiredDependencies];
        cursor = firstBrief.delivery.cursor;
        while (cursor != null) {
          final page = await briefPage(brief(cursor: cursor));
          expect(page.frame!.revision, revision);
          briefIds.addAll(page.result.records.map((r) => r.identity.recordId));
          dependencies.addAll(page.result.requiredDependencies);
          cursor = page.delivery.cursor;
        }
        expect(briefIds, [...ids, publicWorld]);
        expect(dependencies, [publicWorld]);
        expect(
          (await tool(
            author,
            get(opened.contextId, ids.first),
            Records.fromWire,
          )).history,
          hasLength(1),
        );
        final fresh = await openContext(author);
        final current = await tool(
          author,
          get(fresh.contextId, ids.first),
          Records.fromWire,
        );
        expect(
          current.records.single.payload.toWire().toText(),
          newer.payload.toText(),
        );
        expect(current.history, hasLength(2));
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: [publicWorldId],
              propose: false,
              edit: false,
              protected: false,
            ),
          ),
        );
        final scoped = await openContext(writer);
        final scopedSearch = SearchRequest(
          universe: selector,
          contextId: scoped.contextId,
          world: const Selector('Play'),
          query: 'Alpha',
          typedFilters: Filters(recordKinds: [RecordKind.entity]),
          limit: 100,
        );
        final visible = Envelope.fromWire(
          await writer.execute(ToolEngineRequest(request: scopedSearch)),
          SearchResults.fromWire,
        );
        expect(visible.authorizationScope, 'world-scoped grant');
        expect(visible.worldFocus, publicWorldId);
        expect(visible.result.hits.map((h) => h.recordId), ids.skip(1));
        expect(
          (await tool(
            writer,
            DescribeWorldsRequest(
              universe: selector,
              contextId: scoped.contextId,
            ),
            Description.fromWire,
          )).worlds,
          hasLength(1),
        );
        final restricted = await tool(
          writer,
          get(scoped.contextId, ids.first),
          Records.fromWire,
        );
        expect(restricted.historyCoverage, Coverage.restricted);
        expect(restricted.history, isEmpty);
        await expectLater(
          tool(writer, get(scoped.contextId, hidden), Records.fromWire),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          tool(writer, get(opened.contextId, ids.first), Records.fromWire),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await author.execute(
          WithdrawGrantEngineRequest(profileId: writerId, universeId: universe),
        );
        await expectLater(
          tool(writer, scopedSearch, SearchResults.fromWire),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
      });
      test('state and plain facts preserve initialization evidence after its assertion leaves canon', () async {
        var author = await runtime.connect(hello(authorId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final continuity = ContinuityId.parse(created.string('continuity_id'));
        StoredVersion row(RecordVersion source) => StoredVersion.build(
          source.recordVersionId,
          RecordIdentity(
            universeId: universe,
            recordId: source.identity.recordId,
            recordKind: source.identity.recordKind,
          ),
          CanonicalValue.parseWireJson(
            source.payload.toWire().toText().replaceAll(
              f.u.value,
              universe.value,
            ),
          ),
        );
        var head = RevisionId.parse(created.string('revision'));
        Future<RevisionId> publish(
          String key,
          List<StoredVersion> records, {
          List<RecordId> remove = const [],
        }) async {
          head = await store.transaction((s) async {
            final membership = await s
                .kernel(universe)
                .journal
                .snapshot(continuity, head);
            return s
                .kernel(universe)
                .commit(
                  CommitInput(
                    universe: universe,
                    continuity: continuity,
                    expectedHead: head,
                    principal: PrincipalId.generate(),
                    decision: 'Disposable state setup',
                    reason: key,
                    idempotencyKey: key,
                    changes: [
                      for (final r in records)
                        Assignment(
                          recordId: r.identity.recordId,
                          expected: membership[r.identity.recordId],
                          next: r,
                        ),
                      for (final id in remove)
                        Assignment(
                          recordId: id,
                          expected: membership[id],
                          next: null,
                        ),
                    ],
                  ),
                );
          });
          return head;
        }

        final base = objects.fixture();
        objects.edit(base, 4, {
          'labels': CanonicalObject([MapEntry('en', CanonicalString('Cedar'))]),
          'worldAssociations': CanonicalArray([
            WorldAssociation(
              world: recordWorld(f.id(50)),
              role: 'setting',
              validity: const UnspecifiedValidity(),
              qualifiers: {},
            ).toWire(),
          ]),
        });
        base.addAll([
          f.row(
            10,
            CalendarRecord(
              namespace: 'test',
              key: 'clock',
              labels: {},
              unitStructure: {},
            ),
          ),
          f.row(
            99,
            RepresentedContextRecord(
              universe: f.u,
              kind: const ObjectiveContext(),
              labels: {},
            ),
          ),
          f.row(50, WorldRecord(selector: 'Campaign')),
          f.row(51, WorldRecord(selector: 'Private')),
          f.row(12, objects.assertion(6, mode: AttributeMode.initialValue)),
        ]);
        final templateRevision = await publish(
          'template',
          base.map(row).toList(),
        );
        final instance = objects.assertion(20);
        final initialized = AssertionRecord.fromWire(
          CanonicalObject([
            ...instance.toWire().fields.where((e) => e.key != 'basis'),
            MapEntry(
              'basis',
              InstanceInitializationBasis(
                VersionRef(universe: f.u, record: f.id(21), version: f.ver(21)),
                VersionRef(universe: f.u, record: f.id(12), version: f.ver(12)),
                templateRevision,
              ).toWire(),
            ),
          ]),
        );
        await publish('initialize', [
          row(f.row(20, objects.proposition(4))),
          row(
            f.row(
              21,
              EventRecord(
                occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
                time: ExactTime(objects.cal, '10'),
                participants: [EventParticipant(f.ref(4), 'starting_instance')],
                labels: {},
              ),
            ),
          ),
          row(f.row(22, initialized)),
        ]);
        Future<OpenedContext> open(NativePostgresConnection connection) => tool(
          connection,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(f.id(99)),
            temporalQuery: AtFrameTime(ExactTime(objects.cal, '15')),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        GetStateRequest stateRequest(
          ContextId context, {
          RecordId? event,
          EventTimeSide? side,
        }) => GetStateRequest(
          universe: selector,
          contextId: context,
          entityIds: [f.id(4)],
          predicateFilters: [f.id(5)],
          event: event,
          eventSide: side,
        );
        ReadFactsRequest factsRequest(ContextId context) => ReadFactsRequest(
          universe: selector,
          contextId: context,
          objectNames: ['Cedar'],
        );
        CanonicalValue field(CanonicalValue value, String key) =>
            (value as CanonicalObject).fields
                .singleWhere((e) => e.key == key)
                .value;
        List<CanonicalValue> list(CanonicalValue value, String key) =>
            (field(value, key) as CanonicalArray).items;
        final opened = await open(author);
        final state = await tool(
          author,
          stateRequest(opened.contextId),
          State.fromWire,
        );
        expect(state.assertions.single.identity.recordId, f.id(22));
        expect(state.objects.single.initializationReceipts, hasLength(1));
        final facts = await tool(
          author,
          factsRequest(opened.contextId),
          (v) => v,
        );
        final object = list(facts, 'objects').single;
        expect(wireString(field(object, 'identity')), 'resolved');
        expect(field(list(object, 'facts').single, 'value').toText(), 'true');
        expect(list(object, 'initial_value_candidates'), hasLength(1));
        expect(list(object, 'inherited_attributes'), hasLength(1));
        final before = await tool(
          author,
          stateRequest(
            opened.contextId,
            event: f.id(21),
            side: EventTimeSide.before,
          ),
          State.fromWire,
        );
        final after = await tool(
          author,
          stateRequest(
            opened.contextId,
            event: f.id(21),
            side: EventTimeSide.after,
          ),
          State.fromWire,
        );
        expect(before.assertions, isEmpty);
        expect(after.assertions, hasLength(1));
        await publish(
          'remove assertion and add private namesake',
          [
            row(
              f.row(
                24,
                EntityRecord(
                  names: [],
                  classificationResolution:
                      ClassificationResolution.unclassified,
                  labels: {'en': 'Cedar'},
                  metadata: {},
                  worldAssociations: [
                    WorldAssociation(
                      world: recordWorld(f.id(51)),
                      role: 'setting',
                      validity: const UnspecifiedValidity(),
                      qualifiers: {},
                    ),
                  ],
                ),
              ),
            ),
          ],
          remove: [f.id(22)],
        );
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        expect(
          (await tool(
            author,
            factsRequest(opened.contextId),
            (v) => v,
          )).toText(),
          facts.toText(),
        );
        final fresh = await open(author);
        final ambiguous = await tool(
          author,
          factsRequest(fresh.contextId),
          (v) => v,
        );
        expect(
          wireString(field(list(ambiguous, 'objects').single, 'identity')),
          'ambiguous',
        );
        expect(
          field(list(ambiguous, 'objects').single, 'matches').toText(),
          '2',
        );
        final retained = await tool(
          author,
          stateRequest(fresh.contextId),
          State.fromWire,
        );
        expect(retained.assertions, isEmpty);
        expect(
          retained.objects.single.initializationReceipts,
          state.objects.single.initializationReceipts,
        );
        expect(
          retained.objects.single.initializationHistoryCoverage,
          Coverage.complete,
        );
        final contracts = await tool(
          author,
          ReadContractsRequest(universe: selector, contextId: fresh.contextId),
          (v) => v,
        );
        expect(wireString(field(contracts, 'coverage')), 'bounded');
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: [recordWorld(f.id(50))],
              propose: false,
              edit: false,
              protected: false,
            ),
          ),
        );
        final writer = await runtime.connect(hello(writerId));
        final scoped = await open(writer);
        final restricted = await tool(
          writer,
          stateRequest(scoped.contextId),
          State.fromWire,
        );
        expect(restricted.objects.single.initializationReceipts, isEmpty);
        expect(
          restricted.objects.single.initializationHistoryCoverage,
          Coverage.restricted,
        );
        final scopedFacts = await tool(
          writer,
          factsRequest(scoped.contextId),
          (v) => v,
        );
        expect(
          wireString(field(list(scopedFacts, 'objects').single, 'identity')),
          'resolved',
        );
        expect(wireString(field(scopedFacts, 'coverage')), 'restricted');
        final scopedContracts = await tool(
          writer,
          ReadContractsRequest(universe: selector, contextId: scoped.contextId),
          (v) => v,
        );
        expect(wireString(field(scopedContracts, 'coverage')), 'restricted');
        await author.execute(
          WithdrawGrantEngineRequest(profileId: writerId, universeId: universe),
        );
        await expectLater(
          tool(writer, stateRequest(scoped.contextId), State.fromWire),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          tool(writer, factsRequest(scoped.contextId), (v) => v),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          tool(
            writer,
            ReadContractsRequest(
              universe: selector,
              contextId: scoped.contextId,
            ),
            (v) => v,
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
      });
      test('ordinary writing checks retain a provisional exact candidate and recover it without approving or publishing', () async {
        var author = await runtime.connect(hello(authorId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final continuity = ContinuityId.parse(created.string('continuity_id'));
        final opened = await tool(
          author,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(
              RecordId.parse(created.string('context_id')),
            ),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        final request = CheckChangesRequest(
          universe: selector,
          contextId: opened.contextId,
          units: [
            units.declaration(name: 'league', symbol: 'lg', introduce: true),
          ],
        );
        final check = await tool(author, request, WritingCheck.fromWire);
        expect(check.candidateHandle, isNotNull);
        expect(check.clarifications, isEmpty);
        final validation =
            ValidationV3.fromWire(check.validation!) as EvaluatedValidation;
        final candidate = ProposalId.parse(check.candidateHandle!);
        final get = GetProposalRequest(
          universe: selector,
          proposalId: candidate,
          version: BigInt.one,
        );
        final view = await tool(
          author,
          get,
          ProposalViewResult.fromWire,
        ) as FrozenProposalView;
        final proposal = view.proposal;
        expect(proposal.submission, Submission.draft);
        expect(proposal.operations.single, isA<DefineUnitOperation>());
        final ref = ProposalRef(
          proposalId: candidate,
          version: proposal.version,
          digest: proposal.digest,
        );
        await expectLater(
          author.execute(
            ApproveEngineRequest(
              universe: selector,
              proposalReference: ref,
              validationRun: validation.execution.runId,
            ),
          ),
          throwsA(isA<ApprovalStaleError>()),
        );
        final impact = await tool(
          author,
          ProposalImpactRequest(
            universe: selector,
            contextId: opened.contextId,
            proposalReference: ref,
            scope: CheckScope.universe,
            byteBudget: 65536,
          ),
          Impact.fromWire,
        );
        expect(impact.toWire().toText(), check.impact!.toText());
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        final retry = await tool(author, request, WritingCheck.fromWire);
        expect(retry.candidateHandle, check.candidateHandle);
        final repeated =
            ValidationV3.fromWire(retry.validation!) as EvaluatedValidation;
        expect(
          repeated.execution.inputDigest,
          validation.execution.inputDigest,
        );
        expect(repeated.execution.runId, isNot(validation.execution.runId));
        expect(
          (await tool(
            author,
            get,
            ProposalViewResult.fromWire,
          ) as FrozenProposalView).proposal.digest,
          proposal.digest,
        );
        final clarified = await tool(
          author,
          CheckChangesRequest(
            universe: selector,
            contextId: opened.contextId,
            questions: ['Which unit applies?'],
          ),
          WritingCheck.fromWire,
        );
        expect(clarified.candidateHandle, isNull);
        expect(clarified.clarifications, ['Which unit applies?']);
        final withdrawn = await tool(
          author,
          WithdrawProposalRequest(
            universe: selector,
            contextId: opened.contextId,
            proposalReference: ref,
            idempotencyKey: 'withdraw-writing',
          ),
          Proposal.fromWire,
        );
        expect(withdrawn.withdrawn, isTrue);
        expect(
          (await tool(
            author,
            DescribeSummaryRequest(universe: selector),
            Description.fromWire,
          )).continuities.single.revisionId,
          opened.frame.revision,
        );
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: null,
              propose: false,
              edit: false,
              protected: false,
            ),
          ),
        );
        final writer = await runtime.connect(hello(writerId));
        await expectLater(
          tool(writer, get, ProposalViewResult.fromWire),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          tool(writer, request, WritingCheck.fromWire),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final writerContext = await tool(
          writer,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(
              RecordId.parse(created.string('context_id')),
            ),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        await expectLater(
          tool(
            writer,
            CheckChangesRequest(
              universe: selector,
              contextId: writerContext.contextId,
              units: request.units,
            ),
            WritingCheck.fromWire,
          ),
          throwsA(isA<PolicyDeniedError>()),
        );
        await store.transaction((s) async {
          expect(
            await s.kernel(universe).journal.head(continuity),
            opened.frame.revision,
          );
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
        });
      });
      test('private source preparation, inspection, publication and rejection retain exact author decisions through reopen', () async {
        var author = await runtime.connect(hello(authorId));
        final created = WireFields(
          await author.execute(
            const CreateUniverseEngineRequest(
              name: 'Disposable engine universe',
              start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final continuity = ContinuityId.parse(created.string('continuity_id'));
        final opened = await tool(
          author,
          OpenContextRequest(
            universe: selector,
            continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(
              RecordId.parse(created.string('context_id')),
            ),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        Future<WritingCheck> draft(String name) => tool(
          author,
          CheckChangesRequest(
            universe: selector,
            contextId: opened.contextId,
            units: [units.declaration(name: name, symbol: name, introduce: true)],
          ),
          WritingCheck.fromWire,
        );
        final candidate = ProposalId.parse(
          (await draft('league')).candidateHandle!,
        );
        const source = '\uFEFFAuthor: é😀\r\nA league is an authored unit.';
        Future<CanonicalValue> act(AuthorWritingAction action) => author.execute(
          AuthorWritingEngineRequest(universe: selector, action: action),
        );
        WireFields review(CanonicalValue value) => WireFields(value, {
          'acceptance_options',
          'summary',
          'candidate',
          'validation',
          'impact',
          'publishable',
          'review',
        });
        final plainPrepare = PrepareWritingAction(
          candidate: candidate,
          label: 'Author passage',
          text: source,
        );
        await expectLater(act(plainPrepare), throwsA(isA<PolicyDeniedError>()));
        await store.transaction((s) async {
          expect(await s.workflows(universe).keys('source-version:'), isEmpty);
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
        });
        final prepare = PrepareContractsWritingAction(
          candidate: candidate,
          label: 'Author passage',
          text: source,
        );
        final prepared = review(await act(prepare));
        final ref = ProposalRef.fromWire(prepared.require('candidate'));
        expect(ref.version, BigInt.two);
        expect(prepared.boolean('publishable'), isTrue);
        final frozen = await tool(
          author,
          GetProposalRequest(
            universe: selector,
            proposalId: ref.proposalId,
            version: ref.version,
          ),
          ProposalViewResult.fromWire,
        ) as FrozenProposalView;
        final anchor = frozen.proposal.operations
            .whereType<AddSourceAnchorOperation>()
            .single
            .record;
        expect(anchor.excerpt, source);
        expect(
          anchor.excerptDigest,
          sha256.convert(utf8.encode(source)).toString(),
        );
        final sourceVersion = frozen.proposal.operations
            .whereType<RecordNarrativeReferenceOperation>()
            .map((op) => op.payload)
            .whereType<SourceVersionRecord>()
            .single;
        expect(sourceVersion.byteSize, BigInt.from(utf8.encode(source).length));
        expect(
          sourceVersion.importActor.value,
          authorId.value.replaceFirst('prf_', 'prn_'),
        );
        final retry = review(await act(prepare));
        expect(
          ProposalRef.fromWire(retry.require('candidate')).toWire().toText(),
          ref.toWire().toText(),
        );
        final rejectedCandidate = ProposalId.parse(
          (await draft('furlong')).candidateHandle!,
        );
        final reject = RejectWritingAction(candidate: rejectedCandidate);
        final rejected = Proposal.fromWire(await act(reject));
        expect(rejected.withdrawn, isTrue);
        await store.transaction((s) async {
          expect(
            await s.kernel(universe).journal.head(continuity),
            opened.frame.revision,
          );
          expect(
            await s.workflows(universe).keys('source-version:'),
            hasLength(1),
          );
          expect(await s.workflows(universe).keys('approval:'), isEmpty);
        });
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: null,
              propose: true,
              edit: true,
              protected: false,
            ),
          ),
        );
        final writer = await runtime.connect(hello(writerId));
        await expectLater(
          writer.execute(
            AuthorWritingEngineRequest(universe: selector, action: prepare),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        final inspected = review(await act(InspectWritingAction(candidate: ref)));
        expect(
          ProposalRef.fromWire(inspected.require('candidate')).toWire().toText(),
          ref.toWire().toText(),
        );
        expect(inspected.boolean('publishable'), isTrue);
        final report = ValidationV3.fromWire(inspected.require('validation'));
        final publish = PublishWritingAction(
          candidate: ref,
          validationRun: report.execution!.runId,
          idempotencyKey: 'source-publish',
        );
        final published = Envelope.fromWire(
          await act(publish),
          CommitReceipt.fromWire,
        );
        expect(published.frame!.revision, opened.frame.revision);
        final sourceContext = await tool(
          author,
          OpenContextRequest(
            universe: selector,
            universeId: universe,
            continuityId: continuity,
            revision: ExactRevisionSelector(
              revisionId: published.result.revision,
            ),
            representedContext: ContextIdSelector(
              RecordId.parse(created.string('context_id')),
            ),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
          OpenedContext.fromWire,
        );
        final sourceRows = await tool(
          author,
          GetRequest(
            universe: selector,
            universeId: universe,
            contextId: sourceContext.contextId,
            recordIds: [anchor.sourceVersion.record],
            fieldGroups: [FieldGroup.payload],
          ),
          Records.fromWire,
        );
        final retainedVersion = sourceRows.records.single;
        final readSource = ReadSourceEngineRequest(
          universe: selector,
          contextId: sourceContext.contextId,
          sourceVersion: VersionRef(
            universe: universe,
            record: retainedVersion.identity.recordId,
            version: retainedVersion.recordVersionId,
          ),
          after: BigInt.zero,
        );
        final sourcePage = WireFields(await author.execute(readSource), {
          'text',
          'after',
          'next',
        });
        expect(sourcePage.string('text'), source);
        expect(sourcePage.require('next'), isA<CanonicalNull>());
        await expectLater(
          author.execute(ReadSourceEngineRequest(
            universe: selector,
            contextId: opened.contextId,
            sourceVersion: readSource.sourceVersion,
            after: BigInt.zero,
          )),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          author.execute(
            ReadSourceEngineRequest(
              universe: selector,
              contextId: sourceContext.contextId,
              sourceVersion: VersionRef(
                universe: universe,
                record: retainedVersion.identity.recordId,
                version: RecordVersionId.generate(),
              ),
              after: BigInt.zero,
            ),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await store.transaction((s) async {
          final version = StoredVersion.build(
            RecordVersionId.generate(),
            RecordIdentity(
              universeId: universe,
              recordId: RecordId.generate(),
              recordKind: RecordKind.entity,
            ),
            EntityRecord(
              names: [],
              classificationResolution: ClassificationResolution.unclassified,
              worldAssociations: [],
              labels: {},
              metadata: {},
            ).toWire(),
          );
          await s
              .kernel(universe)
              .commit(
                CommitInput(
                  universe: universe,
                  continuity: continuity,
                  expectedHead: published.result.revision,
                  principal: PrincipalId.generate(),
                  decision: 'Disposable advance',
                  reason: 'Disposable advance',
                  idempotencyKey: 'after-source-publish',
                  changes: [
                    Assignment(
                      recordId: version.identity.recordId,
                      next: version,
                    ),
                  ],
                ),
              );
        });
        await runtime.close();
        await store.close();
        store = await PostgresInstallationStore.openExisting(
          endpoint(),
          settings: settings,
        );
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(hello(authorId));
        final recovered = Envelope.fromWire(
          await act(publish),
          CommitReceipt.fromWire,
        );
        expect(
          recovered.result.toWire().toText(),
          published.result.toWire().toText(),
        );
        expect(
          Proposal.fromWire(await act(reject)).toWire().toText(),
          rejected.toWire().toText(),
        );
        await expectLater(act(prepare), throwsA(isA<ApprovalStaleError>()));
        await expectLater(
          act(
            PublishWritingAction(
              candidate: ref,
              validationRun: ValidationRunId.generate(),
              idempotencyKey: publish.idempotencyKey,
            ),
          ),
          throwsA(isA<IdempotencyKeyReusedError>()),
        );
        await store.transaction((s) async {
          expect(
            await s.workflows(universe).keys('source-version:'),
            hasLength(1),
          );
          expect(await s.workflows(universe).keys('approval:'), hasLength(1));
          await s.verifyUniverse(universe, complete: true);
        });
        final beforeCollection = await author.execute(
          const MaintainEngineRequest(universe: selector, collect: false),
        );
        final afterCollection = await author.execute(
          const MaintainEngineRequest(universe: selector, collect: true),
        );
        WireFields maintenance(CanonicalValue value) => WireFields(value, {
          'retention_policy',
          'retained_record_versions',
          'retained_revisions',
          'retained_commit_receipts',
          'retained_workflow_entries',
          'retained_source_assets',
          'eligible_snapshot_caches',
          'collected_snapshot_caches',
          'source_assets_collected',
          'backup_pins',
          'canonical',
        });
        final before = maintenance(beforeCollection),
            after = maintenance(afterCollection);
        for (final field in [
          'retained_record_versions',
          'retained_revisions',
          'retained_commit_receipts',
          'retained_workflow_entries',
          'retained_source_assets',
        ]) {
          expect(after.require(field).toText(), before.require(field).toText());
        }
        expect(after.require('source_assets_collected').toText(), '0');
        expect(after.boolean('canonical'), isFalse);
        expect(
          Envelope.fromWire(
            await act(publish),
            CommitReceipt.fromWire,
          ).result.toWire().toText(),
          published.result.toWire().toText(),
        );
      });
      test('staged images and timed appearances publish and revise together on PostgreSQL', () async {
        final directory = Directory('/tmp').createTempSync('ub-pg-appearance-');
        try {
          final author = await runtime.connect(hello(authorId));
          final created = WireFields(await author.execute(const CreateUniverseEngineRequest(
            name: 'Disposable engine universe', start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          )), {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'});
          final universe = UniverseId.parse(created.string('universe_id'));
          universes.add(universe);
          final continuity = ContinuityId.parse(created.string('continuity_id'));
          final represented = RecordId.parse(created.string('context_id'));
          var revision = RevisionId.parse(created.string('revision'));
          final before = await store.transaction((s) async {
            final journal = s.kernel(universe).journal;
            final snapshot = await journal.snapshot(continuity, revision);
            return RecordVersion.fromWire((await journal.load(snapshot[represented]!)).toCanonical());
          });
          Future<CommitReceipt> publish(List<DomainOperation> operations, String key) async {
            final opened = await tool(author, OpenContextRequest(universe: selector,
              continuityId: continuity, revision: const HeadRevisionSelector(),
              representedContext: ContextIdSelector(represented), temporalQuery: const TimelessFrameTime(),
              temporalSystems: [], perspective: const AuthorPerspective()), OpenedContext.fromWire);
            final proposal = await tool(author, CreateProposalRequest(universe: selector,
              contextId: opened.contextId, operations: operations, submission: Submission.submitted,
              rationale: 'Record an authored appearance phase.', idempotencyKey: key), Proposal.fromWire);
            final ref = ProposalRef(proposalId: proposal.proposalId, version: proposal.version, digest: proposal.digest);
            final validation = await tool(author, ProposalValidationRequest(universe: selector,
              contextId: opened.contextId, proposalReference: ref, checkScope: CheckScope.candidate), ValidationV3.fromWire) as EvaluatedValidation;
            await author.execute(ApproveEngineRequest(universe: selector, proposalReference: ref, validationRun: validation.execution.runId));
            final receipt = await tool(author, CommitRequest(universe: selector,
              proposalReference: ref, expectedBaseRevision: revision,
              validationRun: validation.execution.runId, idempotencyKey: 'publish-$key'), CommitReceipt.fromWire);
            revision = receipt.revision;
            return receipt;
          }
          final bytes = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwHwQBEPgD/U6VwW8AAAAASUVORK5CYII=');
          final source = File('${directory.path}/Portrait é.png')..writeAsBytesSync(bytes);
          final staged = StagedImage.fromWire(await author.execute(StageImageEngineRequest(universe: selector, source: source.path)));
          final id = RecordId.generate();
          final chronology = (before.payload as RepresentedContextRecord).chronology!;
          final first = AppearanceRecord(target: EntryAppearance(RecordRef(record: represented, universe: universe)),
            label: 'Before the reveal', physicalDescription: 'Green robes 記憶\r\n', atmosphere: 'Quiet',
            images: [AppearanceImage(asset: RecordRef(record: staged.assetId, universe: universe), caption: 'Exact portrait 😀', purpose: ImagePurpose.appearance)],
            links: [], validity: CalendarIntervalValidity(chronology.calendar,
              ExactBound((BigInt.parse(chronology.current) - BigInt.one).toString()),
              ExactBound((BigInt.parse(chronology.current) + BigInt.one).toString())));
          final creation = await publish([staged.operation, CreateAppearanceOperation(clientRef: id.value, record: first)], 'create-appearance');
          final prior = await store.transaction((s) async {
            final journal = s.kernel(universe).journal;
            final snapshot = await journal.snapshot(continuity, creation.revision);
            expect(await s.kernel(universe).imageBytes(staged.asset), orderedEquals(bytes));
            return RecordVersion.fromWire((await journal.load(snapshot[id]!)).toCanonical());
          });
          expect(prior.payload.toWire().toText(), first.toWire().toText());
          final replacement = AppearanceRecord(target: first.target, label: first.label,
            physicalDescription: 'Silver robes 記憶\r\n', atmosphere: first.atmosphere,
            images: first.images.reversed, links: first.links, validity: first.validity);
          await publish([ReviseAppearanceOperation(record: RecordRef(record: id, universe: universe),
            expectedVersion: prior.recordVersionId, replacement: replacement)], 'revise-appearance');
          await store.transaction((s) async {
            final journal = s.kernel(universe).journal;
            final current = await journal.snapshot(continuity, revision);
            final historical = await journal.snapshot(continuity, creation.revision);
            expect(RecordVersion.fromWire((await journal.load(current[id]!)).toCanonical()).payload.toWire().toText(), replacement.toWire().toText());
            expect(RecordVersion.fromWire((await journal.load(historical[id]!)).toCanonical()).toWire().toText(), prior.toWire().toText());
            expect(RecordVersion.fromWire((await journal.load(current[represented]!)).toCanonical()).toWire().toText(), before.toWire().toText());
          });
        } finally {
          directory.deleteSync(recursive: true);
        }
      });
      test('story secrets publish and revise through reviewed PostgreSQL operations', () async {
        final author = await runtime.connect(hello(authorId));
        final created = WireFields(await author.execute(const CreateUniverseEngineRequest(
          name: 'Disposable engine universe',
          start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
        )), {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'});
        final universe = UniverseId.parse(created.string('universe_id'));
        universes.add(universe);
        final continuity = ContinuityId.parse(created.string('continuity_id'));
        final represented = RecordId.parse(created.string('context_id'));
        var revision = RevisionId.parse(created.string('revision'));
        final id = RecordId.generate();
        Future<CommitReceipt> publish(DomainOperation operation, String key) async {
          final opened = await tool(author, OpenContextRequest(
            universe: selector, continuityId: continuity,
            revision: const HeadRevisionSelector(),
            representedContext: ContextIdSelector(represented),
            temporalQuery: const TimelessFrameTime(), temporalSystems: [],
            perspective: const AuthorPerspective(),
          ), OpenedContext.fromWire);
          final proposal = await tool(author, CreateProposalRequest(
            universe: selector, contextId: opened.contextId,
            operations: [operation], submission: Submission.submitted,
            rationale: 'Author the story disclosure.', idempotencyKey: key,
          ), Proposal.fromWire);
          final ref = ProposalRef(proposalId: proposal.proposalId, version: proposal.version, digest: proposal.digest);
          final validation = await tool(author, ProposalValidationRequest(
            universe: selector, contextId: opened.contextId,
            proposalReference: ref, checkScope: CheckScope.candidate,
          ), ValidationV3.fromWire) as EvaluatedValidation;
          await author.execute(ApproveEngineRequest(universe: selector, proposalReference: ref, validationRun: validation.execution.runId));
          final receipt = await tool(author, CommitRequest(universe: selector,
            proposalReference: ref, expectedBaseRevision: revision,
            validationRun: validation.execution.runId, idempotencyKey: 'publish-$key',
          ), CommitReceipt.fromWire);
          revision = receipt.revision;
          return receipt;
        }
        final first = SecretRecord(scope: [RecordRef(record: represented, universe: universe)],
          fictionalKnowers: [], readerDisclosed: false,
          concealment: 'Reveal later 記憶\r\n', validity: const UnspecifiedValidity());
        final creation = await publish(CreateSecretOperation(clientRef: id.value, record: first), 'create-secret');
        final prior = await store.transaction((s) async {
          final journal = s.kernel(universe).journal;
          final snapshot = await journal.snapshot(continuity, creation.revision);
          return await journal.load(snapshot[id]!);
        });
        final priorRecord = RecordVersion.fromWire(prior.toCanonical());
        expect(priorRecord.payload.toWire().toText(), first.toWire().toText());
        final replacement = SecretRecord(scope: first.scope, fictionalKnowers: [],
          readerDisclosed: true, concealment: null, validity: first.validity);
        await publish(ReviseSecretOperation(record: RecordRef(record: id, universe: universe),
          expectedVersion: priorRecord.recordVersionId, replacement: replacement), 'reveal-secret');
        await store.transaction((s) async {
          final journal = s.kernel(universe).journal;
          final current = await journal.snapshot(continuity, revision);
          final original = await journal.snapshot(continuity, creation.revision);
          expect(RecordVersion.fromWire((await journal.load(current[id]!)).toCanonical()).payload.toWire().toText(), replacement.toWire().toText());
          expect((await journal.load(original[id]!)).toCanonical().toText(), prior.toCanonical().toText());
          expect(current[represented], original[represented]);
        });
      });
      test('denies invalid handshake and private universe creation without side effects', () async {
        await expectLater(
          runtime.connect(hello(writerId, credential: 'invalid')),
          throwsA(isA<InstallationException>()),
        );
        await expectLater(
          runtime.connect(hello(writerId, version: '2')),
          throwsA(isA<FormatException>()),
        );
        final writer = await runtime.connect(hello(writerId));
        await expectLater(
          writer.execute(
            const CreateUniverseEngineRequest(
              name: 'Denied',
              start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
            ),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final status = WireFields(
          await writer.execute(const StatusEngineRequest()),
          {
            'instance_id',
            'service_instance',
            'universes',
            'canonical_commit',
            'backend',
            'max_requests_per_principal',
            'universe_queue_capacity',
          },
        );
        expect((status.require('universes') as CanonicalArray).items, isEmpty);
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for disposable PostgreSQL'
        : false,
  );
}
