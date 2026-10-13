import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'temporal_validity_draft.dart';

QualifierInput qualifierInput(String key, DomainValue value) {
  if (value is SpatialValue) {
    return switch (value.spatial) {
      SpatialLink(:final relation, :final target) => QualifierInput(
        key: key,
        kind: 'spatial_${relation.wireName}',
        value: target.record.value,
        universe: target.universe?.value ?? '',
        originalKey: key,
      ),
      SpatialCoordinates(:final reference, :final values) => QualifierInput(
        key: key,
        kind: 'spatial_coordinates',
        value: reference,
        children: [
          for (var i = 0; i < values.length; i++)
            qualifierInput(i.toString(), values[i]),
        ],
        originalKey: key,
      ),
      SpatialDistance(:final from, :final value, :final unit) => QualifierInput(
        key: key,
        kind: 'spatial_distance',
        value: from.record.value,
        universe: from.universe?.value ?? '',
        unit: unit.value,
        lower: qualifierInput('amount', value),
        originalKey: key,
      ),
      UnspecifiedSpace() => QualifierInput(
        key: key,
        kind: 'spatial_unspecified',
        originalKey: key,
      ),
    };
  }
  if (value is TemporalValue) {
    return QualifierInput(
      key: key,
      kind: 'temporal',
      originalKey: key,
      temporal: temporalValidityInput(InstantValidity(value.temporal)),
    );
  }
  if (value is RangeValue) {
    return QualifierInput(
      key: key,
      kind: 'range',
      originalKey: key,
      unit: value.unit?.value ?? '',
      lower: qualifierInput('lower', value.lower),
      upper: qualifierInput('upper', value.upper),
      lowerInclusive: value.lowerInclusive.toString(),
      upperInclusive: value.upperInclusive.toString(),
    );
  }
  if (value is ReferenceValue) {
    return QualifierInput(
      key: key,
      kind: value.kind.wireName,
      value: value.record.record.value,
      universe: value.record.universe?.value ?? '',
      originalKey: key,
    );
  }
  if (value is EnumValue) {
    return QualifierInput(
      key: key,
      kind: 'enum',
      definition: value.definition.value,
      value: value.key,
      originalKey: key,
    );
  }
  if (value is SequenceValue || value is SetValue || value is StructuredValue) {
    return QualifierInput(
      key: key,
      kind: value is SequenceValue
          ? 'sequence'
          : value is SetValue
          ? 'set'
          : 'structured',
      definition: value is StructuredValue ? value.definition.value : '',
      originalKey: key,
      children: [
        for (final entry in qualifierChildren(value).entries)
          qualifierInput(entry.key, entry.value),
      ],
    );
  }
  final unit = value is QuantityValue ? value.unit.value : '';
  final amount = value is QuantityValue ? value.value : value;
  final (kind, text, denominator) = switch (amount) {
    TextValue(:final text) => ('text', text, '1'),
    BooleanValue(:final value) => ('boolean', value.toString(), '1'),
    IntegerValue(:final digits) => ('integer', digits, '1'),
    DecimalValue(:final digits) => ('decimal', digits, '1'),
    RationalValue(:final numerator, :final denominator) => (
      'rational',
      numerator,
      denominator,
    ),
    _ => ('retain', '', '1'),
  };
  return QualifierInput(
    key: key,
    kind: kind,
    value: text,
    denominator: denominator,
    unit: unit,
    originalKey: key,
  );
}

Map<String, DomainValue> buildQualifiers(
  List<QualifierInput> input,
  Map<String, DomainValue> original,
) {
  final result = <String, DomainValue>{};
  for (final row in input) {
    if (row.key.trim().isEmpty) {
      throw const FormatException('Enter each qualifier’s name.');
    }
    if (result.containsKey(row.key)) {
      throw const FormatException('Qualifier names must be distinct.');
    }
    result[row.key] = buildQualifierValue(row, original[row.originalKey]);
  }
  return result;
}

Map<String, DomainValue> qualifierChildren(DomainValue? value) =>
    switch (value) {
      SequenceValue(:final items) || SetValue(:final items) => {
        for (var i = 0; i < items.length; i++) i.toString(): items[i],
      },
      StructuredValue(:final fields) => fields,
      SpatialValue(spatial: SpatialCoordinates(:final values)) => {
        for (var i = 0; i < values.length; i++) i.toString(): values[i],
      },
      _ => {},
    };

DomainValue buildQualifierValue(QualifierInput row, DomainValue? original) {
  if (row.kind == 'retain') {
    final value = original;
    if (value == null) {
      throw const FormatException(
        'The original qualifier is unavailable. Reopen current fields.',
      );
    }
    return value;
  }
  final sources = qualifierChildren(original);
  final amount = switch (row.kind) {
    'spatial_coordinates' => SpatialValue(
      SpatialCoordinates(
        row.value,
        row.children.map((c) => buildQualifierValue(c, sources[c.originalKey])),
      ),
    ),
    'spatial_distance' => _buildDistance(row, original),
    'spatial_contained_in' ||
    'spatial_adjacent_to' ||
    'spatial_connected_to' => SpatialValue(
      SpatialLink(
        SpatialRelation.values.singleWhere(
          (r) => 'spatial_${r.wireName}' == row.kind,
        ),
        RecordRef(
          universe: row.universe.isEmpty
              ? null
              : UniverseId.parse(row.universe),
          record: RecordId.parse(row.value),
        ),
      ),
    ),
    'spatial_unspecified' => const SpatialValue(UnspecifiedSpace()),
    'temporal' => _buildTemporal(
      row,
      original is TemporalValue ? original : null,
    ),
    'range' => _buildRange(row, original is RangeValue ? original : null),
    'sequence' => SequenceValue(
      row.children.map((c) => buildQualifierValue(c, sources[c.originalKey])),
    ),
    'set' => SetValue(
      row.children.map((c) => buildQualifierValue(c, sources[c.originalKey])),
    ),
    'structured' => StructuredValue(
      ValueDefinitionId.parse(row.definition),
      buildQualifiers(row.children, sources),
    ),
    'entity_ref' || 'record_ref' || 'proposition_ref' => ReferenceValue(
      ValueReferenceKind.parse(row.kind),
      RecordRef(
        universe: row.universe.isEmpty ? null : UniverseId.parse(row.universe),
        record: RecordId.parse(row.value),
      ),
    ),
    'enum' => EnumValue(ValueDefinitionId.parse(row.definition), row.value),
    'text' => TextValue(row.value),
    'boolean' => BooleanValue(switch (row.value) {
      'true' => true,
      'false' => false,
      _ => throw const FormatException(
        'Choose true or false for each boolean qualifier.',
      ),
    }),
    'integer' => IntegerValue(row.value),
    'decimal' => DecimalValue(row.value),
    'rational' => RationalValue(row.value, row.denominator),
    _ => throw const FormatException('Choose a qualifier value type.'),
  };
  final value =
      row.unit.isEmpty || row.kind == 'range' || row.kind == 'spatial_distance'
      ? amount
      : QuantityValue(amount, UnitId.parse(row.unit));
  value.validate();
  return value;
}

RangeValue _buildRange(QualifierInput row, RangeValue? original) {
  if (row.lower == null || row.upper == null) {
    throw const FormatException('Enter both range bounds.');
  }
  bool included(String input) => switch (input) {
    'true' => true,
    'false' => false,
    _ => throw const FormatException(
      'Choose whether each range bound is included.',
    ),
  };
  return RangeValue(
    lower: buildQualifierValue(row.lower!, original?.lower),
    upper: buildQualifierValue(row.upper!, original?.upper),
    lowerInclusive: included(row.lowerInclusive),
    upperInclusive: included(row.upperInclusive),
    unit: row.unit.isEmpty ? null : UnitId.parse(row.unit),
  );
}

TemporalValue _buildTemporal(QualifierInput row, TemporalValue? original) {
  final input = row.temporal;
  if (input == null || !input.kind.startsWith('instant')) {
    throw const FormatException('Choose a temporal expression.');
  }
  final validity = buildTemporalValidity(
    input,
    original == null ? null : InstantValidity(original.temporal),
  );
  return TemporalValue((validity as InstantValidity).at);
}

SpatialValue _buildDistance(QualifierInput row, DomainValue? original) {
  if (row.lower == null) {
    throw const FormatException('Enter a distance amount.');
  }
  final source = original is SpatialValue && original.spatial is SpatialDistance
      ? (original.spatial as SpatialDistance).value
      : null;
  return SpatialValue(
    SpatialDistance(
      RecordRef(
        universe: row.universe.isEmpty ? null : UniverseId.parse(row.universe),
        record: RecordId.parse(row.value),
      ),
      buildQualifierValue(row.lower!, source),
      UnitId.parse(row.unit),
    ),
  );
}
