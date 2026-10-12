import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

/// Resolve exactly one authored unit from already admitted, visible rows.
/// Matching a name never implies a conversion or creates a definition.
UnitId resolveWritingUnit(List<RecordVersion> rows, String name) {
  final matches = <RecordId>[];
  for (final row in rows) {
    if (row.payload case UnitRecord(:final key, :final symbol, :final labels)) {
      if (key == name || symbol == name || labels.values.contains(name)) {
        matches.add(row.identity.recordId);
      }
    }
  }
  if (matches.length != 1) {
    throw FormatException(
      "Which exact authored unit is '$name'? Research the visible unit names; ambiguity or absence cannot imply conversion.",
    );
  }
  return UnitId.fromRecordId(matches.single);
}

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);

/// Compile the unit portion of a writer delta. The caller must combine all
/// portions and resolve clarifications before proposing any operation.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> unchanged,
  List<String> clarifications,
})
compileWritingUnits(List<WritingUnit> declarations, List<RecordVersion> rows) {
  final operations = <DomainOperation>[];
  final additions = <String>[],
      unchanged = <String>[],
      clarifications = <String>[];
  final names = <String>{};
  for (final declaration in declarations) {
    if (!_nonWhitespace.hasMatch(declaration.name) ||
        !_nonWhitespace.hasMatch(declaration.dimension) ||
        !_nonWhitespace.hasMatch(declaration.symbol) ||
        !names.add(declaration.name)) {
      clarifications.add(
        'Unit name, explicit dimension and symbol must be nonempty and unique in this delta.',
      );
      continue;
    }
    final existing = <UnitRecord>[];
    for (final row in rows) {
      if (row.payload case final UnitRecord unit) {
        if (unit.key == declaration.name ||
            unit.labels.values.contains(declaration.name)) {
          existing.add(unit);
        }
      }
    }
    if (declaration.introduce && existing.isEmpty) {
      operations.add(
        DefineUnitOperation(
          clientRef: RecordId.generate().value,
          record: UnitRecord(
            namespace: 'authoring',
            key: declaration.name,
            dimension: declaration.dimension,
            symbol: declaration.symbol,
            labels: {},
            validity: const UnspecifiedValidity(),
          ),
        ),
      );
      additions.add(
        'Explicit unit: ${declaration.name}; dimension ${declaration.dimension}; symbol ${declaration.symbol}; no conversion declared. Use private contract review.',
      );
    } else if (!declaration.introduce &&
        existing.length == 1 &&
        existing.single.dimension == declaration.dimension &&
        existing.single.symbol == declaration.symbol) {
      unchanged.add('Authored unit: ${declaration.name}');
    } else {
      clarifications.add(
        "Resolve existing unit '${declaration.name}' or revise it explicitly; no duplicate or conversion is inferred.",
      );
    }
  }
  return (
    operations: List.unmodifiable(operations),
    additions: List.unmodifiable(additions),
    unchanged: List.unmodifiable(unchanged),
    clarifications: List.unmodifiable(clarifications),
  );
}
