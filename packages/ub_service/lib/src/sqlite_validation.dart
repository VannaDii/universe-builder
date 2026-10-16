import 'dart:convert';
import 'dart:io';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/installation.dart'
    show InstallationException, InstallationFailure;
import 'package:ub_store/ub_store.dart' show CommitInput, recordWorld;

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
import 'required_evidence_checks.dart';
import 'state_reading.dart';
import 'validation_binding.dart';
import 'validation_task.dart';
import 'validation_job_service.dart';
import 'writing_projection.dart';
import 'writing_contract_projection.dart';
import 'writing_changes.dart';
import 'writing_check.dart';
import 'writing_dates.dart';
import 'writing_source.dart';
import 'writing_binding.dart';
import 'writing_knowledge_corrections.dart';
import 'writing_author_review.dart';
import 'resource_checks.dart';

/// Internal native workflow for an already recovered, writer-owned package.
/// It retains assessments, checked results and exact human approvals, and
/// publishes reviewed canon. The caller must produce checked results through the factual
/// evaluator, not client IO.
final class SqliteValidationWorkflow implements ValidationJobService {
  SqliteValidationWorkflow({
    required this.package,
    required this.authority,
    required this.principal,
  });
  final OwnedSqliteDatabase package;
  final InstallationAuthority authority;
  final InstallationPrincipal principal;
  @override
  UniverseId get universe => package.universeId;
  SqliteJournal get _journal => SqliteJournal(package.database, universe);
  WorkflowStorage get _workflow => WorkflowStorage(package.database);

  RecordVersion _version(RecordVersionId id) =>
      RecordVersion.fromWire(_journal.load(id).toCanonical());
  List<RecordVersion> _canon(ContinuityId continuity, RevisionId revision) {
    final rows =
        [
          for (final record in _journal.loadMany(_journal.snapshot(continuity, revision).values))
            RecordVersion.fromWire(record.toCanonical()),
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
  }

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
  }

  Future<CanonicalObject> maintainRequest(MaintainEngineRequest request) async {
    try {
      return await authority.withUniverseAuthority(principal, universe, (
        current,
      ) {
        if (!current.principal.author ||
            authority
                    .resolveUniverseAlias(principal, request.universe.value)
                    .universeId !=
                universe) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        return package.maintain(collect: request.collect);
      });
    } on InstallationException catch (error) {
      if (error.failure == InstallationFailure.denied) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      rethrow;
    }
  }

  Future<CanonicalObject> exportRequest(
    ExportLogicalEngineRequest request,
  ) async {
    try {
      return await authority.withUniverseAuthority(principal, universe, (
        current,
      ) {
        if (!current.principal.author ||
            authority
                    .resolveUniverseAlias(principal, request.universe.value)
                    .universeId !=
                universe) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        return package.exportLogical(
          request.destination,
          recordIds: request.recordIds,
          completeHistory: request.completeHistory,
        );
      });
    } on InstallationException catch (error) {
      if (error.failure == InstallationFailure.denied) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      rethrow;
    }
  }

  Future<CanonicalObject> backupRequest(BackupEngineRequest request) async {
    try {
      return await authority.withUniverseAuthority(principal, universe, (
        current,
      ) {
        if (!current.principal.author ||
            authority
                    .resolveUniverseAlias(principal, request.universe.value)
                    .universeId !=
                universe) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        package.backup(request.destination);
        return CanonicalObject([
          MapEntry('backup', CanonicalString(request.destination)),
          MapEntry('universe_id', CanonicalString(universe.value)),
          const MapEntry('verified', CanonicalBool(true)),
        ]);
      });
    } on InstallationException catch (error) {
      if (error.failure == InstallationFailure.denied) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      rethrow;
    }
  }

  /// Author-owned pinned branches and explicit adoption intent. Comparison and
  /// adoption preparation never advance either continuity or approve changes.
  Future<CanonicalValue> continuityRequest(EngineRequest request) async {
    try {
      return await authority.withUniverseAuthority(principal, universe, (
        current,
      ) {
        if (!current.principal.author) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        final selector = switch (request) {
          ForkContinuityEngineRequest(:final universe) ||
          CompareContinuitiesEngineRequest(:final universe) ||
          PrepareAdoptionEngineRequest(:final universe) => universe,
          _ => throw const InvalidArgumentError(
            field: 'method',
            message: 'requires continuity fork comparison or adoption',
          ),
        };
        if (authority
                .resolveUniverseAlias(principal, selector.value)
                .universeId !=
            universe) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        if (request is ForkContinuityEngineRequest) {
          if (request.name.trim().isEmpty ||
              utf8.encode(request.name).length > 128) {
            throw const InvalidArgumentError(
              field: 'name',
              message: 'enter a continuity name of 1..128 bytes',
            );
          }
          final RevisionId revision;
          package.database.execute('BEGIN IMMEDIATE');
          try {
            revision = _journal.branch(
              request.continuityId,
              request.source,
              request.revision,
              PrincipalId.parse(
                principal.id.value.replaceFirst('prf_', 'prn_'),
              ),
            );
            package.database.execute('COMMIT');
          } on Object {
            if (!package.database.autocommit) {
              package.database.execute('ROLLBACK');
            }
            rethrow;
          }
          _workflow.compareAppend({}, [
            MapEntry(
              'continuity-name:${request.continuityId.value}',
              CanonicalString(request.name),
            ),
          ]);
          return CanonicalObject([
            MapEntry(
              'continuity_id',
              CanonicalString(request.continuityId.value),
            ),
            MapEntry('revision', CanonicalString(revision.value)),
          ]);
        }
        final (
          target,
          targetRevision,
          source,
          sourceRevision,
        ) = switch (request) {
          CompareContinuitiesEngineRequest(
            :final target,
            :final targetRevision,
            :final source,
            :final sourceRevision,
          ) =>
            (target, targetRevision, source, sourceRevision),
          PrepareAdoptionEngineRequest(
            :final target,
            :final targetRevision,
            :final source,
            :final sourceRevision,
          ) =>
            (target, targetRevision, source, sourceRevision),
          _ => throw StateError('Continuity request was already admitted'),
        };
        if (request is PrepareAdoptionEngineRequest &&
            (request.recordIds.isEmpty || request.recordIds.length > 100)) {
          throw const InvalidArgumentError(
            field: 'record_ids',
            message: 'select 1..100 records',
          );
        }
        final from = {
          for (final row in _canon(source, sourceRevision))
            row.identity.recordId: row,
        };
        final to = {
          for (final row in _canon(target, targetRevision))
            row.identity.recordId: row,
        };
        final entries = <CanonicalValue>[];
        if (request is CompareContinuitiesEngineRequest) {
          final ids = {...from.keys, ...to.keys}.toList()
            ..sort((a, b) => a.value.compareTo(b.value));
          for (final id in ids) {
            final a = to[id], b = from[id];
            if (a?.payloadDigest == b?.payloadDigest) continue;
            if ([a, b].any(
              (r) => switch (r?.payload) {
                AssertionRecord(:final establishedBy)
                    when establishedBy != null =>
                  true,
                _ => false,
              },
            )) {
              continue;
            }
            entries.add(
              CanonicalObject([
                MapEntry('record_id', CanonicalString(id.value)),
                MapEntry('label', CanonicalString(recordReadLabel((b ?? a)!))),
                MapEntry(
                  'kind',
                  CanonicalString((b ?? a)!.identity.recordKind.wireName),
                ),
                MapEntry(
                  'target_version',
                  a == null
                      ? const CanonicalNull()
                      : CanonicalString(a.recordVersionId.value),
                ),
                MapEntry(
                  'source_version',
                  b == null
                      ? const CanonicalNull()
                      : CanonicalString(b.recordVersionId.value),
                ),
              ]),
            );
          }
          if (entries.length > 1000) {
            throw const EvaluationLimitReachedError(
              message: 'continuity comparison exceeds 1,000 changed records',
            );
          }
        } else {
          for (final id
              in (request as PrepareAdoptionEngineRequest).recordIds) {
            final old = to[id], record = from[id];
            if (record != null) {
              if (old?.payloadDigest == record.payloadDigest) continue;
              entries.add(
                AdoptRecordVersionOperation(
                  source: record,
                  expectedVersion: old?.recordVersionId,
                ).toWire(),
              );
            } else if (old != null) {
              entries.add(
                TombstoneRecordOperation(
                  record: RecordRef(universe: universe, record: id),
                  expectedVersion: old.recordVersionId,
                  rationale: 'Explicitly selected absence in source continuity',
                ).toWire(),
              );
            } else {
              throw const NotFoundOrNotAccessibleError(
                message: 'adoption record',
              );
            }
          }
        }
        return CanonicalObject([
          MapEntry(
            request is CompareContinuitiesEngineRequest
                ? 'differences'
                : 'operations',
            CanonicalArray(entries),
          ),
          MapEntry('target_revision', CanonicalString(targetRevision.value)),
          MapEntry('source_revision', CanonicalString(sourceRevision.value)),
        ]);
      });
    } on InstallationException catch (error) {
      if (error.failure == InstallationFailure.denied) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      rethrow;
    }
  }

  /// Private image import retains originals but never publishes a record.
  Future<CanonicalValue> imageRequest(EngineRequest request) async {
    try {
      return await authority.withUniverseAuthority(principal, universe, (
        current,
      ) {
        if (!current.principal.author) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        final selector = switch (request) {
          StageImageEngineRequest(:final universe) ||
          ImagePreviewEngineRequest(:final universe) => universe,
          _ => throw const InvalidArgumentError(
            field: 'method',
            message: 'requires image staging or preview',
          ),
        };
        if (authority
                .resolveUniverseAlias(principal, selector.value)
                .universeId !=
            universe) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        final kernel = SqliteKernel(package.database, universe);
        final RecordId id;
        final ImageAssetRecord asset;
        final staged = request is StageImageEngineRequest;
        if (request is StageImageEngineRequest) {
          final imported = kernel.stageImageBytes(
            readImageFile(request.source),
            File(request.source).uri.pathSegments.last,
          );
          id = imported.record;
          asset = imported.asset;
        } else {
          final preview = request as ImagePreviewEngineRequest;
          final frame = _contextFrame(preview.contextId, current);
          final record = _canon(
            frame.continuity,
            frame.revision,
          ).where((r) => r.identity.recordId == preview.asset).firstOrNull;
          if (record?.payload is! ImageAssetRecord) {
            throw const NotFoundOrNotAccessibleError(message: 'resource');
          }
          id = preview.asset;
          asset = record!.payload as ImageAssetRecord;
        }
        return CanonicalObject([
          if (staged) const MapEntry('canonical', CanonicalBool(false)),
          MapEntry('asset_id', CanonicalString(id.value)),
          MapEntry(
            'metadata',
            CanonicalObject(
              asset.toWire().fields.where((f) => f.key != 'record_kind'),
            ),
          ),
          MapEntry('preview', CanonicalString(kernel.imagePreview(asset))),
          if (staged)
            MapEntry(
              'operations',
              CanonicalArray([
                AddImageAssetOperation(
                  clientRef: id.value,
                  record: asset,
                ).toWire(),
              ]),
            ),
        ]);
      });
    } on InstallationException catch (error) {
      if (error.failure == InstallationFailure.denied) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      rethrow;
    }
  }

  /// Immutable private editor saves. This retains typed intent without compiling
  /// operations, creating proposals, approving facts or advancing canon.
  Future<CanonicalValue> draftRequest(EngineRequest request) async {
    try {
      return await authority.withUniverseAuthority(principal, universe, (
        current,
      ) {
        if (!current.principal.author) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        final (selector, continuity) = switch (request) {
          LoadDraftEngineRequest(:final universe, :final continuityId) ||
          SaveDraftEngineRequest(
            :final universe,
            :final continuityId,
          ) => (universe, continuityId),
          _ => throw const InvalidArgumentError(
            field: 'method',
            message: 'requires draft load or save',
          ),
        };
        if (authority
                .resolveUniverseAlias(principal, selector.value)
                .universeId !=
            universe) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        final prefix = 'draft:${principal.id.value}:${continuity.value}:';
        if (request is SaveDraftEngineRequest) {
          final content = request.content;
          if (CanonicalArray(
                    content.operations.map((operation) => operation.toWire()),
                  ).toBytes().length >
                  128000 ||
              utf8.encode(content.rationale).length > 16000) {
            throw const InvalidArgumentError(
              field: 'draft',
              message: 'draft content exceeds draft size limit',
            );
          }
          final records = _canon(continuity, content.baseRevision);
          if (!records.any(
            (row) =>
                row.identity.recordId == content.representedContext &&
                row.payload is RepresentedContextRecord,
          )) {
            throw const NotFoundOrNotAccessibleError(
              message: 'draft represented context',
            );
          }
        }
        _journal.head(continuity);
        final keys = _workflow.keys(prefix);
        if (keys.length > 10000) {
          throw const EvaluationLimitReachedError(
            message: 'draft history limit reached',
          );
        }
        final latest = keys.lastOrNull;
        final currentDraft = latest == null
            ? null
            : SavedDraft.fromWire(_workflow.get(latest)!);
        if (request is LoadDraftEngineRequest) {
          return currentDraft?.toWire() ?? const CanonicalNull();
        }
        final save = request as SaveDraftEngineRequest;
        final version = currentDraft?.version ?? BigInt.zero;
        if (version != save.expectedVersion) {
          if (version == save.expectedVersion + BigInt.one &&
              currentDraft!.content.toWire().toText() ==
                  save.content.toWire().toText()) {
            return currentDraft.toWire();
          }
          throw BaseRevisionConflictError(
            expected: 'draft:${save.expectedVersion}',
            actual: 'draft:$version',
          );
        }
        if (version >= BigInt.from(10000)) {
          throw const EvaluationLimitReachedError(
            message: 'draft history limit reached; export the draft before further editing',
          );
        }
        final saved = SavedDraft(
          version: version + BigInt.one,
          content: save.content,
        );
        _workflow.compareAppend(
          {prefix: latest},
          [
            MapEntry(
              '$prefix${saved.version.toString().padLeft(20, '0')}',
              saved.toWire(),
            ),
          ],
        );
        return saved.toWire();
      });
    } on InstallationException catch (error) {
      if (error.failure == InstallationFailure.denied) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      rethrow;
    }
  }

  /// Private author library, including pending writing and historical approvals.
  Future<CanonicalObject> libraryRequest(LibraryEngineRequest request) async {
    try {
      return await authority.withUniverseAuthority(principal, universe, (
        current,
      ) {
        if (!current.principal.author) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        if (authority
                .resolveUniverseAlias(principal, request.universe.value)
                .universeId !=
            universe) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        final heads = _journal.heads();
        final worlds = <CanonicalValue>[];
        final contexts = <CanonicalValue>[];
        final continuities = <CanonicalValue>[];
        for (final head in heads.entries) {
          continuities.add(
            CanonicalObject([
              MapEntry('id', CanonicalString(head.key.value)),
              MapEntry('revision', CanonicalString(head.value.value)),
              MapEntry(
                'name',
                _workflow.get('continuity-name:${head.key.value}') ??
                    CanonicalString('Original continuity'),
              ),
            ]),
          );
          for (final row in _canon(head.key, head.value)) {
            switch (row.payload) {
              case WorldRecord(:final selector):
                worlds.add(
                  CanonicalObject([
                    MapEntry(
                      'id',
                      CanonicalString(recordWorld(row.identity.recordId).value),
                    ),
                    MapEntry('name', CanonicalString(selector)),
                    MapEntry('continuity_id', CanonicalString(head.key.value)),
                  ]),
                );
              case RepresentedContextRecord():
                contexts.add(CanonicalString(row.identity.recordId.value));
              default:
                break;
            }
          }
        }
        final latest = <ProposalId, ({Proposal proposal, String label})>{};
        for (final key in _workflow.keys('proposal:')) {
          final stored = StoredProposal.fromWire(_workflow.get(key)!);
          final proposal = stored.proposal;
          final previous = latest[proposal.proposalId];
          if (previous == null ||
              proposal.version > previous.proposal.version) {
            latest[proposal.proposalId] = (
              proposal: proposal,
              label: _libraryLabel(stored),
            );
          }
        }
        final published = <String>{};
        for (final key in _workflow.keys('operation:')) {
          final operation = StoredOperation.fromWire(_workflow.get(key)!);
          final input = operation.input;
          if (input != null && _journal.receipt(input) != null) {
            final digest = operation.status.proposal?.digest;
            if (digest != null) published.add(digest);
          }
        }
        final ids = latest.keys.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        final pending = <CanonicalValue>[];
        for (final id in ids) {
          final entry = latest[id]!;
          final proposal = entry.proposal;
          if (proposal.withdrawn || published.contains(proposal.digest)) {
            continue;
          }
          pending.add(
            CanonicalObject([
              MapEntry(
                'candidate',
                ProposalRef(
                  proposalId: id,
                  version: proposal.version,
                  digest: proposal.digest,
                ).toWire(),
              ),
              MapEntry('label', CanonicalString(entry.label)),
              MapEntry(
                'submission',
                CanonicalString(proposal.submission.wireName),
              ),
              MapEntry(
                'base_revision',
                CanonicalString(proposal.baseFrame.revision.value),
              ),
              MapEntry(
                'continuity',
                CanonicalString(proposal.baseFrame.continuity.value),
              ),
            ]),
          );
        }
        final approved = <CanonicalValue>[];
        for (final key in _workflow.keys('approval:${principal.id.value}:')) {
          final value = WireFields(_workflow.get(key)!, {
            'author',
            'proposal',
            'validation_digest',
            'evaluator',
          });
          if (value.string('author') != principal.id.value) continue;
          final reference = ProposalRef.fromWire(value.require('proposal'));
          approved.add(
            CanonicalObject([
              MapEntry('candidate', reference.toWire()),
              MapEntry('validation_run', CanonicalString(key.split(':').last)),
              MapEntry(
                'label',
                CanonicalString(
                  latest[reference.proposalId]?.label ?? 'Approved writing',
                ),
              ),
            ]),
          );
        }
        return CanonicalObject([
          MapEntry('storage', package.storageStatus()),
          MapEntry('worlds', CanonicalArray(worlds)),
          MapEntry('contexts', CanonicalArray(contexts)),
          MapEntry('continuities', CanonicalArray(continuities)),
          MapEntry(
            'writing',
            CanonicalObject([
              MapEntry('proposals', CanonicalArray(pending)),
              MapEntry('approved', CanonicalArray(approved)),
            ]),
          ),
        ]);
      });
    } on InstallationException catch (error) {
      if (error.failure == InstallationFailure.denied) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      rethrow;
    }
  }

  String _libraryLabel(StoredProposal stored) {
    final proposal = stored.proposal;
    final rows = _canon(
      proposal.baseFrame.continuity,
      proposal.baseFrame.revision,
    );
    for (final change in stored.changes) {
      final next = change.next;
      if (next == null) continue;
      rows.removeWhere((row) => row.identity.recordId == change.recordId);
      rows.add(RecordVersion.fromWire(next.toCanonical()));
    }
    RecordPayload? payload(RecordId id) =>
        rows.where((row) => row.identity.recordId == id).firstOrNull?.payload;
    String? name(RecordId id) {
      return switch (payload(id)) {
        EntityRecord(:final labels, :final names) =>
          labels.isNotEmpty
              ? labels[(labels.keys.toList()..sort()).first]
              : names.firstOrNull?.text,
        PropertyRecord(:final key) ||
        RelationRecord(:final key) ||
        ActionDefinitionRecord(:final key) => key,
        _ => null,
      };
    }

    String? pair(RecordId subject, RecordId predicate) {
      final left = name(subject), right = name(predicate);
      return left == null || right == null ? null : '$left — $right';
    }

    final labels = <String>[];
    for (final change in stored.changes) {
      final next = change.next;
      final row = next == null
          ? payload(change.recordId)
          : RecordVersion.fromWire(next.toCanonical()).payload;
      final label = switch (row) {
        EntityRecord(:final names) => names.firstOrNull?.text,
        SourceRecord(:final label) => label,
        PropertyRecord(:final key) ||
        RelationRecord(:final key) ||
        RuleRecord(:final key) ||
        ActionDefinitionRecord(:final key) => key,
        EntityTypeRecord(:final name) => name,
        SceneRecord(:final sceneId) => sceneId,
        ItemPowerRecord(:final item, :final powerPredicate) => pair(
          item.record,
          powerPredicate.record,
        ),
        EventRecord(:final action) =>
          action == null || name(action.record) == null
              ? null
              : 'Occurred action: ${name(action.record)}',
        AssertionRecord(:final proposition) => switch (payload(
          proposition.record,
        )) {
          PropositionRecord(:final subject, :final predicate) => pair(
            subject.record,
            predicate.record,
          ),
          _ => null,
        },
        _ => null,
      };
      if (label != null) labels.add(label);
    }
    return labels.isEmpty ? proposal.rationale : labels.join(' · ');
  }

  /// Public tool boundary. Result and envelope bindings are selected in the same
  /// authority section; recovered workers never confer cached access rights.
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
        final resolved = authority.resolveUniverseAlias(
          principal,
          request.universe.value,
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
          case CheckChangesRequest():
            final checked = await _checkChangesRequest(
              request,
              current,
              isValidationActive: isValidationActive,
            );
            result = checked.check.toWire();
            frame = checked.frame;
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
          case GetProposalRequest():
            final read = await _getProposalRequest(request, current);
            result = read.result.toWire();
            frame = read.frame;
            delivery = read.delivery;
          case ProposalValidationRequest():
            result = (await _validateProposalRequest(
              request,
              current,
            )).toWire();
            frame = _validationFrame(request.contextId, current);
          case InlineValidationRequest():
            final checked = await _validateInlineRequest(request, current);
            result = checked.validation.toWire();
            frame = checked.frame;
            focus = checked.focus;
          case InlineImpactRequest() || ProposalImpactRequest():
            final read = await _getImpactRequest(
              request as WorkflowRequest,
              current,
            );
            result = read.impact.toWire();
            frame = read.frame;
            focus = read.focus;
          case CommitRequest():
            frame = _proposal(
              request.proposalReference,
              current,
            ).proposal.baseFrame;
            result = (await _commit(
              request,
              current,
              isValidationActive: isValidationActive,
            )).toWire();
          case QueuedProposalValidationRequest():
            frame = _validationFrame(request.contextId, current);
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
              _ => throw StateError('Unreachable assessment request'),
            };
            final reference = switch (request) {
              AttachAssessmentRequest(:final proposalReference) ||
              SelectAssessmentRequest(
                :final proposalReference,
              ) => proposalReference,
              _ => throw StateError('Unreachable assessment request'),
            };
            result = (await _assessmentRequest(
              request as WorkflowRequest,
              current,
            )).toWire();
            frame = _contextFrame(contextId, current);
            focus = _proposal(reference, current).proposal.worldScope;
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

  Future<CanonicalValue> sourceRequest(ReadSourceEngineRequest request) =>
      authority.withUniverseAuthority(principal, universe, (current) async {
        const denied = NotFoundOrNotAccessibleError(message: 'resource');
        if (request.sourceVersion.universe != null &&
            request.sourceVersion.universe != universe) {
          throw denied;
        }
        final read = await _getRequest(
          GetRequest(
            universe: request.universe,
            universeId: universe,
            contextId: request.contextId,
            recordIds: [request.sourceVersion.record],
            fieldGroups: [FieldGroup.payload],
          ),
          current,
        );
        final row = read.records.records.single;
        if (row.recordVersionId != request.sourceVersion.version ||
            row.payload is! SourceVersionRecord) {
          throw denied;
        }
        final source = row.payload as SourceVersionRecord;
        return retainedSourcePage(
          source,
          _workflow.get('source:${source.contentDigest}'),
          request.after,
        );
      });

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
    final visible = {for (final row in accessible) row.identity.recordId: row};
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
                label: recordSearchLabel(
                  row,
                  visible,
                  author: frame.perspective is AuthorPerspective,
                ),
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
    final state = _readState(
      records: snapshot.accessible,
      excludedRules: inactiveUniversePolicyRules(universe, snapshot.all),
      frame: frame,
      ids: request.entityIds,
      predicates: request.predicateFilters,
      world: snapshot.focus,
      current: current,
    );
    return (state: state, frame: frame, focus: snapshot.focus);
  }

  State _readState({
    required List<RecordVersion> records,
    Set<RecordId> excludedRules = const {},
    required Frame frame,
    required List<RecordId> ids,
    required List<RecordId> predicates,
    required WorldId? world,
    required CurrentUniverseAuthority current,
  }) {
    final restricted =
        current.worldScope != null || frame.perspective is! AuthorPerspective;
    final receipts = restricted
        ? <InitializationReceipt>[]
        : SqliteKernel(
            package.database,
            universe,
          ).initializationReceiptsAt(frame.continuity, frame.revision);
    return assembleReadState(
      records: records,
      excludedRules: excludedRules,
      frame: frame,
      ids: ids,
      predicates: predicates,
      world: world,
      restricted: restricted,
      receipts: receipts,
      readVersion: _version,
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
    final frame = _contextFrame(request.contextId, current);
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
          excludedRules: inactiveUniversePolicyRules(universe, selected.all),
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

  /// Ordinary writing creates a provisional candidate, never an approval or
  /// publication. Exact request/frame/principal retries reuse its durable receipt.
  Future<({WritingCheck check, Frame frame})> checkChangesRequest(
    CheckChangesRequest request, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _checkChangesRequest(
      request,
      current,
      isValidationActive: isValidationActive,
    ),
  );

  Future<({WritingCheck check, Frame frame})> _checkChangesRequest(
    CheckChangesRequest request,
    CurrentUniverseAuthority current, {
    required bool Function(OperationId) isValidationActive,
  }) async {
    final frame = _contextFrame(request.contextId, current);
    WritingCheck result({
      String status = 'needs_clarification',
      List<String> additions = const [],
      List<String> unchanged = const [],
      List<String> clarifications = const [],
      List<String> excluded = const [],
      List<String> unknowns = const [],
    }) => WritingCheck(
      status: status,
      additions: additions,
      unchanged: unchanged,
      clarifications: clarifications,
      excluded: excluded,
      unknowns: unknowns,
    );
    if (frame.perspective is! AuthorPerspective) {
      return (
        check: result(
          clarifications: [
            'Canon changes require an explicitly selected authorized author-perspective context; this restricted view is research only.',
          ],
        ),
        frame: frame,
      );
    }
    final base = _canon(frame.continuity, frame.revision);
    final visible = visibleRecordIds(
      records: base,
      worldScope: current.worldScope,
    );
    final rows = base
        .where((r) => visible.contains(r.identity.recordId))
        .toList();
    final CheckChangesRequest input;
    try {
      input = normalizeWritingChangesDates(request, frame, rows);
    } on FormatException catch (error) {
      return (
        check: result(clarifications: [error.message.toString()]),
        frame: frame,
      );
    }
    final binding = canonicalDigest(
      CanonicalArray([
        request.toArgs(),
        frame.toWire(),
        CanonicalString(principal.id.value),
      ]),
    );
    final key = 'writing:$binding';
    final receipt = operationRequestKey(principal.id, 'propose', key);
    if (input.questions.isEmpty && _workflow.get(receipt) != null) {
      if (!current.permissions.$1) {
        throw const PolicyDeniedError(
          message: 'current grant does not permit proposals',
        );
      }
      final prior = await loadStoredOperation(
        key: receipt,
        principal: principal.id,
        worldScope: current.worldScope,
        readWorkflow: _workflow.get,
        readReceipt: _journal.receipt,
        isValidationActive: isValidationActive,
      );
      final proposal = prior.status.proposal;
      if (proposal == null) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      return (
        check: await _finishWritingCheck(
          input,
          frame,
          result(
            additions: ['Reused the exact original uncommitted candidate.'],
          ),
          proposal,
          current,
        ),
        frame: frame,
      );
    }
    final compiled = await compileWritingChanges(
      frame: frame,
      base: base,
      visibleRows: rows,
      input: input,
      canonAt: _canon,
      worldScope: current.worldScope,
    );
    final check = result(
      status: compiled.clarifications.isNotEmpty
          ? 'needs_clarification'
          : compiled.operations.isEmpty
          ? current.worldScope != null
                ? 'incomplete'
                : 'no_changes'
          : 'needs_clarification',
      additions: compiled.additions,
      unchanged: compiled.unchanged,
      clarifications: compiled.clarifications,
      excluded: compiled.excluded,
      unknowns: compiled.unknowns,
    );
    if (compiled.clarifications.isNotEmpty || compiled.operations.isEmpty) {
      return (check: check, frame: frame);
    }
    if (!current.permissions.$1) {
      throw const PolicyDeniedError(
        message: 'current grant does not permit proposals',
      );
    }
    final admission = await _openContext(
      _writingAdmission(input.universe, frame),
      current,
    );
    var rationale =
        'Provisional factual deltas from author writing; no author approval or source publication implied.';
    for (final ending in input.factEndings) {
      rationale += '\nProposed fact ending reason: ${ending.reason}';
    }
    for (final correction in input.policyCorrections) {
      rationale += '\nProposed policy correction reason: ${correction.reason}';
    }
    final proposal = await _propose(
      CreateProposalRequest(
        universe: input.universe,
        contextId: admission.contextId,
        operations: compiled.operations,
        submission: Submission.draft,
        rationale: rationale,
        idempotencyKey: key,
      ),
      current,
      resolvedFrame: admission.frame,
      worldFocus: null,
      isValidationActive: isValidationActive,
    );
    return (
      check: await _finishWritingCheck(input, frame, check, proposal, current),
      frame: frame,
    );
  }

  OpenContextRequest _writingAdmission(Selector selector, Frame frame) =>
      OpenContextRequest(
        universe: selector,
        continuityId: frame.continuity,
        revision: ExactRevisionSelector(revisionId: frame.revision),
        representedContext: ContextIdSelector(frame.context.record),
        temporalQuery: const TimelessFrameTime(),
        temporalSystems: [],
        perspective: const AuthorPerspective(),
      );

  Future<WritingCheck> _finishWritingCheck(
    CheckChangesRequest input,
    Frame frame,
    WritingCheck check,
    Proposal proposal,
    CurrentUniverseAuthority current,
  ) async {
    final admission = await _openContext(
      _writingAdmission(input.universe, frame),
      current,
    );
    final reference = ProposalRef(
      proposalId: proposal.proposalId,
      version: proposal.version,
      digest: proposal.digest,
    );
    final validation = await _validateProposalRequest(
      ProposalValidationRequest(
        universe: input.universe,
        contextId: admission.contextId,
        proposalReference: reference,
        checkScope: CheckScope.universe,
      ),
      current,
    );
    final impact = await _getImpactRequest(
      ProposalImpactRequest(
        universe: input.universe,
        contextId: admission.contextId,
        proposalReference: reference,
        scope: CheckScope.universe,
        byteBudget: 65536,
      ),
      current,
    );
    return finishWritingCheck(
      check: check,
      proposal: proposal,
      validation: validation,
      impact: impact.impact,
      impactDeliveryComplete: true,
    );
  }

  /// Stage exact author bytes and import provenance, without creating canon.
  Future<CanonicalObject> stageSource({
    required String label,
    required String text,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _stageSource(current, label: label, text: text),
  );

  CanonicalObject _stageSource(
    CurrentUniverseAuthority current, {
    required String label,
    required String text,
  }) {
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
    _workflow.compareAppend({}, staged.entries);
    return CanonicalObject([
      const MapEntry('canonical', CanonicalBool(false)),
      MapEntry(
        'operations',
        CanonicalArray(staged.operations.map((op) => op.toWire())),
      ),
    ]);
  }

  void _writingAuthorCurrent(Proposal proposal) {
    final reference = ProposalRef(
      proposalId: proposal.proposalId,
      version: proposal.version,
      digest: proposal.digest,
    );
    if (_workflow.latestKey('proposal:${proposal.proposalId.value}:') !=
            proposalKey(reference) ||
        proposal.withdrawn ||
        _journal.head(proposal.baseFrame.continuity) !=
            proposal.baseFrame.revision) {
      throw const ApprovalStaleError();
    }
  }

  /// Recheck the exact author candidate and present its frozen changes. A
  /// publishable review is not approval and does not authorize publication.
  Future<CanonicalObject> writingAuthorReview(ProposalRef reference) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) => _writingAuthorReview(reference, current),
      );

  Future<CanonicalObject> _writingAuthorReview(
    ProposalRef reference,
    CurrentUniverseAuthority current,
  ) async {
    if (!current.principal.author) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final stored = _proposal(reference, current);
    final p = stored.proposal;
    _writingAuthorCurrent(p);
    final selector = Selector(universe.value);
    final opened = await _openContext(
      _writingAdmission(selector, p.baseFrame),
      current,
    );
    final validation = await _validateProposalRequest(
      ProposalValidationRequest(
        universe: selector,
        contextId: opened.contextId,
        proposalReference: reference,
        checkScope: CheckScope.universe,
      ),
      current,
    );
    final impact = await _getImpactRequest(
      ProposalImpactRequest(
        universe: selector,
        contextId: opened.contextId,
        proposalReference: reference,
        scope: CheckScope.universe,
        byteBudget: 65536,
      ),
      current,
    );
    final execution = validation.execution;
    if (execution == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final checked = CheckedValidation.fromWire(
      _workflow.get('validation:${execution.runId.value}')!,
    );
    final originals = _canon(p.baseFrame.continuity, p.baseFrame.revision);
    final records = {for (final row in originals) row.identity.recordId: row};
    for (final change in stored.changes) {
      records.remove(change.recordId);
      if (change.next != null) {
        records[change.recordId] = RecordVersion.fromWire(
          change.next!.toCanonical(),
        );
      }
    }
    final gaps = assessResourceAccounting(records.values.toList(), p.baseFrame);
    return CanonicalObject([
      MapEntry(
        'acceptance_options',
        CanonicalArray(
          gaps
              .where((g) => g.acceptance == null)
              .map(
                (g) => CanonicalObject([
                  MapEntry('fingerprint', CanonicalString(g.fingerprint.value)),
                  MapEntry(
                    'scope',
                    CanonicalString('resource:${g.proposition.value}'),
                  ),
                ]),
              ),
        ),
      ),
      MapEntry(
        'summary',
        CanonicalArray(
          summarizeWritingAuthorReview(
            stored: stored,
            originals: originals,
          ).map(CanonicalString.new),
        ),
      ),
      MapEntry('candidate', reference.toWire()),
      MapEntry('validation', validation.toWire()),
      MapEntry('impact', impact.impact.toWire()),
      // This native route returns a whole impact or fails its delivery budget.
      MapEntry(
        'publishable',
        CanonicalBool(
          checked.admissible && impact.impact.coverage == Coverage.complete,
        ),
      ),
      MapEntry('review', await _review(reference, current)),
    ]);
  }

  /// Private writing engine boundary for an already authenticated, recovered
  /// universe worker. Socket/HTTP framing and worker ownership belong to runtime.
  Future<CanonicalValue> executeWritingEngineRequest(
    EngineRequest request, {
    required bool Function(OperationId) isValidationActive,
  }) async {
    try {
      return await authority.withUniverseAuthority(principal, universe, (
        current,
      ) async {
        if (!current.principal.author) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        final selector = switch (request) {
          AuthorWritingEngineRequest(:final universe) ||
          StageSourceEngineRequest(:final universe) ||
          ReviewEngineRequest(:final universe) ||
          ApproveEngineRequest(:final universe) => universe,
          _ => throw const InvalidArgumentError(
            field: 'method',
            message: 'requires a private writing engine request',
          ),
        };
        final resolved = authority.resolveUniverseAlias(
          principal,
          selector.value,
        );
        if (resolved.universeId != universe) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        switch (request) {
          case StageSourceEngineRequest(:final label, :final text):
            return _stageSource(current, label: label, text: text);
          case ReviewEngineRequest(:final proposalReference):
            return _review(proposalReference, current);
          case ApproveEngineRequest(
            :final proposalReference,
            :final validationRun,
          ):
            return _approve(proposalReference, validationRun, current);
          case AuthorWritingEngineRequest(:final action):
            final result = await _authorWritingAction(
              action,
              current,
              isValidationActive: isValidationActive,
            );
            if (action is! PublishWritingAction) return result;
            final stored = _proposal(action.candidate, current);
            final envelope = Envelope<CanonicalValue>(
              contractVersion: protocolVersion,
              requestId: BigInt.zero,
              universeId: universe,
              universe: Selector(resolved.name),
              aliasMatched: selector.value != resolved.name,
              frame: stored.proposal.baseFrame,
              authorizationScope: 'universe grant',
              delivery: Delivery(complete: true, cursor: null),
              result: result,
            ).toWire((v) => v);
            if (envelope.toBytes().length > 900000) {
              throw const EvaluationLimitReachedError(
                message: 'response exceeds bounded transport; narrow the batch',
              );
            }
            return envelope;
          default:
            throw StateError('Unreachable private writing request');
        }
      });
    } on InstallationException catch (error) {
      if (error.failure == InstallationFailure.denied) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      rethrow;
    }
  }

  /// Native action dispatch. The transport owns the response envelope, just as
  /// it does for the native commit route; publication returns its durable receipt.
  Future<CanonicalValue> authorWritingAction(
    AuthorWritingAction action, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _authorWritingAction(
      action,
      current,
      isValidationActive: isValidationActive,
    ),
  );

  Future<CanonicalValue> _authorWritingAction(
    AuthorWritingAction action,
    CurrentUniverseAuthority current, {
    required bool Function(OperationId) isValidationActive,
  }) async => switch (action) {
    InspectWritingAction() => await _inspectWriting(action, current),
    PrepareWritingAction() => await _prepareWritingReview(
      current,
      candidate: action.candidate,
      label: action.label,
      text: action.text,
      isValidationActive: isValidationActive,
    ),
    PrepareContractsWritingAction() => await _prepareWritingReview(
      current,
      candidate: action.candidate,
      label: action.label,
      text: action.text,
      contracts: true,
      isValidationActive: isValidationActive,
    ),
    EditKnowledgeWritingAction() => await _editWritingKnowledge(
      action,
      current,
      isValidationActive: isValidationActive,
    ),
    EstablishKnowledgeWritingAction() => await _establishWritingKnowledge(
      action,
      current,
      isValidationActive: isValidationActive,
    ),
    AcceptWritingAction() => await _acceptWriting(
      action,
      current,
      isValidationActive: isValidationActive,
    ),
    RejectWritingAction() => (await _rejectWriting(
      action,
      current,
      isValidationActive: isValidationActive,
    )).toWire(),
    PublishWritingAction() => (await _publishWriting(
      action,
      current,
      isValidationActive: isValidationActive,
    )).toWire(),
  };

  /// Prepare exact source and return the current checked private review.
  Future<CanonicalObject> prepareWritingReview({
    required ProposalId candidate,
    required String label,
    required String text,
    bool contracts = false,
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _prepareWritingReview(
      current,
      candidate: candidate,
      label: label,
      text: text,
      contracts: contracts,
      isValidationActive: isValidationActive,
    ),
  );

  Future<CanonicalObject> _prepareWritingReview(
    CurrentUniverseAuthority current, {
    required ProposalId candidate,
    required String label,
    required String text,
    bool contracts = false,
    required bool Function(OperationId) isValidationActive,
  }) async {
    final proposal = await _prepareWritingSource(
      current,
      candidate: candidate,
      label: label,
      text: text,
      contracts: contracts,
      isValidationActive: isValidationActive,
    );
    return _writingAuthorReview(
      ProposalRef(
        proposalId: proposal.proposalId,
        version: proposal.version,
        digest: proposal.digest,
      ),
      current,
    );
  }

  Future<CanonicalObject> inspectWriting(InspectWritingAction action) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) => _inspectWriting(action, current),
      );

  Future<CanonicalObject> _inspectWriting(
    InspectWritingAction action,
    CurrentUniverseAuthority current,
  ) async {
    if (!current.principal.author) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final stored = _proposal(action.candidate, current);
    if (stored.proposal.submission != Submission.submitted) {
      throw const ApprovalStaleError();
    }
    if (!stored.authorOrigin ||
        !stored.proposal.operations.any(
          (op) => op is AddSourceAnchorOperation,
        )) {
      throw const PolicyDeniedError(
        message:
            'Reopen requires an author-prepared exact-source writing review.',
      );
    }
    return _writingAuthorReview(action.candidate, current);
  }

  Future<Proposal> rejectWriting(
    RejectWritingAction action, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) =>
        _rejectWriting(action, current, isValidationActive: isValidationActive),
  );

  Future<Proposal> _rejectWriting(
    RejectWritingAction action,
    CurrentUniverseAuthority current, {
    required bool Function(OperationId) isValidationActive,
  }) async {
    if (!current.principal.author) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final key =
        'writing-reject:${canonicalDigest(CanonicalString(action.candidate.value))}';
    final receipt = operationRequestKey(principal.id, 'propose', key);
    if (_workflow.get(receipt) != null) {
      final prior = await loadStoredOperation(
        key: receipt,
        principal: principal.id,
        worldScope: current.worldScope,
        readWorkflow: _workflow.get,
        readReceipt: _journal.receipt,
        isValidationActive: isValidationActive,
      );
      final proposal = prior.status.proposal;
      if (proposal == null) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      return proposal;
    }
    final latest = _workflow.latestKey('proposal:${action.candidate.value}:');
    if (latest == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final retained = StoredProposal.fromWire(_workflow.get(latest)!);
    final stored = _proposal(retained.reference, current);
    _writingAuthorCurrent(stored.proposal);
    final opened = await _openContext(
      _writingAdmission(Selector(universe.value), stored.proposal.baseFrame),
      current,
    );
    return _propose(
      WithdrawProposalRequest(
        universe: Selector(universe.value),
        contextId: opened.contextId,
        proposalReference: stored.reference,
        idempotencyKey: key,
      ),
      current,
      resolvedFrame: opened.frame,
      worldFocus: null,
      isValidationActive: isValidationActive,
    );
  }

  Future<OpenedContext> _writingKnowledgeContext(
    ContextId id,
    CurrentUniverseAuthority current,
  ) async {
    final raw = _workflow.get('context:${id.value}');
    if (raw == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final selected = StoredContext.fromWire(raw);
    if (selected.frame.universe != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    if (selected.expires <
        BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000)) {
      throw const ContextExpiredError();
    }
    if (_journal.head(selected.frame.continuity) != selected.frame.revision) {
      throw const ApprovalStaleError();
    }
    // An author may reopen a writer's selection, but uses a new private context.
    return _openContext(
      _writingAdmission(Selector(universe.value), selected.frame),
      current,
    );
  }

  Future<CanonicalObject> _retainWritingKnowledge(
    CurrentUniverseAuthority current, {
    required OpenedContext opened,
    required List<DomainOperation> operations,
    required String key,
    required String rationale,
    required String label,
    required String text,
    required bool Function(OperationId) isValidationActive,
  }) async {
    final receipt = operationRequestKey(principal.id, 'propose', key);
    final retained = _workflow.get(receipt) == null
        ? null
        : await loadStoredOperation(
            key: receipt,
            principal: principal.id,
            worldScope: current.worldScope,
            readWorkflow: _workflow.get,
            readReceipt: _journal.receipt,
            isValidationActive: isValidationActive,
          );
    final candidate = retained == null
        ? await _propose(
            CreateProposalRequest(
              universe: Selector(universe.value),
              contextId: opened.contextId,
              operations: operations,
              submission: Submission.draft,
              rationale: rationale,
              idempotencyKey: key,
            ),
            current,
            resolvedFrame: opened.frame,
            worldFocus: null,
            isValidationActive: isValidationActive,
          )
        : retained.status.proposal;
    if (candidate == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final prepared = await _prepareWritingSource(
      current,
      candidate: candidate.proposalId,
      label: label,
      text: text,
      knowledgeRationale: rationale,
      isValidationActive: isValidationActive,
    );
    return _writingAuthorReview(
      ProposalRef(
        proposalId: prepared.proposalId,
        version: prepared.version,
        digest: prepared.digest,
      ),
      current,
    );
  }

  Future<CanonicalObject> editWritingKnowledge(
    EditKnowledgeWritingAction action, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _editWritingKnowledge(
      action,
      current,
      isValidationActive: isValidationActive,
    ),
  );

  Future<CanonicalObject> _editWritingKnowledge(
    EditKnowledgeWritingAction action,
    CurrentUniverseAuthority current, {
    required bool Function(OperationId) isValidationActive,
  }) async {
    if (!current.principal.author) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final nonWhitespace = RegExp(
      r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
    );
    if (!nonWhitespace.hasMatch(action.text) ||
        !nonWhitespace.hasMatch(action.correction.reason)) {
      throw const InvalidArgumentError(
        field: 'text/reason',
        message: 'Explicit author source and reason required',
      );
    }
    final opened = await _writingKnowledgeContext(action.contextId, current);
    final rows = _canon(opened.frame.continuity, opened.frame.revision);
    final correction = WritingAttitudeCorrection.fromWire(
      normalizeWritingDates(action.correction.toWire(), opened.frame, rows),
    );
    final operations = compileWritingAttitudeCorrection(
      rows: rows,
      frame: opened.frame,
      patch: correction,
      privateKnowledge: true,
    );
    final key =
        'author-knowledge-edit:${canonicalDigest(CanonicalArray([opened.frame.toWire(), correction.toWire(), CanonicalString(action.label), CanonicalString(action.text)]))}';
    return _retainWritingKnowledge(
      current,
      opened: opened,
      operations: operations,
      key: key,
      rationale: correction.reason,
      label: action.label,
      text: action.text,
      isValidationActive: isValidationActive,
    );
  }

  Future<CanonicalObject> establishWritingKnowledge(
    EstablishKnowledgeWritingAction action, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _establishWritingKnowledge(
      action,
      current,
      isValidationActive: isValidationActive,
    ),
  );

  Future<CanonicalObject> _establishWritingKnowledge(
    EstablishKnowledgeWritingAction action,
    CurrentUniverseAuthority current, {
    required bool Function(OperationId) isValidationActive,
  }) async {
    if (!current.principal.author) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final nonWhitespace = RegExp(
      r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
    );
    if (!nonWhitespace.hasMatch(action.rationale) ||
        !nonWhitespace.hasMatch(action.text)) {
      throw const InvalidArgumentError(
        field: 'rationale/text',
        message: 'Explicit author rationale and source required',
      );
    }
    final opened = await _writingKnowledgeContext(action.contextId, current);
    final frame = opened.frame;
    final rows = _canon(frame.continuity, frame.revision);
    final declaration = AuthorKnowledgeDeclaration.fromWire(
      normalizeWritingDates(action.declaration.toWire(), frame, rows),
    );
    final inactivePolicies = inactiveUniversePolicyRules(universe, rows);
    final policies = [
      for (final row in rows)
        if (!inactivePolicies.contains(row.identity.recordId))
        if (row.payload case RuleRecord(:final knowledgePolicy)
            when knowledgePolicy?.context == frame.context)
          knowledgePolicy!,
    ];
    if (policies.length != 1 ||
        policies.single.mode != KnowledgeMode.authorEstablished) {
      throw const InvalidArgumentError(
        field: 'knowledge policy',
        message: 'Select the exact authored author-established context policy.',
      );
    }
    final holder = resolveWritingObject(rows, declaration.holder, frame);
    if (holder == null) {
      throw const InvalidArgumentError(
        field: 'holder',
        message: 'Resolve the exact authored holder.',
      );
    }
    final claim = bindWritingClaim(universe, rows, frame, declaration.claim);
    final at = bindWritingTime(frame, rows, declaration.atTick);
    final world = resolveWorldFocus(
      world: declaration.world == null ? null : Selector(declaration.world!),
      guard: null,
      records: rows,
      scope: current.worldScope,
    );
    final key =
        'author-knowledge:${canonicalDigest(CanonicalArray([frame.toWire(), declaration.toWire(), CanonicalString(action.rationale), CanonicalString(action.label), CanonicalString(action.text)]))}';
    final operations = <DomainOperation>[];
    final proposition = bindWritingProposition(
      operations,
      universe,
      claim,
      rows,
    );
    operations.add(
      AddBeliefOperation(
        clientRef: RecordId.generate().value,
        record: EpistemicAttitudeRecord(
          holder: RecordRef(universe: universe, record: holder),
          proposition: proposition,
          attitude: EpistemicAttitudeKind.knows,
          validity: bindWritingLifetime(at, declaration.lifetime),
          basis: AuthorDecisionBasis(action.rationale),
          acquisition: KnowledgeAcquisition(
            truthContext: frame.context,
            time: at,
            world: world == null
                ? null
                : RecordRef(
                    universe: universe,
                    record: RecordId.parse(
                      world.value.replaceFirst('wld_', 'rec_'),
                    ),
                  ),
            basis: const AuthorEstablishedKnowledge(),
          ),
        ),
      ),
    );
    return _retainWritingKnowledge(
      current,
      opened: opened,
      operations: operations,
      key: key,
      rationale: action.rationale,
      label: action.label,
      text: action.text,
      isValidationActive: isValidationActive,
    );
  }

  /// Accept only an exact unresolved opt-in resource finding. This retains a
  /// new submitted proposal; its validation and approval are separate decisions.
  Future<CanonicalObject> acceptWriting(
    AcceptWritingAction action, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) =>
        _acceptWriting(action, current, isValidationActive: isValidationActive),
  );

  Future<CanonicalObject> _acceptWriting(
    AcceptWritingAction action,
    CurrentUniverseAuthority current, {
    required bool Function(OperationId) isValidationActive,
  }) async {
    if (!current.principal.author) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    if (!RegExp(
      r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
    ).hasMatch(action.rationale)) {
      throw const InvalidArgumentError(
        field: 'rationale',
        message: 'author acceptance requires a reason',
      );
    }
    final binding = canonicalDigest(
      CanonicalArray([
        action.candidate.toWire(),
        CanonicalString(action.fingerprint.value),
        CanonicalString(action.scope),
        CanonicalString(action.rationale),
      ]),
    );
    final key = 'writing-accept:$binding';
    final receipt = operationRequestKey(principal.id, 'propose', key);
    if (_workflow.get(receipt) != null) {
      final prior = await loadStoredOperation(
        key: receipt,
        principal: principal.id,
        worldScope: current.worldScope,
        readWorkflow: _workflow.get,
        readReceipt: _journal.receipt,
        isValidationActive: isValidationActive,
      );
      final proposal = prior.status.proposal;
      if (proposal == null) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      return _writingAuthorReview(
        ProposalRef(
          proposalId: proposal.proposalId,
          version: proposal.version,
          digest: proposal.digest,
        ),
        current,
      );
    }
    final stored = _proposal(action.candidate, current);
    final p = stored.proposal;
    _writingAuthorCurrent(p);
    final kernel = SqliteKernel(package.database, universe);
    final checked = await checkProposalCandidate(
      stored: stored,
      universe: universe,
      principal: principal.id,
      approvalAuthor: current.approvalAuthor,
      scope: current.worldScope,
      preview: (input) => kernel
          .preview(input)
          .map((r) => RecordVersion.fromWire(r.toCanonical()))
          .toList(),
      readCanon: _canon,
      readWorkflow: _workflow.get,
      readVersion: _version,
      readSelectedAssessment: (reference) =>
          _assessmentReview(reference, current),
    );
    final input = await proposalCommitInput(
      stored: stored,
      universe: universe,
      principal: principal.id,
      idempotencyKey: 'acceptance-review',
      readCanon: _canon,
    );
    final records = kernel
        .preview(input)
        .map((r) => RecordVersion.fromWire(r.toCanonical()))
        .toList();
    final matching = assessResourceAccounting(records, p.baseFrame).where(
      (g) =>
          g.fingerprint == action.fingerprint &&
          g.acceptance == null &&
          action.scope == 'resource:${g.proposition.value}',
    );
    if (matching.isEmpty) {
      throw const InvalidArgumentError(
        field: 'scope',
        message: 'select an exact current unresolved resource finding and its resource scope',
      );
    }
    final gap = matching.first;
    final findings = checked.validation.findings.where(
      (f) => f.fingerprint == gap.fingerprint,
    );
    if (findings.isEmpty) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final operations = [
      ...p.operations,
      RecordIssueDecisionOperation(
        clientRef: RecordId.generate().value,
        record: IssueDecisionRecord(
          fingerprints: [findings.first.fingerprint],
          mode: IssueDecisionMode.accept,
          scope: action.scope,
          rationale: action.rationale,
          principal: PrincipalId.parse(
            principal.id.value.replaceFirst('prf_', 'prn_'),
          ),
        ),
      ),
    ];
    final versions = <RecordId, RecordVersionId>{};
    for (final change in stored.changes) {
      if (change.next != null) {
        final row = RecordVersion.fromWire(change.next!.toCanonical());
        if (row.payload is SourceVersionRecord) {
          versions[row.identity.recordId] = row.recordVersionId;
        }
      }
    }
    final opened = await _openContext(
      _writingAdmission(Selector(universe.value), p.baseFrame),
      current,
    );
    final proposed = await _propose(
      ReviseProposalRequest(
        universe: Selector(universe.value),
        contextId: opened.contextId,
        proposalReference: action.candidate,
        operations: operations,
        submission: Submission.submitted,
        rationale: action.rationale,
        idempotencyKey: key,
      ),
      current,
      resolvedFrame: opened.frame,
      worldFocus: null,
      isValidationActive: isValidationActive,
      versions: versions,
    );
    return _writingAuthorReview(
      ProposalRef(
        proposalId: proposed.proposalId,
        version: proposed.version,
        digest: proposed.digest,
      ),
      current,
    );
  }

  Future<CommitReceipt> publishWriting(
    PublishWritingAction action, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _publishWriting(
      action,
      current,
      isValidationActive: isValidationActive,
    ),
  );

  Future<CommitReceipt> _publishWriting(
    PublishWritingAction action,
    CurrentUniverseAuthority current, {
    required bool Function(OperationId) isValidationActive,
  }) async {
    if (!current.principal.author) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final stored = _proposal(action.candidate, current);
    final request = CommitRequest(
      universe: Selector(universe.value),
      proposalReference: action.candidate,
      expectedBaseRevision: stored.proposal.baseFrame.revision,
      validationRun: action.validationRun,
      idempotencyKey: action.idempotencyKey,
    );
    final key = operationRequestKey(
      principal.id,
      'commit',
      action.idempotencyKey,
    );
    if (_workflow.get(key) == null) {
      await _approve(action.candidate, action.validationRun, current);
    }
    return _commit(request, current, isValidationActive: isValidationActive);
  }

  /// Retain the author-selected exact-source revision. This does not approve or
  /// publish it; the private review route must inspect the returned exact state.
  Future<Proposal> prepareWritingSource({
    required ProposalId candidate,
    required String label,
    required String text,
    bool contracts = false,
    String? knowledgeRationale,
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _prepareWritingSource(
      current,
      candidate: candidate,
      label: label,
      text: text,
      contracts: contracts,
      knowledgeRationale: knowledgeRationale,
      isValidationActive: isValidationActive,
    ),
  );

  Future<Proposal> _prepareWritingSource(
    CurrentUniverseAuthority current, {
    required ProposalId candidate,
    required String label,
    required String text,
    bool contracts = false,
    String? knowledgeRationale,
    required bool Function(OperationId) isValidationActive,
  }) async {
    if (!current.principal.author) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    if (!RegExp(
      r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
    ).hasMatch(text)) {
      throw const InvalidArgumentError(
        field: 'text',
        message: 'author source must not be empty',
      );
    }
    final binding = canonicalDigest(
      CanonicalArray([
        CanonicalString(candidate.value),
        CanonicalString(label),
        CanonicalString(text),
        if (knowledgeRationale != null) CanonicalString(knowledgeRationale),
      ]),
    );
    final key =
        '${contracts ? 'writing-contracts-prepare' : 'writing-prepare'}:$binding';
    final receipt = operationRequestKey(principal.id, 'propose', key);
    if (_workflow.get(receipt) != null) {
      final prior = await loadStoredOperation(
        key: receipt,
        principal: principal.id,
        worldScope: current.worldScope,
        readWorkflow: _workflow.get,
        readReceipt: _journal.receipt,
        isValidationActive: isValidationActive,
      );
      final proposal = prior.status.proposal;
      if (proposal == null) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      _writingAuthorCurrent(proposal);
      return proposal;
    }
    final latest = _workflow.latestKey('proposal:${candidate.value}:');
    if (latest == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final retained = StoredProposal.fromWire(_workflow.get(latest)!);
    final stored = _proposal(retained.reference, current);
    final p = stored.proposal;
    _writingAuthorCurrent(p);
    if (p.submission != Submission.draft) throw const ApprovalStaleError();
    final originals = _canon(p.baseFrame.continuity, p.baseFrame.revision);
    await validateWritingSourcePreparation(
      operations: p.operations,
      originals: originals,
      contracts: contracts,
      authorOrigin: stored.authorOrigin,
      canonAt: _canon,
      knowledgeRationale: knowledgeRationale,
    );
    final staged = stageWritingSource(
      universe: universe,
      author: principal.id,
      label: label,
      text: text,
      importTime: DateTime.now().toUtc().toIso8601String(),
    );
    _workflow.compareAppend({}, staged.entries);
    final attached = attachWritingSource(
      universe: universe,
      context: p.baseFrame.context,
      operations: p.operations,
      sourceOperations: staged.operations,
      sourceVersion: staged.sourceVersion,
      text: text,
      digest: staged.digest,
      byteSize: staged.byteSize,
      knowledgeRationale: knowledgeRationale,
    );
    final admission = await _openContext(
      _writingAdmission(Selector(universe.value), p.baseFrame),
      current,
    );
    final rationale =
        '${knowledgeRationale ?? (contracts ? 'Author explicitly declared these supported contracts/policies with exact source; separate approval still required.' : 'Author selected exact source passage for factual review; publication still requires separate exact approval.')}\n${p.rationale}';
    return _propose(
      ReviseProposalRequest(
        universe: Selector(universe.value),
        contextId: admission.contextId,
        proposalReference: stored.reference,
        operations: attached.operations,
        submission: Submission.submitted,
        rationale: rationale,
        idempotencyKey: key,
      ),
      current,
      resolvedFrame: admission.frame,
      worldFocus: null,
      isValidationActive: isValidationActive,
      versions: attached.versions,
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
    final frame = _contextFrame(request.contextId, current);
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
        excludedRules: inactiveUniversePolicyRules(universe, snapshot.all),
        frame: frame,
        restricted:
            current.worldScope != null ||
            frame.perspective is! AuthorPerspective,
      ),
      frame: frame,
    );
  }

  /// Exact private author review, including the frozen historical diff. Reading
  /// an older proposal remains possible; latest reports version currentness.
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
    final stored = _proposal(reference, current);
    final assessment = await _assessmentReview(reference, current);
    final originals = {
      for (final row in _canon(
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
          _workflow.latestKey(
                'proposal:${stored.proposal.proposalId.value}:',
              ) ==
              stored.key,
        ),
      ),
      MapEntry('assessment_review', assessment.toWire()),
    ]);
  }

  Future<({ProposalViewResult result, Delivery delivery})> getProposalRequest(
    GetProposalRequest request,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    final read = await _getProposalRequest(request, current);
    return (result: read.result, delivery: read.delivery);
  });

  Future<({ProposalViewResult result, Delivery delivery, Frame frame})>
  _getProposalRequest(
    GetProposalRequest request,
    CurrentUniverseAuthority current,
  ) async {
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
        frame: frame,
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
      frame: frame,
      result: FrozenProposalView(page.proposal),
      delivery: Delivery(complete: page.complete, cursor: cursor),
    );
  }

  Future<({Impact impact, Frame frame, WorldId? focus})> getImpactRequest(
    WorkflowRequest request,
  ) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _getImpactRequest(request, current),
  );

  Future<({Impact impact, Frame frame, WorldId? focus})> _getImpactRequest(
    WorkflowRequest request,
    CurrentUniverseAuthority current,
  ) async {
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
  }

  /// Native dispatch entry: admit the retained context and resolve named world
  /// focus under the same current authority section as proposal retention.
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
    final frame = _contextFrame(contextId, current);
    final focus = world == null
        ? null
        : resolveWorldFocus(
            world: world,
            guard: guard,
            records: _canon(frame.continuity, frame.revision),
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
      versions: versions,
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
  }

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
  ) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => _validateProposalRequest(request, current),
  );

  Future<ValidationV3> _validateProposalRequest(
    ProposalValidationRequest request,
    CurrentUniverseAuthority current,
  ) async {
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
      readSelectedAssessment: (reference) =>
          _assessmentReview(reference, current),
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
  }

  /// Research an ephemeral candidate. No proposal, reservation, approval
  /// binding or publication operation is created by this check.
  Future<ValidationV3> validateInlineRequest(InlineValidationRequest request) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) async =>
            (await _validateInlineRequest(request, current)).validation,
      );

  Future<({ValidationV3 validation, Frame frame, WorldId? focus})>
  _validateInlineRequest(
    InlineValidationRequest request,
    CurrentUniverseAuthority current,
  ) async {
    if (request.universeId != null && request.universeId != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final frame = _validationFrame(request.contextId, current);
    final base = _canon(frame.continuity, frame.revision);
    // Compilation errors can disclose hidden definitions. Restricted research
    // resolves only its visible world selector and never compiles the candidate.
    if (current.worldScope != null) {
      final focus = resolveWorldFocus(
        world: request.world,
        guard: request.worldId,
        records: base,
        scope: current.worldScope,
      );
      return (
        validation: ValidationV3.restricted(),
        frame: frame,
        focus: focus,
      );
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
    return (validation: report, frame: frame, focus: focus);
  }

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
  }

  @override
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
    List<RecordVersion> evidenceCategories = const [];
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
      evidenceCategories = await resolveRequiredEvidenceCategories(
        records: candidate,
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
    final inactivePolicies = inactiveUniversePolicyRules(universe, candidate);
    return PreparedValidationTask(
      operationId: id,
      proposal: proposal,
      base: base,
      candidate: candidate,
      evidenceCategories: evidenceCategories,
      approvalAuthor: current.approvalAuthor,
      restricted: restricted,
      capture: captured,
      selectedAssessment:
          restricted ||
              !candidate.any(
                (r) =>
                    !inactivePolicies.contains(r.identity.recordId) &&
                    r.payload is RuleRecord &&
                    ((r.payload as RuleRecord)
                            .requiredEvidence
                            ?.reviewMethods
                            .isNotEmpty ??
                        false),
              )
          ? null
          : await _assessmentReview(reference, current),
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
      readSelectedAssessment: (reference) =>
          _assessmentReview(reference, current, publication: true),
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
  }

  @override
  Future<void> finishValidation(
    OperationId id,
    CheckedValidation checked, {
    required bool Function(OperationId) isValidationActive,
  }) => _finishValidation(id, checked, null, isValidationActive);

  @override
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
