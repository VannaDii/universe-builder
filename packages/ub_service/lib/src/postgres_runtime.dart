import 'dart:async';
import 'dart:io';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/ub_store.dart';

import 'installation_authority.dart';
import 'postgres_validation.dart';
import 'postgres_validation_jobs.dart';
import 'runtime_admission.dart';
import 'validation_scheduler.dart';
import 'universe_evidence_policy.dart';

/// Native PostgreSQL engine dispatch. The caller owns the installation store
/// until runtime close has drained requests and validation workers. Socket/host
/// startup remains separate; this does not advertise complete backend support.
final class NativePostgresRuntime {
  NativePostgresRuntime({
    required this.store,
    this.profileRoot,
    BigInt Function()? epochSeconds,
  }) : _epochSeconds = epochSeconds ?? _now;
  static BigInt _now() =>
      BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000);
  final BigInt Function() _epochSeconds;
  final PostgresInstallationStore store;

  /// Trusted local credential storage, supplied explicitly by the native launcher.
  /// It is not a caller path or a default derived from database endpoint data.
  final String? profileRoot;
  final _recovered = <UniverseId>{};
  final OperationId instance = OperationId.generate();
  final _admission = NativeRuntimeAdmission();
  final _scheduler = NativeValidationScheduler();
  final _connections = <NativePostgresConnection>{};
  final _active = <Completer<void>>{};
  bool _stopping = false;
  Future<void>? _shutdown;

  /// Commit the source guard before staging. Retain the complete archive in
  /// bounded installation-owned chunks before publishing a transport copy.
  Future<({String path, String digest, CanonicalObject manifest})>
  stageSourceMove(
    InstallationPrincipal principal, {
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
    required String destination,
  }) async {
    final done = _enter();
    try {
      await store.transaction(
        (s) => PostgresServiceAuthority(s.authority).quiesceUniverseForMove(
          principal,
          universe: universe,
          operation: operation,
          targetInstance: targetInstance,
        ),
      );
      await store.transaction(
        (s) => PostgresServiceAuthority(s.authority).coordinate(
          principal,
          () => s.prepareMoveArchive(
            actor: principal.id,
            universe: universe,
            operation: operation,
            targetInstance: targetInstance,
          ),
        ),
      );
      return await store.transaction(
        (s) => PostgresServiceAuthority(s.authority).coordinate(
          principal,
          () => s.writeMoveArchive(
            actor: principal.id,
            universe: universe,
            operation: operation,
            targetInstance: targetInstance,
            destination: destination,
          ),
        ),
      );
    } finally {
      _leave(done);
    }
  }

  Future<T> _coordinateMove<T>(
    InstallationPrincipal principal,
    Future<T> Function(PostgresInstallationSession) action,
  ) async {
    final done = _enter();
    try {
      return await store.transaction(
        (s) =>
            PostgresServiceAuthority(s.authority)
                .coordinate(principal, () => action(s)),
      );
    } finally {
      _leave(done);
    }
  }

  Future<InstallationMoveReview> reviewMoveTarget(
    InstallationPrincipal principal, {
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
    required InstallationImportPreview preview,
  }) => _coordinateMove(
    principal,
    (s) => s.reviewMoveTarget(
      actor: principal.id,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
      preview: preview,
    ),
  );

  Future<InstallationMoveReview> loadMoveReview(
    InstallationPrincipal principal, {
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
  }) => _coordinateMove(
    principal,
    (s) => s.loadMoveReview(
      actor: principal.id,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    ),
  );

  Future<InstallationMoveReview> beginMoveAdmission(
    InstallationPrincipal principal, {
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
  }) => _coordinateMove(
    principal,
    (s) => s.beginMoveAdmission(
      actor: principal.id,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    ),
  );

  Future<InstallationMoveReview> recordMoveAdmission(
    InstallationPrincipal principal, {
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
    required CanonicalObject receipt,
  }) => _coordinateMove(
    principal,
    (s) => s.recordMoveAdmission(
      actor: principal.id,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
      receipt: receipt,
    ),
  );

  Completer<void> _enter() {
    if (_stopping) throw StateError('Runtime is stopping');
    final done = Completer<void>();
    _active.add(done);
    return done;
  }

  void _leave(Completer<void> done) {
    _active.remove(done);
    done.complete();
  }

  Future<NativePostgresConnection> connect(EngineHello hello) async {
    final done = _enter();
    try {
      final principal = await store.transaction(
        (s) => PostgresServiceAuthority(
          s.authority,
          epochSeconds: _epochSeconds,
        ).authenticateHello(hello),
      );
      if (_stopping) throw StateError('Runtime is stopping');
      final connection = NativePostgresConnection._(
        this,
        principal,
        _admission.connect(principal),
      );
      _connections.add(connection);
      return connection;
    } finally {
      _leave(done);
    }
  }

  Future<CanonicalValue> _execute(
    InstallationPrincipal principal,
    EngineRequest request,
  ) async {
    final done = _enter();
    UniverseId? queuedUniverse;
    try {
      if (request case StageMoveEngineRequest()) {
        await _coordinateMove(
          principal,
          (s) => s.authority.requireAuthor(principal.id),
        );
        final temporary = privateTemporaryDirectory(
          Directory.systemTemp.path,
          'universe-builder-move-service-',
        );
        try {
          final stage = await stageSourceMove(
            principal,
            universe: request.universeId,
            operation: request.operationId,
            targetInstance: request.targetInstance,
            destination: '${temporary.path}/archive.sqlite',
          );
          return CanonicalObject([
            MapEntry(
              'source_instance',
              CanonicalString(principal.instanceId.value),
            ),
            MapEntry('universe_id', CanonicalString(request.universeId.value)),
            MapEntry(
              'operation_id',
              CanonicalString(request.operationId.value),
            ),
            MapEntry(
              'target_instance',
              CanonicalString(request.targetInstance.value),
            ),
            MapEntry('digest', CanonicalString(stage.digest)),
            MapEntry('manifest', stage.manifest),
            MapEntry(
              'bytes',
              CanonicalNumber('${File(stage.path).lengthSync()}'),
            ),
          ]);
        } finally {
          temporary.deleteSync(recursive: true);
        }
      }
      final response = await store.transaction((session) async {
        final authority = PostgresServiceAuthority(
          session.authority,
          epochSeconds: _epochSeconds,
        );
        return authority.coordinate(principal, () async {
          if (request is! ToolEngineRequest &&
              request is! StatusEngineRequest) {
            await authority.requireAuthor(principal);
          }
          switch (request) {
            case StatusEngineRequest():
              final catalog = await session.authority.catalog(
                principal.id,
                epochSeconds: _epochSeconds(),
              );
              return CanonicalObject([
                MapEntry(
                  'instance_id',
                  CanonicalString(principal.instanceId.value),
                ),
                MapEntry('service_instance', CanonicalString(instance.value)),
                MapEntry(
                  'universes',
                  CanonicalArray(
                    catalog.map(
                      (e) => CanonicalObject([
                        MapEntry('id', CanonicalString(e.universeId.value)),
                        MapEntry('name', CanonicalString(e.name)),
                      ]),
                    ),
                  ),
                ),
                MapEntry('backend', CanonicalString('postgres')),
                MapEntry(
                  'canonical_commit',
                  CanonicalString('exact_approval_or_explicit_delegation'),
                ),
                const MapEntry(
                  'max_requests_per_principal',
                  CanonicalNumber('8'),
                ),
                const MapEntry(
                  'universe_queue_capacity',
                  CanonicalNumber('16'),
                ),
              ]);
            case DoctorEngineRequest():
              final catalog = await session.authority.catalog(
                principal.id,
                epochSeconds: _epochSeconds(),
              );
              final packages = <CanonicalValue>[];
              for (final entry in catalog) {
                try {
                  final storage = await session.rollbackOnFailure(() async {
                    await session.recoverUniverse(entry.universeId);
                    session.afterCommit(() => _recovered.add(entry.universeId));
                    return session.kernel(entry.universeId).storageStatus();
                  });
                  packages.add(
                    CanonicalObject([
                      MapEntry('id', CanonicalString(entry.universeId.value)),
                      MapEntry('storage', storage),
                    ]),
                  );
                } on Object {
                  session.afterCommit(
                    () => _recovered.remove(entry.universeId),
                  );
                  packages.add(
                    CanonicalObject([
                      MapEntry('id', CanonicalString(entry.universeId.value)),
                      MapEntry(
                        'error',
                        CanonicalString(
                          'universe unavailable: check schema version and retained-content integrity',
                        ),
                      ),
                    ]),
                  );
                }
              }
              return CanonicalObject([
                MapEntry('service_instance', CanonicalString(instance.value)),
                MapEntry('packages', CanonicalArray(packages)),
                MapEntry(
                  'profile_storage',
                  CanonicalString('installation database authority'),
                ),
                MapEntry(
                  'recovery',
                  CanonicalString(
                    'retained-content verification; atomic projection rebuild',
                  ),
                ),
                MapEntry(
                  'admission',
                  CanonicalObject([
                    const MapEntry('connections', CanonicalNumber('32')),
                    const MapEntry(
                      'requests_per_principal',
                      CanonicalNumber('8'),
                    ),
                    const MapEntry('queue_per_universe', CanonicalNumber('16')),
                  ]),
                ),
              ]);
            case EnrollEngineRequest():
              final root = profileRoot;
              if (root == null) {
                throw const InstallationException(
                  InstallationFailure.unavailable,
                );
              }
              final id = await authority.enroll(principal, profileRoot: root);
              return CanonicalObject([
                MapEntry('profile_id', CanonicalString(id.value)),
              ]);
            case CheckImportTargetEngineRequest():
              return CanonicalArray(
                (await session.importConflicts(
                  actor: principal.id,
                  id: request.universeId,
                  name: request.name,
                )).map(CanonicalString.new),
              );
            case GetImportEngineRequest():
              return (await session.loadImport(
                actor: principal.id,
                id: request.previewId,
                digest: request.digest,
              )).toCanonical();
            case ReviewMoveEngineRequest():
              return (await session.reviewMoveTarget(
                actor: principal.id,
                universe: request.universeId,
                operation: request.operationId,
                targetInstance: request.targetInstance,
                preview: InstallationImportPreview.fromCanonical(
                  request.target,
                ),
              )).preview.toCanonical();
            case BeginMoveAdmissionEngineRequest():
              return (await session.beginMoveAdmission(
                actor: principal.id,
                universe: request.universeId,
                operation: request.operationId,
                targetInstance: request.targetInstance,
              )).acceptRequest.toWire();
            case RecordMoveAdmissionEngineRequest():
              return (await session.recordMoveAdmission(
                actor: principal.id,
                universe: request.universeId,
                operation: request.operationId,
                targetInstance: request.targetInstance,
                receipt: request.receipt,
              )).preview.receipt;
            case BeginArchiveUploadEngineRequest():
              return session.beginArchiveUpload(
                actor: principal.id,
                request: request,
              );
            case WriteArchiveChunkEngineRequest():
              return session.writeArchiveChunk(
                actor: principal.id,
                request: request,
              );
            case ReadMoveChunkEngineRequest():
              return (await session.readMoveArchiveChunk(
                actor: principal.id,
                request: request,
              )).toWire();
            case ListMovesEngineRequest():
              return session.listMoves(
                actor: principal.id,
                after: request.after,
                limit: request.limit,
              );
            case GetMoveEngineRequest():
              return session.getMove(
                actor: principal.id,
                operation: request.operationId,
              );
            case ProfilesEngineRequest():
              final profiles = await session.authority.profiles(principal.id);
              final grants = await session.authority.grants(principal.id);
              return CanonicalObject([
                MapEntry(
                  'profiles',
                  CanonicalArray(
                    profiles.map(
                      (profile) => CanonicalObject([
                        MapEntry(
                          'profile_id',
                          CanonicalString(profile.id.value),
                        ),
                        MapEntry('author', CanonicalBool(profile.author)),
                        MapEntry('revoked', CanonicalBool(profile.revoked)),
                      ]),
                    ),
                  ),
                ),
                MapEntry(
                  'grants',
                  CanonicalArray(grants.map((grant) => grant.toWire())),
                ),
              ]);
            case ReviewArchiveUploadEngineRequest():
              final preview = await session.reviewArchiveUpload(
                actor: principal.id,
                request: request,
              );
              return preview.report(
                await session.importConflicts(
                  actor: principal.id,
                  id: preview.target,
                  name: preview.name,
                ),
              );
            case PreviewImportEngineRequest():
              final preview = await session.prepareImport(
                actor: principal.id,
                source: request.source,
                name: request.name,
                mode: request.mode,
                previewId: request.previewId,
              );
              return preview.report(
                await session.importConflicts(
                  actor: principal.id,
                  id: preview.target,
                  name: preview.name,
                ),
              );
            case AcceptImportEngineRequest():
              return session.acceptImport(
                actor: principal.id,
                id: request.previewId,
                digest: request.digest,
              );
            case RegisterUniverseEngineRequest():
              final universe = await session.registerNamespace(
                actor: principal.id,
                namespace: request.path,
                name: request.name,
              );
              session.afterCommit(() => _recovered.add(universe));
              return CanonicalObject([
                MapEntry('universe_id', CanonicalString(universe.value)),
                MapEntry('name', CanonicalString(request.name)),
              ]);
            case RestoreEngineRequest():
              final universe = await session.restoreUniverse(
                actor: principal.id,
                source: request.source,
                name: request.name,
              );
              return CanonicalObject([
                MapEntry('universe_id', CanonicalString(universe.value)),
                MapEntry('name', CanonicalString(request.name)),
                const MapEntry('restored', CanonicalBool(true)),
              ]);
            case CreateUniverseEngineRequest():
              return _createUniverse(session, principal, request);
            case GrantEngineRequest(:final grant):
              await authority.putGrant(principal, grant);
              return CanonicalObject([
                const MapEntry('granted', CanonicalBool(true)),
              ]);
            case RevokeEngineRequest(:final profileId):
              await authority.revoke(principal, profileId);
              return CanonicalObject([
                const MapEntry('revoked', CanonicalBool(true)),
              ]);
            case WithdrawGrantEngineRequest(
              :final profileId,
              :final universeId,
            ):
              await authority.withdrawGrant(principal, profileId, universeId);
              return CanonicalObject([
                const MapEntry('withdrawn', CanonicalBool(true)),
              ]);
            case RenameUniverseEngineRequest(:final universeId, :final name):
              await session.authority.renameUniverse(
                actor: principal.id,
                id: universeId,
                name: name,
              );
              return CanonicalObject([
                MapEntry('universe_id', CanonicalString(universeId.value)),
                MapEntry('name', CanonicalString(name)),
              ]);
            case ShutdownEngineRequest():
              return CanonicalObject([
                MapEntry('shutdown', CanonicalString('requested')),
              ]);
            default:
              break;
          }
          final selector = switch (request) {
            ToolEngineRequest(:final request) => request.universe,
            ApproveEngineRequest(:final universe) ||
            ReviewEngineRequest(:final universe) ||
            AuthorWritingEngineRequest(:final universe) ||
            StageSourceEngineRequest(:final universe) ||
            ExportLogicalEngineRequest(:final universe) ||
            BackupEngineRequest(:final universe) ||
            MaintainEngineRequest(:final universe) ||
            PreviewPurgeEngineRequest(:final universe) ||
            PurgeEngineRequest(:final universe) ||
            ForkContinuityEngineRequest(:final universe) ||
            CompareContinuitiesEngineRequest(:final universe) ||
            PrepareAdoptionEngineRequest(:final universe) ||
            StageImageEngineRequest(:final universe) ||
            ImagePreviewEngineRequest(:final universe) ||
            ReadSourceEngineRequest(:final universe) ||
            LibraryEngineRequest(:final universe) ||
            LoadDraftEngineRequest(:final universe) ||
            SaveDraftEngineRequest(:final universe) => universe,
            _ => throw const UnsupportedSemanticsError(
              message: 'PostgreSQL request migration incomplete',
            ),
          };
          final catalog = await session.authority.resolveUniverseAlias(
            actor: principal.id,
            name: selector.value,
            epochSeconds: _epochSeconds(),
          );
          final universe = catalog.universeId;
          if (request is PurgeEngineRequest &&
              request.confirmation != 'PURGE ${catalog.name}') {
            throw const FormatException(
              'type the exact purge confirmation shown in the preview',
            );
          }
          if (!_recovered.contains(universe)) {
            await session.recoverUniverse(universe);
            session.afterCommit(() => _recovered.add(universe));
          }
          final workflow = PostgresValidationWorkflow(
            session: session,
            universe: universe,
            authority: authority,
            principal: principal,
            epochSeconds: _epochSeconds,
          );
          switch (request) {
            case ToolEngineRequest(:final request):
              final result = await workflow.executeToolRequest(
                request,
                isValidationActive: (id) => _scheduler.isActive(universe, id),
                signalCancellation: (id) => _scheduler.cancel(universe, id),
              );
              if (request is QueuedProposalValidationRequest) {
                queuedUniverse = universe;
              }
              return result;
            case ApproveEngineRequest(
              :final proposalReference,
              :final validationRun,
            ):
              return workflow.approve(proposalReference, validationRun);
            case ReviewEngineRequest(:final proposalReference):
              return workflow.review(proposalReference);
            case StageSourceEngineRequest(:final label, :final text):
              return workflow.stageSource(label: label, text: text);
            case ExportLogicalEngineRequest():
              return workflow.exportRequest(request);
            case BackupEngineRequest():
              return session.backupUniverse(universe, request.destination);
            case MaintainEngineRequest():
              return workflow.maintainRequest(request);
            case PreviewPurgeEngineRequest():
              return session.purgePreview(universe);
            case PurgeEngineRequest():
              await session.purgeUniverse(
                actor: principal.id,
                universe: universe,
                digest: request.digest,
              );
              session.afterCommit(() {
                _scheduler.cancelUniverse(universe);
                _recovered.remove(universe);
              });
              return CanonicalObject([
                MapEntry('purged', CanonicalString(universe.value)),
                const MapEntry('external_copies_removed', CanonicalBool(false)),
              ]);
            case ForkContinuityEngineRequest() ||
                CompareContinuitiesEngineRequest() ||
                PrepareAdoptionEngineRequest():
              return workflow.continuityRequest(request);
            case ReadSourceEngineRequest():
              return workflow.sourceRequest(request);
            case StageImageEngineRequest() || ImagePreviewEngineRequest():
              return workflow.imageRequest(request);
            case LibraryEngineRequest():
              return workflow.libraryRequest(request);
            case LoadDraftEngineRequest() || SaveDraftEngineRequest():
              return workflow.draftRequest(request);
            case AuthorWritingEngineRequest():
              return workflow.executeWritingEngineRequest(
                request,
                isValidationActive: (id) => _scheduler.isActive(universe, id),
              );
            default:
              throw const UnsupportedSemanticsError(
                message: 'PostgreSQL request migration incomplete',
              );
          }
        });
      });
      // Queue submission is durable before any isolate work can be scheduled.
      if (queuedUniverse case final UniverseId universe when !_stopping) {
        final status = Envelope.fromWire(
          response,
          OperationStatusV3.fromWire,
        ).result;
        if (!{
          OperationState.succeeded,
          OperationState.failed,
          OperationState.cancelled,
        }.contains(status.state)) {
          _scheduler
              .schedule(
                PostgresValidationJobs(
                  store: store,
                  universe: universe,
                  principal: principal,
                  epochSeconds: _epochSeconds,
                ),
                status.operationId,
              )
              .ignore();
        }
      }
      if (request is ShutdownEngineRequest) close().ignore();
      return response;
    } on InstallationException catch (error) {
      if (error.failure == InstallationFailure.denied) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      rethrow;
    } finally {
      _leave(done);
    }
  }

  Future<CanonicalObject> _createUniverse(
    PostgresInstallationSession session,
    InstallationPrincipal principal,
    CreateUniverseEngineRequest request,
  ) async {
    selectorKey(request.name);
    final universe = UniverseId.generate(),
        continuity = ContinuityId.generate();
    final calendar = CalendarId.generate();
    final (chronology, definition) = request.start.build(calendar);
    final actor = PrincipalId.parse(
      principal.id.value.replaceFirst('prf_', 'prn_'),
    );
    final context = RecordId.generate();
    final genesis = await session.createUniverse(
      actor: principal.id,
      universe: universe,
      name: request.name,
      continuity: continuity,
      principal: actor,
    );
    final records = [
      (
        context,
        RepresentedContextRecord(
          universe: universe,
          kind: const ObjectiveContext(),
          chronology: chronology,
          labels: {'en': 'Objective reality'},
        ) as RecordPayload,
      ),
      (calendar.toRecordId(), definition as RecordPayload),
    ];
    final evidence = initialUniversePolicyRecords(universe, request.realWorld);
    final revision = await session
        .kernel(universe)
        .commit(
          CommitInput(
            universe: universe,
            continuity: continuity,
            expectedHead: genesis,
            principal: actor,
            decision: 'create-universe',
            reason: request.realWorld
                ? 'Author created objective context with Real World root policy'
                : 'Author created objective context with scratch root policy',
            idempotencyKey: 'create-universe',
            changes: [
              for (final row in evidence)
                Assignment(
                  recordId: row.identity.recordId,
                  next: StoredVersion(
                    versionId: row.recordVersionId,
                    identity: row.identity,
                    payload: row.payload.toWire(),
                    digest: row.payloadDigest,
                  ),
                ),
              for (final (id, payload) in records)
                Assignment(
                  recordId: id,
                  next: StoredVersion.build(
                    RecordVersionId.generate(),
                    RecordIdentity(
                      universeId: universe,
                      recordId: id,
                      recordKind: payload.recordKind,
                    ),
                    payload.toWire(),
                  ),
                ),
            ],
          ),
        );
    return CanonicalObject([
      MapEntry('universe_id', CanonicalString(universe.value)),
      MapEntry('continuity_id', CanonicalString(continuity.value)),
      MapEntry('context_id', CanonicalString(context.value)),
      MapEntry('revision', CanonicalString(revision.value)),
      MapEntry('name', CanonicalString(request.name)),
    ]);
  }

  Future<void> close() => _shutdown ??= _close();
  Future<void> _close() async {
    _stopping = true;
    for (final connection in _connections.toList()) {
      connection.close();
    }
    await Future.wait(_active.map((done) => done.future));
    await _scheduler.close();
  }
}

final class NativePostgresConnection {
  NativePostgresConnection._(this._runtime, this._principal, this._lease);
  final NativePostgresRuntime _runtime;
  final InstallationPrincipal _principal;
  final NativeConnectionLease _lease;
  bool _closed = false;
  EngineWelcome get welcome => EngineWelcome(
    protocolVersion: protocolVersion,
    serviceInstance: _runtime.instance.value,
    principal: _principal.id,
    author: _principal.author,
    maxFrameBytes: BigInt.from(maxFrameBytes),
    maxInFlight: BigInt.from(engineMaxInFlight),
  );
  Future<CanonicalValue> execute(EngineRequest request) {
    if (_closed) throw StateError('Connection is closed');
    return _lease.run(() => _runtime._execute(_principal, request));
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _lease.close();
    _runtime._connections.remove(this);
  }
}
