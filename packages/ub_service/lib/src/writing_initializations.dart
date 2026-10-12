import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'writing_binding.dart';
import 'writing_candidate.dart';
import 'writing_connected.dart';

/// Sources and existing starts must be approved at [base]. The canonical
/// initialization compiler checks provenance, ancestry, scope and batch duplicates.
/// Durable once-only receipts remain enforced by service admission and storage.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> clarifications,
})
compileWritingInitializations({
  required Frame frame,
  required List<RecordVersion> base,
  required CheckChangesRequest input,
  List<DomainOperation> priorOperations = const [],
  Set<WorldId>? worldScope,
}) {
  final operations = List<DomainOperation>.of(priorOperations),
      additions = <String>[],
      clarifications = <String>[];
  if (input.initializations.isEmpty) {
    return (
      operations: const <DomainOperation>[],
      additions: const <String>[],
      clarifications: const <String>[],
    );
  }
  final rows = compileWritingCandidate(
    universe: frame.universe,
    revision: frame.revision,
    base: base,
    operations: operations,
  );
  for (final request in input.initializations) {
    try {
      final instance =
          resolveWritingObject(rows, request.instance, frame) ??
          (throw FormatException(
            "Which exact instance is '${request.instance}' ?",
          ));
      if (request.initialValueHandles.isEmpty) {
        throw const FormatException(
          'Select an approved initial-value source for this instance start.',
        );
      }
      if (request.scope == 'unspecified') {
        throw const FormatException(
          'What authored jurisdiction applies to this instance start?',
        );
      }
      final scope = Scope(
        context: frame.context,
        applicability: bindWritingApplicability(
          rows,
          request.scope,
          worldScope: worldScope,
        ),
      );
      final additionsForStart = <DomainOperation>[];
      final RecordId start;
      final EventRecord event;
      switch (request.start) {
        case WritingExistingInstanceStart(:final handle):
          final found = base
              .where((r) => r.identity.recordId.value == handle)
              .toList();
          if (found.isEmpty) {
            throw const FormatException(
              'Retrieve the pinned occurred-event handle for the explicit instance start.',
            );
          }
          final payload = found.first.payload;
          if (payload is! EventRecord) {
            throw const FormatException(
              'Instance start handle must select an occurred event.',
            );
          }
          start = found.first.identity.recordId;
          event = payload;
        case WritingOccurredInstanceStart(event: final declaration):
          final partial = compileConnectedWriting(
            frame: frame,
            base: rows,
            input: CheckChangesRequest(
              universe: input.universe,
              contextId: input.contextId,
              events: [declaration],
            ),
          );
          if (partial.clarifications.isNotEmpty) {
            throw FormatException(partial.clarifications.join('; '));
          }
          additionsForStart.addAll(partial.operations);
          final selected = partial.operations
              .whereType<RecordEventOperation>()
              .first;
          start = RecordId.parse(selected.clientRef);
          event = selected.record;
      }
      final time = event.time;
      if (time is! ExactTime) {
        throw const FormatException(
          'An exact authored instance-start time is required.',
        );
      }
      final end = switch (request.lifetime) {
        FactUntilChangedLifetime() => const UnboundedBound(),
        FactUntilLifetime(:final endTick) => ExactBound(endTick),
        FactUnspecifiedLifetime() => throw const FormatException(
          'What explicit interval or until_changed lifetime applies to initialized values?',
        ),
      };
      final validity = CalendarIntervalValidity(
        time.calendar,
        ExactBound(time.value),
        end,
      );
      for (final handle in request.initialValueHandles) {
        final found = base
            .where((r) => r.recordVersionId.value == handle)
            .toList();
        if (found.isEmpty) {
          throw const FormatException(
            'Publish and retrieve the approved initial-value definition before initialization.',
          );
        }
        final source = found.first;
        if (source.payload is! AssertionRecord ||
            (source.payload as AssertionRecord).attributeMode !=
                AttributeMode.initialValue) {
          throw const FormatException(
            'Selected source is not an approved initial-value definition.',
          );
        }
        additionsForStart.add(
          InitializeInstanceOperation(
            clientRef: RecordId.generate().value,
            instance: RecordRef(universe: frame.universe, record: instance),
            start: RecordRef(universe: frame.universe, record: start),
            definition: VersionRef(
              universe: frame.universe,
              record: source.identity.recordId,
              version: source.recordVersionId,
            ),
            scope: scope,
            validity: validity,
          ),
        );
      }
      compileWritingCandidate(
        universe: frame.universe,
        revision: frame.revision,
        base: base,
        operations: [...operations, ...additionsForStart],
      );
      operations.addAll(additionsForStart);
      additions.add(
        'Explicit instance start and selected initialization: ${request.instance}',
      );
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    } on ProtocolError catch (error) {
      clarifications.add(
        WireFields(error.toWire(), {
              'code',
              'field',
              'message',
              'expected',
              'actual',
            }).optional('message', (value) => wireString(value)) ??
            error.code,
      );
    }
  }
  return (
    operations: List.unmodifiable(operations.skip(priorOperations.length)),
    additions: List.unmodifiable(additions),
    clarifications: List.unmodifiable(clarifications),
  );
}
