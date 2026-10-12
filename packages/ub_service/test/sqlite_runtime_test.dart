@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart' hide Description;
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/proposal_state.dart';
import 'package:ub_service/sqlite_runtime.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/ub_store.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_state_test.dart' as proposals;
import 'rule_checks_test.dart' as frames;
import 'structural_checks_test.dart' as structure;
import 'writing_units_test.dart' as units;

void main() {
  late Directory root;
  late SqliteInstallationStore installation;
  late InstallationAuthority authority;
  late InstallationPrincipal author, writer;
  late NativeSqliteRuntime runtime;
  late StoredProposal draft;
  late String path;
  EngineHello hello(ProfileId profile, {String version = protocolVersion}) =>
      EngineHello(
        protocolVersion: version,
        profileId: profile,
        credential: Credential(
          ProfileCredentialStore.read(root: root.path, profile: profile),
        ),
        clientName: 'Disposable runtime client',
      );
  const stage = StageSourceEngineRequest(
    universe: Selector('World'),
    label: 'Session notes',
    text: 'Exact author bytes: é😀',
  );
  setUp(() {
    root = Directory.systemTemp.createTempSync('universe-builder-runtime-');
    installation = SqliteInstallationStore.create(root.path);
    authority = InstallationAuthority(installation);
    author = authority.authenticateHello(hello(authority.initializeAuthor()));
    writer = authority.authenticateHello(hello(authority.enroll(author)));
    path = '${root.path}/packages/world.sqlite';
    final package = OwnedSqliteDatabase.create(path);
    try {
      final kernel = SqliteKernel(package.database, f.u);
      final continuity = frames.frame().continuity;
      package.database.execute('BEGIN IMMEDIATE');
      kernel.journal.initialize(
        'Disposable runtime world',
        continuity,
        PrincipalId.generate(),
      );
      package.database.execute('COMMIT');
      final context = structure.context(99);
      kernel.commit(
        CommitInput(
          universe: f.u,
          continuity: continuity,
          expectedHead: kernel.journal.head(continuity),
          principal: PrincipalId.generate(),
          decision: 'Already admitted fixture',
          reason: 'Runtime fixture',
          idempotencyKey: 'context',
          changes: [
            Assignment(
              recordId: context.identity.recordId,
              next: StoredVersion(
                versionId: context.recordVersionId,
                identity: context.identity,
                payload: context.payload.toWire(),
                digest: context.payloadDigest,
              ),
            ),
          ],
        ),
      );
      draft = proposals.prepare(
        author: true,
        principal: author.id,
        frame: Frame(
          universe: f.u,
          continuity: continuity,
          revision: kernel.journal.head(continuity),
          context: f.ref(99),
          time: const TimelessFrameTime(),
          perspective: const AuthorPerspective(),
        ),
        base: [context],
        request: proposals.create(
          operations: [
            DefineUnitOperation(
              clientRef: f.id(10).value,
              record: units.unit(),
            ),
          ],
        ),
      );
      WorkflowStorage(package.database)
          .compareAppend({}, [MapEntry(draft.key, draft.toWire())]);
    } finally {
      package.close();
    }
    authority.registerUniverse(author, name: 'World', path: path);
    runtime = NativeSqliteRuntime(authority: authority);
  });
  tearDown(() async {
    await runtime.close();
    installation.close();
    root.deleteSync(recursive: true);
  });

  Future<Envelope<CanonicalValue>> tool(
    NativeSqliteConnection connection,
    Request request,
  ) async {
    final decoded = EngineRequest.decode(
      ToolEngineRequest(request: request).toWire().toBytes(),
    );
    return Envelope.fromWire(await connection.execute(decoded), (v) => v);
  }

  test('public discovery and context envelopes retain exact frames and current aliases', () async {
    final connection = runtime.connect(hello(author.id));
    final summary = await tool(
      connection,
      DescribeSummaryRequest(
        universe: const Selector('World'),
        universeId: f.u,
      ),
    );
    expect(summary.contractVersion, protocolVersion);
    expect(summary.requestId, BigInt.zero);
    expect(summary.universeId, f.u);
    expect(summary.aliasMatched, isFalse);
    expect(summary.authorizationScope, 'universe grant');
    expect(summary.delivery.complete, isTrue);
    expect(summary.delivery.cursor, isNull);
    expect(summary.frame, isNull);
    expect(summary.worldFocus, isNull);
    final discovered = Description.fromWire(summary.result);
    final continuity = discovered.continuities.single;
    expect(continuity.id, draft.proposal.baseFrame.continuity);
    final openedEnvelope = await tool(
      connection,
      OpenContextRequest(
        universe: const Selector('World'),
        universeId: f.u,
        continuityId: continuity.id,
        revision: const HeadRevisionSelector(),
        representedContext: ContextIdSelector(f.id(99)),
        temporalQuery: const TimelessFrameTime(),
        temporalSystems: [],
        perspective: const AuthorPerspective(),
      ),
    );
    final opened = OpenedContext.fromWire(openedEnvelope.result);
    expect(
      openedEnvelope.frame!.toWire().toText(),
      opened.frame.toWire().toText(),
    );
    expect(opened.frame.revision, continuity.revisionId);
    authority.renameUniverse(author, id: f.u, name: 'Campaign');
    final worlds = await tool(
      connection,
      DescribeWorldsRequest(
        universe: const Selector('World'),
        contextId: opened.contextId,
      ),
    );
    expect(worlds.universe.value, 'Campaign');
    expect(worlds.aliasMatched, isTrue);
    expect(worlds.frame!.toWire().toText(), opened.frame.toWire().toText());
    expect(Description.fromWire(worlds.result).worlds, isEmpty);
    final capabilities = await tool(
      connection,
      DescribeCapabilitiesRequest(universe: const Selector('Campaign')),
    );
    expect(capabilities.aliasMatched, isFalse);
    expect(Description.fromWire(capabilities.result).capabilities, isNotEmpty);
    final definitions = await tool(
      connection,
      DescribeDefinitionsRequest(
        universe: const Selector('Campaign'),
        contextId: opened.contextId,
      ),
    );
    expect(definitions.frame!.revision, continuity.revisionId);
    await expectLater(
      tool(
        connection,
        DescribeSummaryRequest(
          universe: const Selector('Campaign'),
          universeId: UniverseId.generate(),
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  test('public requests use current grants and cannot reuse another profile context', () async {
    authority.grant(
      author,
      GrantSpec(
        profileId: writer.id,
        universeId: f.u,
        worlds: null,
        propose: false,
        edit: false,
        protected: false,
      ),
    );
    final authorConnection = runtime.connect(hello(author.id));
    final writerConnection = runtime.connect(hello(writer.id));
    OpenContextRequest open() => OpenContextRequest(
      universe: const Selector('World'),
      continuityId: draft.proposal.baseFrame.continuity,
      revision: const HeadRevisionSelector(),
      representedContext: ContextIdSelector(f.id(99)),
      temporalQuery: const TimelessFrameTime(),
      temporalSystems: [],
      perspective: const AuthorPerspective(),
    );
    final opened = OpenedContext.fromWire(
      (await tool(writerConnection, open())).result,
    );
    final describe = DescribeWorldsRequest(
      universe: const Selector('World'),
      contextId: opened.contextId,
    );
    await tool(writerConnection, describe);
    await expectLater(
      tool(authorConnection, describe),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    authority.withdrawGrant(author, profile: writer.id, universe: f.u);
    await expectLater(
      tool(writerConnection, describe),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await expectLater(
      tool(
        writerConnection,
        DescribeSummaryRequest(universe: const Selector('World')),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    await tool(
      authorConnection,
      DescribeSummaryRequest(universe: const Selector('World')),
    );
    authority.revoke(author, writer.id);
    await expectLater(
      tool(writerConnection, open()),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  test('connections share one recovered writer and retain publication receipt across runtime restart', () async {
    final first = runtime.connect(hello(author.id));
    final second = runtime.connect(hello(author.id));
    expect(first.welcome.serviceInstance, second.welcome.serviceInstance);
    expect(first.welcome.maxFrameBytes, BigInt.from(maxFrameBytes));
    expect(first.welcome.author, isTrue);
    await Future.wait([
      first.executeWriting(stage),
      second.executeWriting(stage),
    ]);
    final prepared = await first.executeWriting(
      AuthorWritingEngineRequest(
        universe: const Selector('World'),
        action: PrepareContractsWritingAction(
          candidate: draft.proposal.proposalId,
          label: 'Unit definition',
          text: 'Metres measure length.',
        ),
      ),
    );
    final fields = WireFields(prepared, {
      'acceptance_options',
      'summary',
      'candidate',
      'validation',
      'impact',
      'publishable',
      'review',
    });
    final ref = ProposalRef.fromWire(fields.require('candidate'));
    final review = await second.executeWriting(
      AuthorWritingEngineRequest(
        universe: const Selector('World'),
        action: InspectWritingAction(candidate: ref),
      ),
    );
    final validation = ValidationV3.fromWire(
      WireFields(review, {
        'acceptance_options',
        'summary',
        'candidate',
        'validation',
        'impact',
        'publishable',
        'review',
      }).require('validation'),
    );
    final publish = AuthorWritingEngineRequest(
      universe: const Selector('World'),
      action: PublishWritingAction(
        candidate: ref,
        validationRun: validation.execution!.runId,
        idempotencyKey: 'runtime-publication',
      ),
    );
    final response = await first.executeWriting(publish);
    final receipt = Envelope<CommitReceipt>.fromWire(
      response,
      CommitReceipt.fromWire,
    ).result;
    final oldInstance = first.welcome.serviceInstance;
    await runtime.close();
    expect(() => second.executeWriting(stage), throwsStateError);
    final package = OwnedSqliteDatabase.openExisting(path);
    try {
      package.recover();
      expect(
        SqliteKernel(
          package.database,
          f.u,
        ).journal.head(frames.frame().continuity),
        receipt.revision,
      );
      expect(WorkflowStorage(package.database).keys('approval:'), hasLength(1));
    } finally {
      package.close();
    }
    runtime = NativeSqliteRuntime(authority: authority);
    final restarted = runtime.connect(hello(author.id));
    expect(restarted.welcome.serviceInstance, isNot(oldInstance));
    expect(
      (await restarted.executeWriting(publish)).toText(),
      response.toText(),
    );
  });

  test(
    'runtime shutdown drains admitted work before releasing package ownership',
    () async {
      final connection = runtime.connect(hello(author.id));
      final entered = Completer<void>(), release = Completer<void>();
      final held = authority.coordinate(author, () async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final pending = connection.executeWriting(stage);
      var closed = false;
      final shutdown = runtime.close().then((_) {
        closed = true;
      });
      await Future<void>.value();
      expect(closed, isFalse);
      expect(() => runtime.connect(hello(author.id)), throwsStateError);
      expect(() => connection.executeWriting(stage), throwsStateError);
      release.complete();
      await held;
      await pending;
      await shutdown;
      final package = OwnedSqliteDatabase.openExisting(path);
      try {
        package.recover();
        expect(
          WorkflowStorage(package.database).keys('source-version:'),
          hasLength(1),
        );
      } finally {
        package.close();
      }
    },
  );

  test(
    'failed worker open can retry without retaining a failed ownership slot',
    () async {
      final blocker = OwnedSqliteDatabase.openExisting(path);
      final connection = runtime.connect(hello(author.id));
      try {
        await expectLater(
          connection.executeWriting(stage),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        blocker.close();
      }
      final staged = WireFields(await connection.executeWriting(stage), {
        'canonical',
        'operations',
      });
      expect(staged.boolean('canonical'), isFalse);
    },
  );

  test(
    'handshake and current rights are checked before opening private workers',
    () async {
      expect(
        () => runtime.connect(hello(author.id, version: 'wrong')),
        throwsFormatException,
      );
      final connection = runtime.connect(hello(writer.id));
      await expectLater(
        connection.executeWriting(stage),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      authority.revoke(author, writer.id);
      await expectLater(
        connection.executeWriting(stage),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      final package = OwnedSqliteDatabase.openExisting(path);
      try {
        expect(WorkflowStorage(package.database).keys('source:'), isEmpty);
      } finally {
        package.close();
      }
      connection.close();
    },
  );
}
