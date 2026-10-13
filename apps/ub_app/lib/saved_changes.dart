import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

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
