import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'world_draft.dart';

/// Uses the service's existing drafts, operation recovery and frozen proposals.
final class SavedChanges {
  const SavedChanges({
    required this.session,
    required this.universe,
    required this.scope,
  });
  final AppSession session;
  final Selector universe;
  final EditorFormScope scope;

  ProposalRef reference(Proposal proposal) => ProposalRef(
    proposalId: proposal.proposalId,
    version: proposal.version,
    digest: proposal.digest,
  );

  Future<ValidationV3> validate(Proposal proposal) async {
    final frame = proposal.baseFrame;
    final opened = Envelope<OpenedContext>.fromWire(
      await session.call(
        ToolEngineRequest(
          request: OpenContextRequest(
            universe: universe,
            universeId: scope.universe,
            continuityId: frame.continuity,
            revision: ExactRevisionSelector(revisionId: frame.revision),
            representedContext: ContextIdSelector(frame.context.record),
            temporalQuery: frame.time,
            temporalSystems: [],
            perspective: frame.perspective,
          ),
        ),
      ),
      OpenedContext.fromWire,
    ).result;
    return Envelope<ValidationV3>.fromWire(
      await session.call(
        ToolEngineRequest(
          request: ProposalValidationRequest(
            universe: universe,
            universeId: scope.universe,
            contextId: opened.contextId,
            proposalReference: reference(proposal),
            checkScope: CheckScope.universe,
          ),
        ),
      ),
      ValidationV3.fromWire,
    ).result;
  }

  Future<void> approve(
    Proposal proposal,
    EvaluatedValidation validation,
  ) async {
    await session.call(
      ApproveEngineRequest(
        universe: universe,
        proposalReference: reference(proposal),
        validationRun: validation.execution.runId,
      ),
    );
  }

  /// Optional display material at the checked proposal's frame. Candidate
  /// versions take precedence; unavailable names never change check results.
  Future<Map<RecordId, RecordVersion>> findingRecords(
    Proposal proposal,
    EvaluatedValidation validation,
  ) async {
    final records = <RecordId, RecordVersion>{
      for (final change in proposal.compiledChanges)
        change.recordId: ?change.next,
    };
    final removed = {
      for (final change in proposal.compiledChanges)
        if (change.next == null) change.recordId,
    };
    final attempted = <RecordId>{...records.keys, ...removed};
    final frame = proposal.baseFrame;
    try {
      final opened = Envelope<OpenedContext>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: OpenContextRequest(
              universe: universe,
              universeId: scope.universe,
              continuityId: frame.continuity,
              revision: ExactRevisionSelector(revisionId: frame.revision),
              representedContext: ContextIdSelector(frame.context.record),
              temporalQuery: frame.time,
              temporalSystems: [],
              perspective: frame.perspective,
            ),
          ),
        ),
        OpenedContext.fromWire,
      ).result;
      Future<void> read(Iterable<RecordId> ids) async {
        final missing = ids.toSet().difference(attempted).toList();
        attempted.addAll(missing);
        for (var offset = 0; offset < missing.length; offset += 50) {
          final batch = missing.skip(offset).take(50).toSet();
          try {
            final result = Envelope<Records>.fromWire(
              await session.call(
                ToolEngineRequest(
                  request: GetRequest(
                    universe: universe,
                    universeId: scope.universe,
                    contextId: opened.contextId,
                    recordIds: batch,
                    fieldGroups: [FieldGroup.payload],
                  ),
                ),
              ),
              Records.fromWire,
            );
            if (result.delivery.complete) {
              for (final row in result.result.records) {
                if (row.identity.universeId == scope.universe &&
                    batch.contains(row.identity.recordId)) {
                  records[row.identity.recordId] = row;
                }
              }
            }
          } on Object {
            // A missing/inaccessible label does not invalidate the check result.
          }
        }
      }

      bool local(RecordRef ref) =>
          ref.universe == null || ref.universe == scope.universe;
      await read([
        for (final finding in validation.execution.findings) ...[
          finding.ruleId,
          for (final ref in finding.records)
            if (local(ref)) ref.record,
        ],
      ]);
      await read([
        for (final row in records.values.toList())
          ...switch (row.payload) {
            AssertionRecord(:final proposition) => [
              if (local(proposition)) proposition.record,
            ],
            RuleRecord(:final requiredEvidence) => [
              for (final ref
                  in requiredEvidence?.sourceCategories ?? <VersionRef>[])
                if (ref.universe == null || ref.universe == scope.universe)
                  ref.record,
            ],
            EventRecord(:final participants) => [
              for (final p in participants)
                if (local(p.record)) p.record.record,
            ],
            _ => <RecordId>[],
          },
      ]);
      await read([
        for (final row in records.values.toList())
          if (row.payload case PropositionRecord(
            :final subject,
            :final predicate,
          )) ...[
            if (local(subject)) subject.record,
            if (local(predicate)) predicate.record,
          ],
      ]);
    } on Object {
      // The checked proposal still supplies any newly authored display names.
    }
    return Map.unmodifiable(records);
  }

  String publicationKey(Proposal proposal, ValidationRunId run) =>
      'flutter-publish-${proposal.digest}-${run.value}';

  Future<CommitReceipt> publish(Proposal proposal, ValidationRunId run) async =>
      Envelope<CommitReceipt>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: CommitRequest(
              universe: universe,
              universeId: scope.universe,
              proposalReference: reference(proposal),
              expectedBaseRevision: proposal.baseFrame.revision,
              validationRun: run,
              idempotencyKey: publicationKey(proposal, run),
            ),
          ),
        ),
        CommitReceipt.fromWire,
      ).result;

  /// Existing author approvals identify exact publication requests after restart.
  /// A null status means the approval exists without a publication attempt.
  /// Looking them up never approves or retries publication.
  Future<({ValidationRunId run, OperationStatusV3? status})?> publication(
    Proposal proposal,
  ) async {
    final library = await session.call(
      LibraryEngineRequest(universe: universe),
    );
    final body = Map.fromEntries((library as CanonicalObject).fields);
    final writing = WireFields(body['writing']!, {'approved', 'proposals'});
    ({ValidationRunId run, OperationStatusV3? status})? pending;
    ({ValidationRunId run, OperationStatusV3? status})? approved;
    for (final row in writing.array('approved')) {
      final approval = WireFields(row, {
        'candidate',
        'validation_run',
        'label',
      });
      if (ProposalRef.fromWire(approval.require('candidate')) !=
          reference(proposal)) {
        continue;
      }
      final run = ValidationRunId.parse(approval.string('validation_run'));
      OperationStatusV3 status;
      try {
        status = Envelope<OperationStatusV3>.fromWire(
          await session.call(
            ToolEngineRequest(
              request: GetOperationKeyRequest(
                universe: universe,
                universeId: scope.universe,
                operationKind: OperationKind.commit,
                idempotencyKey: publicationKey(proposal, run),
              ),
            ),
          ),
          OperationStatusV3.fromWire,
        ).result;
      } on NotFoundOrNotAccessibleError {
        approved ??= (run: run, status: null);
        continue;
      }
      if (status.receipt != null) return (run: run, status: status);
      pending ??= (run: run, status: status);
    }
    return pending ?? approved;
  }

  Future<List<RecordVersion>> readPublished(
    Proposal proposal,
    CommitReceipt receipt,
  ) async {
    final frame = proposal.baseFrame;
    final opened = Envelope<OpenedContext>.fromWire(
      await session.call(
        ToolEngineRequest(
          request: OpenContextRequest(
            universe: universe,
            universeId: scope.universe,
            continuityId: frame.continuity,
            revision: ExactRevisionSelector(revisionId: receipt.revision),
            representedContext: ContextIdSelector(frame.context.record),
            temporalQuery: const TimelessFrameTime(),
            temporalSystems: [],
            perspective: const AuthorPerspective(),
          ),
        ),
      ),
      OpenedContext.fromWire,
    ).result;
    final records = <RecordVersion>[];
    for (final change in proposal.compiledChanges.where(
      (change) => change.next != null,
    )) {
      final read = Envelope<Records>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: GetRequest(
              universe: universe,
              universeId: scope.universe,
              contextId: opened.contextId,
              recordIds: [change.recordId],
              fieldGroups: [FieldGroup.payload],
            ),
          ),
        ),
        Records.fromWire,
      );
      if (!read.delivery.complete) {
        throw const FormatException('Record delivery is incomplete.');
      }
      records.addAll(read.result.records);
    }
    return records;
  }

  Future<SavedDraft?> load() async {
    final value = await session.call(
      LoadDraftEngineRequest(
        universe: universe,
        continuityId: scope.continuity,
      ),
    );
    return value is CanonicalNull ? null : SavedDraft.fromWire(value);
  }

  Future<SavedDraft> saveRationale(SavedDraft draft, String rationale) async {
    if (draft.content.proposal != null) {
      throw const FormatException(
        'Review the submitted proposal before changing it.',
      );
    }
    return SavedDraft.fromWire(
      await session.call(
        SaveDraftEngineRequest(
          universe: universe,
          continuityId: scope.continuity,
          expectedVersion: draft.version,
          content: DraftContent(
            baseRevision: draft.content.baseRevision,
            representedContext: draft.content.representedContext,
            operations: draft.content.operations,
            rationale: rationale,
          ),
        ),
      ),
    );
  }

  Future<SavedDraft> saveContent(
    SavedDraft draft,
    DraftContent content,
  ) async => SavedDraft.fromWire(
    await session.call(
      SaveDraftEngineRequest(
        universe: universe,
        continuityId: scope.continuity,
        expectedVersion: draft.version,
        content: content,
      ),
    ),
  );

  Future<SavedDraft> editWorldFields(
    SavedDraft draft,
    int index, {
    required String selector,
    required String settingType,
    required String englishLabel,
  }) => saveContent(
    draft,
    editWorldDraftFields(
      draft: draft.content,
      index: index,
      selector: selector,
      settingType: settingType,
      englishLabel: englishLabel,
    ),
  );

  Future<SavedDraft> removeOperation(SavedDraft draft, int index) {
    if (draft.content.proposal != null) {
      throw const FormatException(
        'Continue editing separately before changing a submitted proposal.',
      );
    }
    final operations = [...draft.content.operations]..removeAt(index);
    return saveContent(
      draft,
      DraftContent(
        baseRevision: draft.content.baseRevision,
        representedContext: draft.content.representedContext,
        operations: operations,
        rationale: draft.content.rationale,
      ),
    );
  }

  Future<SavedDraft> continueEditing(SavedDraft draft) => saveContent(
    draft,
    DraftContent(
      baseRevision: draft.content.baseRevision,
      representedContext: draft.content.representedContext,
      operations: draft.content.operations,
      rationale: draft.content.rationale,
    ),
  );

  Future<SavedDraft> rebase(SavedDraft draft, {bool startNew = false}) async {
    if (draft.content.proposal != null && !startNew) {
      throw const FormatException(
        'Continue editing separately before rebasing a submitted proposal.',
      );
    }
    final summary = Envelope<Description>.fromWire(
      await session.call(
        ToolEngineRequest(
          request: DescribeSummaryRequest(
            universe: universe,
            universeId: scope.universe,
          ),
        ),
      ),
      Description.fromWire,
    ).result;
    final continuity = summary.continuities.singleWhere(
      (item) => item.id == scope.continuity,
    );
    if (!continuity.representedContexts.any(
      (context) => context.id == draft.content.representedContext,
    )) {
      throw const FormatException(
        'The represented context is no longer available. Choose a context before rebasing.',
      );
    }
    // Keep expected record versions and exact authored operations unchanged.
    // Submission resolves any conflicting edits; rebase never guesses a merge.
    return saveContent(
      draft,
      DraftContent(
        baseRevision: continuity.revisionId,
        representedContext: draft.content.representedContext,
        operations: startNew ? [] : draft.content.operations,
        rationale: startNew ? '' : draft.content.rationale,
      ),
    );
  }

  Future<Proposal> proposal(ProposalRef reference) async {
    String? cursor;
    Proposal? first;
    final operations = <DomainOperation>[];
    final changes = <CompiledChange>[];
    do {
      final page = Envelope<Proposal>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: GetProposalRequest(
              universe: universe,
              universeId: scope.universe,
              proposalId: reference.proposalId,
              version: reference.version,
              cursor: cursor,
            ),
          ),
        ),
        Proposal.fromWire,
      );
      first ??= page.result;
      operations.addAll(page.result.operations);
      changes.addAll(page.result.compiledChanges);
      if (page.delivery.complete) break;
      cursor = page.delivery.cursor;
      if (cursor == null) {
        throw const FormatException('Could not load all changes.');
      }
    } while (true);
    return Proposal(
      baseFrame: first.baseFrame,
      worldScope: first.worldScope,
      proposalId: first.proposalId,
      version: first.version,
      digest: first.digest,
      submission: first.submission,
      operations: operations,
      compiledChanges: changes,
      rationale: first.rationale,
      canonical: first.canonical,
      operationId: first.operationId,
      withdrawn: first.withdrawn,
    );
  }

  String submissionKey(SavedDraft draft) =>
      'flutter-draft-${canonicalDigest(CanonicalObject([MapEntry('instance', CanonicalString(scope.instance.value)), MapEntry('profile', CanonicalString(scope.profile.value)), MapEntry('universe', CanonicalString(scope.universe.value)), MapEntry('continuity', CanonicalString(scope.continuity.value)), MapEntry('generation', CanonicalString(draft.version.toString())), MapEntry('content', draft.content.toWire())]))}';

  Future<Proposal?> recover(SavedDraft draft) async {
    if (draft.content.proposal case final reference?) {
      return proposal(reference);
    }
    OperationStatusV3 status;
    try {
      status = Envelope<OperationStatusV3>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: GetOperationKeyRequest(
              universe: universe,
              universeId: scope.universe,
              operationKind: OperationKind.propose,
              idempotencyKey: submissionKey(draft),
            ),
          ),
        ),
        OperationStatusV3.fromWire,
      ).result;
    } on NotFoundOrNotAccessibleError {
      return null;
    }
    if (status.proposal == null) {
      throw const FormatException(
        'Submission has not finished. Check again before submitting.',
      );
    }
    final recovered = status.proposal!;
    return proposal(
      ProposalRef(
        proposalId: recovered.proposalId,
        version: recovered.version,
        digest: recovered.digest,
      ),
    );
  }

  Future<Map<RecordId, RecordVersion>> before(Proposal proposal) async {
    final changed = proposal.compiledChanges
        .where((change) => change.expected != null)
        .toList();
    if (changed.isEmpty) return {};
    final frame = proposal.baseFrame;
    final opened = Envelope<OpenedContext>.fromWire(
      await session.call(
        ToolEngineRequest(
          request: OpenContextRequest(
            universe: universe,
            universeId: scope.universe,
            continuityId: frame.continuity,
            revision: ExactRevisionSelector(revisionId: frame.revision),
            representedContext: ContextIdSelector(frame.context.record),
            temporalQuery: frame.time,
            temporalSystems: [],
            perspective: frame.perspective,
          ),
        ),
      ),
      OpenedContext.fromWire,
    ).result;
    final records = <RecordId, RecordVersion>{};
    for (final change in changed) {
      final read = Envelope<Records>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: GetRequest(
              universe: universe,
              universeId: scope.universe,
              contextId: opened.contextId,
              recordIds: [change.recordId],
              fieldGroups: [FieldGroup.payload],
            ),
          ),
        ),
        Records.fromWire,
      );
      final record = read.result.records.single;
      if (!read.delivery.complete ||
          record.recordVersionId != change.expected) {
        throw const FormatException(
          'Could not load the exact previous record.',
        );
      }
      records[change.recordId] = record;
    }
    return records;
  }

  Future<Proposal> submit(SavedDraft draft) async {
    var result = await recover(draft);
    if (result == null) {
      final opened = Envelope<OpenedContext>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: OpenContextRequest(
              universe: universe,
              universeId: scope.universe,
              continuityId: scope.continuity,
              revision: ExactRevisionSelector(
                revisionId: draft.content.baseRevision,
              ),
              representedContext: ContextIdSelector(
                draft.content.representedContext,
              ),
              temporalQuery: const TimelessFrameTime(),
              temporalSystems: [],
              perspective: const AuthorPerspective(),
            ),
          ),
        ),
        OpenedContext.fromWire,
      ).result;
      result = Envelope<Proposal>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: CreateProposalRequest(
              universe: universe,
              universeId: scope.universe,
              contextId: opened.contextId,
              operations: draft.content.operations,
              submission: Submission.submitted,
              rationale: draft.content.rationale,
              idempotencyKey: submissionKey(draft),
            ),
          ),
        ),
        Proposal.fromWire,
      ).result;
    }
    if (draft.content.proposal == null) {
      await session.call(
        SaveDraftEngineRequest(
          universe: universe,
          continuityId: scope.continuity,
          expectedVersion: draft.version,
          content: DraftContent(
            baseRevision: draft.content.baseRevision,
            representedContext: draft.content.representedContext,
            operations: draft.content.operations,
            rationale: draft.content.rationale,
            proposal: ProposalRef(
              proposalId: result.proposalId,
              version: result.version,
              digest: result.digest,
            ),
          ),
        ),
      );
    }
    return proposal(
      ProposalRef(
        proposalId: result.proposalId,
        version: result.version,
        digest: result.digest,
      ),
    );
  }
}
