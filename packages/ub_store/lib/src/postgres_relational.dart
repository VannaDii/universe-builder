import 'dart:typed_data';

import 'package:postgres/postgres.dart';
import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'postgres_schema.dart';
import 'postgres_values.dart';

/// Internal typed codec, usable only within a driver's owned transaction.
/// Row pointers remain storage details and never participate in domain digests.
final class PostgresRelationalCodec {
  PostgresRelationalCodec(this._session, UniverseId universe)
    : _schema = postgresUniverseSchema(universe);
  final TxSession _session;
  final String _schema;
  final _catalog = BodyCatalog.instance;
  String _table(String name) => '$_schema.${postgresIdentifier(name)}';

  Future<Object?> put(String name, CanonicalValue value) async {
    if (!_catalog.fits(name, value)) {
      throw FormatException('Value does not match $name contract');
    }
    return _write(name, value);
  }

  Future<Object?> _write(String name, CanonicalValue value) async {
    final model = _catalog.model(name);
    if (model.scalar) {
      return switch (value) {
        CanonicalNull() => null,
        CanonicalBool(:final value) => value,
        CanonicalString(:final value) => postgresAuthoredText(value),
        CanonicalNumber(:final digits) => digits,
        _ => throw const FormatException('Invalid scalar'),
      };
    }
    final columns = <String>[], values = <Object?>[];
    if (model.kind == 'object' || model.kind == 'tuple') {
      final fields = value is CanonicalObject
          ? objectFields(value)
          : <String, CanonicalValue>{};
      for (final entry in model.fields.entries) {
        final child = value is CanonicalArray
            ? value.items[int.parse(entry.key)]
            : fields[entry.key];
        final state = child == null ? 0 : (child is CanonicalNull ? 1 : 2);
        columns.addAll([
          postgresIdentifier('${entry.key}__state'),
          postgresIdentifier(entry.key),
        ]);
        values.addAll([
          state,
          state == 2 ? await _write(entry.value.model, child!) : null,
        ]);
      }
    } else if (model.kind == 'union') {
      final branch = model.variants.indexWhere((v) => _catalog.fits(v, value));
      if (branch < 0) throw const FormatException('No matching branch');
      columns.addAll(['variant', 'v$branch']);
      values.addAll([branch, await _write(model.variants[branch], value)]);
    }
    final result = await _session.execute(
      columns.isEmpty
          ? 'INSERT INTO ${_table(model.table)} DEFAULT VALUES RETURNING __row_id'
          : 'INSERT INTO ${_table(model.table)} (${columns.join(',')}) VALUES '
                '(${List.generate(values.length, (i) => '\$${i + 1}').join(',')}) RETURNING __row_id',
      parameters: values,
    );
    final row = result.single.single as int;
    if (model.kind == 'array' || model.kind == 'map') {
      final entries = value is CanonicalArray
          ? [
              for (var i = 0; i < value.items.length; i++)
                MapEntry<Object, CanonicalValue>(i, value.items[i]),
            ]
          : [
              for (final entry in (value as CanonicalObject).fields)
                MapEntry<Object, CanonicalValue>(
                  postgresAuthoredText(entry.key),
                  entry.value,
                ),
            ];
      for (final entry in entries) {
        await _session.execute(
          'INSERT INTO ${_table('${model.table}_items')} (owner,${model.kind == 'array' ? 'ordinal' : 'name'},item) VALUES (\$1,\$2,\$3)',
          parameters: [row, entry.key, await _write(model.item!, entry.value)],
        );
      }
    }
    return row;
  }

  Future<CanonicalValue> get(String name, Object? reference) async {
    final value = await _read(name, reference, <(String, int)>{});
    if (!_catalog.fits(name, value)) {
      throw const FormatException('Stored value violates closed contract');
    }
    return value;
  }

  Future<CanonicalValue> _read(
    String name,
    Object? reference,
    Set<(String, int)> trail,
  ) async {
    final model = _catalog.model(name);
    if (model.scalar) {
      return switch ((model.kind, reference)) {
        ('null', null) => const CanonicalNull(),
        ('boolean', bool value) => CanonicalBool(value),
        ('string', Uint8List bytes) => CanonicalString(
          readPostgresAuthoredText(bytes),
        ),
        ('integer', String text) => CanonicalValue.parseJson(text),
        _ => throw const FormatException('Stored scalar type'),
      };
    }
    if (reference is! int) throw const FormatException('Stored row pointer');
    final marker = (name, reference);
    if (trail.length >= maxBodyDepth || !trail.add(marker)) {
      throw const FormatException('Cyclic or excessive body nesting');
    }
    try {
      final rows = await _session.execute(
        'SELECT * FROM ${_table(model.table)} WHERE __row_id=\$1',
        parameters: [reference],
      );
      if (rows.length != 1) throw const FormatException('Missing body row');
      final row = rows.single.toColumnMap();
      if (model.kind == 'object' || model.kind == 'tuple') {
        final fields = <String, CanonicalValue>{};
        for (final entry in model.fields.entries) {
          final state = row['${entry.key}__state'], ref = row[entry.key];
          if (state == 0 && !entry.value.required && ref == null) continue;
          if (state == 1 &&
              ref == null &&
              _catalog.fits(entry.value.model, const CanonicalNull())) {
            fields[entry.key] = const CanonicalNull();
          } else if (state == 2 && ref != null) {
            fields[entry.key] = await _read(entry.value.model, ref, trail);
          } else {
            throw const FormatException('Invalid stored field state');
          }
        }
        return model.kind == 'object'
            ? CanonicalObject(fields.entries)
            : CanonicalArray(
                List.generate(
                  model.fields.length,
                  (i) =>
                      fields['$i'] ??
                      (throw const FormatException('Missing tuple element')),
                ),
              );
      }
      if (model.kind == 'union') {
        final branch = row['variant'];
        if (branch is! int || branch < 0 || branch >= model.variants.length) {
          throw const FormatException('Invalid stored branch');
        }
        for (var i = 0; i < model.variants.length; i++) {
          if (i != branch && row['v$i'] != null) {
            throw const FormatException('Multiple stored branches');
          }
        }
        return await _read(model.variants[branch], row['v$branch'], trail);
      }
      if (model.kind == 'array' || model.kind == 'map') {
        final key = model.kind == 'array' ? 'ordinal' : 'name';
        final rows = await _session.execute(
          'SELECT $key,item FROM ${_table('${model.table}_items')} WHERE owner=\$1 ORDER BY $key',
          parameters: [reference],
        );
        final array = <CanonicalValue>[],
            map = <MapEntry<String, CanonicalValue>>[];
        for (var i = 0; i < rows.length; i++) {
          final row = rows[i].toColumnMap();
          final value = await _read(model.item!, row['item'], trail);
          if (model.kind == 'array') {
            if (row[key] != i) {
              throw const FormatException('Noncontiguous collection');
            }
            array.add(value);
          } else {
            if (row[key] is! Uint8List) {
              throw const FormatException('Invalid map key');
            }
            map.add(
              MapEntry(readPostgresAuthoredText(row[key] as Uint8List), value),
            );
          }
        }
        return model.kind == 'array'
            ? CanonicalArray(array)
            : CanonicalObject(map);
      }
      throw const FormatException('Invalid stored row contract');
    } finally {
      trail.remove(marker);
    }
  }
}
