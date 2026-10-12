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

  test('retained complete move archive and target review recover independently across restart', () async {
    var author = runtime.connect(hello(authorId));
    final source = await create(author, 'Move source');
    final universe = UniverseId.parse(text(source, 'universe_id'));
    final draft = await author.execute(save(source, 'Move source'));
    final operation = OperationId.generate();
    final targetRoot = Directory.systemTemp.createTempSync(
      'universe-builder-move-target-',
    );
    var targetStore = SqliteInstallationStore.create(targetRoot.path);
    var targetAuthority = InstallationAuthority(targetStore);
    final targetAuthor = targetAuthority.initializeAuthor();
    EngineHello targetHello() => EngineHello(
      protocolVersion: protocolVersion,
      profileId: targetAuthor,
      credential: Credential(
        ProfileCredentialStore.read(
          root: targetRoot.path,
          profile: targetAuthor,
        ),
      ),
      clientName: 'Disposable move target',
    );
    var targetRuntime = NativeSqliteRuntime(authority: targetAuthority);
    try {
      final targetInstance = targetStore.instanceId;
      final stage = await runtime.stageSourceMove(
        authority.authenticateHello(hello(authorId)),
        universe: universe,
        operation: operation,
        targetInstance: targetInstance,
      );
      expect(File(stage.path).statSync().mode & 0x1ff, 0x180);
      final bytes = File(stage.path).readAsBytesSync();
      final manifest = Map.fromEntries(stage.manifest.fields);
      expect((manifest['complete'] as CanonicalBool).value, isTrue);
      expect((manifest['includes_workflow'] as CanonicalBool).value, isTrue);
      final target = targetRuntime.connect(targetHello());
      final preview = await target.execute(
        PreviewImportEngineRequest(
          source: stage.path,
          name: 'Moved source',
          mode: ImportMode.restore,
        ),
      );
      final accept = AcceptImportEngineRequest(
        previewId: OperationId.parse(text(preview, 'preview_id')),
        digest: text(preview, 'digest'),
      );
      final targetReview = targetAuthority.loadImport(
        targetAuthority.authenticateHello(targetHello()),
        accept,
      );
      final sourcePrincipal = authority.authenticateHello(hello(authorId));
      await authority.reviewMoveTarget(
        sourcePrincipal,
        universe: universe,
        operation: operation,
        targetInstance: targetInstance,
        preview: targetReview,
      );
      await authority.reviewMoveTarget(
        sourcePrincipal,
        universe: universe,
        operation: operation,
        targetInstance: targetInstance,
        preview: targetReview,
      );
      await expectLater(
        authority.recordMoveAdmission(
          sourcePrincipal,
          universe: universe,
          operation: operation,
          targetInstance: targetInstance,
          receipt: targetReview.receipt,
        ),
        throwsStateError,
      );
      final changedPreview = await target.execute(
        PreviewImportEngineRequest(
          source: stage.path,
          name: 'Another target review',
          mode: ImportMode.restore,
        ),
      );
      final changedReview = targetAuthority.loadImport(
        targetAuthority.authenticateHello(targetHello()),
        AcceptImportEngineRequest(
          previewId: OperationId.parse(text(changedPreview, 'preview_id')),
          digest: text(changedPreview, 'digest'),
        ),
      );
      await expectLater(
        authority.reviewMoveTarget(
          sourcePrincipal,
          universe: universe,
          operation: operation,
          targetInstance: targetInstance,
          preview: changedReview,
        ),
        throwsFormatException,
      );
      final failingAudit = sqlite3.open('${store.root}/installation.sqlite');
      failingAudit.execute(
        "CREATE TRIGGER refuse_admission BEFORE INSERT ON audit WHEN NEW.action='begin_move_admission' BEGIN SELECT RAISE(ABORT, 'disposable admission failure'); END",
      );
      try {
        await expectLater(
          authority.beginMoveAdmission(
            sourcePrincipal,
            universe: universe,
            operation: operation,
            targetInstance: targetInstance,
          ),
          throwsA(
            isA<InstallationException>().having(
              (e) => e.failure,
              'failure',
              InstallationFailure.unavailable,
            ),
          ),
        );
        expect(
          (await authority.loadMoveReview(
            sourcePrincipal,
            universe: universe,
            operation: operation,
            targetInstance: targetInstance,
          )).state,
          MoveAdmissionState.reviewed,
        );
      } finally {
        failingAudit.execute('DROP TRIGGER refuse_admission');
        failingAudit.close();
      }
      await authority.beginMoveAdmission(
        sourcePrincipal,
        universe: universe,
        operation: operation,
        targetInstance: targetInstance,
      );
      await authority.beginMoveAdmission(
        sourcePrincipal,
        universe: universe,
        operation: operation,
        targetInstance: targetInstance,
      );
      // Stop before admission. Neither restart depends on the original client.
      await targetRuntime.close();
      targetStore.close();
      await runtime.close();
      store.close();
      final cutover = '${root.path}/admission-cutover';
      convertInstallation(root.path, cutover);
      store = SqliteInstallationStore.openExisting(cutover);
      authority = InstallationAuthority(store);
      runtime = NativeSqliteRuntime(authority: authority);
      author = runtime.connect(hello(authorId));
      final recovered = await runtime.stageSourceMove(
        authority.authenticateHello(hello(authorId)),
        universe: universe,
        operation: operation,
        targetInstance: targetInstance,
      );
      expect(
        recovered.path,
        '${Directory(cutover).resolveSymbolicLinksSync()}/moves/${operation.value}.sqlite',
      );
      expect(recovered.digest, stage.digest);
      expect(File(recovered.path).readAsBytesSync(), bytes);
      await expectLater(
        author.execute(save(source, 'Move source')),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      targetStore = SqliteInstallationStore.openExisting(targetRoot.path);
      targetAuthority = InstallationAuthority(targetStore);
      targetRuntime = NativeSqliteRuntime(authority: targetAuthority);
      final reconnected = targetRuntime.connect(targetHello());
      final recoveredPrincipal = authority.authenticateHello(hello(authorId));
      final pending = await authority.loadMoveReview(
        recoveredPrincipal,
        universe: universe,
        operation: operation,
        targetInstance: targetInstance,
      );
      expect(pending.state, MoveAdmissionState.admitting);
      expect(pending.acceptRequest.previewId, accept.previewId);
      expect(pending.acceptRequest.digest, accept.digest);
      final receipt = await reconnected.execute(pending.acceptRequest);
      expect(text(receipt, 'universe_id'), universe.value);
      // A lost admission response is recovered by the exact target receipt.
      expect((await reconnected.execute(accept)).toText(), receipt.toText());
      await expectLater(
        authority.recordMoveAdmission(
          recoveredPrincipal,
          universe: universe,
          operation: operation,
          targetInstance: targetInstance,
          receipt: CanonicalObject([]),
        ),
        throwsFormatException,
      );
      await expectLater(
        authority.beginMoveAdmission(
          authority.authenticateHello(hello(writerId)),
          universe: universe,
          operation: operation,
          targetInstance: targetInstance,
        ),
        denied(),
      );
      final failedCompletion = sqlite3.open(
        '${store.root}/installation.sqlite',
      );
      failedCompletion.execute(
        "CREATE TRIGGER refuse_completion BEFORE INSERT ON audit WHEN NEW.action='complete_move_admission' BEGIN SELECT RAISE(ABORT, 'disposable completion failure'); END",
      );
      try {
        await expectLater(
          authority.recordMoveAdmission(
            recoveredPrincipal,
            universe: universe,
            operation: operation,
            targetInstance: targetInstance,
            receipt: receipt as CanonicalObject,
          ),
          throwsA(
            isA<InstallationException>().having(
              (e) => e.failure,
              'failure',
              InstallationFailure.unavailable,
            ),
          ),
        );
        expect(
          (await authority.loadMoveReview(
            recoveredPrincipal,
            universe: universe,
            operation: operation,
            targetInstance: targetInstance,
          )).state,
          MoveAdmissionState.admitting,
        );
        expect((await reconnected.execute(accept)).toText(), receipt.toText());
      } finally {
        failedCompletion.execute('DROP TRIGGER refuse_completion');
        failedCompletion.close();
      }
      for (var i = 0; i < 2; i++) {
        final completed = await authority.recordMoveAdmission(
          recoveredPrincipal,
          universe: universe,
          operation: operation,
          targetInstance: targetInstance,
          receipt: receipt,
        );
        expect(completed.state, MoveAdmissionState.admitted);
      }
      for (final action in [
        'review_move',
        'begin_move_admission',
        'complete_move_admission',
      ]) {
        expect(
          store.audit(authorId).where((e) => e.action == action),
          hasLength(1),
        );
      }
      await runtime.close();
      store.close();
      store = SqliteInstallationStore.openExisting(cutover);
      authority = InstallationAuthority(store);
      runtime = NativeSqliteRuntime(authority: authority);
      expect(
        (await authority.loadMoveReview(
          authority.authenticateHello(hello(authorId)),
          universe: universe,
          operation: operation,
          targetInstance: targetInstance,
        )).state,
        MoveAdmissionState.admitted,
      );
      final targetPrincipal = targetAuthority.authenticateHello(targetHello());
      final targetPath = targetAuthority
          .resolveUniverseAlias(targetPrincipal, 'Moved source')
          .path;
      await targetRuntime.close();
      final package = OwnedSqliteDatabase.openExisting(targetPath);
      try {
        expect(
          SqliteJournal(
            package.database,
            universe,
          ).head(ContinuityId.parse(text(source, 'continuity_id'))),
          RevisionId.parse(text(source, 'revision')),
        );
        final workflow = WorkflowStorage(package.database);
        final keys = workflow.keys('draft:${authorId.value}:');
        expect(keys, hasLength(1));
        expect(workflow.evidence(keys.single)!.toText(), draft.toText());
        expect(
          package.database.select(
            'SELECT key FROM historical_workflow WHERE key=?',
            [keys.single],
          ),
          hasLength(1),
        );
      } finally {
        package.close();
      }
      expect(
        store.audit(authorId).where((e) => e.action == 'quiesce_move'),
        hasLength(1),
      );
      expect(File(stage.path).readAsBytesSync(), bytes);
    } finally {
      await targetRuntime.close();
      targetStore.close();
      targetRoot.deleteSync(recursive: true);
    }
  });

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

  test('installation conversion retains the exact pending move archive', () async {
    final client = runtime.connect(hello(authorId));
    final source = await create(client, 'Move source');
    final universe = UniverseId.parse(text(source, 'universe_id'));
    final operation = OperationId.generate(), target = OperationId.generate();
    final stage = await runtime.stageSourceMove(
      authority.authenticateHello(hello(authorId)),
      universe: universe,
      operation: operation,
      targetInstance: target,
    );
    final bytes = File(stage.path).readAsBytesSync();
    await runtime.close();
    store.close();
    final converted = '${root.path}/cutover';
    convertInstallation(root.path, converted);
    expect(File(stage.path).readAsBytesSync(), bytes);
    store = SqliteInstallationStore.openExisting(converted);
    authority = InstallationAuthority(store);
    runtime = NativeSqliteRuntime(authority: authority);
    final recovered = await runtime.stageSourceMove(
      authority.authenticateHello(hello(authorId)),
      universe: universe,
      operation: operation,
      targetInstance: target,
    );
    expect(
      recovered.path,
      '${Directory(converted).resolveSymbolicLinksSync()}/moves/${operation.value}.sqlite',
    );
    expect(recovered.digest, stage.digest);
    expect(File(recovered.path).readAsBytesSync(), bytes);
    expect(
      store.audit(authorId).where((e) => e.action == 'quiesce_move'),
      hasLength(1),
    );
  });

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
