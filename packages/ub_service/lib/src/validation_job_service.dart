import 'package:ub_domain/ub_domain.dart';

import 'validation_binding.dart';
import 'validation_task.dart';

/// The existing native scheduler owns liveness; each backend owns database work.
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
