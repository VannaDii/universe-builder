import 'dart:async';
import 'dart:isolate';

import 'package:ub_contracts/ub_contracts.dart';

import 'validation_binding.dart';
import 'validation_task.dart';

/// Native execution of frozen inputs only. The owning service retains results
/// and cancellation; isolate completion never establishes durable success.
final class ValidationEvaluationWorker {
  ValidationEvaluationWorker(PreparedValidationTask task) {
    _port.listen((message) {
      if (_result.isCompleted) return;
      if (message is CheckedValidation) {
        _complete(message);
      } else {
        _fail(
          StateError(
            message == null
                ? 'Validation worker exited without a result'
                : 'Validation worker failed: $message',
          ),
        );
      }
    });
    unawaited(_spawn(task));
  }
  final _port = ReceivePort();
  final _result = Completer<CheckedValidation>();
  final _spawned = Completer<void>();
  Isolate? _isolate;
  Future<CheckedValidation> get result => _result.future;

  /// Resolves after spawn admission and any cancellation during admission.
  Future<void> get ready => _spawned.future;

  Future<void> _spawn(PreparedValidationTask task) async {
    try {
      final isolate = await Isolate.spawn(
        _evaluate,
        (task, _port.sendPort),
        onError: _port.sendPort,
        onExit: _port.sendPort,
        errorsAreFatal: true,
        debugName: 'universe-builder-validation',
      );
      _isolate = isolate;
      if (_result.isCompleted) isolate.kill(priority: Isolate.immediate);
    } on Object catch (error, stack) {
      _fail(error, stack);
    } finally {
      _spawned.complete();
    }
  }

  static void _evaluate((PreparedValidationTask, SendPort) input) {
    final (task, port) = input;
    port.send(task.evaluate());
  }

  void _complete(CheckedValidation checked) {
    if (_result.isCompleted) return;
    _result.complete(checked);
    _port.close();
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (_result.isCompleted) return;
    _result.completeError(error, stack);
    _port.close();
    _isolate?.kill(priority: Isolate.immediate);
  }

  /// Called after the owner's durable cancellation, or on runtime shutdown.
  /// Synchronous evaluation cannot receive event-loop cancellation messages.
  void cancel() =>
      _fail(const UnsupportedSemanticsError(message: 'validation cancelled'));
}
