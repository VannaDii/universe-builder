@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/sqlite_runtime.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/sqlite.dart';

void main() {
  late Directory root;
  late SqliteInstallationStore store;
  late InstallationAuthority authority;
  late NativeSqliteRuntime runtime;
  late ProfileId authorId, writerId;
  EngineHello hello(ProfileId id) => EngineHello(
    protocolVersion: protocolVersion,
    profileId: id,
    credential: Credential(
      ProfileCredentialStore.read(root: root.path, profile: id),
    ),
    clientName: 'Disposable move client',
  );
  String text(CanonicalValue value, String key) =>
      wireString(Map.fromEntries((value as CanonicalObject).fields)[key]!);
  CanonicalArray catalog(CanonicalValue value) =>
      Map.fromEntries((value as CanonicalObject).fields)['universes']!
          as CanonicalArray;
  SaveDraftEngineRequest save(CanonicalValue row, String name) =>
      SaveDraftEngineRequest(
        universe: Selector(name),
        continuityId: ContinuityId.parse(text(row, 'continuity_id')),
        expectedVersion: BigInt.zero,
        content: DraftContent(
          baseRevision: RevisionId.parse(text(row, 'revision')),
          representedContext: RecordId.parse(text(row, 'context_id')),
          operations: const [],
          rationale: 'Exact retained draft é😀',
          proposal: null,
        ),
      );
  Future<CanonicalValue> create(
    NativeSqliteConnection connection,
    String name,
  ) => connection.execute(
    CreateUniverseEngineRequest(
      name: name,
      start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
    ),
  );
  Matcher denied() => throwsA(
    isA<InstallationException>().having(
      (e) => e.failure,
      'failure',
      InstallationFailure.denied,
    ),
  );
  setUp(() {
    root = Directory.systemTemp.createTempSync('universe-builder-move-');
    store = SqliteInstallationStore.create(root.path);
    authority = InstallationAuthority(store);
    authorId = authority.initializeAuthor();
    writerId = authority.enroll(authority.authenticateHello(hello(authorId)));
    runtime = NativeSqliteRuntime(authority: authority);
  });
  tearDown(() async {
    await runtime.close();
    store.close();
    root.deleteSync(recursive: true);
  });

  test('connected clients and restart respect source guard without changing original data or grants', () async {
    var author = runtime.connect(hello(authorId));
    final peer = runtime.connect(hello(authorId));
    final writer = runtime.connect(hello(writerId));
    final source = await create(author, 'Move source');
    final other = await create(author, 'Other universe');
    final universe = UniverseId.parse(text(source, 'universe_id'));
    final principal = authority.authenticateHello(hello(authorId));
    authority.grant(
      principal,
      GrantSpec(
        profileId: writerId,
        universeId: universe,
        worlds: null,
        propose: true,
        edit: true,
        protected: true,
      ),
    );
    authority.renameUniverse(principal, id: universe, name: 'Renamed source');
    final path = authority.resolveUniverseAlias(principal, 'Move source').path;
    final request = save(source, 'Move source');
    final draft = await peer.execute(request);
    expect(
      catalog(await writer.execute(const StatusEngineRequest())).items,
      hasLength(1),
    );
    final operation = OperationId.generate(), target = OperationId.generate();
    Future<void> quiesce(OperationId op, OperationId instance) =>
        authority.quiesceUniverseForMove(
          principal,
          universe: universe,
          operation: op,
          targetInstance: instance,
        );
    await quiesce(operation, target);
    await quiesce(operation, target);
    expect(
      store.audit(authorId).where((e) => e.action == 'quiesce_move'),
      hasLength(1),
    );
    for (final client in [author, peer]) {
      await expectLater(
        client.execute(request),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
    }
    expect(
      catalog(await writer.execute(const StatusEngineRequest())).items,
      isEmpty,
    );
    expect(store.readGrant(writerId, universe).propose, isTrue);
    await author.execute(save(other, 'Other universe'));
    await expectLater(
      authority.quiesceUniverseForMove(
        principal,
        universe: UniverseId.parse(text(other, 'universe_id')),
        operation: operation,
        targetInstance: target,
      ),
      throwsFormatException,
    );
    await expectLater(
      quiesce(OperationId.generate(), target),
      throwsFormatException,
    );
    await expectLater(
      quiesce(operation, OperationId.generate()),
      throwsFormatException,
    );
    await runtime.close();
    final instance = store.instanceId;
    store.close();
    final control = sqlite3.open(
      '${root.path}/installation.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      expect(
        control.select('SELECT * FROM catalog WHERE id=?', [universe.value]),
        hasLength(1),
      );
      expect(
        control.select('SELECT * FROM aliases WHERE universe=?', [
          universe.value,
        ]),
        hasLength(2),
      );
      expect(
        control.select('SELECT * FROM move_quiescence').single['operation'],
        operation.value,
      );
    } finally {
      control.close();
    }
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      expect(
        SqliteJournal(
          package.database,
          universe,
        ).head(ContinuityId.parse(text(source, 'continuity_id'))),
        RevisionId.parse(text(source, 'revision')),
      );
      final workflows = WorkflowStorage(package.database);
      final keys = workflows.keys('draft:${authorId.value}:');
      expect(keys, hasLength(1));
      expect(workflows.get(keys.single)!.toText(), draft.toText());
    } finally {
      package.close();
    }
    store = SqliteInstallationStore.openExisting(root.path);
    expect(store.instanceId, instance);
    authority = InstallationAuthority(store);
    runtime = NativeSqliteRuntime(authority: authority);
    author = runtime.connect(hello(authorId));
    await expectLater(
      author.execute(request),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(store.readGrant(writerId, universe).propose, isTrue);
    await authority.quiesceUniverseForMove(
      authority.authenticateHello(hello(authorId)),
      universe: universe,
      operation: operation,
      targetInstance: target,
    );
    expect(
      store.audit(authorId).where((e) => e.action == 'quiesce_move'),
      hasLength(1),
    );
  });

  test(
    'writer self-target and stale principal cannot suspend source',
    () async {
      final author = runtime.connect(hello(authorId));
      final source = await create(author, 'Move source');
      final universe = UniverseId.parse(text(source, 'universe_id'));
      final writer = authority.authenticateHello(hello(writerId));
      final principal = authority.authenticateHello(hello(authorId));
      final operation = OperationId.generate();
      await expectLater(
        authority.quiesceUniverseForMove(
          writer,
          universe: universe,
          operation: operation,
          targetInstance: OperationId.generate(),
        ),
        denied(),
      );
      await expectLater(
        authority.quiesceUniverseForMove(
          principal,
          universe: universe,
          operation: operation,
          targetInstance: store.instanceId,
        ),
        throwsFormatException,
      );
      authority.revoke(principal, writerId);
      await expectLater(
        authority.quiesceUniverseForMove(
          writer,
          universe: universe,
          operation: operation,
          targetInstance: OperationId.generate(),
        ),
        denied(),
      );
      expect(
        catalog(await author.execute(const StatusEngineRequest())).items,
        hasLength(1),
      );
      expect(
        store.audit(authorId).where((e) => e.action == 'quiesce_move'),
        isEmpty,
      );
    },
  );

  test('failed staging retains the guarded source and never replaces retained archive bytes', () async {
    final author = runtime.connect(hello(authorId));
    final source = await create(author, 'Move source');
    final universe = UniverseId.parse(text(source, 'universe_id'));
    final principal = authority.authenticateHello(hello(authorId));
    final operation = OperationId.generate(), target = OperationId.generate();
    final stage = await runtime.stageSourceMove(
      principal,
      universe: universe,
      operation: operation,
      targetInstance: target,
    );
    final original = File(stage.path).readAsBytesSync();
    File(stage.path).writeAsBytesSync([1, 2, 3]);
    await expectLater(
      runtime.stageSourceMove(
        principal,
        universe: universe,
        operation: operation,
        targetInstance: target,
      ),
      throwsA(isA<Exception>()),
    );
    expect(File(stage.path).readAsBytesSync(), [1, 2, 3]);
    expect(
      catalog(await author.execute(const StatusEngineRequest())).items,
      isEmpty,
    );
    // Restore the exact retained snapshot to exercise recovery, not regeneration.
    File(stage.path).writeAsBytesSync(original);
    expect(
      (await runtime.stageSourceMove(
        principal,
        universe: universe,
        operation: operation,
        targetInstance: target,
      )).digest,
      stage.digest,
    );
    await expectLater(
      runtime.stageSourceMove(
        authority.authenticateHello(hello(writerId)),
        universe: universe,
        operation: operation,
        targetInstance: target,
      ),
      denied(),
    );
    expect(File(stage.path).readAsBytesSync(), original);
  });

  test(
    'private discovery pages retained moves after restart and denies writers',
    () async {
      var author = runtime.connect(hello(authorId));
      final principal = authority.authenticateHello(hello(authorId));
      final operations = <OperationId>[];
      for (var i = 0; i < 3; i++) {
        final source = await create(author, 'Move $i');
        final operation = OperationId.generate();
        operations.add(operation);
        await authority.quiesceUniverseForMove(
          principal,
          universe: UniverseId.parse(text(source, 'universe_id')),
          operation: operation,
          targetInstance: OperationId.generate(),
        );
      }
      operations.sort((a, b) => a.value.compareTo(b.value));
      await runtime.close();
      store.close();
      store = SqliteInstallationStore.openExisting(root.path);
      authority = InstallationAuthority(store);
      runtime = NativeSqliteRuntime(authority: authority);
      author = runtime.connect(hello(authorId));
      OperationId? after;
      for (var i = 0; i < operations.length; i++) {
        final page = await author.execute(
          EngineRequest.decode(
            ListMovesEngineRequest(after: after, limit: 1).toWire().toBytes(),
          ),
        );
        final fields = Map.fromEntries((page as CanonicalObject).fields);
        final rows = (fields['moves'] as CanonicalArray).items;
        expect(rows, hasLength(1));
        expect(text(rows.single, 'operation_id'), operations[i].value);
        expect(text(rows.single, 'state'), 'suspended');
        expect(text(page, 'source_instance'), store.instanceId.value);
        if (i == operations.length - 1) {
          expect(fields['next_after'], isA<CanonicalNull>());
        } else {
          after = OperationId.parse(wireString(fields['next_after']!));
          expect(after, operations[i]);
        }
        final report = await author.execute(
          GetMoveEngineRequest(operationId: operations[i]),
        );
        final data = Map.fromEntries((report as CanonicalObject).fields);
        expect(text(report, 'operation_id'), operations[i].value);
        expect(data['target_review'], isA<CanonicalNull>());
        expect(data['accept_request'], isA<CanonicalNull>());
        expect(report.toText(), isNot(contains(root.path)));
      }
      final writer = runtime.connect(hello(writerId));
      await expectLater(
        writer.execute(const ListMovesEngineRequest()),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await expectLater(
        writer.execute(GetMoveEngineRequest(operationId: operations.first)),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await expectLater(
        author.execute(const ListMovesEngineRequest(limit: 0)),
        throwsFormatException,
      );
      await expectLater(
        author.execute(
          GetMoveEngineRequest(operationId: OperationId.generate()),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      expect(
        store.audit(authorId).where((e) => e.action == 'quiesce_move'),
        hasLength(3),
      );
    },
  );

  test('opening an older layout refuses it unchanged', () async {
    await runtime.close();
    store.close();
    final path = '${root.path}/installation.sqlite';
    final db = sqlite3.open(path);
    db.execute('DROP TABLE move_quiescence');
    db.close();
    final bytes = File(path).readAsBytesSync();
    expect(
      () => SqliteInstallationStore.openExisting(root.path),
      throwsA(
        isA<InstallationException>().having(
          (e) => e.failure,
          'failure',
          InstallationFailure.incompatibleSchema,
        ),
      ),
    );
    expect(File(path).readAsBytesSync(), bytes);
  });
}
