import 'package:ub_domain/ub_domain.dart';

import 'validation_binding.dart';
import 'validation_task.dart';

/// The native scheduler runs evaluation; each backend owns database work.
abstract interface class ValidationJobService {
  UniverseId get universe;
  Future<PreparedValidationTask?> prepareValidation(
    OperationId id, {
    required bool Function(OperationId) isValidationActive,
  });
  Future<void> finishValidation(
    OperationId id,
    CheckedValidation checked, {
    required bool Function(OperationId) isValidationActive,
  });
  Future<void> failValidation(
    OperationId id,
    Object error, {
    required bool Function(OperationId) isValidationActive,
  });
}

/// PostgreSQL jobs hold connection-owned guards across frozen evaluation.
/// Losing the connection releases ownership without manufacturing a result.
abstract interface class ValidationJobOwnership {
  Future<bool> acquireValidation(OperationId id);
  Future<void> releaseValidation(OperationId id);
}
