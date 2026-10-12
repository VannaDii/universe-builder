import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'writing_units.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);

PersistenceSemantics _persistence(PlainPersistence value) => switch (value) {
  PlainPersistence.unspecified => PersistenceSemantics.unspecified,
  PlainPersistence.untilChanged => PersistenceSemantics.persistentUntilChanged,
  PlainPersistence.explicitInterval => PersistenceSemantics.explicitInterval,
};

List<(RecordVersion, PropertyRecord)> _properties(
  List<RecordVersion> rows,
  String name,
) => [
  for (final row in rows)
    if (row.payload case final PropertyRecord property)
      if (property.key == name || property.labels.values.contains(name))
        (row, property),
];

/// Compile declared property settings against admitted pinned rows. Unit rows
/// may include earlier candidate unit definitions. No proposal is persisted.
({
  List<DomainOperation> operations,
  Map<String, (RecordId, PropertyRecord)> properties,
  List<String> additions,
  List<String> unchanged,
  List<String> clarifications,
})
compileWritingProperties({
  required UniverseId universe,
  required List<RecordVersion> rows,
  required List<WritingProperty> declarations,
  required List<WritingPropertyCorrection> corrections,
}) {
  final operations = <DomainOperation>[];
  final properties = <String, (RecordId, PropertyRecord)>{};
  final additions = <String>[],
      unchanged = <String>[],
      clarifications = <String>[];
  for (final declaration in declarations) {
    if (!_nonWhitespace.hasMatch(declaration.name)) {
      throw const InvalidArgumentError(
        field: 'properties.name',
        message: 'nonempty property name required',
      );
    }
    if (declaration.unit != null &&
        declaration.valueType != PlainPropertyType.quantity) {
      clarifications.add(
        "Property '${declaration.name}' supplies a unit without explicitly declaring quantity values.",
      );
      continue;
    }
    final ValueShape shape;
    switch (declaration.valueType) {
      case PlainPropertyType.text:
        shape = const SimpleValueShape(SimpleShapeKind.text);
      case PlainPropertyType.boolean:
        shape = const SimpleValueShape(SimpleShapeKind.boolean);
      case PlainPropertyType.integer:
        shape = const SimpleValueShape(SimpleShapeKind.integer);
      case PlainPropertyType.decimal:
        shape = const SimpleValueShape(SimpleShapeKind.decimal);
      case PlainPropertyType.object:
        shape = EntityRefShape([]);
      case PlainPropertyType.quantity:
        final name = declaration.unit;
        if (name == null) {
          clarifications.add(
            "What authored unit applies to quantity property '${declaration.name}' ?",
          );
          continue;
        }
        try {
          shape = QuantityShape(resolveWritingUnit(rows, name));
        } on FormatException catch (error) {
          clarifications.add(error.message.toString());
          continue;
        }
    }
    final definition = PropertyRecord(
      namespace: 'authoring',
      key: declaration.name,
      labels: {},
      value: shape,
      multiplicity: declaration.singleValue
          ? Multiplicity.single
          : Multiplicity.multiple,
      persistence: _persistence(declaration.persistence),
      exclusive: false,
      symmetric: false,
      transitive: false,
    );
    final found = _properties(rows, declaration.name);
    if (declaration.introduce &&
        found.isEmpty &&
        !properties.containsKey(declaration.name)) {
      final id = RecordId.generate();
      operations.add(
        DefinePropertyOperation(clientRef: id.value, record: definition),
      );
      properties[declaration.name] = (id, definition);
      additions.add(
        'New property: ${declaration.name} (${declaration.singleValue ? 'single' : 'multiple'} values)',
      );
    } else if (!declaration.introduce &&
        found.length == 1 &&
        found.single.$2.value == definition.value &&
        found.single.$2.multiplicity == definition.multiplicity &&
        found.single.$2.persistence == definition.persistence) {
      properties[declaration.name] = (
        found.single.$1.identity.recordId,
        found.single.$2,
      );
      unchanged.add('Property definition: ${declaration.name}');
    } else {
      clarifications.add(
        "Resolve property '${declaration.name}' or explicitly revise its existing definition; this declaration cannot duplicate or change it.",
      );
    }
  }
  for (final patch in corrections) {
    if (!_nonWhitespace.hasMatch(patch.reason) ||
        (patch.singleValue == null && patch.persistence == null)) {
      clarifications.add(
        'Specify the property settings to correct and a reason; omitted settings stay unchanged.',
      );
      continue;
    }
    final found = _properties(rows, patch.name);
    if (found.length != 1) {
      clarifications.add("Which exact authored property is '${patch.name}'?");
      continue;
    }
    final (original, definition) = found.single;
    final replacement = PropertyRecord(
      namespace: definition.namespace,
      key: definition.key,
      labels: definition.labels,
      subjectTypes: definition.subjectTypes,
      value: definition.value,
      multiplicity: patch.singleValue == null
          ? definition.multiplicity
          : patch.singleValue!
          ? Multiplicity.single
          : Multiplicity.multiple,
      persistence: patch.persistence == null
          ? definition.persistence
          : _persistence(patch.persistence!),
      unitDimension: definition.unitDimension,
      inverse: definition.inverse,
      exclusive: definition.exclusive,
      symmetric: definition.symmetric,
      transitive: definition.transitive,
    );
    final id = original.identity.recordId;
    for (final name in [
      definition.key,
      ...definition.labels.values,
      patch.name,
    ]) {
      properties[name] = (id, replacement);
    }
    operations.add(
      ReviseDefinitionOperation(
        record: RecordRef(universe: universe, record: id),
        expectedVersion: original.recordVersionId,
        replacement: replacement,
      ),
    );
    additions.add('Property rule correction: ${patch.name} — ${patch.reason}');
  }
  return (
    operations: List.unmodifiable(operations),
    properties: Map.unmodifiable(properties),
    additions: List.unmodifiable(additions),
    unchanged: List.unmodifiable(unchanged),
    clarifications: List.unmodifiable(clarifications),
  );
}
