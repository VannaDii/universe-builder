import 'dart:async';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/sqlite.dart';

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

  Future<CanonicalValue> _writing(
    InstallationPrincipal principal,
    EngineRequest request,
  ) async {
    if (_stopping) throw StateError('Runtime is stopping');
    final finished = Completer<void>();
    _active.add(finished);
    try {
      final package = await authority.coordinate(principal, () {
        authority.requireAuthor(principal);
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
        final catalog = authority.resolveUniverseAlias(
          principal,
          selector.value,
        );
        final cached = _packages[catalog.universeId];
        if (cached != null) return cached;
        if (_packages.length >= 32) {
          throw const EvaluationLimitReachedError(
            message: 'universe worker limit',
          );
        }
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
      });
      // Execution rechecks current authority after recovery/admission. No caller
      // acquires raw database access or inherits rights from a cached worker.
      return await SqliteValidationWorkflow(
        package: package,
        authority: authority,
        principal: principal,
      ).executeWritingEngineRequest(
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

  Future<void> close() => _shutdown ??= _close();
  Future<void> _close() async {
    _stopping = true;
    for (final connection in _connections.toList()) {
      connection.close();
    }
    await Future.wait(_active.map((c) => c.future));
    await _scheduler.close();
    for (final package in _packages.values) {
      package.close();
    }
    _packages.clear();
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
  Future<CanonicalValue> executeWriting(EngineRequest request) {
    if (_closed) throw StateError('Connection is closed');
    return _lease.run(() => _runtime._writing(_principal, request));
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _lease.close();
    _runtime._connections.remove(this);
  }
}
