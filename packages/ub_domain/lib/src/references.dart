import 'canonical.dart';
import 'ids.dart';

/// An omitted universe exists only while resolving a wire request. Namespace
/// expansion cannot authorize access or redirect a conflicting reference.
final class RecordRef {
  const RecordRef({this.universe, required this.record});
  final UniverseId? universe;
  final RecordId record;

  factory RecordRef.fromCanonical(CanonicalValue value) {
    final fields = _fields(value, {'universe', 'record'});
    return RecordRef(
      universe: _universe(fields),
      record: RecordId.parse(_requiredString(fields, 'record')),
    );
  }

  RecordRef resolveNamespace(UniverseId requested) {
    if (universe != null && universe != requested) {
      throw FormatException('Cross-universe record reference: $record');
    }
    return RecordRef(universe: requested, record: record);
  }

  CanonicalObject toCanonical() => CanonicalObject([
    if (universe != null)
      MapEntry('universe', CanonicalString(universe!.value)),
    MapEntry('record', CanonicalString(record.value)),
  ]);

  @override
  bool operator ==(Object other) =>
      other is RecordRef &&
      universe == other.universe &&
      record == other.record;
  @override
  int get hashCode => Object.hash(universe, record);
}

/// Pins an immutable version, rather than resolving through a snapshot's
/// record membership. The reference kinds are deliberately separate types.
final class VersionRef {
  const VersionRef({
    this.universe,
    required this.record,
    required this.version,
  });
  final UniverseId? universe;
  final RecordId record;
  final RecordVersionId version;

  factory VersionRef.fromCanonical(CanonicalValue value) {
    final fields = _fields(value, {'universe', 'record', 'version'});
    return VersionRef(
      universe: _universe(fields),
      record: RecordId.parse(_requiredString(fields, 'record')),
      version: RecordVersionId.parse(_requiredString(fields, 'version')),
    );
  }

  CanonicalObject toCanonical() => CanonicalObject([
    if (universe != null)
      MapEntry('universe', CanonicalString(universe!.value)),
    MapEntry('record', CanonicalString(record.value)),
    MapEntry('version', CanonicalString(version.value)),
  ]);

  @override
  bool operator ==(Object other) =>
      other is VersionRef &&
      universe == other.universe &&
      record == other.record &&
      version == other.version;
  @override
  int get hashCode => Object.hash(universe, record, version);
}

final class LocalRef {
  const LocalRef(this.clientRef);
  final String clientRef;
  factory LocalRef.fromCanonical(CanonicalValue value) =>
      LocalRef(_requiredString(_fields(value, {'clientRef'}), 'clientRef'));
  CanonicalObject toCanonical() =>
      CanonicalObject([MapEntry('clientRef', CanonicalString(clientRef))]);
}

Map<String, CanonicalValue> _fields(CanonicalValue value, Set<String> allowed) {
  if (value is! CanonicalObject) {
    throw const FormatException('Expected reference object');
  }
  final fields = {for (final entry in value.fields) entry.key: entry.value};
  if (fields.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Unknown reference field');
  }
  return fields;
}

String _requiredString(Map<String, CanonicalValue> fields, String key) {
  final value = fields[key];
  if (value is! CanonicalString) {
    throw FormatException('Expected string field: $key');
  }
  return value.value;
}

UniverseId? _universe(Map<String, CanonicalValue> fields) {
  // serde Option accepts both omitted and explicit null on input; output
  // always omits the missing namespace rather than serializing null.
  if (!fields.containsKey('universe') || fields['universe'] is CanonicalNull) {
    return null;
  }
  return UniverseId.parse(_requiredString(fields, 'universe'));
}
