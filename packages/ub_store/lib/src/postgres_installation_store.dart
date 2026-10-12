import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:ub_domain/ub_domain.dart';

import 'installation_store.dart'
    show InstallationException, InstallationFailure;
import 'postgres_authority.dart';
import 'postgres_canonical_integrity.dart';
import 'postgres_export.dart';
import 'postgres_authority_schema.dart';
import 'postgres_journal.dart';
import 'postgres_kernel.dart';
import 'postgres_kernel_schema.dart';
import 'postgres_projection_recovery.dart';
import 'postgres_projection_schema.dart';
import 'postgres_schema.dart';
import 'postgres_semantic_schema.dart';
import 'postgres_values.dart';
import 'postgres_workflow_schema.dart';
import 'postgres_workflow_storage.dart';

/// Owns one connection to one installation database. Opening never creates or
/// converts authority. Setup is explicit and transactional; no live endpoint is
/// retained in diagnostics. Service callbacks own the complete transaction.
final class PostgresInstallationStore {
  PostgresInstallationStore._(this._connection, this.instanceId);
  final Connection _connection;
  final OperationId instanceId;
  bool _closed = false;
  int _active = 0;
  final _drained = Completer<void>();
  Future<void>? _shutdown;

  static Future<PostgresInstallationStore> create(
    Endpoint endpoint, {
    required ConnectionSettings settings,
  }) => _open(endpoint, settings, create: true);

  static Future<PostgresInstallationStore> openExisting(
    Endpoint endpoint, {
    required ConnectionSettings settings,
  }) => _open(endpoint, settings, create: false);

  static Future<PostgresInstallationStore> _open(
    Endpoint endpoint,
    ConnectionSettings settings, {
    required bool create,
  }) async {
    Connection? connection;
    try {
      connection = await Connection.open(endpoint, settings: settings);
      final instance = await connection.runTx(
        (tx) async {
          // Same database-local setup lock for every process, including absent
          // control rows. No runtime transaction relies on this setup lock.
          await tx.execute(
            'SELECT pg_catalog.pg_advisory_xact_lock(1430407502)',
          );
          await tx.execute('SET LOCAL search_path TO pg_catalog');
          final namespaces = await tx.execute(
            "SELECT nspname FROM pg_catalog.pg_namespace WHERE left(nspname,11)='ub_install_' ORDER BY nspname",
          );
          if (create) {
            final universes = await tx.execute(
              "SELECT nspname FROM pg_catalog.pg_namespace WHERE left(nspname,7)='ub_unv_' LIMIT 1",
            );
            if (namespaces.isNotEmpty || universes.isNotEmpty) {
              throw const InstallationException(
                InstallationFailure.incompatibleSchema,
              );
            }
            final id = OperationId.generate();
            for (final sql in postgresAuthoritySchema(id)) {
              await tx.execute(sql);
            }
            return id;
          }
          if (namespaces.isEmpty) {
            throw const InstallationException(
              InstallationFailure.identityNotInitialized,
            );
          }
          if (namespaces.length != 1) {
            throw const InstallationException(
              InstallationFailure.incompatibleSchema,
            );
          }
          final name = namespaces.single.single as String;
          final id = OperationId.parse(name.substring(11));
          final schema = postgresAuthorityNamespace(id);
          final rows = await tx.execute(
            'SELECT instance_id,normalization,schema_version FROM $schema.authority WHERE singleton=1 FOR UPDATE',
          );
          if (rows.length != 1 ||
              rows.single[0] != id.value ||
              rows.single[1] != selectorNormalizationVersion ||
              rows.single[2] != 1) {
            throw const InstallationException(
              InstallationFailure.incompatibleSchema,
            );
          }
          // Refuse incomplete control layouts before serving any profile. These
          // reads never repair or migrate a partially restored installation.
          for (final entry in const {
            'profiles': 'id,hash,author,revoked',
            'catalog': 'id,name,schema_name',
            'aliases': 'key,universe',
            'grants': 'profile,universe,worlds_state,propose,edit,protected,entities_state,predicates_state,continuities_state,expires_at,delegated_commit,allow_shared',
            'grant_worlds': 'profile,universe,ordinal,world',
            'grant_entities': 'profile,universe,ordinal,entity',
            'grant_predicates': 'profile,universe,ordinal,predicate',
            'grant_continuities': 'profile,universe,ordinal,continuity',
            'audit': 'sequence,actor,action,target',
          }.entries) {
            await tx.execute(
              'SELECT ${entry.value} FROM $schema.${entry.key} LIMIT 0',
            );
          }
          return id;
        },
        settings: TransactionSettings(
          isolationLevel: IsolationLevel.readCommitted,
        ),
      );
      return PostgresInstallationStore._(connection, instance);
    } on Object catch (error) {
      try {
        await connection?.close();
      } on Object {
        // Preserve only fixed diagnostics even if cleanup fails.
      }
      if (error is InstallationException) rethrow;
      if (error is FormatException ||
          (error is ServerException &&
              const {'42P01', '42703'}.contains(error.code))) {
        throw const InstallationException(
          InstallationFailure.incompatibleSchema,
        );
      }
      throw const InstallationException(InstallationFailure.unavailable);
    }
  }

  /// Installation authority is locked before any universe work. Errors escape
  /// the callback and roll back all writes; success returns only after COMMIT.
  Future<T> transaction<T>(
    Future<T> Function(PostgresInstallationSession) action,
  ) async {
    if (_closed) {
      throw const InstallationException(InstallationFailure.unavailable);
    }
    _active++;
    try {
      late PostgresInstallationSession session;
      final result = await _connection.runTx(
        (tx) async {
          await tx.execute('SET LOCAL search_path TO pg_catalog');
          session = PostgresInstallationSession._(tx, instanceId);
          await session.authority.lockAuthority();
          return action(session);
        },
        settings: TransactionSettings(
          isolationLevel: IsolationLevel.readCommitted,
        ),
      );
      for (final notify in session._afterCommit) {
        notify();
      }
      return result;
    } finally {
      _active--;
      if (_closed && _active == 0 && !_drained.isCompleted) {
        _drained.complete();
      }
    }
  }

  Future<void> close() => _shutdown ??= _close();

  Future<void> _close() async {
    _closed = true;
    if (_active != 0) await _drained.future;
    try {
      await _connection.close();
    } on Object {
      throw const InstallationException(InstallationFailure.unavailable);
    }
  }

  @override
  String toString() => 'PostgresInstallationStore(${instanceId.value})';
}

/// Internal service transaction access. These primitives do not replace exact
/// approval or footprint admission by the service and expose no connection.
final class PostgresInstallationSession {
  PostgresInstallationSession._(this._tx, OperationId instance)
    : authority = PostgresInstallationAuthority(_tx, instance);
  final TxSession _tx;
  final PostgresInstallationAuthority authority;
  final _afterCommit = <void Function()>[];

  /// Trusted worker notifications occur after outer COMMIT, never on rollback.
  /// A notification failure cannot undo already-durable operation state.
  void afterCommit(void Function() notify) => _afterCommit.add(notify);

  /// Completion may catch a failed evidence append and retain terminal failure
  /// in the same outer transaction. Discard partial rows and clear failed SQL
  /// state before that fallback; never commit the outer transaction here.
  Future<T> rollbackOnFailure<T>(Future<T> Function() action) async {
    final notifications = _afterCommit.length;
    final name = 'ub_completion_${OperationId.generate().value}';
    await _tx.execute('SAVEPOINT $name');
    try {
      return await action();
    } on Object {
      await _tx.execute('ROLLBACK TO SAVEPOINT $name');
      _afterCommit.removeRange(notifications, _afterCommit.length);
      rethrow;
    } finally {
      await _tx.execute('RELEASE SAVEPOINT $name');
    }
  }

  /// Verify retained author data before atomically replacing disposable indexes.
  Future<void> recoverUniverse(UniverseId universe) async {
    await PostgresCanonicalIntegrity(_tx, universe).verify();
    await recovery(universe).rebuild();
  }

  /// Retention-safe collection removes only reconstructible snapshot caches.
  /// PostgreSQL owns physical vacuuming outside the service transaction.
  Future<CanonicalObject> maintainUniverse(
    UniverseId universe, {
    required bool collect,
  }) async {
    await verifyUniverse(universe);
    final schema = postgresUniverseSchema(universe);
    Future<int> count(String table) async =>
        (await _tx.execute('SELECT count(*) FROM $schema.$table')).single.single
            as int;
    final versions = await count('record_versions');
    final revisions = await count('commits');
    final receipts = await count('operation_receipts');
    final workflows = await count('workflow_index');
    final sources = await count('source_content');
    final caches = await count('snapshot_membership');
    if (collect) {
      await _tx.execute('DELETE FROM $schema.snapshot_member');
      await _tx.execute('DELETE FROM $schema.snapshot_membership');
      await verifyUniverse(universe);
    }
    return CanonicalObject([
      MapEntry('retention_policy', CanonicalString('retain-all-history-v1')),
      MapEntry(
        'retained_record_versions',
        CanonicalNumber(versions.toString()),
      ),
      MapEntry('retained_revisions', CanonicalNumber(revisions.toString())),
      MapEntry(
        'retained_commit_receipts',
        CanonicalNumber(receipts.toString()),
      ),
      MapEntry(
        'retained_workflow_entries',
        CanonicalNumber(workflows.toString()),
      ),
      MapEntry('retained_source_assets', CanonicalNumber(sources.toString())),
      MapEntry('eligible_snapshot_caches', CanonicalNumber(caches.toString())),
      MapEntry(
        'collected_snapshot_caches',
        CanonicalNumber((collect ? caches : 0).toString()),
      ),
      const MapEntry('source_assets_collected', CanonicalNumber('0')),
      MapEntry(
        'backup_pins',
        CanonicalString(
          'retained source bytes are never collected; back up separately',
        ),
      ),
      const MapEntry('canonical', CanonicalBool(false)),
    ]);
  }

  Future<CanonicalObject> exportUniverse(
    UniverseId universe,
    String destination, {
    Iterable<RecordId> recordIds = const [],
    bool completeHistory = false,
  }) => PostgresLogicalExport(
    _tx,
    universe,
  ).export(destination, recordIds: recordIds, completeHistory: completeHistory);

  Future<void> verifyUniverse(UniverseId universe, {bool complete = false}) =>
      complete
      ? PostgresCanonicalIntegrity(_tx, universe).verifyComplete()
      : PostgresCanonicalIntegrity(_tx, universe).verify();

  PostgresKernel kernel(UniverseId universe) => PostgresKernel(_tx, universe);
  PostgresWorkflowStorage workflows(UniverseId universe) =>
      PostgresWorkflowStorage(_tx, universe);
  PostgresProjectionRecovery recovery(UniverseId universe) =>
      PostgresProjectionRecovery(_tx, universe);

  /// Catalog, schemas and genesis become visible together, or not at all.
  Future<RevisionId> createUniverse({
    required ProfileId actor,
    required UniverseId universe,
    required String name,
    required ContinuityId continuity,
    required PrincipalId principal,
  }) async {
    await authority.requireAuthor(actor);
    selectorKey(name);
    await _tx.execute('CREATE SCHEMA ${postgresUniverseSchema(universe)}');
    for (final sql in [
      ...postgresBodySchema(universe),
      ...postgresKernelSchema(universe),
      ...postgresSemanticSchema(universe),
      ...postgresWorkflowSchema(universe),
      ...postgresProjectionSchema(universe),
    ]) {
      await _tx.execute(sql);
    }
    final genesis = await PostgresJournal(
      _tx,
      universe,
    ).initialize(name, continuity, principal);
    await authority.registerUniverse(
      actor: actor,
      universe: universe,
      name: name,
    );
    return genesis;
  }
}
