import 'dart:convert';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/installation.dart'
    show InstallationException, InstallationFailure;
import 'package:ub_store/ub_store.dart';

import 'assessment_resolution.dart';
import 'assessment_validation.dart';
import 'candidate_validation.dart';
import 'context_binding.dart';
import 'context_opening.dart';
import 'record_search.dart';
import 'writing_contract_projection.dart';
import 'writing_projection.dart';
import 'state_reading.dart';
import 'record_reading.dart';
import 'discovery.dart';
import 'context_brief.dart';
import 'installation_authority.dart';
import 'operation_state.dart';
import 'read_cursor.dart';
import 'writing_source.dart';
import 'proposal_authorization.dart';
import 'proposal_state.dart';
import 'proposal_validation.dart';
import 'validation_binding.dart';
import 'validation_task.dart';
import 'source_verification.dart';

/// Native PostgreSQL proposal workflow in the caller's installation transaction.
/// Request routes admit retained contexts under current authority; lower-level
/// frame routes are for trusted service composition.
/// Approval remains a private human route; publication re-evaluates the exact
/// retained candidate. Worker completion accepts only internally evaluated
/// checked results; public requests cannot provide validation evidence.
final class PostgresValidationWorkflow {
  PostgresValidationWorkflow({
    required this.session,
    required this.universe,
    required this.authority,
    required this.principal,
    BigInt Function()? epochSeconds,
  }) : _epochSeconds = epochSeconds ?? _now;
  static BigInt _now() =>
      BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000);
  final BigInt Function() _epochSeconds;
  final PostgresInstallationSession session;
  final UniverseId universe;
  final PostgresServiceAuthority authority;
  final InstallationPrincipal principal;
  PostgresKernel get _kernel => session.kernel(universe);
  PostgresJournal get _journal => _kernel.journal;
  PostgresWorkflowStorage get _workflow => session.workflows(universe);
  Future<RecordVersion> _version(RecordVersionId id) async =>
      RecordVersion.fromWire((await _journal.load(id)).toCanonical());
  Future<List<RecordVersion>> _canon(
    ContinuityId continuity,
    RevisionId revision,
  ) async {
    final rows = <RecordVersion>[];
    for (final id in (await _journal.snapshot(continuity, revision)).values) {
      rows.add(await _version(id));
    }
    rows.sort(
      (a, b) => a.identity.recordId.value.compareTo(b.identity.recordId.value),
    );
    return rows;
  }

  Future<List<RecordVersion>> _preview(CommitInput input) async =>
      (await _kernel.preview(input))
          .map((r) => RecordVersion.fromWire(r.toCanonical()))
          .toList();
  Future<StoredProposal> _proposal(
    ProposalRef reference,
    CurrentUniverseAuthority current,
  ) async {
    final value = await _workflow.get(proposalKey(reference));
    if (value == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final proposal = StoredProposal.fromWire(value);
    await _admitProposal(proposal, reference, current);
    return proposal;
  }

  Future<void> _admitProposal(
    StoredProposal proposal,
    ProposalRef reference,
    CurrentUniverseAuthority current,
  ) async {
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
    await authority.authorizeWrite(
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
            ? await _canon(
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
    readProposal: (reference) async => await _proposal(reference, current),
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
    final all = await _canon(frame.continuity, frame.revision);
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
    (current) => _describeRequest(request, current),
  );

  Future<({Description description, Frame? frame, WorldId? focus})>
  _describeRequest(
    ReadRequest request,
    CurrentUniverseAuthority current,
  ) async {
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
      for (final head in (await _journal.heads()).entries) {
        final name = await _workflow.get('continuity-name:${head.key.value}');
        final summary = discoveryContinuity(
          id: head.key,
          revision: head.value,
          name: name is CanonicalString ? name.value : 'Original continuity',
          records: await _canon(head.key, head.value),
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
      frame = await _contextFrame(context, current);
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
  }

  Future<Records> getRequest(GetRequest request) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) async => (await _getRequest(request, current)).records,
      );

  Future<({Records records, Frame frame, WorldId? focus})> _getRequest(
    GetRequest request,
    CurrentUniverseAuthority current,
  ) async {
    const denied = NotFoundOrNotAccessibleError(message: 'resource');
    if (request.universeId != null && request.universeId != universe) {
      throw denied;
    }
    final frame = await _contextFrame(request.contextId, current);
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
        changes = (await _journal.recordHistory(
          frame.continuity,
          frame.revision,
          id,
        )).map(HistoryEntry.fromWire).toList();
        if (changes.isEmpty) throw denied;
      }
      if (historyRequested && fullHistory) {
        history.addAll(
          changes ??
              (await _journal.recordHistory(
                frame.continuity,
                frame.revision,
                id,
              )).map(HistoryEntry.fromWire),
        );
      }
    }
    final needed = groups.contains(FieldGroup.evidence)
        ? readResearchClosure(accessible, request.recordIds)
        : <RecordId>{};
    final result = Records(
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
    return (records: result, frame: frame, focus: snapshot.focus);
  }

  Future<({ContextBrief brief, Delivery delivery})> getContextRequest(
    GetContextRequest request,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    final result = await _getContextRequest(request, current);
    return (brief: result.brief, delivery: result.delivery);
  });

  Future<({ContextBrief brief, Delivery delivery, Frame frame, WorldId? focus})>
  _getContextRequest(
    GetContextRequest request,
    CurrentUniverseAuthority current,
  ) async {
    const denied = NotFoundOrNotAccessibleError(message: 'resource');
    if (request.universeId != null && request.universeId != universe) {
      throw denied;
    }
    final frame = await _contextFrame(request.contextId, current);
    final offset = await _readOffset(
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
    final cursor = await _retainReadCursor(
      request.toArgs(),
      frame,
      current,
      page.complete,
      page.next,
    );
    return (
      frame: frame,
      focus: snapshot.focus,
      brief: page.brief,
      delivery: Delivery(complete: page.complete, cursor: cursor),
    );
  }

  Future<({SearchResults results, Delivery delivery})> searchRequest(
    SearchRequest request,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    final result = await _searchRequest(request, current);
    return (results: result.results, delivery: result.delivery);
  });

  Future<
    ({SearchResults results, Delivery delivery, Frame frame, WorldId? focus})
  >
  _searchRequest(
    SearchRequest request,
    CurrentUniverseAuthority current,
  ) async {
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
    final frame = await _contextFrame(request.contextId, current);
    final snapshot = await _readSnapshot(
      frame: frame,
      world: request.world,
      guard: request.worldId,
      current: current,
    );
    final indexed = (await _kernel.search(
      frame.continuity,
      frame.revision,
      request.query,
    )).map((row) => row.identity.recordId).toSet();
    final hits = buildSearchHits(
      accessible: snapshot.accessible,
      indexed: indexed,
      query: request.query,
      filters: request.typedFilters,
      world: snapshot.focus,
      author: frame.perspective is AuthorPerspective,
    );
    final offset = await _readOffset(
      request.toArgs(),
      frame,
      current,
      request.cursor,
    );
    if (offset > hits.length) throw denied;
    final end = (offset + request.limit).clamp(0, hits.length);
    final complete = end == hits.length;
    final cursor = await _retainReadCursor(
      request.toArgs(),
      frame,
      current,
      complete,
      end,
    );
    return (
      frame: frame,
      focus: snapshot.focus,
      results: SearchResults(hits: hits.sublist(offset, end)),
      delivery: Delivery(complete: complete, cursor: cursor),
    );
  }

  Future<({State state, Frame frame})> getStateRequest(
    GetStateRequest request,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    final result = await _getStateRequest(request, current);
    return (state: result.state, frame: result.frame);
  });

  Future<({State state, Frame frame, WorldId? focus})> _getStateRequest(
    GetStateRequest request,
    CurrentUniverseAuthority current,
  ) async {
    if (request.universeId != null && request.universeId != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final retained = await _contextFrame(request.contextId, current);
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
    final state = await _readState(
      records: snapshot.accessible,
      frame: frame,
      ids: request.entityIds,
      predicates: request.predicateFilters,
      world: snapshot.focus,
      current: current,
    );
    return (state: state, frame: frame, focus: snapshot.focus);
  }

  Future<State> _readState({
    required List<RecordVersion> records,
    required Frame frame,
    required List<RecordId> ids,
    required List<RecordId> predicates,
    required WorldId? world,
    required CurrentUniverseAuthority current,
  }) async {
    final restricted =
        current.worldScope != null || frame.perspective is! AuthorPerspective;
    final receipts = restricted
        ? <InitializationReceipt>[]
        : await _kernel.initializationReceiptsAt(
            frame.continuity,
            frame.revision,
          );
    final originals = <RecordVersionId, RecordVersion>{
      for (final id
          in receipts
              .where(
                (r) =>
                    ids.contains(r.instance) &&
                    (predicates.isEmpty || predicates.contains(r.property)),
              )
              .map((r) => r.assertion)
              .toSet())
        id: await _version(id),
    };
    return assembleReadState(
      records: records,
      frame: frame,
      ids: ids,
      predicates: predicates,
      world: world,
      restricted: restricted,
      receipts: receipts,
      readVersion: (id) =>
          originals[id] ??
          (throw StateError('Initialization assertion was not loaded')),
    );
  }

  Future<({CanonicalObject facts, Frame frame, WorldId? focus})>
  readFactsRequest(ReadFactsRequest request) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _readFactsRequest(request, current),
  );

  Future<({CanonicalObject facts, Frame frame, WorldId? focus})>
  _readFactsRequest(
    ReadFactsRequest request,
    CurrentUniverseAuthority current,
  ) async {
    final frame = await _contextFrame(request.contextId, current);
    // Plain name resolution uses all visible records; the state projection then
    // enforces world focus. A same-named hidden identity never enters a count.
    final snapshot = await _readSnapshot(
      frame: frame,
      world: null,
      guard: null,
      current: current,
    );
    final visible = snapshot.all
        .where((r) => snapshot.visibility.contains(r.identity.recordId))
        .toList();
    final focus = resolveWorldFocus(
      world: request.world == null ? null : Selector(request.world!),
      guard: null,
      records: visible,
      scope: current.worldScope,
    );
    final selected = request.world == null
        ? snapshot
        : await _readSnapshot(
            frame: frame,
            world: Selector(request.world!),
            guard: null,
            current: current,
          );
    return (
      facts: await projectWritingFacts(
        request: request,
        records: visible,
        frame: frame,
        restricted:
            current.worldScope != null ||
            frame.perspective is! AuthorPerspective,
        readState: (id) => _readState(
          records: selected.accessible,
          frame: frame,
          ids: [id],
          predicates: [],
          world: focus,
          current: current,
        ),
      ),
      frame: frame,
      focus: focus,
    );
  }

  Future<({CanonicalObject contracts, Frame frame})> readContractsRequest(
    ReadContractsRequest request,
  ) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _readContractsRequest(request, current),
  );

  Future<({CanonicalObject contracts, Frame frame})> _readContractsRequest(
    ReadContractsRequest request,
    CurrentUniverseAuthority current,
  ) async {
    final frame = await _contextFrame(request.contextId, current);
    final snapshot = await _readSnapshot(
      frame: frame,
      world: null,
      guard: null,
      current: current,
    );
    return (
      contracts: projectWritingContracts(
        request: request,
        rows: snapshot.accessible,
        frame: frame,
        restricted:
            current.worldScope != null ||
            frame.perspective is! AuthorPerspective,
      ),
      frame: frame,
    );
  }

  Future<int> _readOffset(
    CanonicalObject args,
    Frame frame,
    CurrentUniverseAuthority current,
    String? cursor,
  ) async {
    const denied = NotFoundOrNotAccessibleError(message: 'resource');
    final binding = readCursorBinding(
      args: args,
      frame: frame,
      principal: principal.id,
      scopeHash: current.scopeHash,
    );
    var offset = 0;
    if (cursor != null) {
      final value = await _workflow.get('cursor:$cursor');
      if (value == null) throw denied;
      final saved = StoredReadCursor.fromWire(value);
      if (saved.binding != binding) throw denied;
      offset = saved.offset.toInt();
      if (BigInt.from(offset) != saved.offset) throw denied;
    }
    return offset;
  }

  Future<String?> _retainReadCursor(
    CanonicalObject args,
    Frame frame,
    CurrentUniverseAuthority current,
    bool complete,
    int next,
  ) async {
    final binding = readCursorBinding(
      args: args,
      frame: frame,
      principal: principal.id,
      scopeHash: current.scopeHash,
    );
    String? cursor;
    if (!complete) {
      cursor = OperationId.generate().value;
      await _workflow.compareAppend({}, [
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

  Future<({OperationStatusV3 status, Frame? frame, Delivery delivery})>
  getOperationRequest(
    WorkflowRequest request, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _getOperationRequest(
      request,
      current,
      isValidationActive: isValidationActive,
    ),
  );

  Future<({OperationStatusV3 status, Frame? frame, Delivery delivery})>
  _getOperationRequest(
    WorkflowRequest request,
    CurrentUniverseAuthority current, {
    required bool Function(OperationId) isValidationActive,
  }) async {
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
      final offset = await _readOffset(binding, frame, current, cursor);
      final page = pageOperationFindings(status, offset);
      status = page.status;
      delivery = Delivery(
        complete: page.complete,
        cursor: await _retainReadCursor(
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
  }

  Future<CanonicalObject> review(ProposalRef reference) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) => _review(reference, current),
      );

  Future<CanonicalObject> _review(
    ProposalRef reference,
    CurrentUniverseAuthority current,
  ) async {
    if (!current.principal.author) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final stored = await _proposal(reference, current);
    final assessment = await _assessmentReview(reference, current);
    final originals = {
      for (final row in await _canon(
        stored.proposal.baseFrame.continuity,
        stored.proposal.baseFrame.revision,
      ))
        row.identity.recordId: row,
    };
    return CanonicalObject([
      MapEntry('proposal', stored.proposal.toWire()),
      MapEntry(
        'changes',
        CanonicalArray(stored.changes.map((c) => c.toCanonical())),
      ),
      MapEntry(
        'diff',
        CanonicalArray(
          stored.changes.map(
            (change) => CanonicalObject([
              MapEntry('record', CanonicalString(change.recordId.value)),
              MapEntry(
                'before',
                originals[change.recordId]?.toWire() ?? const CanonicalNull(),
              ),
              MapEntry(
                'after',
                change.next?.toCanonical() ?? const CanonicalNull(),
              ),
            ]),
          ),
        ),
      ),
      MapEntry('footprint', stored.footprint.toWire()),
      MapEntry(
        'latest',
        CanonicalBool(
          await _workflow.latestKey(
                'proposal:${stored.proposal.proposalId.value}:',
              ) ==
              stored.key,
        ),
      ),
      MapEntry('assessment_review', assessment.toWire()),
    ]);
  }

  Future<CanonicalObject> stageSource({
    required String label,
    required String text,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _stageSource(current, label: label, text: text),
  );

  Future<CanonicalObject> _stageSource(
    CurrentUniverseAuthority current, {
    required String label,
    required String text,
  }) async {
    if (!current.principal.author) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final staged = stageWritingSource(
      universe: universe,
      author: principal.id,
      label: label,
      text: text,
      importTime: DateTime.now().toUtc().toIso8601String(),
    );
    await _workflow.compareAppend({}, staged.entries);
    return CanonicalObject([
      const MapEntry('canonical', CanonicalBool(false)),
      MapEntry(
        'operations',
        CanonicalArray(staged.operations.map((op) => op.toWire())),
      ),
    ]);
  }

  /// Native protocol dispatch for the migrated authoring routes. Unmigrated
  /// requests fail explicitly; they never fall back to another backend.
  Future<CanonicalValue> executeToolRequest(
    Request request, {
    required bool Function(OperationId) isValidationActive,
    required void Function(OperationId) signalCancellation,
  }) async {
    try {
      return await authority.withUniverseAuthority(principal, universe, (
        current,
      ) async {
        request.validate();
        final resolved = await session.authority.resolveUniverseAlias(
          actor: principal.id,
          name: request.universe.value,
          epochSeconds: _epochSeconds(),
        );
        if (resolved.universeId != universe) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        CanonicalValue result;
        Frame? frame;
        WorldId? focus;
        var delivery = Delivery(complete: true, cursor: null);
        switch (request) {
          case OpenContextRequest():
            final opened = await _openContext(request, current);
            result = opened.toWire();
            frame = opened.frame;
          case DescribeSummaryRequest() ||
              DescribeCapabilitiesRequest() ||
              DescribeWorldsRequest() ||
              DescribeDefinitionsRequest():
            final described = await _describeRequest(
              request as ReadRequest,
              current,
            );
            result = described.description.toWire();
            frame = described.frame;
            focus = described.focus;
          case GetRequest():
            final read = await _getRequest(request, current);
            result = read.records.toWire();
            frame = read.frame;
            focus = read.focus;
          case GetContextRequest():
            final read = await _getContextRequest(request, current);
            result = read.brief.toWire();
            frame = read.frame;
            focus = read.focus;
            delivery = read.delivery;
          case SearchRequest():
            final read = await _searchRequest(request, current);
            result = read.results.toWire();
            frame = read.frame;
            focus = read.focus;
            delivery = read.delivery;
          case GetStateRequest():
            final read = await _getStateRequest(request, current);
            result = read.state.toWire();
            frame = read.frame;
            focus = read.focus;
          case ReadFactsRequest():
            final read = await _readFactsRequest(request, current);
            result = read.facts;
            frame = read.frame;
            focus = read.focus;
          case ReadContractsRequest():
            final read = await _readContractsRequest(request, current);
            result = read.contracts;
            frame = read.frame;
          case CreateProposalRequest() ||
              ReviseProposalRequest() ||
              SubmitProposalRequest() ||
              WithdrawProposalRequest():
            final retained = await _proposeRequest(
              request as WorkflowRequest,
              current,
              isValidationActive: isValidationActive,
            );
            result = retained.proposal.toWire();
            frame = retained.frame;
            focus = retained.focus;
          case ProposalValidationRequest():
            frame = await _validationFrame(request.contextId, current);
            if (request.universeId != null && request.universeId != universe) {
              throw const NotFoundOrNotAccessibleError(message: 'resource');
            }
            result = (await _validate(
              request.proposalReference,
              frame,
              current,
            )).toWire();
          case QueuedProposalValidationRequest():
            frame = await _validationFrame(request.contextId, current);
            result = (await _queueValidation(
              request,
              current,
              resolvedFrame: frame,
              isValidationActive: isValidationActive,
            )).toWire();
          case GetOperationIdRequest() || GetOperationKeyRequest():
            final read = await _getOperationRequest(
              request as WorkflowRequest,
              current,
              isValidationActive: isValidationActive,
            );
            result = read.status.toWire();
            frame = read.frame;
            delivery = read.delivery;
          case CancelOperationRequest():
            result = (await _cancelOperation(
              request,
              current,
              isValidationActive: isValidationActive,
              signalCancellation: signalCancellation,
            )).toWire();
          case AttachAssessmentRequest() || SelectAssessmentRequest():
            final contextId = switch (request) {
              AttachAssessmentRequest(:final contextId) ||
              SelectAssessmentRequest(:final contextId) => contextId,
              _ => throw StateError('Unreachable assessment'),
            };
            final reference = switch (request) {
              AttachAssessmentRequest(:final proposalReference) ||
              SelectAssessmentRequest(
                :final proposalReference,
              ) => proposalReference,
              _ => throw StateError('Unreachable assessment'),
            };
            result = (await _assessmentRequest(
              request as WorkflowRequest,
              current,
            )).toWire();
            frame = await _contextFrame(contextId, current);
            focus = (await _proposal(reference, current)).proposal.worldScope;
          case CommitRequest():
            frame = (await _proposal(
              request.proposalReference,
              current,
            )).proposal.baseFrame;
            result = (await _commit(
              request,
              current,
              isValidationActive: isValidationActive,
            )).toWire();
          default:
            throw const UnsupportedSemanticsError(
              message: 'PostgreSQL request migration incomplete',
            );
        }
        final envelope = Envelope<CanonicalValue>(
          contractVersion: protocolVersion,
          requestId: BigInt.zero,
          universeId: universe,
          universe: Selector(resolved.name),
          aliasMatched: request.universe.value != resolved.name,
          frame: frame,
          worldFocus: focus,
          authorizationScope: current.worldScope == null
              ? 'universe grant'
              : 'world-scoped grant',
          delivery: delivery,
          result: result,
        ).toWire((value) => value);
        if (envelope.toBytes().length > 900000) {
          throw const EvaluationLimitReachedError(
            message: 'response exceeds bounded transport; narrow the batch',
          );
        }
        return envelope;
      });
    } on InstallationException catch (error) {
      if (error.failure == InstallationFailure.denied) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      rethrow;
    }
  }

  Future<OpenedContext> openContext(OpenContextRequest request) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) => _openContext(request, current),
      );

  Future<OpenedContext> _openContext(
    OpenContextRequest request,
    CurrentUniverseAuthority current,
  ) async {
    if (request.universeId != null && request.universeId != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final revision = switch (request.revision) {
      HeadRevisionSelector() => await _journal.head(request.continuityId),
      ExactRevisionSelector(:final revisionId) => revisionId,
    };
    final frame = await prepareContextFrame(
      request: request,
      universe: universe,
      revision: revision,
      records: await _canon(request.continuityId, revision),
      worldScope: current.worldScope,
      readCanon: _canon,
    );
    final id = ContextId.generate();
    final stored = StoredContext(
      owner: principal.id,
      scope: current.scopeHash,
      expires: _epochSeconds() + BigInt.from(3600),
      frame: frame,
    );
    await _workflow.compareAppend({}, [
      MapEntry('context:${id.value}', stored.toWire()),
    ]);
    return OpenedContext(contextId: id, frame: frame);
  }

  Future<Frame> _contextFrame(
    ContextId id,
    CurrentUniverseAuthority current,
  ) async {
    final value = await _workflow.get('context:${id.value}');
    if (value == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    return StoredContext.fromWire(value).admit(
      principal: principal.id,
      scopeHash: current.scopeHash,
      universe: universe,
      epochSeconds: _epochSeconds(),
    );
  }

  Future<Frame> _validationFrame(
    ContextId id,
    CurrentUniverseAuthority current,
  ) async {
    final frame = await _contextFrame(id, current);
    if (frame.perspective is! AuthorPerspective) {
      throw const UnsupportedSemanticsError(
        message: 'validation requires an author perspective frame',
      );
    }
    return frame;
  }

  Future<Proposal> proposeRequest(
    WorkflowRequest request, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) async => (await _proposeRequest(
      request,
      current,
      isValidationActive: isValidationActive,
    )).proposal,
  );

  Future<({Proposal proposal, Frame frame, WorldId? focus})> _proposeRequest(
    WorkflowRequest request,
    CurrentUniverseAuthority current, {
    required bool Function(OperationId) isValidationActive,
  }) async {
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
    final frame = await _contextFrame(contextId, current);
    final focus = world == null
        ? null
        : resolveWorldFocus(
            world: world,
            guard: guard,
            records: await _canon(frame.continuity, frame.revision),
            scope: current.worldScope,
          );
    final proposal = await _propose(
      request,
      current,
      resolvedFrame: frame,
      worldFocus: focus,
      isValidationActive: isValidationActive,
    );
    return (proposal: proposal, frame: frame, focus: focus);
  }

  Future<ValidationV3> validateProposalRequest(
    ProposalValidationRequest request,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    if (request.universeId != null && request.universeId != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final frame = await _validationFrame(request.contextId, current);
    return _validate(request.proposalReference, frame, current);
  });

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

  Future<Proposal> _propose(
    WorkflowRequest request,
    CurrentUniverseAuthority current, {
    required Frame resolvedFrame,
    required WorldId? worldFocus,
    required bool Function(OperationId) isValidationActive,
    Map<RecordId, RecordVersionId> versions = const {},
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
    if (await _workflow.get(key) != null) {
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
    final previous = reference == null
        ? null
        : await _proposal(reference, current);
    if (previous != null &&
        await _workflow.latestKey('proposal:${reference!.proposalId.value}:') !=
            previous.key) {
      throw const ApprovalStaleError();
    }
    final base = await _canon(resolvedFrame.continuity, resolvedFrame.revision);
    final prepared = prepareProposal(
      request: request,
      frame: resolvedFrame,
      base: base,
      principal: principal.id,
      author: principal.author,
      worldFocus: worldFocus,
      previous: previous,
      versions: versions,
    );
    await _admitProposal(prepared, prepared.reference, current);
    final kernel = _kernel;
    if (compile) {
      await checkProposalReservations(
        stored: prepared,
        readWorkflow: _workflow.get,
        identityExists: kernel.journal.identityExists,
        readVersion: _version,
      );
      final input = await proposalCommitInput(
        stored: prepared,
        universe: universe,
        principal: principal.id,
        idempotencyKey: 'proposal-preview',
        readCanon: _canon,
      );
      await kernel.preview(input);
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
    await _workflow.compareAppend(comparisons, entries);
    return p;
  }

  Future<ValidationCapture> capture(ProposalRef reference) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) async =>
            _capture(await _proposal(reference, current), current),
      );

  Future<ValidationV3> validate(
    ProposalRef reference, {
    required Frame resolvedFrame,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _validate(reference, resolvedFrame, current),
  );

  Future<ValidationV3> _validate(
    ProposalRef reference,
    Frame frame,
    CurrentUniverseAuthority current,
  ) async {
    if (frame.universe != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final stored = await _proposal(reference, current);
    if (stored.proposal.baseFrame != frame) {
      throw const ApprovalStaleError();
    }
    final captured = current.worldScope == null
        ? await _capture(stored, current)
        : null;
    final result = await checkProposalCandidate(
      stored: stored,
      universe: universe,
      principal: principal.id,
      approvalAuthor: current.approvalAuthor,
      scope: current.worldScope,
      preview: _preview,
      readCanon: _canon,
      readWorkflow: _workflow.get,
      readVersion: _version,
    );
    final report =
        captured?.report(
          proposal: reference,
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
    await _persistValidation(reference, completed, current, [
      MapEntry(
        'validation:${result.validation.runId.value}',
        completed.toWire(),
      ),
    ]);
    return report;
  }

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

  Future<OperationStatusV3> queueValidation(
    QueuedProposalValidationRequest request, {
    required Frame resolvedFrame,
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) async => _queueValidation(
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
    (current) async => _queueValidation(
      request,
      current,
      resolvedFrame: await _validationFrame(request.contextId, current),
      isValidationActive: isValidationActive,
    ),
  );

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
        final proposal = await _proposal(request.proposalReference, current);
        if (proposal.proposal.baseFrame != resolvedFrame) {
          throw const ApprovalStaleError();
        }
        final key = operationRequestKey(
          principal.id,
          'validate',
          request.idempotencyKey,
        );
        final digest = canonicalDigest(request.toArgs());
        if (await _workflow.get(key) != null) {
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
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _cancelOperation(
      request,
      current,
      isValidationActive: isValidationActive,
      signalCancellation: signalCancellation,
    ),
  );

  Future<OperationStatusV3> _cancelOperation(
    CancelOperationRequest request,
    CurrentUniverseAuthority current, {
    required bool Function(OperationId) isValidationActive,
    required void Function(OperationId) signalCancellation,
  }) async {
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
        final existing = await _workflow.get(key);
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
    if (fresh) {
      session.afterCommit(() => signalCancellation(request.operationId));
    }
    return publicOperationStatus(
      status: operation.status,
      worldScope: current.worldScope,
      readWorkflow: _workflow.get,
    );
  }

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
    final proposal = await _proposal(reference, current);
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
      candidate = await _preview(input);
      await verifyCandidateSources(
        records: candidate,
        readWorkflow: _workflow.get,
        readVersion: _version,
      );
      base = await _canon(
        proposal.proposal.baseFrame.continuity,
        proposal.proposal.baseFrame.revision,
      );
    }
    final key = 'job:${id.value}:running';
    if (await _workflow.get(key) == null) {
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
      await _workflow.compareAppend({}, [MapEntry(key, running.toWire())]);
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
        (await _workflow.get(proposalKey(reference)))!,
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
        await session.rollbackOnFailure(
          () => _persistValidation(reference, completed, current, [
            MapEntry(
              'validation:${validation.runId.value}',
              completed.toWire(),
            ),
            MapEntry(
              terminalKey,
              terminal(
                OperationState.succeeded,
                validation,
                op.status.failure,
              ).toWire(),
            ),
          ]),
        );
        return;
      } on Object catch (failure) {
        error = failure;
      }
    }
    final initial = StoredOperation.fromWire(
      (await _workflow.get('operation:${id.value}'))!,
    );
    await _workflow.compareAppend({}, [
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
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) => _assessmentRequest(request, current),
      );

  Future<AssessmentSelection> _assessmentRequest(
    WorkflowRequest request,
    CurrentUniverseAuthority current,
  ) async {
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
    final frame = await _contextFrame(contextId, current);
    final StoredProposal proposal;
    try {
      proposal = await _proposal(reference, current);
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
  }

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
          proposal = await _proposal(reference, current);
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
        final receipt = await _workflow.get(receiptKey);
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
        if (await _workflow.latestKey(
                  'proposal:${reference.proposalId.value}:',
                ) !=
                proposal.key ||
            proposal.proposal.withdrawn ||
            proposal.proposal.submission != Submission.submitted ||
            await _journal.head(frame.continuity) != frame.revision) {
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
          final value = await _workflow.get(assessmentEnvelopeKey(selected));
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

  Future<CommitReceipt> commit(
    CommitRequest request, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) =>
        _commit(request, current, isValidationActive: isValidationActive),
  );

  Future<CommitReceipt> _commit(
    CommitRequest request,
    CurrentUniverseAuthority current, {
    required bool Function(OperationId) isValidationActive,
  }) async {
    if (request.universeId != null && request.universeId != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final proposal = await _proposal(request.proposalReference, current);
    final p = proposal.proposal;
    await authority.authorizeWrite(
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
    if (await _workflow.get(key) != null) {
      operation = await load();
      if (operation.digest != digest) {
        throw const IdempotencyKeyReusedError(message: 'request differs');
      }
      if (operation.status.receipt != null) return operation.status.receipt!;
    }
    if (await _workflow.latestKey('proposal:${p.proposalId.value}:') !=
            proposal.key ||
        p.withdrawn ||
        p.submission != Submission.submitted ||
        request.expectedBaseRevision != p.baseFrame.revision) {
      throw const ApprovalStaleError();
    }
    final value = await _workflow.get(
      'validation:${request.validationRun.value}',
    );
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
      final approval = await _workflow.get(
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
    final head = await _journal.head(p.baseFrame.continuity);
    if (head != request.expectedBaseRevision) {
      throw BaseRevisionConflictError(
        expected: request.expectedBaseRevision.value,
        actual: head.value,
      );
    }
    final kernel = _kernel;
    final fresh = await checkProposalCandidate(
      stored: proposal,
      universe: universe,
      principal: principal.id,
      approvalAuthor: current.approvalAuthor,
      scope: null,
      preview: _preview,
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
      await _workflow.compareAppend({}, [
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
    final revision = await kernel.commit(
      input,
      expectedWorkflow: captured.comparisons(),
    );
    return CommitReceipt(
      operationId: operation.status.operationId,
      proposalId: p.proposalId,
      revision: revision,
    );
  }

  /// Private human approval route. Public model requests cannot supply approval
  /// evidence; this binds the current author's decision to retained Checked data.
  Future<CanonicalObject> approve(ProposalRef reference, ValidationRunId run) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) => _approve(reference, run, current),
      );

  Future<CanonicalObject> _approve(
    ProposalRef reference,
    ValidationRunId run,
    CurrentUniverseAuthority current,
  ) async {
    if (!current.principal.author) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final entries = <MapEntry<String, CanonicalValue>>[];
    await _workflow.compareAppendWithVerification(
      entries: entries,
      verify: () async {
        final proposal = await _proposal(reference, current);
        final value = await _workflow.get('validation:${run.value}');
        if (value == null) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        final checked = CheckedValidation.fromWire(value);
        final p = proposal.proposal;
        if (await _workflow.latestKey(
                  'proposal:${reference.proposalId.value}:',
                ) !=
                proposal.key ||
            p.withdrawn ||
            p.submission != Submission.submitted ||
            checked.proposalDigest != reference.digest ||
            checked.validation.evaluatorVersion != candidateEvaluatorVersion ||
            await _journal.head(p.baseFrame.continuity) !=
                p.baseFrame.revision) {
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
  }

  Future<void> _persistValidation(
    ProposalRef reference,
    CheckedValidation checked,
    CurrentUniverseAuthority current,
    List<MapEntry<String, CanonicalValue>> entries,
  ) => _workflow.compareAppendWithVerification(
    verify: () async {
      final proposal = await _proposal(reference, current);
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
