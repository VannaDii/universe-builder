import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'writing_binding.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);
RecordId? resolveWritingContext(List<RecordVersion> rows, String name) {
  final matches = [
    for (final row in rows)
      if (row.payload case final RepresentedContextRecord context)
        if (row.identity.recordId.value == name ||
            context.labels.values.contains(name) ||
            context.kind is AuthoredContext &&
                (context.kind as AuthoredContext).label == name)
          row.identity.recordId,
  ];
  return matches.length == 1 ? matches.single : null;
}

/// New contexts are explicit structure, not inherited truth. Parents, narrator
/// identities and clocks must already exist in the admitted pinned rows.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> unchanged,
  List<String> clarifications,
})
compileWritingContexts({
  required Frame frame,
  required List<RecordVersion> rows,
  required List<WritingStoryContext> declarations,
  Set<WorldId>? worldScope,
}) {
  final operations = <DomainOperation>[],
      additions = <String>[],
      unchanged = <String>[],
      clarifications = <String>[];
  final introduced = <String>{};
  for (final declaration in declarations) {
    try {
      if (!_nonWhitespace.hasMatch(declaration.name)) {
        throw const FormatException('Name the authored context explicitly.');
      }
      final existing = resolveWritingContext(rows, declaration.name);
      if (existing != null) {
        if (declaration.kind == StoryContextKind.narrator) {
          if (declaration.narrator == null) {
            throw const FormatException(
              'Select the existing narrator explicitly.',
            );
          }
          final holder =
              resolveWritingObject(rows, declaration.narrator!, frame) ??
              (throw const FormatException(
                'Select one existing narrator identity.',
              ));
          if (!rows.any(
            (r) =>
                r.identity.recordId == existing &&
                r.payload is RepresentedContextRecord &&
                (r.payload as RepresentedContextRecord).kind
                    is NarratorContext &&
                ((r.payload as RepresentedContextRecord).kind
                            as NarratorContext)
                        .narrator
                        .record ==
                    holder,
          )) {
            throw const FormatException(
              'This context has another authored kind or narrator; declaration does not revise it.',
            );
          }
        }
        unchanged.add('Existing context: ${declaration.name}');
        continue;
      }
      if (rows.any(
        (r) =>
            r.payload is RepresentedContextRecord &&
            ((r.payload as RepresentedContextRecord).labels.values.contains(
                  declaration.name,
                ) ||
                (r.payload as RepresentedContextRecord).kind
                        is AuthoredContext &&
                    ((r.payload as RepresentedContextRecord).kind
                                as AuthoredContext)
                            .label ==
                        declaration.name),
      )) {
        throw const FormatException(
          'Select one accessible authored context; this name is ambiguous.',
        );
      }
      if (!declaration.introduce || worldScope != null) {
        throw const FormatException(
          'Select an accessible context or explicitly introduce it with universe-wide authoring access.',
        );
      }
      if (!introduced.add(declaration.name)) {
        throw const FormatException('Declare each new context once per delta.');
      }
      final parent =
          resolveWritingContext(rows, declaration.parent) ??
          (throw const FormatException(
            'Select one accessible parent context explicitly.',
          ));
      final calendars = rows
          .where(
            (r) =>
                r.payload is CalendarRecord &&
                ((r.payload as CalendarRecord).key == declaration.calendar ||
                    (r.payload as CalendarRecord).labels.values.contains(
                      declaration.calendar,
                    )),
          )
          .toList();
      if (calendars.length != 1) {
        throw const FormatException(
          'Select one accessible authored calendar explicitly.',
        );
      }
      final calendar = CalendarId.fromRecordId(
        calendars.single.identity.recordId,
      );
      final clocks = [
        for (final row in rows)
          if (row.payload case RepresentedContextRecord(:final chronology))
            if (chronology != null && chronology.calendar == calendar)
              chronology,
      ];
      if (clocks.isEmpty) {
        throw const FormatException(
          'This calendar has no authored clock system; declare it before creating a timed context.',
        );
      }
      final clock = clocks.first;
      if (clocks.any(
        (other) =>
            other.system.toWire().toText() != clock.system.toWire().toText(),
      )) {
        throw const FormatException(
          'The selected calendar has conflicting authored clock systems.',
        );
      }
      final time = clock.coordinate(declaration.storyTime);
      final chronology = Chronology(
        calendar: calendar,
        system: clock.system,
        firstInteraction: time,
        current: time,
      );
      chronology.validate();
      final RepresentedContextKind kind;
      if (declaration.kind == StoryContextKind.narrator) {
        if (declaration.narrator == null) {
          throw const FormatException(
            'Select an existing narrator entity explicitly.',
          );
        }
        final narrator =
            resolveWritingObject(rows, declaration.narrator!, frame) ??
            (throw const FormatException(
              'Select one accessible existing narrator entity.',
            ));
        kind = NarratorContext(
          RecordRef(universe: frame.universe, record: narrator),
        );
      } else {
        if (declaration.narrator != null) {
          throw const FormatException(
            'Narrator identity applies only to narrator contexts.',
          );
        }
        kind = AuthoredContext(
          '${declaration.kind.wireName}: ${declaration.name}',
        );
      }
      operations.add(
        RecordNarrativeReferenceOperation(
          clientRef: RecordId.generate().value,
          record: RecordKind.representedContext,
          payload: RepresentedContextRecord(
            universe: frame.universe,
            kind: kind,
            parent: RecordRef(universe: frame.universe, record: parent),
            chronology: chronology,
            labels: {'en': declaration.name},
          ),
        ),
      );
      additions.add(
        'New authored context: ${declaration.name} (parent ${declaration.parent}; explicit time ${declaration.storyTime}). Publish and open it before adding local facts.',
      );
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
  }
  return (
    operations: List.unmodifiable(operations),
    additions: List.unmodifiable(additions),
    unchanged: List.unmodifiable(unchanged),
    clarifications: List.unmodifiable(clarifications),
  );
}
