import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'sqlite_validation.dart';
import 'validation_worker.dart';

/// One scheduler per native engine. Database access remains in the owning
/// service; only frozen evaluation inputs enter a validation isolate.
final class NativeValidationScheduler {
  NativeValidationScheduler({this.capacity = 2}) {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
  }
  final int capacity;
  final _jobs = <(UniverseId, OperationId), _ValidationJob>{};
  bool _stopping = false;

  bool isActive(UniverseId universe, OperationId id) =>
      _jobs.containsKey((universe, id));

  /// Call after durable queue submission. If busy, retry the same queue key.
  /// The caller observes this future for runtime errors; queued responses need
  /// not await evaluation. Repeated scheduling returns the existing job future.
  Future<void> schedule(SqliteValidationWorkflow service, OperationId id) {
    final key = (service.universe, id);
    final existing = _jobs[key];
    if (existing != null) return existing.done;
    if (_stopping || _jobs.length >= capacity) {
      throw const EvaluationLimitReachedError(
        message: 'validation busy; retry the same key',
      );
    }
    final job = _ValidationJob();
    _jobs[key] = job;
    job.done = _run(service, id, job, key.$1);
    return job.done;
  }

  Future<void> _run(
    SqliteValidationWorkflow service,
    OperationId id,
    _ValidationJob job,
    UniverseId universe,
  ) async {
    bool active(OperationId operation) => isActive(universe, operation);
    try {
      try {
        final task = await service.prepareValidation(
          id,
          isValidationActive: active,
        );
        if (task == null || _stopping || job.retired) return;
        final worker = ValidationEvaluationWorker(task);
        job.worker = worker;
        if (job.cancelled) worker.cancel();
        final checked = await worker.result;
        if (!_stopping && !job.retired) {
          await service.finishValidation(
            id,
            checked,
            isValidationActive: active,
          );
        }
      } on Object catch (error) {
        if (!_stopping && !job.retired) {
          await service.failValidation(id, error, isValidationActive: active);
        }
      }
    } finally {
      await job.worker?.ready;
      _jobs.remove((universe, id));
    }
  }

  /// The service's cancellation route calls this after retaining its marker.
  void cancel(UniverseId universe, OperationId id) {
    final job = _jobs[(universe, id)];
    if (job == null) return;
    job.cancelled = true;
    job.worker?.cancel();
  }

  /// Confirmed package purge retires evaluation without writing terminal rows
  /// into a package whose installation authority is being removed.
  void cancelUniverse(UniverseId universe) {
    for (final entry in _jobs.entries) {
      if (entry.key.$1 != universe) continue;
      entry.value.retired = true;
      entry.value.cancelled = true;
      entry.value.worker?.cancel();
    }
  }

  /// Stop evaluation without manufacturing terminal evidence during shutdown.
  Future<void> close() async {
    _stopping = true;
    final jobs = _jobs.values.toList();
    for (final job in jobs) {
      job.cancelled = true;
      job.worker?.cancel();
    }
    await Future.wait(jobs.map((job) => job.done));
  }
}

final class _ValidationJob {
  late Future<void> done;
  ValidationEvaluationWorker? worker;
  bool cancelled = false;
  bool retired = false;
}
