import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'writing_binding.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);
final _limit = BigInt.one << 127;
BigInt? _integer(String value) {
  if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(value)) return null;
  final n = BigInt.parse(value);
  return n >= -_limit && n < _limit ? n : null;
}

Validity _correctValidity(Validity original, WritingItemPowerCorrection patch) {
  var result = original;
  if (patch.atTick != null || patch.lifetime != null) {
    final (
      CalendarId calendar,
      TemporalBound oldStart,
      TemporalBound? oldEnd,
    ) = switch (original) {
      CalendarIntervalValidity(:final calendar, :final start, :final end) => (
        calendar,
        start,
        end,
      ),
      InstantValidity(at: ExactTime(:final calendar, :final value)) => (
        calendar,
        ExactBound(value),
        null,
      ),
      _ => throw const FormatException(
        'This grant has no supported exact authored calendar validity; use advanced authoring',
      ),
    };
    final start = patch.atTick == null ? oldStart : ExactBound(patch.atTick!);
    if (patch.lifetime != null) {
      if (start is! ExactBound) {
        throw const FormatException(
          'Supply an explicit start for this unresolved grant',
        );
      }
      result = bindWritingLifetime(
        ExactTime(calendar, start.value),
        patch.lifetime!,
      );
    } else if (oldEnd != null) {
      result = CalendarIntervalValidity(calendar, start, oldEnd);
    } else {
      result = InstantValidity(
        ExactTime(calendar, (start as ExactBound).value),
      );
    }
  }
  if (patch.endTick != null) {
    if (result is! CalendarIntervalValidity) {
      throw const FormatException(
        'Ending requires an existing authored calendar interval',
      );
    }
    final coordinate = _integer(patch.endTick!);
    if (coordinate == null) {
      throw const FormatException('Invalid signed 128-bit coordinate');
    }
    final start = result.start, end = result.end;
    if (start is ExactBound &&
            coordinate <= (_integer(start.value) ?? (_limit - BigInt.one)) ||
        end is ExactBound && coordinate > (_integer(end.value) ?? -_limit)) {
      throw const FormatException(
        'End the grant after its start and no later than its authored end',
      );
    }
    result = CalendarIntervalValidity(
      result.calendar,
      start,
      ExactBound(patch.endTick!),
    );
  }
  return result;
}

/// Compile possession-dependent grants and exhaustive sets from admitted
/// candidate rows. These declarations do not imply ownership or knowledge.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> clarifications,
})
compileWritingPowersAndSets({
  required UniverseId universe,
  required Frame frame,
  required List<RecordVersion> rows,
  required List<WritingItemPower> powers,
  required List<WritingItemPowerCorrection> corrections,
  required List<WritingExhaustiveSet> exhaustiveSets,
  Set<WorldId>? worldScope,
}) {
  final operations = <DomainOperation>[],
      additions = <String>[],
      clarifications = <String>[];
  final edited = <String>{};
  void attempt(DomainOperation Function() build, String addition) {
    try {
      operations.add(build());
      additions.add(addition);
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    } on NotFoundOrNotAccessibleError catch (error) {
      clarifications.add(error.message);
    }
  }

  for (final patch in corrections) {
    if (!edited.add(patch.grantHandle)) {
      clarifications.add('Correct each grant once in a delta');
      continue;
    }
    attempt(
      () {
        final found = rows
            .where(
              (row) =>
                  row.recordVersionId.value == patch.grantHandle &&
                  row.payload is ItemPowerRecord &&
                  (row.payload as ItemPowerRecord).scope.context ==
                      frame.context,
            )
            .toList();
        if (found.isEmpty) {
          throw const FormatException(
            'Retrieve the current pinned author-visible grant handle before correcting it',
          );
        }
        final original = found.first, old = original.payload as ItemPowerRecord;
        if (!_nonWhitespace.hasMatch(patch.reason) ||
            (patch.value == null &&
                patch.scope == null &&
                patch.atTick == null &&
                patch.lifetime == null &&
                patch.endTick == null)) {
          throw const FormatException(
            'Choose grant fields to change and explain the author correction',
          );
        }
        if (patch.endTick != null &&
            (patch.atTick != null || patch.lifetime != null)) {
          throw const FormatException(
            'Choose an explicit ending or a validity correction, not both',
          );
        }
        return ReviseItemPowerOperation(
          record: RecordRef(
            universe: universe,
            record: original.identity.recordId,
          ),
          expectedVersion: original.recordVersionId,
          rationale: patch.reason,
          replacement: ItemPowerRecord(
            item: old.item,
            holderPredicate: old.holderPredicate,
            powerPredicate: old.powerPredicate,
            value: patch.value == null
                ? old.value
                : bindWritingValue(universe, rows, frame, patch.value!),
            scope: Scope(
              context: old.scope.context,
              realm: old.scope.realm,
              applicability: patch.scope == null
                  ? old.scope.applicability
                  : bindWritingApplicability(
                      rows,
                      patch.scope!,
                      worldScope: worldScope,
                    ),
            ),
            validity: _correctValidity(old.validity, patch),
          ),
        );
      },
      'Item-power correction: ${patch.reason}; private contract review required',
    );
  }
  for (final power in powers) {
    attempt(
      () {
        final item =
            resolveWritingObject(rows, power.item, frame) ??
            (throw FormatException(
              "Which exact authored item is '${power.item}' ?",
            ));
        final (holder, definition) = resolveWritingProperty(
          rows,
          power.holderProperty,
        );
        if (definition.value is! EntityRefShape ||
            definition.multiplicity != Multiplicity.single) {
          throw const FormatException(
            'Possession requires an explicitly authored single-valued object holder property on the item; ownership relations are not possession evidence.',
          );
        }
        final (ability, _) = resolveWritingProperty(
          rows,
          power.abilityProperty,
        );
        final time = bindWritingTime(frame, rows, power.atTick);
        final scope = bindWritingApplicability(
          rows,
          power.scope,
          worldScope: worldScope,
        );
        if (scope is UnspecifiedApplicability) {
          throw const FormatException(
            'Which authored world or universe scope applies to this possession-dependent ability?',
          );
        }
        return DefineItemPowerOperation(
          clientRef: RecordId.generate().value,
          record: ItemPowerRecord(
            item: RecordRef(universe: universe, record: item),
            holderPredicate: RecordRef(
              universe: universe,
              record: holder.identity.recordId,
            ),
            powerPredicate: RecordRef(
              universe: universe,
              record: ability.identity.recordId,
            ),
            value: bindWritingValue(universe, rows, frame, power.value),
            scope: Scope(context: frame.context, applicability: scope),
            validity: bindWritingLifetime(time, power.lifetime),
          ),
        );
      },
      'Possession-dependent ability: ${power.item} grants ${power.abilityProperty}; requires private contract review.',
    );
  }
  for (final boundary in exhaustiveSets) {
    attempt(
      () {
        final subject =
            resolveWritingObject(rows, boundary.subject, frame) ??
            (throw FormatException(
              "Which exact authored object is '${boundary.subject}'?",
            ));
        final (_, property) = resolveWritingProperty(rows, boundary.property);
        if (property.value is! EntityRefShape) {
          throw const FormatException(
            'Exhaustive sets require an authored object-valued property.',
          );
        }
        if (boundary.scope == 'unspecified') {
          throw const FormatException(
            'Which authored world or universe scope applies to this exhaustive set?',
          );
        }
        final members = [
          for (final name in boundary.members)
            RecordRef(
              universe: universe,
              record:
                  resolveWritingObject(rows, name, frame) ??
                  (throw FormatException(
                    "Which exact authored member is '$name'?",
                  )),
            ),
        ];
        final time = bindWritingTime(frame, rows, boundary.atTick);
        return SetCompletenessOperation(
          clientRef: RecordId.generate().value,
          record: CompletenessRecord(
            subject: RecordRef(universe: universe, record: subject),
            predicate: '${property.namespace}:${property.key}',
            members: members,
            completeness: const ObjectiveCompleteness(),
            scope: Scope(
              context: frame.context,
              applicability: bindWritingApplicability(
                rows,
                boundary.scope,
                worldScope: worldScope,
              ),
            ),
            validity: bindWritingLifetime(time, boundary.lifetime),
          ),
        );
      },
      'Authored exhaustive set: ${boundary.subject} — ${boundary.property}; ${boundary.members.length} members; requires private contract review.',
    );
  }
  return (
    operations: List.unmodifiable(operations),
    additions: List.unmodifiable(additions),
    clarifications: List.unmodifiable(clarifications),
  );
}
