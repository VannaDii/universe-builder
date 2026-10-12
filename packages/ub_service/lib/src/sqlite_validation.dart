import 'dart:convert';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/ub_store.dart' show CommitInput;

import 'assessment_resolution.dart';
import 'assessment_validation.dart';
import 'candidate_validation.dart';
import 'context_binding.dart';
import 'context_brief.dart';
import 'context_opening.dart';
import 'discovery.dart';
import 'installation_authority.dart';
import 'impact.dart';
import 'operation_compilation.dart';
import 'operation_state.dart';
import 'proposal_authorization.dart';
import 'proposal_state.dart';
import 'proposal_validation.dart';
import 'proposal_reading.dart';
import 'record_reading.dart';
import 'record_search.dart';
import 'read_cursor.dart';
import 'source_verification.dart';
import 'state_reading.dart';
import 'validation_binding.dart';
import 'validation_task.dart';

/// Internal native workflow for an already recovered, writer-owned package.
/// It retains assessments, checked results and exact human approvals, and
/// publishes reviewed canon. The caller must produce checked results through the factual
/// evaluator, not client IO.
final class SqliteValidationWorkflow {
  SqliteValidationWorkflow({
    required this.package,
    required this.authority,
    required this.principal,
  });
  final OwnedSqliteDatabase package;
  final InstallationAuthority authority;
  final InstallationPrincipal principal;
  UniverseId get universe => package.universeId;
  SqliteJournal get _journal => SqliteJournal(package.database, universe);
  WorkflowStorage get _workflow => WorkflowStorage(package.database);

  RecordVersion _version(RecordVersionId id) =>
      RecordVersion.fromWire(_journal.load(id).toCanonical());
  List<RecordVersion> _canon(ContinuityId continuity, RevisionId revision) {
    final rows =
        [
          for (final version in _journal.snapshot(continuity, revision).values)
            _version(version),
        ]..sort(
          (a, b) =>
              a.identity.recordId.value.compareTo(b.identity.recordId.value),
        );
    return rows;
  }

  StoredProposal _proposal(
    ProposalRef reference,
    CurrentUniverseAuthority current,
  ) {
    final value = _workflow.get(proposalKey(reference));
    if (value == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final proposal = StoredProposal.fromWire(value);
    _admitProposal(proposal, reference, current);
    return proposal;
  }

  void _admitProposal(
    StoredProposal proposal,
    ProposalRef reference,
    CurrentUniverseAuthority current,
  ) {
    if (proposal.proposal.baseFrame.universe != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    authorizeStoredProposal(
      stored: proposal,
      reference: reference,
      principal: current.principal.id,
      author: current.principal.author,
      scope: current.worldScope,
    );
    authority.authorizeWrite(
      principal,
      universe: universe,
      worlds: proposal.footprint.worlds,
      shared: proposal.footprint.shared,
      protected: proposal.footprint.protected,
      commit: false,
    );
    try {
      if (current.limits.continuities != null &&
          !current.limits.continuities!.contains(
            proposal.proposal.baseFrame.continuity,
          )) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      checkWriteBoundaries(
        base:
            current.limits.entities != null || current.limits.predicates != null
            ? _canon(
                proposal.proposal.baseFrame.continuity,
                proposal.proposal.baseFrame.revision,
              )
            : const [],
        changes: proposal.changes,
        continuity: proposal.proposal.baseFrame.continuity,
        limits: current.limits,
      );
    } on Object {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
  }

  Future<AssessmentReview> _assessmentReview(
    ProposalRef reference,
    CurrentUniverseAuthority current, {
    AssessmentRef? exact,
    bool publication = false,
  }) => resolveAssessment(
    reference: reference,
    exact: exact,
    universe: universe,
    canObserveMissingMaterial:
        publication || current.principal.author && current.worldScope == null,
    readProposal: (reference) => _proposal(reference, current),
    checkAccess: (proposal, body) async {
      if (publication) return;
      await checkAssessmentAccess(
        proposal: proposal,
        body: body,
        limits: current.limits,
        worldScope: current.worldScope,
        readCanon: _canon,
        readVersion: _version,
      );
    },
    readLatestKey: _workflow.latestKey,
    readWorkflow: _workflow.get,
    readHead: _journal.head,
    readCanon: _canon,
    readVersion: _version,
  );

  Future<ValidationCapture> _capture(
    StoredProposal proposal,
    CurrentUniverseAuthority current, {
    bool publication = false,
  }) => captureValidationBinding(
    proposal: proposal,
    authorityDigest: current.validationDigest,
    authoritySequence: current.sequence,
    readLatestKey: _workflow.latestKey,
    readWorkflow: _workflow.get,
    readHead: _journal.head,
    resolveSelected: (reference) =>
        _assessmentReview(reference, current, publication: publication),
  );

  /// The dispatcher resolves the universe before invoking this native route.
  Future<OpenedContext> openContext(OpenContextRequest request) =>
      authority.withUniverseAuthority(principal, universe, (current) async {
        if (request.universeId != null && request.universeId != universe) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        final revision = switch (request.revision) {
          HeadRevisionSelector() => _journal.head(request.continuityId),
          ExactRevisionSelector(:final revisionId) => revisionId,
        };
        final frame = await prepareContextFrame(
          request: request,
          universe: universe,
          revision: revision,
          records: _canon(request.continuityId, revision),
          worldScope: current.worldScope,
          readCanon: _canon,
        );
        final id = ContextId.generate();
        final stored = StoredContext(
          owner: principal.id,
          scope: current.scopeHash,
          expires: BigInt.from(
            DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          ),
          frame: frame,
        );
        _workflow.compareAppend({}, [
          MapEntry('context:${id.value}', stored.toWire()),
        ]);
        return OpenedContext(contextId: id, frame: frame);
      });

  /// The dispatcher resolves context and world focus under current read access.
  /// Compilation/preview is outside the workflow transaction, which the kernel
  /// owns; proposal history, reservation and request receipts append together.
  Future<Proposal> propose(
    WorkflowRequest request, {
    required Frame resolvedFrame,
    required WorldId? worldFocus,
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _propose(
      request,
      current,
      resolvedFrame: resolvedFrame,
      worldFocus: worldFocus,
      isValidationActive: isValidationActive,
    ),
  );

  Frame _contextFrame(ContextId id, CurrentUniverseAuthority current) {
    final value = _workflow.get('context:${id.value}');
    if (value == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    return StoredContext.fromWire(value).admit(
      principal: principal.id,
      scopeHash: current.scopeHash,
      universe: universe,
      epochSeconds: BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000),
    );
  }

  Frame _validationFrame(ContextId id, CurrentUniverseAuthority current) {
    final frame = _contextFrame(id, current);
    if (frame.perspective is! AuthorPerspective) {
      throw const UnsupportedSemanticsError(
        message: 'validation requires an author perspective frame',
      );
    }
    return frame;
  }

  Future<
    ({
      List<RecordVersion> all,
      List<RecordVersion> accessible,
      Set<RecordId> visibility,
      WorldId? focus,
    })
  >
  _readSnapshot({
    required Frame frame,
    required Selector? world,
    required WorldId? guard,
    required CurrentUniverseAuthority current,
  }) async {
    final all = _canon(frame.continuity, frame.revision);
    final focus = resolveWorldFocus(
      world: world,
      guard: guard,
      records: all,
      scope: current.worldScope,
    );
    final visibleIds = visibleRecordIds(
      records: all,
      worldScope: current.worldScope,
    );
    final perspective = await perspectiveRecordIds(
      records: all,
      frame: frame,
      readCanon: _canon,
    );
    final visible = all
        .where(
          (row) =>
              visibleIds.contains(row.identity.recordId) &&
              perspective.contains(row.identity.recordId),
        )
        .toList();
    final seeds = visible
        .where((row) {
          final worlds = recordWorlds(row);
          return focus == null || worlds.isEmpty || worlds.contains(focus);
        })
        .map((row) => row.identity.recordId);
    final included = focus == null
        ? seeds.toSet()
        : readDependencyClosure(visible, seeds);
    final accessible = visible
        .where((row) => included.contains(row.identity.recordId))
        .toList();
    return (
      all: all,
      accessible: accessible,
      visibility: visible.map((row) => row.identity.recordId).toSet(),
      focus: focus,
    );
  }

  Future<({Description description, Frame? frame, WorldId? focus})>
  describeRequest(ReadRequest request) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) async {
      final (guard, context, world, worldGuard) = switch (request) {
        DescribeSummaryRequest r => (r.universeId, null, null, null),
        DescribeCapabilitiesRequest r => (r.universeId, null, null, null),
        DescribeWorldsRequest r => (r.universeId, r.contextId, null, null),
        DescribeDefinitionsRequest r => (
          r.universeId,
          r.contextId,
          r.world,
          r.worldId,
        ),
        _ => throw const InvalidArgumentError(
          field: 'mode',
          message: 'requires describe request',
        ),
      };
      if (guard != null && guard != universe) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      final continuities = <ContinuitySummary>[];
      if (request is DescribeSummaryRequest) {
        for (final head in _journal.heads().entries) {
          final name = _workflow.get('continuity-name:${head.key.value}');
          final summary = discoveryContinuity(
            id: head.key,
            revision: head.value,
            name: name is CanonicalString ? name.value : 'Original continuity',
            records: _canon(head.key, head.value),
            worldScope: current.worldScope,
          );
          if (summary != null) continuities.add(summary);
        }
      }
      Frame? frame;
      WorldId? focus;
      var records = <RecordVersion>[];
      var visibility = <RecordId>{};
      if (context != null) {
        frame = _contextFrame(context, current);
        final snapshot = await _readSnapshot(
          frame: frame,
          world: world,
          guard: worldGuard,
          current: current,
        );
        records = snapshot.all;
        visibility = snapshot.visibility;
        focus = snapshot.focus;
      }
      return (
        description: discoveryDescription(
          records: records,
          visibility: visibility,
          definitions: request is DescribeDefinitionsRequest,
          focus: focus,
          continuities: continuities,
        ),
        frame: frame,
        focus: focus,
      );
    },
  );

  Future<Records> getRequest(
    GetRequest request,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    const denied = NotFoundOrNotAccessibleError(message: 'resource');
    if (request.universeId != null && request.universeId != universe) {
      throw denied;
    }
    final frame = _contextFrame(request.contextId, current);
    final snapshot = await _readSnapshot(
      frame: frame,
      world: request.world,
      guard: request.worldId,
      current: current,
    );
    final accessible = snapshot.accessible;
    final groups = request.fieldGroups;
    final historyRequested = groups.contains(FieldGroup.history);
    final fullHistory =
        current.worldScope == null && frame.perspective is AuthorPerspective;
    final records = <RecordVersion>[];
    final history = <HistoryEntry>[];
    for (final id in request.recordIds) {
      final matching = accessible.where((row) => row.identity.recordId == id);
      List<HistoryEntry>? changes;
      if (matching.isNotEmpty) {
        records.add(matching.single);
      } else {
        if (!historyRequested || !fullHistory) throw denied;
        changes = _journal
            .recordHistory(frame.continuity, frame.revision, id)
            .map(HistoryEntry.fromWire)
            .toList();
        if (changes.isEmpty) throw denied;
      }
      if (historyRequested && fullHistory) {
        history.addAll(
          changes ??
              _journal
                  .recordHistory(frame.continuity, frame.revision, id)
                  .map(HistoryEntry.fromWire),
        );
      }
    }
    final needed = groups.contains(FieldGroup.evidence)
        ? readResearchClosure(accessible, request.recordIds)
        : <RecordId>{};
    return Records(
      records: groups.isEmpty || groups.contains(FieldGroup.payload)
          ? records
          : [],
      summaries: groups.contains(FieldGroup.summary)
          ? records.map(
              (row) => RecordSummary(
                recordId: row.identity.recordId,
                kind: row.identity.recordKind,
                label: recordReadLabel(row),
              ),
            )
          : [],
      evidence: accessible.where(
        (row) =>
            needed.contains(row.identity.recordId) &&
            !request.recordIds.contains(row.identity.recordId),
      ),
      history: history,
      historyCoverage: historyRequested
          ? (fullHistory ? Coverage.complete : Coverage.restricted)
          : null,
    );
  });

  int _readOffset(
    CanonicalObject args,
    Frame frame,
    CurrentUniverseAuthority current,
    String? cursor,
  ) {
    const denied = NotFoundOrNotAccessibleError(message: 'resource');
    final binding = readCursorBinding(
      args: args,
      frame: frame,
      principal: principal.id,
      scopeHash: current.scopeHash,
    );
    var offset = 0;
    if (cursor != null) {
      final value = _workflow.get('cursor:$cursor');
      if (value == null) throw denied;
      final saved = StoredReadCursor.fromWire(value);
      if (saved.binding != binding) throw denied;
      offset = saved.offset.toInt();
      if (BigInt.from(offset) != saved.offset) throw denied;
    }
    return offset;
  }

  String? _retainReadCursor(
    CanonicalObject args,
    Frame frame,
    CurrentUniverseAuthority current,
    bool complete,
    int next,
  ) {
    final binding = readCursorBinding(
      args: args,
      frame: frame,
      principal: principal.id,
      scopeHash: current.scopeHash,
    );
    String? cursor;
    if (!complete) {
      cursor = OperationId.generate().value;
      _workflow.compareAppend({}, [
        MapEntry(
          'cursor:$cursor',
          StoredReadCursor(
            binding: binding,
            offset: BigInt.from(next),
          ).toWire(),
        ),
      ]);
    }
    return cursor;
  }

  Future<({ContextBrief brief, Delivery delivery})> getContextRequest(
    GetContextRequest request,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    const denied = NotFoundOrNotAccessibleError(message: 'resource');
    if (request.universeId != null && request.universeId != universe) {
      throw denied;
    }
    final frame = _contextFrame(request.contextId, current);
    final offset = _readOffset(
      request.toArgs(),
      frame,
      current,
      request.cursor,
    );
    final snapshot = await _readSnapshot(
      frame: frame,
      world: request.world,
      guard: request.worldId,
      current: current,
    );
    final page = buildContextBrief(
      all: snapshot.all,
      accessible: snapshot.accessible,
      visibility: snapshot.visibility,
      focusIds: request.focusIds,
      frame: frame,
      world: snapshot.focus,
      restricted:
          current.worldScope != null || frame.perspective is! AuthorPerspective,
      byteBudget: request.byteBudget,
      offset: offset,
    );
    final cursor = _retainReadCursor(
      request.toArgs(),
      frame,
      current,
      page.complete,
      page.next,
    );
    return (
      brief: page.brief,
      delivery: Delivery(complete: page.complete, cursor: cursor),
    );
  });

  Future<({SearchResults results, Delivery delivery})> searchRequest(
    SearchRequest request,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    const denied = NotFoundOrNotAccessibleError(message: 'resource');
    if (request.universeId != null && request.universeId != universe) {
      throw denied;
    }
    if (request.limit < 1 || request.limit > 100) {
      throw const InvalidArgumentError(
        field: 'limit',
        message: 'outside request limits',
      );
    }
    final frame = _contextFrame(request.contextId, current);
    final snapshot = await _readSnapshot(
      frame: frame,
      world: request.world,
      guard: request.worldId,
      current: current,
    );
    final indexed = SqliteKernel(package.database, universe)
        .search(frame.continuity, frame.revision, request.query)
        .map((row) => row.identity.recordId)
        .toSet();
    final hits = buildSearchHits(
      accessible: snapshot.accessible,
      indexed: indexed,
      query: request.query,
      filters: request.typedFilters,
      world: snapshot.focus,
      author: frame.perspective is AuthorPerspective,
    );
    final offset = _readOffset(
      request.toArgs(),
      frame,
      current,
      request.cursor,
    );
    if (offset > hits.length) throw denied;
    final end = (offset + request.limit).clamp(0, hits.length);
    final complete = end == hits.length;
    final cursor = _retainReadCursor(
      request.toArgs(),
      frame,
      current,
      complete,
      end,
    );
    return (
      results: SearchResults(hits: hits.sublist(offset, end)),
      delivery: Delivery(complete: complete, cursor: cursor),
    );
  });

  Future<({State state, Frame frame})> getStateRequest(
    GetStateRequest request,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    if (request.universeId != null && request.universeId != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final retained = _contextFrame(request.contextId, current);
    final snapshot = await _readSnapshot(
      frame: retained,
      world: request.world,
      guard: request.worldId,
      current: current,
    );
    for (final id in request.entityIds) {
      if (!snapshot.accessible.any((row) => row.identity.recordId == id)) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
    }
    final frame = stateReadFrame(
      retained,
      snapshot.accessible,
      request.event,
      request.eventSide,
    );
    final restricted =
        current.worldScope != null || frame.perspective is! AuthorPerspective;
    final receipts = restricted
        ? <InitializationReceipt>[]
        : SqliteKernel(
            package.database,
            universe,
          ).initializationReceiptsAt(frame.continuity, frame.revision);
    final state = assembleReadState(
      records: snapshot.accessible,
      frame: frame,
      ids: request.entityIds,
      predicates: request.predicateFilters,
      world: snapshot.focus,
      restricted: restricted,
      receipts: receipts,
      readVersion: _version,
    );
    return (state: state, frame: frame);
  });

  Future<({ProposalViewResult result, Delivery delivery})> getProposalRequest(
    GetProposalRequest request,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    const denied = NotFoundOrNotAccessibleError(message: 'resource');
    if (request.universeId != null && request.universeId != universe) {
      throw denied;
    }
    if (request.assessmentReference != null &&
        request.viewGroup != ProposalView.assessment) {
      throw const InvalidArgumentError(
        field: 'assessment_reference',
        message: 'requires assessment view',
      );
    }
    final key =
        'proposal:${request.proposalId.value}:${request.version.toString().padLeft(20, '0')}';
    final value = _workflow.get(key);
    if (value == null) throw denied;
    final stored = StoredProposal.fromWire(value);
    final reference = ProposalRef(
      proposalId: request.proposalId,
      version: request.version,
      digest: stored.proposal.digest,
    );
    try {
      _admitProposal(stored, reference, current);
    } on Object {
      throw denied;
    }
    final frame = stored.proposal.baseFrame;
    if (request.viewGroup == ProposalView.assessment) {
      late AssessmentReview review;
      try {
        review = await _assessmentReview(
          reference,
          current,
          exact: request.assessmentReference,
        );
      } on Object {
        throw denied;
      }
      final binding = assessmentPageBinding(
        request.toArgs(),
        reference,
        review,
      );
      final offset = _readOffset(binding, frame, current, request.cursor);
      final page = pageAssessmentReview(review, offset);
      final cursor = _retainReadCursor(
        binding,
        frame,
        current,
        page.complete,
        page.next,
      );
      return (
        result: AssessmentProposalView(page.page),
        delivery: Delivery(complete: page.complete, cursor: cursor),
      );
    }
    final offset = _readOffset(
      request.toArgs(),
      frame,
      current,
      request.cursor,
    );
    final page = pageFrozenProposal(stored, offset);
    final cursor = _retainReadCursor(
      request.toArgs(),
      frame,
      current,
      page.complete,
      page.next,
    );
    return (
      result: FrozenProposalView(page.proposal),
      delivery: Delivery(complete: page.complete, cursor: cursor),
    );
  });

  Future<({Impact impact, Frame frame, WorldId? focus})> getImpactRequest(
    WorkflowRequest request,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    final (context, guard, world, worldGuard, budget) = switch (request) {
      InlineImpactRequest r => (
        r.contextId,
        r.universeId,
        r.world,
        r.worldId,
        r.byteBudget,
      ),
      ProposalImpactRequest r => (
        r.contextId,
        r.universeId,
        null,
        null,
        r.byteBudget,
      ),
      _ => throw const InvalidArgumentError(
        field: 'mode',
        message: 'requires impact request',
      ),
    };
    if (guard != null && guard != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final frame = _contextFrame(context, current);
    if (frame.perspective is! AuthorPerspective) {
      throw const UnsupportedSemanticsError(
        message: 'impact requires an author perspective frame',
      );
    }
    final all = _canon(frame.continuity, frame.revision);
    final focus = resolveWorldFocus(
      world: world,
      guard: worldGuard,
      records: all,
      scope: current.worldScope,
    );
    late Iterable<RecordId> seeds;
    if (request is ProposalImpactRequest) {
      final stored = _proposal(request.proposalReference, current);
      if (stored.proposal.baseFrame != frame) throw const ApprovalStaleError();
      all.addAll([
        for (final change in stored.changes)
          if (change.next != null)
            RecordVersion.fromWire(change.next!.toCanonical()),
      ]);
      seeds = stored.changes.map((change) => change.recordId);
    } else {
      seeds = (request as InlineImpactRequest).changedRecords;
    }
    return (
      impact: conservativeImpact(
        records: all,
        changedRecords: seeds,
        worldScope: current.worldScope,
        byteBudget: budget,
      ),
      frame: frame,
      focus: focus,
    );
  });

  /// Native dispatch entry: admit the retained context and resolve named world
  /// focus under the same current authority section as proposal retention.
  Future<Proposal> proposeRequest(
    WorkflowRequest request, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(principal, universe, (current) {
    final (
      ContextId contextId,
      Selector? world,
      WorldId? guard,
    ) = switch (request) {
      CreateProposalRequest() => (
        request.contextId,
        request.world,
        request.worldId,
      ),
      ReviseProposalRequest() => (
        request.contextId,
        request.world,
        request.worldId,
      ),
      SubmitProposalRequest() => (request.contextId, null, null),
      WithdrawProposalRequest() => (request.contextId, null, null),
      _ => throw ArgumentError.value(
        request,
        'request',
        'Expected proposal state action',
      ),
    };
    final frame = _contextFrame(contextId, current);
    final focus = world == null
        ? null
        : resolveWorldFocus(
            world: world,
            guard: guard,
            records: _canon(frame.continuity, frame.revision),
            scope: current.worldScope,
          );
    return _propose(
      request,
      current,
      resolvedFrame: frame,
      worldFocus: focus,
      isValidationActive: isValidationActive,
    );
  });

  Future<Proposal> _propose(
    WorkflowRequest request,
    CurrentUniverseAuthority current, {
    required Frame resolvedFrame,
    required WorldId? worldFocus,
    required bool Function(OperationId) isValidationActive,
  }) async {
    final (
      String idempotencyKey,
      UniverseId? requestedUniverse,
      ProposalRef? reference,
      bool compile,
    ) = switch (request) {
      CreateProposalRequest() => (
        request.idempotencyKey,
        request.universeId,
        null,
        true,
      ),
      ReviseProposalRequest() => (
        request.idempotencyKey,
        request.universeId,
        request.proposalReference,
        true,
      ),
      SubmitProposalRequest() => (
        request.idempotencyKey,
        request.universeId,
        request.proposalReference,
        false,
      ),
      WithdrawProposalRequest() => (
        request.idempotencyKey,
        request.universeId,
        request.proposalReference,
        false,
      ),
      _ => throw ArgumentError.value(
        request,
        'request',
        'Expected proposal state action',
      ),
    };
    if (resolvedFrame.universe != universe ||
        requestedUniverse != null && requestedUniverse != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    if (resolvedFrame.time is! TimelessFrameTime) {
      throw const UnsupportedSemanticsError(
        message:
            'create or revise proposals from an all-validities author frame',
      );
    }
    final key = operationRequestKey(principal.id, 'propose', idempotencyKey);
    final digest = canonicalDigest(request.toArgs());
    if (_workflow.get(key) != null) {
      final op = await loadStoredOperation(
        key: key,
        principal: principal.id,
        worldScope: current.worldScope,
        readWorkflow: _workflow.get,
        readReceipt: _journal.receipt,
        isValidationActive: isValidationActive,
      );
      if (op.digest != digest) {
        throw const IdempotencyKeyReusedError(message: 'request differs');
      }
      final saved = op.status.proposal;
      if (saved == null) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      return saved;
    }
    final previous = reference == null ? null : _proposal(reference, current);
    if (previous != null &&
        _workflow.latestKey('proposal:${reference!.proposalId.value}:') !=
            previous.key) {
      throw const ApprovalStaleError();
    }
    final base = _canon(resolvedFrame.continuity, resolvedFrame.revision);
    final prepared = prepareProposal(
      request: request,
      frame: resolvedFrame,
      base: base,
      principal: principal.id,
      author: principal.author,
      worldFocus: worldFocus,
      previous: previous,
    );
    _admitProposal(prepared, prepared.reference, current);
    final kernel = SqliteKernel(package.database, universe);
    if (compile) {
      await checkProposalReservations(
        stored: prepared,
        readWorkflow: _workflow.get,
        identityExists: kernel.identityExists,
        readVersion: _version,
      );
      final input = await proposalCommitInput(
        stored: prepared,
        universe: universe,
        principal: principal.id,
        idempotencyKey: 'proposal-preview',
        readCanon: _canon,
      );
      kernel.preview(input);
    }
    final p = prepared.proposal;
    final op = StoredOperation(
      owner: principal.id,
      digest: digest,
      input: null,
      footprint: prepared.footprint,
      status: OperationStatus(
        operationId: p.operationId,
        kind: OperationKind.propose,
        state: OperationState.succeeded,
        proposal: p,
        cancellationRequested: false,
      ),
    );
    final entries = [
      MapEntry(prepared.key, prepared.toWire()),
      MapEntry(key, op.toWire()),
      MapEntry('operation:${p.operationId.value}', op.toWire()),
      ...await proposalReservationEntries(
        stored: prepared,
        readWorkflow: _workflow.get,
      ),
    ];
    final comparisons = <String, String?>{};
    if (previous != null) {
      comparisons['proposal:${previous.proposal.proposalId.value}:'] =
          previous.key;
    }
    _workflow.compareAppend(comparisons, entries);
    return p;
  }

  Future<ValidationCapture> capture(ProposalRef reference) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) => _capture(_proposal(reference, current), current),
      );

  Future<StoredOperation> operation(
    OperationId id, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => loadStoredOperation(
      key: 'operation:${id.value}',
      principal: current.principal.id,
      worldScope: current.worldScope,
      readWorkflow: _workflow.get,
      readReceipt: _journal.receipt,
      isValidationActive: isValidationActive,
    ),
  );

  Future<OperationStatusV3> operationStatus(
    OperationId id, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(principal, universe, (current) async {
    final op = await loadStoredOperation(
      key: 'operation:${id.value}',
      principal: current.principal.id,
      worldScope: current.worldScope,
      readWorkflow: _workflow.get,
      readReceipt: _journal.receipt,
      isValidationActive: isValidationActive,
    );
    return publicOperationStatus(
      status: op.status,
      worldScope: current.worldScope,
      readWorkflow: _workflow.get,
    );
  });

  Future<({OperationStatusV3 status, Frame? frame, Delivery delivery})>
  getOperationRequest(
    WorkflowRequest request, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(principal, universe, (current) async {
    const denied = NotFoundOrNotAccessibleError(message: 'resource');
    final (key, guard, cursor) = switch (request) {
      GetOperationIdRequest r => (
        'operation:${r.operationId.value}',
        r.universeId,
        r.cursor,
      ),
      GetOperationKeyRequest r => (
        operationRequestKey(
          current.principal.id,
          r.operationKind.wireName,
          r.idempotencyKey,
        ),
        r.universeId,
        r.cursor,
      ),
      _ => throw const InvalidArgumentError(
        field: 'lookup',
        message: 'requires operation lookup',
      ),
    };
    if (guard != null && guard != universe) throw denied;
    var status = (await loadStoredOperation(
      key: key,
      principal: current.principal.id,
      worldScope: current.worldScope,
      readWorkflow: _workflow.get,
      readReceipt: _journal.receipt,
      isValidationActive: isValidationActive,
    )).status;
    final frame = status.proposal?.baseFrame;
    var delivery = Delivery(complete: true, cursor: null);
    final validation = status.validation;
    if (current.worldScope != null && validation != null) {
      if (cursor != null) throw denied;
    } else if (validation != null) {
      if (frame == null) throw denied;
      final binding = CanonicalObject([
        ...request.toArgs().fields,
        MapEntry(
          'result_digest',
          CanonicalString(canonicalDigest(validation.toWire())),
        ),
        MapEntry(
          'resolved_operation',
          CanonicalString(status.operationId.value),
        ),
      ]);
      final offset = _readOffset(binding, frame, current, cursor);
      final page = pageOperationFindings(status, offset);
      status = page.status;
      delivery = Delivery(
        complete: page.complete,
        cursor: _retainReadCursor(
          binding,
          frame,
          current,
          page.complete,
          page.next,
        ),
      );
    } else if (cursor != null) {
      throw denied;
    }
    return (
      status: await publicOperationStatus(
        status: status,
        worldScope: current.worldScope,
        readWorkflow: _workflow.get,
      ),
      frame: frame,
      delivery: delivery,
    );
  });

  /// The dispatcher resolves the request's universe/context before passing its
  /// exact frame here. Submission retains work; execution is a separate step.
  Future<OperationStatusV3> queueValidation(
    QueuedProposalValidationRequest request, {
    required Frame resolvedFrame,
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _queueValidation(
      request,
      current,
      resolvedFrame: resolvedFrame,
      isValidationActive: isValidationActive,
    ),
  );

  Future<OperationStatusV3> queueValidationRequest(
    QueuedProposalValidationRequest request, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _queueValidation(
      request,
      current,
      resolvedFrame: _validationFrame(request.contextId, current),
      isValidationActive: isValidationActive,
    ),
  );

  /// Complete a proposal check and retain its exact evidence under current
  /// authority. This does not create a queued operation or publish canon.
  Future<ValidationV3> validateProposalRequest(
    ProposalValidationRequest request,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    if (request.universeId != null && request.universeId != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final frame = _validationFrame(request.contextId, current);
    final stored = _proposal(request.proposalReference, current);
    if (stored.proposal.baseFrame != frame) {
      throw const ApprovalStaleError();
    }
    final captured = current.worldScope == null
        ? await _capture(stored, current)
        : null;
    final kernel = SqliteKernel(package.database, universe);
    final result = await checkProposalCandidate(
      stored: stored,
      universe: universe,
      principal: principal.id,
      approvalAuthor: current.approvalAuthor,
      scope: current.worldScope,
      preview: (input) => kernel
          .preview(input)
          .map((row) => RecordVersion.fromWire(row.toCanonical()))
          .toList(),
      readCanon: _canon,
      readWorkflow: _workflow.get,
      readVersion: _version,
    );
    final report =
        captured?.report(
          proposal: request.proposalReference,
          baseFrame: frame,
          execution: result.validation,
          finished: true,
        ) ??
        ValidationV3.restricted();
    final completed = CheckedValidation(
      proposalDigest: result.proposalDigest,
      validation: result.validation,
      admissible: result.admissible,
      capture: captured,
      report: report,
    );
    await _persistValidation(request.proposalReference, completed, current, [
      MapEntry(
        'validation:${result.validation.runId.value}',
        completed.toWire(),
      ),
    ]);
    return report;
  });

  /// Research an ephemeral candidate. No proposal, reservation, approval
  /// binding or publication operation is created by this check.
  Future<ValidationV3> validateInlineRequest(
    InlineValidationRequest request,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    if (request.universeId != null && request.universeId != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final frame = _validationFrame(request.contextId, current);
    final base = _canon(frame.continuity, frame.revision);
    // Compilation errors can disclose hidden definitions. Restricted research
    // resolves only its visible world selector and never compiles the candidate.
    if (current.worldScope != null) {
      resolveWorldFocus(
        world: request.world,
        guard: request.worldId,
        records: base,
        scope: current.worldScope,
      );
      return ValidationV3.restricted();
    }
    final changes = compileOperations(
      universe: universe,
      revision: frame.revision,
      base: base,
      operations: request.operations,
    );
    final footprint = writeFootprint(base: base, changes: changes);
    final focus = resolveWorldFocus(
      world: request.world,
      guard: request.worldId,
      records: base,
      scope: null,
    );
    if (focus != null &&
        (footprint.shared || footprint.worlds.any((world) => world != focus))) {
      throw const WorldScopeConflictError(
        message: 'full write footprint exceeds named world',
      );
    }
    final stored = StoredProposal(
      owner: principal.id,
      authorOrigin: principal.author,
      changes: changes,
      footprint: footprint,
      proposal: Proposal(
        baseFrame: frame,
        worldScope: focus,
        proposalId: ProposalId.generate(),
        version: BigInt.one,
        digest: canonicalDigest(request.toArgs()),
        submission: Submission.draft,
        operations: request.operations,
        compiledChanges: [],
        rationale: 'inline validation',
        canonical: false,
        operationId: OperationId.generate(),
        withdrawn: false,
      ),
    );
    final kernel = SqliteKernel(package.database, universe);
    final result = await checkProposalCandidate(
      stored: stored,
      universe: universe,
      principal: principal.id,
      approvalAuthor: current.approvalAuthor,
      scope: null,
      preview: (input) => kernel
          .preview(input)
          .map((row) => RecordVersion.fromWire(row.toCanonical()))
          .toList(),
      readCanon: _canon,
      readWorkflow: _workflow.get,
      readVersion: _version,
    );
    final report = EvaluatedValidation(
      execution: result.validation,
      submittedInput: QueryInput(frame: frame, checkScope: request.checkScope),
      assessment: const AbsentAssessment(),
      finalBindingDigest: null,
    );
    final completed = CheckedValidation(
      proposalDigest: result.proposalDigest,
      validation: result.validation,
      admissible: result.admissible,
      report: report,
    );
    _workflow.compareAppend({}, [
      MapEntry(
        'validation:${result.validation.runId.value}',
        completed.toWire(),
      ),
    ]);
    return report;
  });

  Future<OperationStatusV3> _queueValidation(
    QueuedProposalValidationRequest request,
    CurrentUniverseAuthority current, {
    required Frame resolvedFrame,
    required bool Function(OperationId) isValidationActive,
  }) async {
    const denied = NotFoundOrNotAccessibleError(message: 'resource');
    if (resolvedFrame.universe != universe ||
        request.universeId != null && request.universeId != universe) {
      throw denied;
    }
    final entries = <MapEntry<String, CanonicalValue>>[];
    late StoredOperation operation;
    await _workflow.compareAppendWithVerification(
      entries: entries,
      verify: () async {
        final proposal = _proposal(request.proposalReference, current);
        if (proposal.proposal.baseFrame != resolvedFrame) {
          throw const ApprovalStaleError();
        }
        final key = operationRequestKey(
          principal.id,
          'validate',
          request.idempotencyKey,
        );
        final digest = canonicalDigest(request.toArgs());
        if (_workflow.get(key) != null) {
          operation = await loadStoredOperation(
            key: key,
            principal: principal.id,
            worldScope: current.worldScope,
            readWorkflow: _workflow.get,
            readReceipt: _journal.receipt,
            isValidationActive: isValidationActive,
          );
          if (operation.digest != digest) {
            throw const IdempotencyKeyReusedError(
              message: 'validation request differs',
            );
          }
          return const {};
        }
        final id = OperationId.generate();
        operation = StoredOperation(
          owner: principal.id,
          digest: digest,
          input: null,
          footprint: proposal.footprint,
          validationCapture: current.worldScope != null
              ? null
              : await _capture(proposal, current),
          status: OperationStatus(
            operationId: id,
            kind: OperationKind.validate,
            state: OperationState.queued,
            proposal: proposal.proposal,
            cancellationRequested: false,
            validation: Validation(
              operationId: id,
              runId: ValidationRunId.generate(),
              coverage: Coverage.partial,
              findings: [],
              opposingEvidence: [],
              unsupportedCapabilities: [
                'Validation queued; poll this operation for completed evidence',
              ],
              inputDigest: proposal.proposal.digest,
              evaluatorVersion: candidateEvaluatorVersion,
            ),
          ),
        );
        entries.addAll([
          MapEntry(key, operation.toWire()),
          MapEntry('operation:${id.value}', operation.toWire()),
        ]);
        return const {};
      },
    );
    return publicOperationStatus(
      status: operation.status,
      worldScope: current.worldScope,
      readWorkflow: _workflow.get,
    );
  }

  /// The dispatcher resolves the universe before calling this route. The live
  /// cancellation signal is sent only after durable cancellation is retained.
  Future<OperationStatusV3> cancelOperation(
    CancelOperationRequest request, {
    required bool Function(OperationId) isValidationActive,
    required void Function(OperationId) signalCancellation,
  }) => authority.withUniverseAuthority(principal, universe, (current) async {
    if (request.universeId != null && request.universeId != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final entries = <MapEntry<String, CanonicalValue>>[];
    late StoredOperation operation;
    var fresh = false;
    await _workflow.compareAppendWithVerification(
      entries: entries,
      verify: () async {
        Future<StoredOperation> load(String key) => loadStoredOperation(
          key: key,
          principal: principal.id,
          worldScope: current.worldScope,
          readWorkflow: _workflow.get,
          readReceipt: _journal.receipt,
          isValidationActive: isValidationActive,
        );
        operation = await load('operation:${request.operationId.value}');
        final key = operationRequestKey(
          principal.id,
          'cancel',
          request.idempotencyKey,
        );
        final digest = canonicalDigest(request.toArgs());
        final existing = _workflow.get(key);
        if (existing != null) {
          if (StoredOperation.fromWire(existing).digest != digest) {
            throw const IdempotencyKeyReusedError(
              message: 'cancel key names another request',
            );
          }
          operation = await load(key);
          return const {};
        }
        final s = operation.status;
        final cancel =
            s.state != OperationState.succeeded &&
            s.state != OperationState.failed;
        if (cancel) {
          entries.add(
            MapEntry(
              'cancel:${request.operationId.value}',
              CanonicalObject([
                MapEntry('owner', CanonicalString(principal.id.value)),
                MapEntry('cancelled', const CanonicalBool(true)),
              ]),
            ),
          );
        }
        operation = StoredOperation(
          owner: operation.owner,
          digest: digest,
          input: operation.input,
          footprint: operation.footprint,
          validationCapture: operation.validationCapture,
          status: OperationStatus(
            operationId: s.operationId,
            kind: s.kind,
            state: cancel ? OperationState.cancelled : s.state,
            proposal: s.proposal,
            validation: s.validation,
            failure: s.failure,
            receipt: s.receipt,
            cancellationRequested: cancel || s.cancellationRequested,
          ),
        );
        entries.add(MapEntry(key, operation.toWire()));
        fresh = true;
        return const {};
      },
    );
    if (fresh) signalCancellation(request.operationId);
    return publicOperationStatus(
      status: operation.status,
      worldScope: current.worldScope,
      readWorkflow: _workflow.get,
    );
  });

  Future<PreparedValidationTask?> prepareValidation(
    OperationId id, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(principal, universe, (current) async {
    const denied = NotFoundOrNotAccessibleError(message: 'resource');
    final op = await loadStoredOperation(
      key: 'operation:${id.value}',
      principal: principal.id,
      worldScope: current.worldScope,
      readWorkflow: _workflow.get,
      readReceipt: _journal.receipt,
      isValidationActive: isValidationActive,
    );
    if (op.status.kind != OperationKind.validate ||
        {
          OperationState.succeeded,
          OperationState.failed,
          OperationState.cancelled,
        }.contains(op.status.state)) {
      return null;
    }
    final stored = op.status.proposal;
    if (stored == null) throw denied;
    final reference = ProposalRef(
      proposalId: stored.proposalId,
      version: stored.version,
      digest: stored.digest,
    );
    final proposal = _proposal(reference, current);
    final restricted = current.worldScope != null;
    final captured = restricted ? null : op.validationCapture;
    if (!restricted && captured == null) {
      throw const UnsupportedSemanticsError(
        message: 'queued validation requires a fresh selection capture',
      );
    }
    if (captured != null) {
      verifyValidationAuthority(captured, current.sequence);
      final fresh = await _capture(proposal, current);
      verifyValidationCapture(
        proposal: reference,
        captured: captured,
        current: fresh,
      );
    }
    final List<RecordVersion> base, candidate;
    if (restricted) {
      base = const [];
      candidate = const [];
    } else {
      await verifyImmutableAdoptions(stored: proposal, readVersion: _version);
      final input = await proposalCommitInput(
        stored: proposal,
        universe: universe,
        principal: principal.id,
        idempotencyKey: 'validation',
        readCanon: _canon,
      );
      candidate = SqliteKernel(package.database, universe)
          .preview(input)
          .map((row) => RecordVersion.fromWire(row.toCanonical()))
          .toList();
      await verifyCandidateSources(
        records: candidate,
        readWorkflow: _workflow.get,
        readVersion: _version,
      );
      base = _canon(
        proposal.proposal.baseFrame.continuity,
        proposal.proposal.baseFrame.revision,
      );
    }
    final key = 'job:${id.value}:running';
    if (_workflow.get(key) == null) {
      final s = op.status;
      final running = StoredOperation(
        owner: op.owner,
        digest: op.digest,
        input: op.input,
        footprint: op.footprint,
        validationCapture: op.validationCapture,
        status: OperationStatus(
          validation: s.validation,
          failure: s.failure,
          operationId: s.operationId,
          kind: s.kind,
          state: OperationState.running,
          proposal: s.proposal,
          receipt: s.receipt,
          cancellationRequested: s.cancellationRequested,
        ),
      );
      _workflow.compareAppend({}, [MapEntry(key, running.toWire())]);
    }
    return PreparedValidationTask(
      operationId: id,
      proposal: proposal,
      base: base,
      candidate: candidate,
      approvalAuthor: current.approvalAuthor,
      restricted: restricted,
      capture: captured,
    );
  });

  Future<AssessmentSelection> attachAssessment(
    ProposalRef reference, {
    required BigInt expectedGeneration,
    required SourceAssessmentV1 body,
    required String idempotencyKey,
  }) => _changeAssessment(
    reference,
    expectedGeneration,
    body,
    null,
    idempotencyKey,
  );

  Future<AssessmentSelection> selectAssessment(
    ProposalRef reference, {
    required BigInt expectedGeneration,
    required AssessmentRef? selected,
    required String idempotencyKey,
  }) => _changeAssessment(
    reference,
    expectedGeneration,
    null,
    selected,
    idempotencyKey,
  );

  Future<AssessmentSelection> _changeAssessment(
    ProposalRef reference,
    BigInt expected,
    SourceAssessmentV1? body,
    AssessmentRef? selected,
    String key,
  ) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _changeAssessmentUnderAuthority(
      reference,
      expected,
      body,
      selected,
      key,
      current,
    ),
  );

  Future<AssessmentSelection> assessmentRequest(WorkflowRequest request) =>
      authority.withUniverseAuthority(principal, universe, (current) {
        final (
          ContextId contextId,
          UniverseId? requestedUniverse,
          ProposalRef reference,
          BigInt expected,
          SourceAssessmentV1? body,
          AssessmentRef? selected,
          String key,
        ) = switch (request) {
          AttachAssessmentRequest() => (
            request.contextId,
            request.universeId,
            request.proposalReference,
            request.expectedSelectionGeneration,
            request.body,
            null,
            request.idempotencyKey,
          ),
          SelectAssessmentRequest() => (
            request.contextId,
            request.universeId,
            request.proposalReference,
            request.expectedSelectionGeneration,
            null,
            request.assessmentReference,
            request.idempotencyKey,
          ),
          _ => throw ArgumentError.value(
            request,
            'request',
            'Expected assessment action',
          ),
        };
        const denied = NotFoundOrNotAccessibleError(message: 'resource');
        if (requestedUniverse != null && requestedUniverse != universe) {
          throw denied;
        }
        final frame = _contextFrame(contextId, current);
        final StoredProposal proposal;
        try {
          proposal = _proposal(reference, current);
        } on Object {
          throw denied;
        }
        if (frame != proposal.proposal.baseFrame) {
          throw const ApprovalStaleError();
        }
        return _changeAssessmentUnderAuthority(
          reference,
          expected,
          body,
          selected,
          key,
          current,
        );
      });

  Future<AssessmentSelection> _changeAssessmentUnderAuthority(
    ProposalRef reference,
    BigInt expected,
    SourceAssessmentV1? body,
    AssessmentRef? selected,
    String key,
    CurrentUniverseAuthority current,
  ) async {
    const denied = NotFoundOrNotAccessibleError(message: 'resource');
    InvalidArgumentError invalid(String message) =>
        InvalidArgumentError(field: 'assessment', message: message);
    final entries = <MapEntry<String, CanonicalValue>>[];
    late AssessmentSelection result;
    await _workflow.compareAppendWithVerification(
      entries: entries,
      verify: () async {
        StoredProposal proposal;
        try {
          proposal = _proposal(reference, current);
        } on Object {
          throw denied;
        }
        Future<void> access(SourceAssessmentV1? body) async {
          await checkAssessmentAccess(
            proposal: proposal,
            body: body,
            limits: current.limits,
            worldScope: current.worldScope,
            readCanon: _canon,
            readVersion: _version,
          );
        }

        Future<void> verify(SourceAssessmentV1 body) =>
            verifyAssessmentCandidate(
              proposal: proposal,
              universe: universe,
              body: body,
              readCanon: _canon,
              readVersion: _version,
              readWorkflow: _workflow.get,
            );
        await access(body);
        final encoded = utf8.encode(key);
        if (encoded.isEmpty ||
            encoded.length > 16384 ||
            utf8.decode(encoded) != key) {
          throw invalid('invalid idempotency key');
        }
        if (expected < BigInt.zero || expected >= BigInt.one << 64) {
          throw invalid('invalid selection generation');
        }
        if (body != null) {
          if (body.assessor.principal.value !=
              principal.id.value.replaceFirst('prf_', 'prn_')) {
            throw denied;
          }
          await verify(body);
        }
        final digest = canonicalDigest(
          CanonicalArray([
            reference.toWire(),
            CanonicalNumber(expected.toString()),
            body?.toWire() ?? const CanonicalNull(),
            selected?.toWire() ?? const CanonicalNull(),
          ]),
        );
        final receiptKey =
            'assessment-receipt:${principal.id.value}:${canonicalDigest(CanonicalString(key))}';
        final receipt = _workflow.get(receiptKey);
        if (receipt != null) {
          final fields = WireFields(receipt, {
            'request_digest',
            'selection',
            'envelope',
          });
          final envelope = fields.optional(
            'envelope',
            AssessmentEnvelope.fromWire,
          );
          if (envelope != null) await access(envelope.body);
          if (fields.string('request_digest') != digest) {
            throw const IdempotencyKeyReusedError(message: 'request differs');
          }
          result = AssessmentSelection.fromWire(fields.require('selection'));
          return const {};
        }
        final frame = proposal.proposal.baseFrame;
        if (_workflow.latestKey('proposal:${reference.proposalId.value}:') !=
                proposal.key ||
            proposal.proposal.withdrawn ||
            proposal.proposal.submission != Submission.submitted ||
            _journal.head(frame.continuity) != frame.revision) {
          throw const ApprovalStaleError();
        }
        final previous = await readAssessmentSelection(
          reference: reference,
          readLatestKey: _workflow.latestKey,
          readWorkflow: _workflow.get,
        );
        if (previous.generation != expected) throw const ApprovalStaleError();
        AssessmentEnvelope? envelope;
        if (body != null) {
          envelope = AssessmentEnvelope(
            assessmentId: AssessmentId(
              RecordId.generate().value.replaceFirst('rec_', 'asm_'),
            ),
            digest: body.digest(),
            body: body,
          );
        } else if (selected != null) {
          final value = _workflow.get(assessmentEnvelopeKey(selected));
          if (value == null) throw denied;
          envelope = AssessmentEnvelope.fromWire(value);
          try {
            envelope.verify();
          } on FormatException catch (e) {
            throw invalid(e.message);
          }
          if (envelope.digest != selected.digest) throw denied;
          await access(envelope.body);
          await verify(envelope.body);
        }
        final next = envelope == null
            ? null
            : AssessmentRef(
                assessmentId: envelope.assessmentId,
                digest: envelope.digest,
              );
        CanonicalValue pin(AssessmentRef? ref) =>
            ref?.toWire() ?? const CanonicalNull();
        if (canonicalDigest(pin(next)) ==
            canonicalDigest(pin(previous.selected))) {
          throw invalid('selection is unchanged');
        }
        if (expected == (BigInt.one << 64) - BigInt.one) {
          throw invalid('selection generation exhausted');
        }
        result = AssessmentSelection(
          proposal: reference,
          generation: expected + BigInt.one,
          selected: next,
        );
        final prefix = assessmentSelectionPrefix(reference);
        entries.addAll([
          MapEntry(
            '$prefix${result.generation.toString().padLeft(20, '0')}',
            result.toWire(),
          ),
          MapEntry(
            receiptKey,
            CanonicalObject([
              MapEntry('request_digest', CanonicalString(digest)),
              MapEntry('selection', result.toWire()),
              MapEntry('envelope', envelope?.toWire() ?? const CanonicalNull()),
            ]),
          ),
          if (envelope != null)
            MapEntry(assessmentEnvelopeKey(next!), envelope.toWire()),
        ]);
        return {
          prefix: expected > BigInt.zero
              ? '$prefix${expected.toString().padLeft(20, '0')}'
              : null,
          'proposal:${reference.proposalId.value}:': proposal.key,
        };
      },
    );
    return result;
  }

  /// Publish only a retained, exactly checked and approved/delegated proposal.
  /// The dispatcher resolves the request's universe before calling this route.
  Future<CommitReceipt> commit(
    CommitRequest request, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(principal, universe, (current) async {
    if (request.universeId != null && request.universeId != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final proposal = _proposal(request.proposalReference, current);
    final p = proposal.proposal;
    authority.authorizeWrite(
      principal,
      universe: universe,
      worlds: proposal.footprint.worlds,
      shared: proposal.footprint.shared,
      protected: proposal.footprint.protected,
      commit: true,
    );
    final key = operationRequestKey(
      principal.id,
      'commit',
      request.idempotencyKey,
    );
    final digest = canonicalDigest(request.toArgs());
    Future<StoredOperation> load() => loadStoredOperation(
      key: key,
      principal: principal.id,
      worldScope: current.worldScope,
      readWorkflow: _workflow.get,
      readReceipt: _journal.receipt,
      isValidationActive: isValidationActive,
    );
    StoredOperation? operation;
    if (_workflow.get(key) != null) {
      operation = await load();
      if (operation.digest != digest) {
        throw const IdempotencyKeyReusedError(message: 'request differs');
      }
      if (operation.status.receipt != null) return operation.status.receipt!;
    }
    if (_workflow.latestKey('proposal:${p.proposalId.value}:') !=
            proposal.key ||
        p.withdrawn ||
        p.submission != Submission.submitted ||
        request.expectedBaseRevision != p.baseFrame.revision) {
      throw const ApprovalStaleError();
    }
    final value = _workflow.get('validation:${request.validationRun.value}');
    if (value == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final checked = CheckedValidation.fromWire(value);
    if (checked.proposalDigest != p.digest ||
        !checked.admissible ||
        checked.validation.evaluatorVersion != candidateEvaluatorVersion) {
      throw const ApprovalStaleError();
    }
    final limits = current.limits;
    final delegated =
        limits.delegatedCommit &&
        !proposal.footprint.protected &&
        (!proposal.footprint.shared || limits.allowShared) &&
        checked.validation.coverage == Coverage.complete;
    if (!delegated) {
      final approval = _workflow.get(
        'approval:${current.approvalAuthor.value}:${p.digest}:${request.validationRun.value}',
      );
      if (approval == null) {
        throw const ApprovalRequiredError(
          message: 'author must approve this exact proposal and validation',
        );
      }
      final fields = WireFields(approval, {
        'author',
        'proposal',
        'validation_digest',
        'evaluator',
      });
      if (fields.string('evaluator') != candidateEvaluatorVersion ||
          fields.string('author') != current.approvalAuthor.value ||
          fields.string('validation_digest') !=
              canonicalDigest(checked.toWire())) {
        throw const ApprovalStaleError();
      }
    }
    Future<ValidationCapture> capture() async {
      final result = await _capture(proposal, current, publication: true);
      verifyPublicationReport(
        report: checked.report,
        current: result,
        proposal: request.proposalReference,
        baseFrame: p.baseFrame,
        execution: checked.validation,
      );
      return result;
    }

    final captured = await capture();
    final head = _journal.head(p.baseFrame.continuity);
    if (head != request.expectedBaseRevision) {
      throw BaseRevisionConflictError(
        expected: request.expectedBaseRevision.value,
        actual: head.value,
      );
    }
    final kernel = SqliteKernel(package.database, universe);
    final fresh = await checkProposalCandidate(
      stored: proposal,
      universe: universe,
      principal: principal.id,
      approvalAuthor: current.approvalAuthor,
      scope: null,
      preview: (input) => kernel
          .preview(input)
          .map((r) => RecordVersion.fromWire(r.toCanonical()))
          .toList(),
      readCanon: _canon,
      readWorkflow: _workflow.get,
      readVersion: _version,
    );
    final v = fresh.validation;
    final comparable = Validation(
      operationId: checked.validation.operationId,
      runId: checked.validation.runId,
      coverage: v.coverage,
      findings: v.findings,
      opposingEvidence: v.opposingEvidence,
      unsupportedCapabilities: v.unsupportedCapabilities,
      inputDigest: v.inputDigest,
      evaluatorVersion: v.evaluatorVersion,
    );
    if (!fresh.admissible ||
        canonicalDigest(comparable.toWire()) !=
            canonicalDigest(checked.validation.toWire())) {
      throw const ApprovalStaleError();
    }
    await capture();
    final CommitInput input = await proposalCommitInput(
      stored: proposal,
      universe: universe,
      principal: principal.id,
      idempotencyKey: request.idempotencyKey,
      readCanon: _canon,
    );
    if (operation == null) {
      final id = OperationId.generate();
      operation = StoredOperation(
        owner: principal.id,
        digest: digest,
        input: input,
        footprint: proposal.footprint,
        status: OperationStatus(
          operationId: id,
          kind: OperationKind.commit,
          state: OperationState.committing,
          proposal: p,
          cancellationRequested: false,
        ),
      );
      _workflow.compareAppend({}, [
        MapEntry(key, operation.toWire()),
        MapEntry('operation:${id.value}', operation.toWire()),
      ]);
    }
    if (operation.status.cancellationRequested) {
      throw const PolicyDeniedError(
        message: 'operation cancelled before commit',
      );
    }
    verifyValidationAuthority(captured, current.sequence);
    final revision = kernel.commit(
      input,
      expectedWorkflow: captured.comparisons(),
    );
    return CommitReceipt(
      operationId: operation.status.operationId,
      proposalId: p.proposalId,
      revision: revision,
    );
  });

  /// Private human approval route. Public model requests cannot supply approval
  /// evidence; this binds the current author's decision to retained Checked data.
  Future<CanonicalObject> approve(
    ProposalRef reference,
    ValidationRunId run,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    if (!current.principal.author) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final entries = <MapEntry<String, CanonicalValue>>[];
    await _workflow.compareAppendWithVerification(
      entries: entries,
      verify: () async {
        final proposal = _proposal(reference, current);
        final value = _workflow.get('validation:${run.value}');
        if (value == null) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        final checked = CheckedValidation.fromWire(value);
        final p = proposal.proposal;
        if (_workflow.latestKey('proposal:${reference.proposalId.value}:') !=
                proposal.key ||
            p.withdrawn ||
            p.submission != Submission.submitted ||
            checked.proposalDigest != reference.digest ||
            checked.validation.evaluatorVersion != candidateEvaluatorVersion ||
            _journal.head(p.baseFrame.continuity) != p.baseFrame.revision) {
          throw const ApprovalStaleError();
        }
        if (!checked.admissible) {
          throw const PolicyDeniedError(
            message: 'validation blocks approval; review the blocking findings',
          );
        }
        final capture = await _capture(proposal, current);
        verifyPublicationReport(
          report: checked.report,
          current: capture,
          proposal: reference,
          baseFrame: p.baseFrame,
          execution: checked.validation,
        );
        verifyValidationAuthority(capture, current.sequence);
        entries.add(
          MapEntry(
            'approval:${current.approvalAuthor.value}:${reference.digest}:${run.value}',
            CanonicalObject([
              MapEntry('author', CanonicalString(principal.id.value)),
              MapEntry('proposal', reference.toWire()),
              MapEntry(
                'validation_digest',
                CanonicalString(canonicalDigest(checked.toWire())),
              ),
              MapEntry('evaluator', CanonicalString(candidateEvaluatorVersion)),
            ]),
          ),
        );
        return capture.comparisons();
      },
    );
    return CanonicalObject([
      MapEntry('approved', reference.toWire()),
      MapEntry('validation_run', CanonicalString(run.value)),
    ]);
  });

  Future<void> finishValidation(
    OperationId id,
    CheckedValidation checked, {
    required bool Function(OperationId) isValidationActive,
  }) => _finishValidation(id, checked, null, isValidationActive);

  Future<void> failValidation(
    OperationId id,
    Object error, {
    required bool Function(OperationId) isValidationActive,
  }) => _finishValidation(id, null, error, isValidationActive);

  Future<void> _finishValidation(
    OperationId id,
    CheckedValidation? checked,
    Object? error,
    bool Function(OperationId) isValidationActive,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    final op = await loadStoredOperation(
      key: 'operation:${id.value}',
      principal: principal.id,
      worldScope: current.worldScope,
      readWorkflow: _workflow.get,
      readReceipt: _journal.receipt,
      isValidationActive: isValidationActive,
    );
    if ({
      OperationState.cancelled,
      OperationState.succeeded,
      OperationState.failed,
    }.contains(op.status.state)) {
      return;
    }
    final terminalKey = 'job:${id.value}:terminal';
    StoredOperation terminal(
      OperationState state,
      Validation? validation,
      String? failure,
    ) => StoredOperation(
      owner: op.owner,
      digest: op.digest,
      input: op.input,
      footprint: op.footprint,
      validationCapture: op.validationCapture,
      status: OperationStatus(
        operationId: id,
        kind: op.status.kind,
        state: state,
        proposal: op.status.proposal,
        validation: validation,
        failure: failure,
        receipt: op.status.receipt,
        cancellationRequested: op.status.cancellationRequested,
      ),
    );
    if (checked != null) {
      final proposal = op.status.proposal;
      if (proposal == null) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      final reference = ProposalRef(
        proposalId: proposal.proposalId,
        version: proposal.version,
        digest: proposal.digest,
      );
      final stored = StoredProposal.fromWire(
        _workflow.get(proposalKey(reference))!,
      );
      final v = checked.validation;
      final validation = Validation(
        operationId: id,
        runId: v.runId,
        coverage: v.coverage,
        findings: v.findings,
        opposingEvidence: v.opposingEvidence,
        unsupportedCapabilities: v.unsupportedCapabilities,
        inputDigest: v.inputDigest,
        evaluatorVersion: v.evaluatorVersion,
      );
      final captured = checked.capture;
      final completed = CheckedValidation(
        proposalDigest: checked.proposalDigest,
        validation: validation,
        admissible: checked.admissible,
        capture: captured,
        report:
            captured?.report(
              proposal: reference,
              baseFrame: stored.proposal.baseFrame,
              execution: validation,
              finished: true,
            ) ??
            ValidationV3.restricted(),
      );
      try {
        await _persistValidation(reference, completed, current, [
          MapEntry('validation:${validation.runId.value}', completed.toWire()),
          MapEntry(
            terminalKey,
            terminal(
              OperationState.succeeded,
              validation,
              op.status.failure,
            ).toWire(),
          ),
        ]);
        return;
      } on Object catch (failure) {
        error = failure;
      }
    }
    final initial = StoredOperation.fromWire(
      _workflow.get('operation:${id.value}')!,
    );
    _workflow.compareAppend({}, [
      MapEntry(
        terminalKey,
        terminal(
          OperationState.failed,
          initial.status.validation,
          error.toString(),
        ).toWire(),
      ),
    ]);
  });

  Future<void> persist(ProposalRef reference, CheckedValidation checked) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) => _persistValidation(reference, checked, current, [
          MapEntry(
            'validation:${checked.validation.runId.value}',
            checked.toWire(),
          ),
        ]),
      );

  Future<void> _persistValidation(
    ProposalRef reference,
    CheckedValidation checked,
    CurrentUniverseAuthority current,
    List<MapEntry<String, CanonicalValue>> entries,
  ) => _workflow.compareAppendWithVerification(
    verify: () async {
      final proposal = _proposal(reference, current);
      if (checked.proposalDigest != proposal.proposal.digest) {
        throw const ApprovalStaleError();
      }
      final captured = checked.capture;
      if (captured == null) return const {};
      verifyValidationAuthority(captured, current.sequence);
      final fresh = await _capture(proposal, current);
      verifyValidationCapture(
        proposal: reference,
        captured: captured,
        current: fresh,
      );
      return captured.comparisons();
    },
    entries: entries,
  );
}
