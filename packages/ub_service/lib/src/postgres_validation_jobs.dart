import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/postgres_installation.dart';

import 'installation_authority.dart';
import 'postgres_validation.dart';
import 'validation_binding.dart';
import 'validation_job_service.dart';
import 'validation_task.dart';

/// Scheduler bridge for an authenticated principal. No transaction/session
/// survives evaluation; both preparation and completion recheck current rights.
final class PostgresValidationJobs
    implements ValidationJobService, ValidationJobOwnership {
  PostgresValidationJobs({
    required this.store,
    required this.universe,
    required this.principal,
    this.epochSeconds,
  });
  final PostgresInstallationStore store;
  @override
  final UniverseId universe;
  final InstallationPrincipal principal;
  final BigInt Function()? epochSeconds;

  @override
  Future<bool> acquireValidation(OperationId id) =>
      store.acquireValidation(universe, id);

  @override
  Future<void> releaseValidation(OperationId id) =>
      store.releaseValidation(universe, id);

  Future<T> _run<T>(Future<T> Function(PostgresValidationWorkflow) action) =>
      store.transaction(
        (session) => action(
          PostgresValidationWorkflow(
            session: session,
            universe: universe,
            authority: PostgresServiceAuthority(
              session.authority,
              epochSeconds: epochSeconds,
            ),
            principal: principal,
            epochSeconds: epochSeconds,
          ),
        ),
      );

  @override
  Future<PreparedValidationTask?> prepareValidation(
    OperationId id, {
    required bool Function(OperationId) isValidationActive,
  }) => _run(
    (w) => w.prepareValidation(id, isValidationActive: isValidationActive),
  );

  @override
  Future<void> finishValidation(
    OperationId id,
    CheckedValidation checked, {
    required bool Function(OperationId) isValidationActive,
  }) => _run(
    (w) =>
        w.finishValidation(id, checked, isValidationActive: isValidationActive),
  );

  @override
  Future<void> failValidation(
    OperationId id,
    Object error, {
    required bool Function(OperationId) isValidationActive,
  }) => _run(
    (w) => w.failValidation(id, error, isValidationActive: isValidationActive),
  );
}
