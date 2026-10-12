import 'dart:async';
import 'dart:io';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/ub_store.dart'
    show CommitInput, Assignment, StoredVersion;

import 'installation_authority.dart';
import 'runtime_admission.dart';
import 'sqlite_validation.dart';
import 'validation_scheduler.dart';

/// Native engine ownership. Run the service in the engine process or the mobile
/// service isolate, keeping native database work away from the Flutter renderer.
/// The installation authority remains owned by the caller until close completes.
final class NativeSqliteRuntime {
  NativeSqliteRuntime({required this.authority});
  final InstallationAuthority authority;
  final OperationId instance = OperationId.generate();
  final _admission = NativeRuntimeAdmission();
  final _scheduler = NativeValidationScheduler();
  final _packages = <UniverseId, OwnedSqliteDatabase>{};
  final _connections = <NativeSqliteConnection>{};
  final _active = <Completer<void>>{};
  bool _stopping = false;
  Future<void>? _shutdown;

  NativeSqliteConnection connect(EngineHello hello) {
    if (_stopping) throw StateError('Runtime is stopping');
    final principal = authority.authenticateHello(hello);
    final connection = NativeSqliteConnection._(
      this,
      principal,
      _admission.connect(principal),
    );
    _connections.add(connection);
    return connection;
  }

  Future<CanonicalValue> _execute(
    InstallationPrincipal principal,
    EngineRequest request,
  ) async {
    if (_stopping) throw StateError('Runtime is stopping');
    final finished = Completer<void>();
    _active.add(finished);
    try {
      if (request is DoctorEngineRequest) return await _doctor(principal);
      if (request is PreviewImportEngineRequest ||
          request is AcceptImportEngineRequest) {
        return await authority.coordinate(
          principal,
          () => _import(principal, request),
        );
      }
      if (request is RestoreEngineRequest) {
        return await authority.coordinate(
          principal,
          () => _restore(principal, request),
        );
      }
      if (request is PreviewPurgeEngineRequest ||
          request is PurgeEngineRequest) {
        return await authority.coordinate(
          principal,
          () => _purge(principal, request),
        );
      }
      if (request
          case StatusEngineRequest() ||
              ProfilesEngineRequest() ||
              EnrollEngineRequest() ||
              GrantEngineRequest() ||
              RevokeEngineRequest() ||
              WithdrawGrantEngineRequest() ||
              RenameUniverseEngineRequest() ||
              ShutdownEngineRequest() ||
              CreateUniverseEngineRequest() ||
              RegisterUniverseEngineRequest()) {
        final result = await authority.coordinate(
          principal,
          () => _installation(principal, request),
        );
        // Close begins without awaiting this request's own active token. Its
        // acknowledgement can return while shutdown drains admitted work.
        if (request is ShutdownEngineRequest) close().ignore();
        return result;
      }
      final package = await authority.coordinate(principal, () {
        if (request is! ToolEngineRequest) authority.requireAuthor(principal);
        if (request case ToolEngineRequest(:final request)) request.validate();
        final selector = switch (request) {
          ToolEngineRequest(:final request) => request.universe,
          LibraryEngineRequest(:final universe) => universe,
          MaintainEngineRequest(:final universe) => universe,
          BackupEngineRequest(:final universe) => universe,
          ExportLogicalEngineRequest(:final universe) => universe,
          LoadDraftEngineRequest(:final universe) ||
          SaveDraftEngineRequest(:final universe) => universe,
          StageImageEngineRequest(:final universe) ||
          ImagePreviewEngineRequest(:final universe) => universe,
          ForkContinuityEngineRequest(:final universe) ||
          CompareContinuitiesEngineRequest(:final universe) ||
          PrepareAdoptionEngineRequest(:final universe) => universe,
          AuthorWritingEngineRequest(:final universe) ||
          StageSourceEngineRequest(:final universe) ||
          ReviewEngineRequest(:final universe) ||
          ApproveEngineRequest(:final universe) => universe,
          _ => throw const InvalidArgumentError(
            field: 'method',
            message:
                'requires a universe tool or private writing engine request',
          ),
        };
        return _openPackage(principal, selector);
      });
      // Execution rechecks current authority after recovery/admission. No caller
      // acquires raw database access or inherits rights from a cached worker.
      final workflow = SqliteValidationWorkflow(
        package: package,
        authority: authority,
        principal: principal,
      );
      if (request is LibraryEngineRequest) {
        return await workflow.libraryRequest(request);
      }
      if (request is MaintainEngineRequest) {
        return await workflow.maintainRequest(request);
      }
      if (request is BackupEngineRequest) {
        return await workflow.backupRequest(request);
      }
      if (request is ExportLogicalEngineRequest) {
        return await workflow.exportRequest(request);
      }
      if (request is ForkContinuityEngineRequest ||
          request is CompareContinuitiesEngineRequest ||
          request is PrepareAdoptionEngineRequest) {
        return await workflow.continuityRequest(request);
      }
      if (request is StageImageEngineRequest ||
          request is ImagePreviewEngineRequest) {
        return await workflow.imageRequest(request);
      }
      if (request is LoadDraftEngineRequest ||
          request is SaveDraftEngineRequest) {
        return await workflow.draftRequest(request);
      }
      if (request case ToolEngineRequest(:final request)) {
        final response = await workflow.executeToolRequest(
          request,
          isValidationActive: (id) =>
              _scheduler.isActive(package.universeId, id),
          signalCancellation: (id) => _scheduler.cancel(package.universeId, id),
        );
        if (request is QueuedProposalValidationRequest) {
          final status = Envelope.fromWire(
            response,
            OperationStatusV3.fromWire,
          ).result;
          if (!{
            OperationState.succeeded,
            OperationState.failed,
            OperationState.cancelled,
          }.contains(status.state)) {
            // Start only after the authority section has finished. Execution
            // persists its own result; if retaining it is denied or fails, the
            // durable operation remains recoverable through polling and retry,
            // matching the existing engine's background completion behavior.
            _scheduler.schedule(workflow, status.operationId).ignore();
          }
        }
        return response;
      }
      return await workflow.executeWritingEngineRequest(
        request,
        isValidationActive: (id) => _scheduler.isActive(package.universeId, id),
      );
    } on InstallationException catch (error) {
      if (error.failure == InstallationFailure.denied) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      rethrow;
    } finally {
      _active.remove(finished);
      finished.complete();
    }
  }

  // Caller retains the current installation authority section.
  OwnedSqliteDatabase _openPackage(
    InstallationPrincipal principal,
    Selector selector,
  ) {
    final catalog = authority.resolveUniverseAlias(principal, selector.value);
    final cached = _packages[catalog.universeId];
    if (cached != null) return cached;
    _requireWorkerCapacity();
    final opened = OwnedSqliteDatabase.openExisting(catalog.path);
    try {
      if (opened.universeId != catalog.universeId) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      opened.recover();
      _packages[catalog.universeId] = opened;
      return opened;
    } on Object {
      opened.close();
      rethrow;
    }
  }

  Future<CanonicalObject> _doctor(InstallationPrincipal principal) async {
    final catalog = await authority.coordinate(principal, () {
      authority.requireAuthor(principal);
      return authority.catalog(principal);
    });
    final packages = <CanonicalValue>[];
    for (final entry in catalog) {
      packages.add(
        await authority.coordinate(principal, () {
          authority.requireAuthor(principal);
          try {
            final package = _openPackage(principal, Selector(entry.name));
            if (package.universeId != entry.universeId) {
              throw const NotFoundOrNotAccessibleError(message: 'resource');
            }
            return CanonicalObject([
              MapEntry('id', CanonicalString(entry.universeId.value)),
              MapEntry('storage', package.storageStatus()),
            ]);
          } on Object {
            return CanonicalObject([
              MapEntry('id', CanonicalString(entry.universeId.value)),
              MapEntry(
                'error',
                CanonicalString(
                  'package unavailable: check file ownership, writer lock, schema version, and integrity',
                ),
              ),
            ]);
          }
        }),
      );
    }
    return CanonicalObject([
      MapEntry('service_instance', CanonicalString(instance.value)),
      MapEntry('packages', CanonicalArray(packages)),
      MapEntry(
        'profile_storage',
        CanonicalString('installation-only protected files'),
      ),
      MapEntry(
        'recovery',
        CanonicalString('immutable history replay; atomic projection rebuild'),
      ),
      MapEntry(
        'admission',
        CanonicalObject([
          const MapEntry('connections', CanonicalNumber('32')),
          const MapEntry('requests_per_principal', CanonicalNumber('8')),
          const MapEntry('queue_per_universe', CanonicalNumber('16')),
        ]),
      ),
    ]);
  }

  CanonicalObject _import(
    InstallationPrincipal principal,
    EngineRequest request,
  ) {
    authority.requireAuthor(principal);
    if (request is PreviewImportEngineRequest) {
      final preview = authority.prepareImport(principal, request);
      return preview.report(
        authority.importConflicts(
          principal,
          id: preview.target,
          name: preview.name,
        ),
      );
    }
    final preview = authority.loadImport(
      principal,
      request as AcceptImportEngineRequest,
    );
    final receipt = preview.receipt;
    final key = 'logical-import-admission:${preview.id.value}';
    final existing = authority
        .catalog(principal)
        .where((entry) => entry.universeId == preview.target);
    if (existing.isNotEmpty) {
      final package = _openPackage(principal, Selector(existing.single.name));
      final stored = WorkflowStorage(package.database).get(key);
      if (stored?.toText() != receipt.toText()) {
        throw const PolicyDeniedError(
          message:
              'existing universe belongs to another import; choose a clone',
        );
      }
      return receipt;
    }
    if (authority
        .importConflicts(principal, id: preview.target, name: preview.name)
        .isNotEmpty) {
      throw const NameUnavailableError(
        message: 'import identity or name is reserved',
      );
    }
    _requireWorkerCapacity();
    final destination = authority.newUniversePath(principal, preview.target);
    final created =
        FileSystemEntity.typeSync(destination, followLinks: false) ==
        FileSystemEntityType.notFound;
    if (created) {
      final archive = OwnedSqliteDatabase.stageLogicalArchive(
        authority.importArchivePath(principal, preview),
        authority.universeDirectory(principal),
      );
      try {
        if (archive.digest != preview.sourceDigest) {
          throw const ApprovalStaleError();
        }
        final staged = archive.reconstruct(
          authority.universeDirectory(principal),
          target: preview.target,
          name: preview.name,
        );
        try {
          staged.package.database.execute('BEGIN IMMEDIATE');
          try {
            WorkflowStorage(staged.package.database).put(key, receipt);
            staged.package.database.execute('COMMIT');
          } on Object {
            if (!staged.package.database.autocommit) {
              staged.package.database.execute('ROLLBACK');
            }
            rethrow;
          }
          staged.package.backup(destination);
        } finally {
          staged.close();
        }
      } finally {
        archive.close();
      }
    }
    OwnedSqliteDatabase? opened;
    try {
      opened = OwnedSqliteDatabase.openExisting(destination);
      if (opened.universeId != preview.target ||
          WorkflowStorage(opened.database).get(key)?.toText() !=
              receipt.toText()) {
        throw const ApprovalStaleError();
      }
      authority.registerOpenedUniverse(
        principal,
        name: preview.name,
        package: opened,
      );
    } on Object {
      try {
        opened?.close();
      } finally {
        if (created) OwnedSqliteDatabase.removeUnregisteredPackage(destination);
      }
      rethrow;
    }
    _packages[preview.target] = opened;
    return receipt;
  }

  CanonicalObject _restore(
    InstallationPrincipal principal,
    RestoreEngineRequest request,
  ) {
    authority.requireAuthor(principal);
    _requireWorkerCapacity();
    final staged = OwnedSqliteDatabase.stageRestore(
      request.source,
      authority.universeDirectory(principal),
    );
    try {
      final id = staged.package.universeId;
      if (authority
          .importConflicts(principal, id: id, name: request.name)
          .isNotEmpty) {
        throw const NameUnavailableError(
          message: 'restore identity or name is reserved',
        );
      }
      final destination = authority.newUniversePath(principal, id);
      staged.package.backup(destination);
      OwnedSqliteDatabase? opened;
      try {
        opened = OwnedSqliteDatabase.openExisting(destination);
        if (opened.universeId != id) {
          throw const NotFoundOrNotAccessibleError(message: 'resource');
        }
        authority.registerOpenedUniverse(
          principal,
          name: request.name,
          package: opened,
        );
      } on Object {
        try {
          opened?.close();
        } finally {
          OwnedSqliteDatabase.removeUnregisteredPackage(destination);
        }
        rethrow;
      }
      _packages[id] = opened;
      return CanonicalObject([
        MapEntry('universe_id', CanonicalString(id.value)),
        MapEntry('name', CanonicalString(request.name)),
        const MapEntry('restored', CanonicalBool(true)),
      ]);
    } finally {
      staged.close();
    }
  }

  CanonicalObject _purge(
    InstallationPrincipal principal,
    EngineRequest request,
  ) {
    authority.requireAuthor(principal);
    final selector = switch (request) {
      PreviewPurgeEngineRequest(:final universe) => universe,
      PurgeEngineRequest(:final universe) => universe,
      _ => throw StateError('Expected a purge request'),
    };
    final catalog = authority.resolveUniverseAlias(principal, selector.value);
    if (request is PurgeEngineRequest &&
        request.confirmation != 'PURGE ${catalog.name}') {
      throw const FormatException(
        'type the exact purge confirmation shown in the preview',
      );
    }
    final package = _openPackage(principal, selector);
    if (request is PreviewPurgeEngineRequest) return package.purgePreview();
    final purge = request as PurgeEngineRequest;
    package.preparePurge(purge.digest);
    _scheduler.cancelUniverse(catalog.universeId);
    authority.beginPurge(principal, catalog.universeId);
    _packages.remove(catalog.universeId)?.close();
    authority.finishPurges(principal);
    return CanonicalObject([
      MapEntry('purged', CanonicalString(catalog.universeId.value)),
      const MapEntry('external_copies_removed', CanonicalBool(false)),
    ]);
  }

  CanonicalValue _installation(
    InstallationPrincipal principal,
    EngineRequest request,
  ) {
    if (request is! StatusEngineRequest) authority.requireAuthor(principal);
    switch (request) {
      case StatusEngineRequest():
        return CanonicalObject([
          MapEntry('service_instance', CanonicalString(instance.value)),
          MapEntry('principal', CanonicalString(principal.id.value)),
          MapEntry('author', CanonicalBool(principal.author)),
          MapEntry(
            'universes',
            CanonicalArray(
              authority
                  .catalog(principal)
                  .map(
                    (entry) => CanonicalObject([
                      MapEntry('id', CanonicalString(entry.universeId.value)),
                      MapEntry('name', CanonicalString(entry.name)),
                    ]),
                  ),
            ),
          ),
          MapEntry(
            'canonical_commit',
            CanonicalString('exact_approval_or_explicit_delegation'),
          ),
          MapEntry('max_requests_per_principal', CanonicalNumber('8')),
          // Global request admission is tighter than this legacy queue bound.
          MapEntry('universe_queue_capacity', CanonicalNumber('16')),
        ]);
      case ProfilesEngineRequest():
        return CanonicalObject([
          MapEntry(
            'profiles',
            CanonicalArray(
              authority
                  .profiles(principal)
                  .map(
                    (profile) => CanonicalObject([
                      MapEntry('profile_id', CanonicalString(profile.id.value)),
                      MapEntry('author', CanonicalBool(profile.author)),
                      MapEntry('revoked', CanonicalBool(profile.revoked)),
                    ]),
                  ),
            ),
          ),
          MapEntry(
            'grants',
            CanonicalArray(
              authority.grants(principal).map((grant) => grant.toWire()),
            ),
          ),
        ]);
      case EnrollEngineRequest():
        return CanonicalObject([
          MapEntry(
            'profile_id',
            CanonicalString(authority.enroll(principal).value),
          ),
        ]);
      case GrantEngineRequest(:final grant):
        authority.grant(principal, grant);
        return CanonicalObject([
          MapEntry('granted', const CanonicalBool(true)),
        ]);
      case RevokeEngineRequest(:final profileId):
        authority.revoke(principal, profileId);
        return CanonicalObject([
          MapEntry('revoked', const CanonicalBool(true)),
        ]);
      case WithdrawGrantEngineRequest(:final profileId, :final universeId):
        authority.withdrawGrant(
          principal,
          profile: profileId,
          universe: universeId,
        );
        return CanonicalObject([
          MapEntry('withdrawn', const CanonicalBool(true)),
        ]);
      case RenameUniverseEngineRequest(:final universeId, :final name):
        authority.renameUniverse(principal, id: universeId, name: name);
        return CanonicalObject([
          MapEntry('universe_id', CanonicalString(universeId.value)),
          MapEntry('name', CanonicalString(name)),
        ]);
      case ShutdownEngineRequest():
        return CanonicalObject([
          MapEntry('shutdown', CanonicalString('requested')),
        ]);
      case CreateUniverseEngineRequest():
        return _createUniverse(principal, request);
      case RegisterUniverseEngineRequest():
        _requireWorkerCapacity();
        selectorKey(request.name);
        final package = OwnedSqliteDatabase.openExisting(request.path);
        try {
          final id = authority.registerOpenedUniverse(
            principal,
            name: request.name,
            package: package,
          );
          _packages[id] = package;
          return CanonicalObject([
            MapEntry('universe_id', CanonicalString(id.value)),
            MapEntry('name', CanonicalString(request.name)),
          ]);
        } on Object {
          package.close();
          rethrow;
        }
      default:
        throw StateError('Unreachable installation request');
    }
  }

  void _requireWorkerCapacity() {
    if (_packages.length >= 32) {
      throw const EvaluationLimitReachedError(message: 'universe worker limit');
    }
  }

  CanonicalObject _createUniverse(
    InstallationPrincipal principal,
    CreateUniverseEngineRequest request,
  ) {
    _requireWorkerCapacity();
    selectorKey(request.name);
    final id = UniverseId.generate();
    final continuity = ContinuityId.generate();
    final calendar = CalendarId.generate();
    final (chronology, definition) = request.start.build(calendar);
    final actor = PrincipalId.parse(
      principal.id.value.replaceFirst('prf_', 'prn_'),
    );
    final contextId = RecordId.generate();
    final package = OwnedSqliteDatabase.create(
      authority.newUniversePath(principal, id),
    );
    try {
      final kernel = SqliteKernel(package.database, id);
      package.database.execute('BEGIN IMMEDIATE');
      try {
        kernel.journal.initialize(request.name, continuity, actor);
        package.database.execute('COMMIT');
      } on Object {
        package.database.execute('ROLLBACK');
        rethrow;
      }
      RecordVersion record(RecordId recordId, RecordPayload payload) =>
          RecordVersion.build(
            recordVersionId: RecordVersionId.generate(),
            identity: RecordIdentity(
              universeId: id,
              recordId: recordId,
              recordKind: payload.recordKind,
            ),
            payload: payload,
          );
      final records = [
        record(
          contextId,
          RepresentedContextRecord(
            universe: id,
            kind: const ObjectiveContext(),
            chronology: chronology,
            labels: {'en': 'Objective reality'},
          ),
        ),
        record(calendar.toRecordId(), definition),
      ];
      final revision = kernel.commit(
        CommitInput(
          universe: id,
          continuity: continuity,
          expectedHead: kernel.journal.head(continuity),
          principal: actor,
          decision: 'create-universe',
          reason: 'Author created objective context',
          idempotencyKey: 'create-universe',
          changes: records.map(
            (row) => Assignment(
              recordId: row.identity.recordId,
              next: StoredVersion(
                versionId: row.recordVersionId,
                identity: row.identity,
                payload: row.payload.toWire(),
                digest: row.payloadDigest,
              ),
            ),
          ),
        ),
      );
      authority.registerOpenedUniverse(
        principal,
        name: request.name,
        package: package,
      );
      _packages[id] = package;
      return CanonicalObject([
        MapEntry('universe_id', CanonicalString(id.value)),
        MapEntry('continuity_id', CanonicalString(continuity.value)),
        MapEntry('context_id', CanonicalString(contextId.value)),
        MapEntry('revision', CanonicalString(revision.value)),
        MapEntry('name', CanonicalString(request.name)),
      ]);
    } on Object {
      // Failed registration must release ownership without deleting authored
      // package data. It remains available for explicit registration/recovery.
      package.close();
      rethrow;
    }
  }

  Future<void> close() => _shutdown ??= _close();
  Future<void> _close() async {
    _stopping = true;
    for (final connection in _connections.toList()) {
      connection.close();
    }
    await Future.wait(_active.map((c) => c.future));
    try {
      await _scheduler.close();
    } finally {
      for (final package in _packages.values) {
        package.close();
      }
      _packages.clear();
    }
  }
}

/// Authenticated native connection. Credentials are consumed by the handshake;
/// current profile status and universe access are rechecked for every request.
final class NativeSqliteConnection {
  NativeSqliteConnection._(this._runtime, this._principal, this._lease);
  final NativeSqliteRuntime _runtime;
  final InstallationPrincipal _principal;
  final NativeConnectionLease _lease;
  bool _closed = false;
  EngineWelcome get welcome => EngineWelcome(
    protocolVersion: protocolVersion,
    serviceInstance: _runtime.instance.value,
    principal: _principal.id,
    author: _principal.author,
    maxFrameBytes: BigInt.from(maxFrameBytes),
    maxInFlight: BigInt.from(maxInFlight),
  );
  Future<CanonicalValue> executeWriting(EngineRequest request) =>
      execute(request);

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
