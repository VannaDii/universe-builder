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
import 'package:ub_service/postgres_validation.dart';
import 'package:ub_service/validation_scheduler.dart';
import 'package:ub_service/validation_worker.dart';
import 'package:ub_service/proposal_state.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/ub_store.dart';
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_values.dart';

import 'operation_compilation_test.dart' as f;
import 'structural_checks_test.dart' as structure;
import 'rule_checks_test.dart' as frames;
import 'source_verification_test.dart' as sources;
import 'assessment_validation_test.dart' as assessments;
import 'required_evidence_sources_test.dart' as evidence;
import 'fictional_departures_test.dart' as departures;
import 'required_evidence_reviews_test.dart' as reviews;
import 'required_event_evidence_test.dart' as event_evidence;
import 'knowledge_checks_test.dart' as knowledge;
import 'resource_checks_test.dart' as resources;
import '../../ub_contracts/test/assessment_integrity_test.dart' as accounting;

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  late PostgresInstallationStore store;
  late Connection observer;
  late ProfileId owner, writer;
  late ContinuityId continuity;
  late Frame frame;
  late ContextId writerContext;
  var now = BigInt.from(100);
  const secret = 'disposable-proposal-profile';
  final hash = sha256.convert(utf8.encode(secret)).toString();
  Future<PostgresInstallationStore> open({bool create = false}) {
    final endpoint = Endpoint(
      host: '127.0.0.1',
      port: port!,
      database: 'ub_disposable',
      username: 'postgres',
    );
    const settings = ConnectionSettings(sslMode: SslMode.disable);
    return create
        ? PostgresInstallationStore.create(endpoint, settings: settings)
        : PostgresInstallationStore.openExisting(endpoint, settings: settings);
  }

  Future<T> run<T>(
    ProfileId actor,
    Future<T> Function(PostgresValidationWorkflow) action,
  ) => store.transaction((s) async {
    final authority = PostgresServiceAuthority(
      s.authority,
      epochSeconds: () => now,
    );
    final principal = await authority.authenticate(
      profile: actor,
      credential: Credential(secret),
    );
    return action(
      PostgresValidationWorkflow(
        session: s,
        universe: f.u,
        authority: authority,
        principal: principal,
        epochSeconds: () => now,
      ),
    );
  });
  Future<void> seed(List<RecordVersion> records) =>
      store.transaction((s) async {
        final journal = s.kernel(f.u).journal;
        final head = await journal.head(continuity);
        final membership = await journal.snapshot(continuity, head);
        await s
            .kernel(f.u)
            .commit(
              CommitInput(
                universe: f.u,
                continuity: continuity,
                expectedHead: head,
                principal: PrincipalId.generate(),
                decision: 'Disposable author action setup',
                reason: 'Disposable author action setup',
                idempotencyKey: 'author-action-fixture',
                changes: [
                  for (final row in records)
                    Assignment(
                      recordId: row.identity.recordId,
                      expected: membership[row.identity.recordId],
                      next: StoredVersion.build(
                        row.recordVersionId,
                        row.identity,
                        row.payload.toWire(),
                      ),
                    ),
                ],
              ),
            );
      });
  Future<WireFields> authorAction(AuthorWritingAction action) async =>
      WireFields(
        await run(
          owner,
          (w) => w.executeWritingEngineRequest(
            AuthorWritingEngineRequest(
              universe: const Selector('Disposable universe'),
              action: action,
            ),
            isValidationActive: (_) => false,
          ),
        ),
        {
          'acceptance_options',
          'summary',
          'candidate',
          'validation',
          'impact',
          'publishable',
          'review',
        },
      );
  CreateProposalRequest create({
    String key = 'create',
    Submission submission = Submission.submitted,
    int record = 10,
  }) => CreateProposalRequest(
    universe: const Selector('Disposable universe'),
    universeId: f.u,
    contextId: writerContext,
    operations: [
      CreateEntityOperation(clientRef: f.id(record).value, record: f.entity()),
    ],
    submission: submission,
    rationale: 'Disposable authoring',
    idempotencyKey: key,
  );
  ProposalRef reference(Proposal p) => ProposalRef(
    proposalId: p.proposalId,
    version: p.version,
    digest: p.digest,
  );
  Future<Proposal> propose(WorkflowRequest request) => run(
    writer,
    (w) => w.proposeRequest(request, isValidationActive: (_) => false),
  );
  Future<ValidationV3> validate(Proposal p) => run(
    writer,
    (w) => w.validateProposalRequest(
      ProposalValidationRequest(
        universe: const Selector('Disposable universe'),
        universeId: f.u,
        contextId: writerContext,
        proposalReference: reference(p),
        checkScope: CheckScope.candidate,
      ),
    ),
  );
  Future<OpenedContext> openContext(
    ProfileId actor, {
    RevisionSelector revision = const HeadRevisionSelector(),
    UniverseId? guard,
    RecordId? represented,
  }) => run(
    actor,
    (w) => w.openContext(
      OpenContextRequest(
        universe: const Selector('Disposable universe'),
        universeId: guard ?? f.u,
        continuityId: continuity,
        revision: revision,
        representedContext: ContextIdSelector(represented ?? f.id(99)),
        temporalQuery: const TimelessFrameTime(),
        temporalSystems: [],
        perspective: const AuthorPerspective(),
      ),
    ),
  );
  Future<void> refreshContext() async {
    final opened = await openContext(writer);
    writerContext = opened.contextId;
    frame = opened.frame;
  }

  Future<({Proposal proposal, SourceAssessmentV1 body})>
  researchedProposal() async {
    await store.transaction((s) async {
      await s
          .workflows(f.u)
          .compareAppend(
            {},
            sources.staging(sources.source()).entries.toList(),
          );
      final rows = [
        f.row(
          1,
          SourceRecord(
            label: 'External source',
            origin: const OriginMetadata(),
            versions: [f.id(2)],
          ),
        ),
        f.row(2, sources.source()),
      ];
      await s
          .kernel(f.u)
          .commit(
            CommitInput(
              universe: f.u,
              continuity: continuity,
              expectedHead: frame.revision,
              principal: PrincipalId.generate(),
              decision: 'Source fixture',
              reason: 'Retained external research',
              idempotencyKey: 'sources',
              changes: [
                for (final version in rows)
                  Assignment(
                    recordId: version.identity.recordId,
                    expected: null,
                    next: StoredVersion.build(
                      version.recordVersionId,
                      version.identity,
                      version.payload.toWire(),
                    ),
                  ),
              ],
            ),
          );
    });
    await refreshContext();
    final proposal = await propose(create());
    var wire = accounting.replace(assessments.body().toWire(), [
      'proposal',
    ], reference(proposal).toWire());
    wire = accounting.replace(wire, ['base_frame'], frame.toWire());
    wire = accounting.replace(wire, [
      'assessor',
      'principal',
    ], CanonicalString(writer.value.replaceFirst('prf_', 'prn_')));
    return (proposal: proposal, body: SourceAssessmentV1.fromWire(wire));
  }

  Future<AssessmentSelection> attach(
    Proposal p,
    SourceAssessmentV1 body, {
    String key = 'attach',
    BigInt? generation,
  }) => run(
    writer,
    (w) => w.assessmentRequest(
      AttachAssessmentRequest(
        universe: const Selector('Disposable universe'),
        universeId: f.u,
        contextId: writerContext,
        proposalReference: reference(p),
        expectedSelectionGeneration: generation ?? BigInt.zero,
        body: body,
        idempotencyKey: key,
      ),
    ),
  );
  Future<AssessmentSelection> select(
    Proposal p,
    AssessmentRef? selected,
    BigInt generation,
    String key,
  ) => run(
    writer,
    (w) => w.assessmentRequest(
      SelectAssessmentRequest(
        universe: const Selector('Disposable universe'),
        universeId: f.u,
        contextId: writerContext,
        proposalReference: reference(p),
        expectedSelectionGeneration: generation,
        assessmentReference: selected,
        idempotencyKey: key,
      ),
    ),
  );
  QueuedProposalValidationRequest queued(Proposal p) =>
      QueuedProposalValidationRequest(
        universe: const Selector('Disposable universe'),
        universeId: f.u,
        contextId: writerContext,
        proposalReference: reference(p),
        checkScope: CheckScope.candidate,
        idempotencyKey: 'queue',
      );
  CancelOperationRequest cancel(OperationId id) => CancelOperationRequest(
    universe: const Selector('Disposable universe'),
    universeId: f.u,
    operationId: id,
    idempotencyKey: 'cancel',
  );
  CommitRequest request(
    Proposal p,
    ValidationRunId validation, {
    String key = 'commit',
    RevisionId? base,
  }) => CommitRequest(
    universe: const Selector('Disposable universe'),
    universeId: f.u,
    proposalReference: reference(p),
    expectedBaseRevision: base ?? frame.revision,
    validationRun: validation,
    idempotencyKey: key,
  );
  Future<CommitReceipt> commit(CommitRequest request) =>
      run(writer, (w) => w.commit(request, isValidationActive: (_) => false));
  final stale = throwsA(isA<ApprovalStaleError>());
  group(
    'PostgreSQL exact proposal publication',
    () {
      setUp(() async {
        now = BigInt.from(100);
        owner = ProfileId.generate();
        writer = ProfileId.generate();
        continuity = ContinuityId.generate();
        observer = await Connection.open(
          Endpoint(
            host: '127.0.0.1',
            port: port!,
            database: 'ub_disposable',
            username: 'postgres',
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        store = await open(create: true);
        final base = await store.transaction((s) async {
          await s.authority.enroll(id: owner, credentialHash: hash);
          await s.authority.enroll(
            id: writer,
            credentialHash: hash,
            actor: owner,
          );
          final genesis = await s.createUniverse(
            actor: owner,
            universe: f.u,
            name: 'Disposable universe',
            continuity: continuity,
            principal: PrincipalId.generate(),
          );
          // Seed only the pre-existing represented context; authoring below uses
          // real proposal creation, factual evaluation and private author approval.
          final context = structure.context(99);
          final revision = await s
              .kernel(f.u)
              .commit(
                CommitInput(
                  universe: f.u,
                  continuity: continuity,
                  expectedHead: genesis,
                  principal: PrincipalId.generate(),
                  decision: 'Fixture context',
                  reason: 'Disposable setup',
                  idempotencyKey: 'context',
                  changes: [
                    Assignment(
                      recordId: context.identity.recordId,
                      expected: null,
                      next: StoredVersion.build(
                        context.recordVersionId,
                        context.identity,
                        context.payload.toWire(),
                      ),
                    ),
                  ],
                ),
              );
          await s.authority.putGrant(
            actor: owner,
            grant: GrantSpec(
              profileId: writer,
              universeId: f.u,
              worlds: null,
              propose: true,
              edit: true,
              protected: false,
            ),
            epochSeconds: now,
          );
          return revision;
        });
        frame = Frame(
          universe: f.u,
          continuity: continuity,
          revision: base,
          context: f.ref(99),
          time: const TimelessFrameTime(),
          perspective: const AuthorPerspective(),
        );
        await refreshContext();
      });
      tearDown(() async {
        await store.close();
        try {
          await observer.execute(
            'DROP SCHEMA IF EXISTS ${postgresUniverseSchema(f.u)} CASCADE',
          );
          await observer.execute(
            'DROP SCHEMA IF EXISTS ${postgresAuthorityNamespace(store.instanceId)} CASCADE',
          );
        } finally {
          await observer.close();
        }
      });
      for (final includeEvents in [false, true]) {
        for (final (requiresReview, fictional) in [
          (false, false),
          (true, false),
          (true, true),
        ]) {
          test(
            'scoped evidence policy validates and publishes through PostgreSQL with review=$requiresReview events=$includeEvents fictional=$fictional',
            () async {
              final rows =
                  (includeEvents
                          ? event_evidence.fixture(effect: true)
                          : evidence.fixture())
                      .where(
                        (r) => ![
                          f.id(99),
                          f.id(10),
                          f.id(40),
                        ].contains(r.identity.recordId),
                      )
                      .toList();
              final source = SourceVersionRecord.fromWire(
                accounting.replace(
                  rows
                      .singleWhere((r) => r.identity.recordId == f.id(12))
                      .payload
                      .toWire(),
                  ['source'],
                  f.ref(14).toCanonical(),
                ),
              );
              evidence.replace(rows, 12, source);
              rows.addAll([
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
                  14,
                  SourceRecord(
                    label: 'Private recollection',
                    origin: const OriginMetadata(),
                    versions: [f.id(12)],
                  ),
                ),
              ]);
              if (fictional) {
                rows.addAll([
                  f.row(
                    40,
                    evidence.policy(
                      predicates: includeEvents ? [] : ['test:answer'],
                      reviewMethods: [EvidenceReviewMethod.humanReview],
                    ),
                  ),
                  f.row(
                    41,
                    IssueDecisionRecord(
                      fingerprints: [],
                      mode: IssueDecisionMode.accept,
                      scope: f.id(40).value,
                      rationale: 'Explicit scoped fiction',
                      principal: PrincipalId.parse(
                        owner.value.replaceFirst('prf_', 'prn_'),
                      ),
                    ),
                  ),
                ]);
              }
              await store.transaction(
                (s) => s.workflows(f.u).compareAppend({}, [
                  MapEntry('source-version:${f.id(12).value}', source.toWire()),
                  MapEntry(
                    'source:${source.contentDigest}',
                    CanonicalString(sources.sourceText),
                  ),
                ]),
              );
              await seed(rows);
              await store.transaction(
                (s) => s.authority.putGrant(
                  actor: owner,
                  grant: GrantSpec(
                    profileId: writer,
                    universeId: f.u,
                    worlds: null,
                    propose: true,
                    edit: true,
                    protected: true,
                  ),
                  epochSeconds: now,
                ),
              );
              await refreshContext();
              final proposal = await propose(
                CreateProposalRequest(
                  universe: const Selector('Disposable universe'),
                  universeId: f.u,
                  contextId: writerContext,
                  operations: [
                    if (fictional)
                      AddExceptionOperation(
                        clientRef: f.id(50).value,
                        record: departures.departure(
                          policy: 40,
                          decision: 41,
                          validity: const UnspecifiedValidity(),
                        ),
                      )
                    else
                      DefineRuleOperation(
                        clientRef: f.id(40).value,
                        record: evidence.policy(
                          predicates: includeEvents ? [] : ['test:answer'],
                          reviewMethods: requiresReview
                              ? [EvidenceReviewMethod.humanReview]
                              : [],
                        ),
                      ),
                  ],
                  submission: Submission.submitted,
                  rationale: 'Scoped evidence policy',
                  idempotencyKey: 'scoped-policy',
                ),
              );
              final initial = await validate(proposal) as EvaluatedValidation;
              expect(
                initial.execution.findings.any(
                  (f) => f.outcome == EvidenceOutcome.notEstablished,
                ),
                requiresReview,
              );
              if (requiresReview && !fictional) {
                CanonicalValue body =
                    (includeEvents
                            ? event_evidence.review(rows, includeEffect: true)
                            : reviews.review())
                        .envelope!
                        .body
                        .toWire();
                body = accounting.replace(body, [
                  'proposal',
                ], reference(proposal).toWire());
                body = accounting.replace(body, [
                  'base_frame',
                ], proposal.baseFrame.toWire());
                body = accounting.replace(body, [
                  'assessor',
                  'principal',
                ], CanonicalString(writer.value.replaceFirst('prf_', 'prn_')));
                await attach(proposal, SourceAssessmentV1.fromWire(body));
              }
              final queuedStatus = await run(
                writer,
                (w) => w.queueValidationRequest(
                  queued(proposal),
                  isValidationActive: (_) => false,
                ),
              );
              final task = (await run(
                writer,
                (w) => w.prepareValidation(
                  queuedStatus.operationId,
                  isValidationActive: (_) => true,
                ),
              ))!;
              expect(task.selectedAssessment != null, requiresReview);
              final checked = await ValidationEvaluationWorker(task).result;
              expect(checked.admissible, isTrue);
              await run(
                writer,
                (w) => w.finishValidation(
                  queuedStatus.operationId,
                  checked,
                  isValidationActive: (_) => true,
                ),
              );
              if (fictional)
                expect(
                  checked.validation.findings.any(
                    (f) =>
                        f.outcome == EvidenceOutcome.notEstablished &&
                        f.message?.startsWith('Fictional departure:') == true,
                  ),
                  isTrue,
                );
              await run(
                owner,
                (w) => w.approve(reference(proposal), checked.validation.runId),
              );
              final receipt = await commit(
                request(proposal, checked.validation.runId),
              );
              final head = await store.transaction(
                (s) => s.kernel(f.u).journal.head(continuity),
              );
              expect(head, receipt.revision);
              if (!requiresReview && !includeEvents) {
                await refreshContext();
                final upgrading = await propose(
                  CreateProposalRequest(
                    universe: const Selector('Disposable universe'),
                    contextId: writerContext,
                    operations: [
                      UpgradePackOperation(
                        record: f.ref(11),
                        expectedVersion: f.ver(11),
                        replacement: DomainPackRecord(
                          key: 'private_memories',
                          version: '2',
                          dependencies: {},
                          capabilities: [],
                          records: [],
                        ),
                      ),
                    ],
                    submission: Submission.submitted,
                    rationale: 'Revise source category',
                    idempotencyKey: 'upgrade-category',
                  ),
                );
                final synchronous =
                    await validate(upgrading) as EvaluatedValidation;
                expect(
                  synchronous.execution.findings
                      .where((finding) => finding.records.contains(f.ref(4)))
                      .single
                      .outcome,
                  EvidenceOutcome.supported,
                );
                final operation = await run(
                  writer,
                  (w) => w.queueValidationRequest(
                    QueuedProposalValidationRequest(
                      universe: const Selector('Disposable universe'),
                      contextId: writerContext,
                      proposalReference: reference(upgrading),
                      checkScope: CheckScope.candidate,
                      idempotencyKey: 'upgrade-category-check',
                    ),
                    isValidationActive: (_) => false,
                  ),
                );
                final task = (await run(
                  writer,
                  (w) => w.prepareValidation(
                    operation.operationId,
                    isValidationActive: (_) => true,
                  ),
                ))!;
                expect(
                  task.evidenceCategories.single.recordVersionId,
                  f.ver(11),
                );
                final result = await ValidationEvaluationWorker(task).result;
                expect(result.admissible, isTrue);
                await run(
                  writer,
                  (w) => w.finishValidation(
                    operation.operationId,
                    result,
                    isValidationActive: (_) => true,
                  ),
                );
                await run(
                  owner,
                  (w) =>
                      w.approve(reference(upgrading), result.validation.runId),
                );
                final published = await commit(
                  request(
                    upgrading,
                    result.validation.runId,
                    key: 'upgrade-category-publish',
                  ),
                );
                final current = await store.transaction((s) async {
                  final journal = s.kernel(f.u).journal;
                  final membership = await journal.snapshot(
                    continuity,
                    published.revision,
                  );
                  return [
                    for (final version in membership.values)
                      RecordVersion.fromWire(
                        (await journal.load(version)).toCanonical(),
                      ),
                  ];
                });
                final category = current.singleWhere(
                  (r) => r.identity.recordId == f.id(11),
                );
                final rule = current.singleWhere(
                  (r) => r.identity.recordId == f.id(40),
                );
                expect(category.recordVersionId, isNot(f.ver(11)));
                expect(
                  (rule.payload as RuleRecord)
                      .requiredEvidence!
                      .sourceCategories
                      .single
                      .version,
                  f.ver(11),
                );
                await refreshContext();
                final replacement = RuleRecord.fromWire(
                  CanonicalObject(
                    rule.payload.toWire().fields.map(
                      (field) => MapEntry(
                        field.key,
                        field.key == 'requiredEvidence'
                            ? RequiredEvidence(
                                sourceCategories: [
                                  VersionRef(
                                    universe: f.u,
                                    record: f.id(11),
                                    version: category.recordVersionId,
                                  ),
                                ],
                              ).toWire()
                            : field.value,
                      ),
                    ),
                  ),
                );
                final changed = await propose(
                  CreateProposalRequest(
                    universe: const Selector('Disposable universe'),
                    contextId: writerContext,
                    operations: [
                      ReviseDefinitionOperation(
                        record: f.ref(40),
                        expectedVersion: rule.recordVersionId,
                        replacement: replacement,
                      ),
                    ],
                    submission: Submission.submitted,
                    rationale: 'Choose the new category version',
                    idempotencyKey: 'new-policy-pin',
                  ),
                );
                final report = await validate(changed) as EvaluatedValidation;
                expect(
                  report.execution.findings.any(
                    (finding) =>
                        finding.ruleId == f.id(40) &&
                        finding.outcome == EvidenceOutcome.notEstablished,
                  ),
                  isTrue,
                );
              }
            },
          );
        }
      }
      test('readable proposition search and summaries agree in the pinned PostgreSQL context', () async {
        await seed([
          f.row(
            1,
            EntityRecord(
              names: [],
              classificationResolution: ClassificationResolution.unclassified,
              worldAssociations: [],
              labels: {'en': 'Mara'},
              metadata: {},
            ),
          ),
          f.row(
            2,
            PropertyRecord(
              namespace: 'authored',
              key: 'age',
              labels: {'en': 'Age'},
              subjectTypes: [],
              value: const SimpleValueShape(SimpleShapeKind.integer),
              multiplicity: Multiplicity.single,
              persistence: PersistenceSemantics.unspecified,
              exclusive: false,
              symmetric: false,
              transitive: false,
            ),
          ),
          f.row(
            4,
            PropositionRecord(
              subject: f.ref(1),
              predicate: f.ref(2),
              context: f.ref(99),
              quantification: Quantification.particular,
              value: IntegerValue('9007199254740997'),
            ),
          ),
        ]);
        await refreshContext();
        final found = await run(
          writer,
          (w) => w.searchRequest(
            SearchRequest(
              universe: const Selector('Disposable universe'),
              contextId: writerContext,
              query: 'Mara.Age',
              typedFilters: Filters(recordKinds: [RecordKind.proposition]),
              limit: 100,
            ),
          ),
        );
        final summary = await run(
          writer,
          (w) => w.getRequest(
            GetRequest(
              universe: const Selector('Disposable universe'),
              contextId: writerContext,
              recordIds: [f.id(4)],
              fieldGroups: [FieldGroup.summary],
            ),
          ),
        );
        expect(found.results.hits.single.recordId, f.id(4));
        expect(
          summary.summaries.single.label,
          'Particular: Mara.Age = 9007199254740997 [${f.id(99).value}]',
        );
        expect(found.results.hits.single.label, summary.summaries.single.label);
        expect(summary.records, isEmpty);
      });
      test('private knowledge establishes only attributed claims and preserves original acquisition during duration edits', () async {
        final clock = FictionalUniverseStart(
          calendarName: 'Knowledge clock',
          initialTick: '0',
          tickLabel: 'ticks',
        ).build(frames.calendar);
        final context = f.ref(55);
        final original = EpistemicAttitudeRecord(
          holder: f.ref(80),
          proposition: f.ref(2),
          attitude: EpistemicAttitudeKind.knows,
          certainty: 'authored',
          validity: CalendarIntervalValidity(
            frames.calendar,
            const ExactBound('10'),
            const ExactBound('30'),
          ),
          basis: const AuthorDecisionBasis('Original author decision'),
          acquisition: KnowledgeAcquisition(
            truthContext: context,
            time: ExactTime(frames.calendar, '10'),
            basis: const AuthorEstablishedKnowledge(),
          ),
        );
        await seed([
          f.row(10, clock.$2),
          f.row(
            55,
            RepresentedContextRecord(
              universe: f.u,
              kind: const ObjectiveContext(),
              chronology: clock.$1,
              labels: {},
            ),
          ),
          f.row(
            80,
            EntityRecord(
              names: [],
              classificationResolution: ClassificationResolution.unclassified,
              worldAssociations: [],
              labels: {'en': 'Mara'},
              metadata: {},
            ),
          ),
          frames.fixture().first,
          f.row(
            2,
            PropositionRecord(
              subject: f.ref(80),
              predicate: f.ref(1),
              context: context,
              value: const BooleanValue(true),
              quantification: Quantification.particular,
            ),
          ),
          f.row(
            7,
            knowledge.policy(
              mode: KnowledgeMode.authorEstablished,
              context: context,
            ),
          ),
          f.row(6, original),
        ]);
        final selected = await openContext(writer, represented: f.id(55));
        final action = EstablishKnowledgeWritingAction(
          contextId: selected.contextId,
          declaration: AuthorKnowledgeDeclaration(
            holder: 'Mara',
            claim: WritingClaim(
              subject: 'Mara',
              property: 'open',
              value: const FactBooleanValue(false),
            ),
            atTick: '9007199254740993',
            lifetime: const FactUntilLifetime(endTick: '9007199254740995'),
          ),
          rationale: 'Explicit author knowledge',
          label: 'Author passage',
          text: 'Mara knows the gate is closed.',
        );
        await expectLater(
          run(
            writer,
            (w) => w.executeWritingEngineRequest(
              AuthorWritingEngineRequest(
                universe: const Selector('Disposable universe'),
                action: action,
              ),
              isValidationActive: (_) => false,
            ),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final reviewed = await authorAction(action);
        final ref = ProposalRef.fromWire(reviewed.require('candidate'));
        final retained = await store.transaction(
          (s) async => StoredProposal.fromWire(
            (await s.workflows(f.u).get(proposalKey(ref)))!,
          ),
        );
        expect(retained.owner, owner);
        expect(retained.authorOrigin, isTrue);
        expect(
          retained.proposal.operations.whereType<AssertPropositionOperation>(),
          isEmpty,
        );
        final attitude = retained.proposal.operations
            .whereType<AddBeliefOperation>()
            .single
            .record;
        expect(attitude.basis, AuthorDecisionBasis(action.rationale));
        expect(attitude.acquisition!.basis, isA<AuthorEstablishedKnowledge>());
        expect(
          attitude.acquisition!.time,
          ExactTime(frames.calendar, '9007199254740993'),
        );
        final edit = EditKnowledgeWritingAction(
          contextId: selected.contextId,
          correction: WritingAttitudeCorrection(
            attitudeHandle: f.ver(6).value,
            reason: 'Correct authored duration',
            endTick: '20',
          ),
          label: 'Corrected notes',
          text: 'Mara knew until twenty.',
        );
        final edited = await authorAction(edit);
        final editRef = ProposalRef.fromWire(edited.require('candidate'));
        final replacement = await store.transaction(
          (s) async =>
              StoredProposal.fromWire(
                    (await s.workflows(f.u).get(proposalKey(editRef)))!,
                  ).proposal.operations
                  .whereType<ReviseAttitudeOperation>()
                  .single
                  .replacement,
        );
        expect(replacement.proposition, original.proposition);
        expect(replacement.holder, original.holder);
        expect(replacement.basis, original.basis);
        expect(
          replacement.acquisition!.toWire().toText(),
          original.acquisition!.toWire().toText(),
        );
        expect(
          replacement.validity,
          CalendarIntervalValidity(
            frames.calendar,
            const ExactBound('10'),
            const ExactBound('20'),
          ),
        );
        await expectLater(
          authorAction(
            EditKnowledgeWritingAction(
              contextId: selected.contextId,
              correction: WritingAttitudeCorrection(
                attitudeHandle: f.ver(6).value,
                reason: 'Change claim',
                value: const FactBooleanValue(false),
              ),
              label: 'Changed claim',
              text: 'Changed claim',
            ),
          ),
          throwsA(isA<FormatException>()),
        );
        await store.close();
        store = await open();
        expect(
          ProposalRef.fromWire(
            (await authorAction(action)).require('candidate'),
          ).toWire().toText(),
          ref.toWire().toText(),
        );
        expect(
          ProposalRef.fromWire((await authorAction(edit)).require('candidate'))
              .toWire()
              .toText(),
          editRef.toWire().toText(),
        );
        await store.transaction((s) async {
          expect(await s.workflows(f.u).keys('source-version:'), hasLength(2));
          expect(await s.workflows(f.u).keys('approval:'), isEmpty);
          expect(
            await s.kernel(f.u).journal.head(continuity),
            selected.frame.revision,
          );
        });
        final report = ValidationV3.fromWire(reviewed.require('validation'));
        now = BigInt.from(200000);
        await expectLater(
          authorAction(action),
          throwsA(isA<ContextExpiredError>()),
        );
        await expectLater(
          authorAction(edit),
          throwsA(isA<ContextExpiredError>()),
        );
        now = BigInt.from(100);
        final receipt = CommitReceipt.fromWire(
          await run(
            owner,
            (w) => w.authorWritingAction(
              PublishWritingAction(
                candidate: ref,
                validationRun: report.execution!.runId,
                idempotencyKey: 'publish-knowledge',
              ),
              isValidationActive: (_) => false,
            ),
          ),
        );
        final payloads = await store.transaction((s) async {
          final journal = s.kernel(f.u).journal;
          return [
            for (final id in (await journal.snapshot(
              continuity,
              receipt.revision,
            )).values)
              RecordVersion.fromWire((await journal.load(id)).toCanonical())
                  .payload,
          ];
        });
        expect(payloads.whereType<AssertionRecord>(), isEmpty);
        expect(payloads.whereType<EpistemicAttitudeRecord>(), hasLength(2));
      });
      test('private resource acceptance preserves exact source versions without approving or publishing the accepted finding', () async {
        final clock = FictionalUniverseStart(
          calendarName: 'Campaign clock',
          initialTick: '0',
          tickLabel: 'ticks',
        ).build(resources.cal);
        await seed([
          ...resources.fixture(),
          f.row(6, clock.$2),
          f.row(
            5,
            RepresentedContextRecord(
              universe: f.u,
              kind: const ObjectiveContext(),
              chronology: clock.$1,
              labels: {},
            ),
          ),
        ]);
        final opened = await openContext(owner, represented: f.id(5));
        final draft = await run(
          owner,
          (w) => w.proposeRequest(
            CreateProposalRequest(
              universe: const Selector('Disposable universe'),
              contextId: opened.contextId,
              operations: [
                AddNameOperation(
                  record: f.ref(3),
                  expectedVersion: f.ver(3),
                  name: const ContextualName(
                    text: 'Actor',
                    validity: UnspecifiedValidity(),
                  ),
                ),
              ],
              submission: Submission.draft,
              rationale: 'Resource timeline review',
              idempotencyKey: 'resource-draft',
            ),
            isValidationActive: (_) => false,
          ),
        );
        final prepared = await authorAction(
          PrepareWritingAction(
            candidate: draft.proposalId,
            label: 'Session notes',
            text: 'The actor acquired another round at tick five.',
          ),
        );
        expect(prepared.boolean('publishable'), isFalse);
        final ref = ProposalRef.fromWire(prepared.require('candidate'));
        final option = WireFields(prepared.array('acceptance_options').single, {
          'fingerprint',
          'scope',
        });
        final action = AcceptWritingAction(
          candidate: ref,
          fingerprint: FindingFingerprint(option.string('fingerprint')),
          scope: option.string('scope'),
          rationale: 'Author accepts this exact unexplained arrival',
        );
        Future<List<String>> sourceVersions(ProposalRef ref) =>
            store.transaction((s) async {
              final stored = StoredProposal.fromWire(
                (await s.workflows(f.u).get(proposalKey(ref)))!,
              );
              return stored.changes
                  .where((c) => c.next != null)
                  .map((c) => RecordVersion.fromWire(c.next!.toCanonical()))
                  .where((r) => r.payload is SourceVersionRecord)
                  .map((r) => r.toWire().toText())
                  .toList();
            });
        final sources = await sourceVersions(ref);
        await expectLater(
          authorAction(
            AcceptWritingAction(
              candidate: ref,
              fingerprint: action.fingerprint,
              scope: 'wrong scope',
              rationale: action.rationale,
            ),
          ),
          throwsA(isA<InvalidArgumentError>()),
        );
        final accepted = await authorAction(action);
        final next = ProposalRef.fromWire(accepted.require('candidate'));
        expect(next.version, ref.version + BigInt.one);
        expect(accepted.boolean('publishable'), isTrue);
        expect(accepted.array('acceptance_options'), isEmpty);
        expect(await sourceVersions(next), sources);
        await store.close();
        store = await open();
        expect(
          ProposalRef.fromWire(
            (await authorAction(action)).require('candidate'),
          ).toWire().toText(),
          next.toWire().toText(),
        );
        expect(await sourceVersions(next), sources);
        await store.transaction((s) async {
          expect(
            await s.kernel(f.u).journal.head(continuity),
            opened.frame.revision,
          );
          expect(await s.workflows(f.u).keys('approval:'), isEmpty);
          expect(await s.workflows(f.u).keys('source-version:'), hasLength(1));
        });
      });
      test('queued validation uses the native isolate scheduler with fresh PostgreSQL transactions', () async {
        final researched = await researchedProposal();
        await attach(researched.proposal, researched.body);
        final status = await run(
          writer,
          (w) => w.queueValidationRequest(
            queued(researched.proposal),
            isValidationActive: (_) => false,
          ),
        );
        final principal = await store.transaction(
          (s) => PostgresServiceAuthority(s.authority)
              .authenticate(profile: writer, credential: Credential(secret)),
        );
        final scheduler = NativeValidationScheduler();
        try {
          await scheduler.schedule(
            PostgresValidationJobs(
              store: store,
              universe: f.u,
              principal: principal,
              epochSeconds: () => now,
            ),
            status.operationId,
          );
          expect(scheduler.isActive(f.u, status.operationId), isFalse);
          final completed = await run(
            writer,
            (w) => w.operationStatus(
              status.operationId,
              isValidationActive: (_) => false,
            ),
          );
          expect(completed.state, OperationState.succeeded);
          final report = completed.validation as EvaluatedValidation;
          expect(report.finalBindingDigest, isNotNull);
          await run(
            owner,
            (w) => w.approve(
              reference(researched.proposal),
              report.execution.runId,
            ),
          );
          await commit(request(researched.proposal, report.execution.runId));
        } finally {
          await scheduler.close();
        }
      });
      test('terminated PostgreSQL preparation process resumes exact captured validation without publishing', () async {
        final researched = await researchedProposal();
        await attach(researched.proposal, researched.body);
        final queuedStatus = await run(
          writer,
          (w) => w.queueValidationRequest(
            queued(researched.proposal),
            isValidationActive: (_) => false,
          ),
        );
        final id = queuedStatus.operationId;
        final originalHead = await store.transaction(
          (s) => s.kernel(f.u).journal.head(continuity),
        );
        final directory = Directory.systemTemp.createTempSync(
          'universe-builder-validation-process-',
        );
        Process? process;
        StreamIterator<String>? lines;
        Future<String>? stderr;
        final scheduler = NativeValidationScheduler();
        try {
          final vm = File(Platform.resolvedExecutable);
          final dart = vm.uri.pathSegments.last == 'dartvm'
              ? '${vm.parent.path}/dart'
              : vm.path;
          final build = await Process.run(dart, [
            'build',
            'cli',
            '-o',
            directory.path,
            '--target',
            'test/helpers/postgres_validation_process.dart',
          ]);
          expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
          process = await Process.start(
            '${directory.path}/bundle/bin/postgres_validation_process',
            ['$port', writer.value, f.u.value, id.value],
          );
          stderr = process.stderr.transform(utf8.decoder).join();
          lines = StreamIterator(
            process.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter()),
          );
          expect(
            await lines.moveNext().timeout(const Duration(seconds: 30)),
            isTrue,
          );
          final capture = CanonicalValue.parseJson(lines.current).toText();
          expect(
            (await run(
              writer,
              (w) => w.operationStatus(id, isValidationActive: (_) => false),
            )).state,
            OperationState.running,
          );
          final competingPrincipal = await store.transaction(
            (s) => PostgresServiceAuthority(s.authority)
                .authenticate(profile: writer, credential: Credential(secret)),
          );
          await scheduler.schedule(
            PostgresValidationJobs(
              store: store,
              universe: f.u,
              principal: competingPrincipal,
              epochSeconds: () => now,
            ),
            id,
          );
          expect(scheduler.isActive(f.u, id), isFalse);
          await store.transaction((s) async {
            expect(
              await s.workflows(f.u).keys('job:${id.value}:terminal'),
              isEmpty,
            );
            expect(await s.isValidationActive(f.u, id), isTrue);
          });
          expect(await store.acquireValidation(f.u, id), isFalse);
          final independent = OperationId.generate();
          expect(await store.acquireValidation(f.u, independent), isTrue);
          await store.releaseValidation(f.u, independent);
          // SIGKILL skips the child's shutdown and leaves only committed work.
          expect(process.kill(ProcessSignal.sigkill), isTrue);
          expect(
            await process.exitCode.timeout(const Duration(seconds: 30)),
            isNot(0),
          );
          expect(await stderr, isEmpty);
          final interrupted = await run(
            writer,
            (w) => w.operationStatus(id, isValidationActive: (_) => false),
          );
          expect(interrupted.state, OperationState.interrupted);
          final resumed = (await run(
            writer,
            (w) => w.prepareValidation(id, isValidationActive: (_) => true),
          ))!;
          expect(resumed.capture!.toWire().toText(), capture);
          final principal = await store.transaction(
            (s) => PostgresServiceAuthority(s.authority)
                .authenticate(profile: writer, credential: Credential(secret)),
          );
          await scheduler.schedule(
            PostgresValidationJobs(
              store: store,
              universe: f.u,
              principal: principal,
              epochSeconds: () => now,
            ),
            id,
          );
          final completed = await run(
            writer,
            (w) => w.operationStatus(id, isValidationActive: (_) => false),
          );
          expect(completed.state, OperationState.succeeded);
          final report = completed.validation as EvaluatedValidation;
          expect(report.finalBindingDigest, isNotNull);
          final retained = completed.toWire().toText();
          expect(await store.acquireValidation(f.u, id), isTrue);
          expect(await store.acquireValidation(f.u, id), isFalse);
          await store.releaseValidation(f.u, id);
          final missing = OperationId.generate();
          await expectLater(
            scheduler.schedule(
              PostgresValidationJobs(
                store: store,
                universe: f.u,
                principal: principal,
                epochSeconds: () => now,
              ),
              missing,
            ),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
          expect(scheduler.isActive(f.u, missing), isFalse);
          expect(await store.acquireValidation(f.u, missing), isTrue);
          await store.releaseValidation(f.u, missing);
          await store.close();
          store = await open();
          expect(
            (await run(
              writer,
              (w) => w.operationStatus(id, isValidationActive: (_) => false),
            )).toWire().toText(),
            retained,
          );
          await store.transaction((s) async {
            expect(await s.kernel(f.u).journal.head(continuity), originalHead);
            expect(await s.workflows(f.u).keys('approval:'), isEmpty);
            expect(
              await s.workflows(f.u).keys('job:${id.value}:terminal'),
              hasLength(1),
            );
            await s.verifyUniverse(f.u, complete: true);
          });
        } finally {
          process?.kill(ProcessSignal.sigkill);
          if (process != null) await process.exitCode;
          await lines?.cancel();
          await stderr;
          await scheduler.close();
          directory.deleteSync(recursive: true);
        }
      });

      test('queued source validation completes outside transactions and retains exact results through reconnect', () async {
        final researched = await researchedProposal();
        await attach(researched.proposal, researched.body);
        final queuedStatus = await run(
          writer,
          (w) => w.queueValidationRequest(
            queued(researched.proposal),
            isValidationActive: (_) => false,
          ),
        );
        final id = queuedStatus.operationId;
        expect(queuedStatus.state, OperationState.queued);
        final task = await run(
          writer,
          (w) => w.prepareValidation(id, isValidationActive: (_) => true),
        );
        expect(task, isNotNull);
        await store.close();
        store = await open();
        expect(
          (await run(
            writer,
            (w) => w.operationStatus(id, isValidationActive: (_) => false),
          )).state,
          OperationState.interrupted,
        );
        final resumed = (await run(
          writer,
          (w) => w.prepareValidation(id, isValidationActive: (_) => true),
        ))!;
        expect(
          resumed.capture!.toWire().toText(),
          task!.capture!.toWire().toText(),
        );
        final checked = resumed.evaluate();
        await run(
          writer,
          (w) =>
              w.finishValidation(id, checked, isValidationActive: (_) => true),
        );
        final completed = await run(
          writer,
          (w) => w.operationStatus(id, isValidationActive: (_) => false),
        );
        expect(completed.state, OperationState.succeeded);
        expect(
          (completed.validation as EvaluatedValidation).assessment,
          isA<BoundAssessment>(),
        );
        expect(
          (completed.validation as EvaluatedValidation).finalBindingDigest,
          isNotNull,
        );
        await store.close();
        store = await open();
        expect(
          (await run(
            writer,
            (w) => w.queueValidationRequest(
              queued(researched.proposal),
              isValidationActive: (_) => false,
            ),
          )).toWire().toText(),
          completed.toWire().toText(),
        );
        await run(
          owner,
          (w) => w.approve(
            reference(researched.proposal),
            checked.validation.runId,
          ),
        );
        await commit(request(researched.proposal, checked.validation.runId));
      });
      test('queued completion refuses changed assessment capture and retains failure without checked evidence', () async {
        final researched = await researchedProposal();
        await attach(researched.proposal, researched.body);
        final status = await run(
          writer,
          (w) => w.queueValidationRequest(
            queued(researched.proposal),
            isValidationActive: (_) => false,
          ),
        );
        final task = (await run(
          writer,
          (w) => w.prepareValidation(
            status.operationId,
            isValidationActive: (_) => true,
          ),
        ))!;
        final checked = task.evaluate();
        await select(
          researched.proposal,
          null,
          BigInt.one,
          'clear-before-completion',
        );
        await run(
          writer,
          (w) => w.finishValidation(
            status.operationId,
            checked,
            isValidationActive: (_) => true,
          ),
        );
        expect(
          (await run(
            writer,
            (w) => w.operationStatus(
              status.operationId,
              isValidationActive: (_) => false,
            ),
          )).state,
          OperationState.failed,
        );
        expect(
          await store.transaction(
            (s) => s
                .workflows(f.u)
                .get('validation:${checked.validation.runId.value}'),
          ),
          isNull,
        );
      });
      test('cancellation signals after durable commit, never after rollback, and blocks late completion', () async {
        final p = await propose(create());
        final status = await run(
          writer,
          (w) => w.queueValidationRequest(
            queued(p),
            isValidationActive: (_) => false,
          ),
        );
        final id = status.operationId;
        final task = (await run(
          writer,
          (w) => w.prepareValidation(id, isValidationActive: (_) => true),
        ))!;
        var signals = 0;
        await expectLater(
          run(writer, (w) async {
            await w.cancelOperation(
              cancel(id),
              isValidationActive: (_) => true,
              signalCancellation: (_) => signals++,
            );
            expect(signals, 0);
            throw StateError('disposable rollback');
          }),
          throwsStateError,
        );
        expect(signals, 0);
        final cancelled = await run(writer, (w) async {
          final result = await w.cancelOperation(
            cancel(id),
            isValidationActive: (_) => true,
            signalCancellation: (_) => signals++,
          );
          expect(signals, 0);
          return result;
        });
        expect(signals, 1);
        expect(cancelled.state, OperationState.cancelled);
        await run(
          writer,
          (w) => w.cancelOperation(
            cancel(id),
            isValidationActive: (_) => false,
            signalCancellation: (_) => signals++,
          ),
        );
        expect(signals, 1);
        final checked = task.evaluate();
        await run(
          writer,
          (w) =>
              w.finishValidation(id, checked, isValidationActive: (_) => true),
        );
        expect(
          await store.transaction(
            (s) => s
                .workflows(f.u)
                .get('validation:${checked.validation.runId.value}'),
          ),
          isNull,
        );
      });
      test('assessment attachment binds source bytes through exact approval, publication and reconnect retry', () async {
        final researched = await researchedProposal();
        final p = researched.proposal;
        final selection = await attach(p, researched.body);
        expect(selection.generation, BigInt.one);
        final key = 'assessment:${selection.selected!.assessmentId.value}';
        final original = await store.transaction(
          (s) => s.workflows(f.u).get(key),
        );
        final checked = await validate(p);
        expect(
          (checked as EvaluatedValidation).assessment,
          isA<BoundAssessment>(),
        );
        expect(checked.submittedInput, isA<SourceAssessedCandidateInput>());
        expect(checked.finalBindingDigest, isNotNull);
        await run(
          owner,
          (w) => w.approve(reference(p), checked.execution.runId),
        );
        final receipt = await commit(request(p, checked.execution.runId));
        await store.close();
        store = await open();
        expect(
          (await attach(p, researched.body)).toWire().toText(),
          selection.toWire().toText(),
        );
        expect(
          (await commit(request(p, checked.execution.runId))).toWire().toText(),
          receipt.toWire().toText(),
        );
        expect(
          (await store.transaction((s) => s.workflows(f.u).get(key)))!.toText(),
          original!.toText(),
        );
      });
      test('assessment clearing and reselection preserve evidence and invalidate prior approval', () async {
        final researched = await researchedProposal();
        final p = researched.proposal;
        final first = await attach(p, researched.body);
        final checked = await validate(p);
        await run(
          owner,
          (w) => w.approve(reference(p), checked.execution!.runId),
        );
        final cleared = await select(p, null, BigInt.one, 'clear');
        expect(cleared.generation, BigInt.two);
        expect(cleared.selected, isNull);
        await expectLater(commit(request(p, checked.execution!.runId)), stale);
        expect(
          (await attach(p, researched.body)).toWire().toText(),
          first.toWire().toText(),
        );
        final restored = await select(
          p,
          first.selected,
          BigInt.two,
          'reselect',
        );
        expect(restored.generation, BigInt.from(3));
        expect(
          restored.selected!.toWire().toText(),
          first.selected!.toWire().toText(),
        );
        await expectLater(
          attach(p, researched.body, generation: BigInt.one),
          throwsA(isA<IdempotencyKeyReusedError>()),
        );
        await expectLater(select(p, null, BigInt.one, 'stale-clear'), stale);
        final again = await validate(p);
        await run(
          owner,
          (w) => w.approve(reference(p), again.execution!.runId),
        );
        await commit(
          request(p, again.execution!.runId, key: 'reselected-commit'),
        );
      });
      test('assessment attribution and unverifiable sources fail without retained selection or receipt', () async {
        final researched = await researchedProposal();
        final wrong = SourceAssessmentV1.fromWire(
          accounting.replace(researched.body.toWire(), [
            'assessor',
            'principal',
          ], CanonicalString(owner.value.replaceFirst('prf_', 'prn_'))),
        );
        await expectLater(
          attach(researched.proposal, wrong),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        final wrongBytes = SourceAssessmentV1.fromWire(
          accounting.replace(researched.body.toWire(), [
            'sources',
            0,
            'blob_digest',
          ], CanonicalString('a' * 64)),
        );
        await expectLater(
          attach(researched.proposal, wrongBytes, key: 'unverified-source'),
          throwsA(isA<InvalidArgumentError>()),
        );
        expect(
          await store.transaction(
            (s) => s.workflows(f.u).latestKey('assessment-selection:'),
          ),
          isNull,
        );
        expect(
          await store.transaction(
            (s) => s.workflows(f.u).latestKey('assessment-receipt:'),
          ),
          isNull,
        );
        final first = await attach(researched.proposal, researched.body);
        expect(first.generation, BigInt.one);
      });
      test('creates, validates, requires exact author approval, publishes and retries after reconnect', () async {
        final proposal = await propose(create());
        expect(
          (await propose(create())).toWire().toText(),
          proposal.toWire().toText(),
        );
        final checked = await validate(proposal);
        final validation = checked.execution!;
        expect(validation.coverage, Coverage.complete);
        final publish = request(proposal, validation.runId);
        await expectLater(
          commit(publish),
          throwsA(isA<ApprovalRequiredError>()),
        );
        await expectLater(
          run(writer, (w) => w.approve(reference(proposal), validation.runId)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await run(
          owner,
          (w) => w.approve(reference(proposal), validation.runId),
        );
        final receipt = await commit(publish);
        expect(receipt.revision, isNot(frame.revision));
        final saved = await store.transaction(
          (s) async => StoredProposal.fromWire(
            (await s.workflows(f.u).get(proposalKey(reference(proposal))))!,
          ),
        );
        await store.close();
        store = await open();
        expect(
          (await commit(publish)).toWire().toText(),
          receipt.toWire().toText(),
        );
        await expectLater(
          commit(request(proposal, validation.runId, base: receipt.revision)),
          throwsA(isA<IdempotencyKeyReusedError>()),
        );
        await store.transaction((s) async {
          expect(
            await s.kernel(f.u).journal.head(continuity),
            receipt.revision,
          );
          final next = saved.changes.single.next!;
          expect(
            (await s.kernel(f.u).journal.load(next.versionId)).digest,
            next.digest,
          );
          expect(
            await s.kernel(f.u).journal.identityExists(next.identity.recordId),
            isTrue,
          );
        });
      });
      test(
        'new proposal version and withdrawal invalidate exact approval',
        () async {
          final original = await propose(create());
          final checked = await validate(original);
          await run(
            owner,
            (w) => w.approve(reference(original), checked.execution!.runId),
          );
          final revised = await propose(
            ReviseProposalRequest(
              universe: const Selector('Disposable universe'),
              contextId: writerContext,
              proposalReference: reference(original),
              operations: create().operations,
              submission: Submission.submitted,
              rationale: 'Revised exact input',
              idempotencyKey: 'revise',
            ),
          );
          await expectLater(
            commit(request(original, checked.execution!.runId)),
            stale,
          );
          await expectLater(
            run(
              owner,
              (w) => w.approve(reference(original), checked.execution!.runId),
            ),
            stale,
          );
          final checkedAgain = await validate(revised);
          await run(
            owner,
            (w) => w.approve(reference(revised), checkedAgain.execution!.runId),
          );
          await propose(
            WithdrawProposalRequest(
              universe: const Selector('Disposable universe'),
              contextId: writerContext,
              proposalReference: reference(revised),
              idempotencyKey: 'withdraw',
            ),
          );
          await expectLater(
            commit(
              request(
                revised,
                checkedAgain.execution!.runId,
                key: 'after-withdraw',
              ),
            ),
            stale,
          );
          expect(
            await store.transaction(
              (s) => s.kernel(f.u).journal.head(continuity),
            ),
            frame.revision,
          );
        },
      );
      test(
        'validation is immutable and approval does not cover another run',
        () async {
          final proposal = await propose(create());
          final checked = await validate(proposal);
          final runId = checked.execution!.runId;
          await run(owner, (w) => w.approve(reference(proposal), runId));
          final key = 'validation:${runId.value}';
          final before = await store.transaction(
            (s) => s.workflows(f.u).get(key),
          );
          await expectLater(
            store.transaction(
              (s) => s.workflows(f.u).put(key, const CanonicalNull()),
            ),
            throwsFormatException,
          );
          expect(
            (await store.transaction((s) => s.workflows(f.u).get(key)))!
                .toText(),
            before!.toText(),
          );
          final another = await validate(proposal);
          expect(another.execution!.runId, isNot(runId));
          await expectLater(
            commit(request(proposal, another.execution!.runId)),
            throwsA(isA<ApprovalRequiredError>()),
          );
          expect(
            await store.transaction(
              (s) => s.kernel(f.u).journal.head(continuity),
            ),
            frame.revision,
          );
        },
      );
      test(
        'current grant edit denial and revocation precede receipt retry',
        () async {
          final proposal = await propose(create());
          final checked = await validate(proposal);
          await run(
            owner,
            (w) => w.approve(reference(proposal), checked.execution!.runId),
          );
          final publish = request(proposal, checked.execution!.runId);
          await commit(publish);
          await store.transaction(
            (s) => s.authority.putGrant(
              actor: owner,
              grant: GrantSpec(
                profileId: writer,
                universeId: f.u,
                worlds: null,
                propose: true,
                edit: false,
                protected: false,
              ),
              epochSeconds: now,
            ),
          );
          await expectLater(
            commit(publish),
            throwsA(isA<InstallationException>()),
          );
          await store.transaction(
            (s) => s.authority.revoke(actor: owner, target: writer),
          );
          await expectLater(
            commit(publish),
            throwsA(isA<InstallationException>()),
          );
        },
      );
      test(
        'bounded delegated commit requires complete validation and live expiry',
        () async {
          final base = await store.transaction(
            (s) => s
                .kernel(f.u)
                .commit(
                  CommitInput(
                    universe: f.u,
                    continuity: continuity,
                    expectedHead: frame.revision,
                    principal: PrincipalId.generate(),
                    decision: 'Delegation fixture base',
                    reason: 'Existing predicate and entity',
                    idempotencyKey: 'delegation-base',
                    changes: [
                      for (final version in [
                        frames.fixture().first,
                        f.row(2, f.entity()),
                      ])
                        Assignment(
                          recordId: version.identity.recordId,
                          expected: null,
                          next: StoredVersion.build(
                            version.recordVersionId,
                            version.identity,
                            version.payload.toWire(),
                          ),
                        ),
                    ],
                  ),
                ),
          );
          frame = Frame(
            universe: f.u,
            continuity: continuity,
            revision: base,
            context: f.ref(99),
            time: const TimelessFrameTime(),
            perspective: const AuthorPerspective(),
          );
          Future<void> delegation(bool shared) => store.transaction(
            (s) => s.authority.putGrant(
              actor: owner,
              grant: GrantSpec(
                profileId: writer,
                universeId: f.u,
                worlds: null,
                propose: true,
                edit: true,
                protected: true,
                limits: GrantLimits(
                  entities: [f.id(2)],
                  predicates: [f.id(1)],
                  continuities: [continuity],
                  expiresAt: BigInt.from(200),
                  delegatedCommit: true,
                  allowShared: shared,
                ),
              ),
              epochSeconds: now,
            ),
          );
          await delegation(false);
          await refreshContext();
          final proposal = await propose(
            CreateProposalRequest(
              universe: const Selector('Disposable universe'),
              universeId: f.u,
              contextId: writerContext,
              operations: [
                DefinePropositionOperation(
                  clientRef: f.id(10).value,
                  record: PropositionRecord(
                    subject: f.ref(2),
                    predicate: f.ref(1),
                    context: f.ref(99),
                    value: const BooleanValue(true),
                    quantification: Quantification.particular,
                  ),
                ),
              ],
              submission: Submission.submitted,
              rationale: 'Delegated factual edit',
              idempotencyKey: 'delegated-proposal',
            ),
          );
          final checked = await validate(proposal);
          expect(checked.execution!.coverage, Coverage.complete);
          final publish = request(proposal, checked.execution!.runId);
          await expectLater(
            commit(publish),
            throwsA(isA<ApprovalRequiredError>()),
          );
          await delegation(true);
          final receipt = await commit(publish);
          expect(receipt.revision, isNot(frame.revision));
          expect(
            await store.transaction(
              (s) => s.workflows(f.u).latestKey('approval:'),
            ),
            isNull,
          );
          now = BigInt.from(200);
          await expectLater(
            commit(publish),
            throwsA(isA<InstallationException>()),
          );
        },
      );
      test('moved head blocks approval and publication without partial operation retention', () async {
        final proposal = await propose(create());
        final checked = await validate(proposal);
        await run(
          owner,
          (w) => w.approve(reference(proposal), checked.execution!.runId),
        );
        final version = f.row(400, f.entity());
        final moved = await store.transaction(
          (s) => s
              .kernel(f.u)
              .commit(
                CommitInput(
                  universe: f.u,
                  continuity: continuity,
                  expectedHead: frame.revision,
                  principal: PrincipalId.generate(),
                  decision: 'Independent fixture change',
                  reason: 'Stale base check',
                  idempotencyKey: 'move-head',
                  changes: [
                    Assignment(
                      recordId: version.identity.recordId,
                      expected: null,
                      next: StoredVersion.build(
                        version.recordVersionId,
                        version.identity,
                        version.payload.toWire(),
                      ),
                    ),
                  ],
                ),
              ),
        );
        await expectLater(
          run(
            owner,
            (w) => w.approve(reference(proposal), checked.execution!.runId),
          ),
          stale,
        );
        await expectLater(
          commit(request(proposal, checked.execution!.runId)),
          throwsA(isA<BaseRevisionConflictError>()),
        );
        expect(
          await store.transaction(
            (s) => s.kernel(f.u).journal.head(continuity),
          ),
          moved,
        );
        expect(
          await store.transaction(
            (s) =>
                s.workflows(f.u).latestKey('request:${writer.value}:commit:'),
          ),
          isNull,
        );
      });
      test('contexts are principal-bound, expire and reject changed scope before retention', () async {
        final foreign = await openContext(owner);
        final original = writerContext;
        writerContext = foreign.contextId;
        await expectLater(
          propose(create()),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        writerContext = original;
        now += BigInt.from(3601);
        await expectLater(
          propose(create()),
          throwsA(isA<ContextExpiredError>()),
        );
        now = BigInt.from(100);
        await store.transaction(
          (s) => s.authority.putGrant(
            actor: owner,
            grant: GrantSpec(
              profileId: writer,
              universeId: f.u,
              worlds: null,
              propose: true,
              edit: false,
              protected: false,
            ),
            epochSeconds: now,
          ),
        );
        await expectLater(
          propose(create()),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        expect(
          await store.transaction(
            (s) => s.workflows(f.u).latestKey('proposal:'),
          ),
          isNull,
        );
      });
      test('opening preserves exact revisions and validation rejects a different pinned context', () async {
        final proposal = await propose(create());
        final original = frame;
        final version = f.row(400, f.entity());
        final moved = await store.transaction(
          (s) => s
              .kernel(f.u)
              .commit(
                CommitInput(
                  universe: f.u,
                  continuity: continuity,
                  expectedHead: frame.revision,
                  principal: PrincipalId.generate(),
                  decision: 'Context fixture movement',
                  reason: 'Pinned context check',
                  idempotencyKey: 'context-move',
                  changes: [
                    Assignment(
                      recordId: version.identity.recordId,
                      expected: null,
                      next: StoredVersion.build(
                        version.recordVersionId,
                        version.identity,
                        version.payload.toWire(),
                      ),
                    ),
                  ],
                ),
              ),
        );
        final historical = await openContext(
          writer,
          revision: ExactRevisionSelector(revisionId: original.revision),
        );
        expect(historical.frame.revision, original.revision);
        final latest = await openContext(writer);
        expect(latest.frame.revision, moved);
        writerContext = latest.contextId;
        await expectLater(validate(proposal), stale);
        expect(
          await store.transaction(
            (s) => s.workflows(f.u).latestKey('validation:'),
          ),
          isNull,
        );
      });
      test('unknown represented context and mismatched universe guard fail opening', () async {
        await expectLater(
          openContext(writer, represented: f.id(777)),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          openContext(writer, guard: UniverseId.generate()),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
      });
      test(
        'continuity and entity boundaries deny proposal retention atomically',
        () async {
          await store.transaction(
            (s) => s.authority.putGrant(
              actor: owner,
              grant: GrantSpec(
                profileId: writer,
                universeId: f.u,
                worlds: null,
                propose: true,
                edit: true,
                protected: false,
                limits: GrantLimits(continuities: [ContinuityId.generate()]),
              ),
              epochSeconds: now,
            ),
          );
          await refreshContext();
          await expectLater(
            propose(create()),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
          expect(
            await store.transaction(
              (s) => s.workflows(f.u).latestKey('proposal:'),
            ),
            isNull,
          );
          await store.transaction(
            (s) => s.authority.putGrant(
              actor: owner,
              grant: GrantSpec(
                profileId: writer,
                universeId: f.u,
                worlds: null,
                propose: true,
                edit: true,
                protected: false,
                limits: GrantLimits(entities: [f.id(500)]),
              ),
              epochSeconds: now,
            ),
          );
          await refreshContext();
          await expectLater(
            propose(create()),
            throwsA(isA<NotFoundOrNotAccessibleError>()),
          );
          expect(
            await store.transaction(
              (s) => s.workflows(f.u).latestKey('proposal:'),
            ),
            isNull,
          );
        },
      );
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for the owned disposable PostgreSQL fixture.'
        : false,
  );
}
