import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';

String quoteIdentifier(String name) => '"${name.replaceAll('"', '""')}"';

/// Internal codec for the normative schema. The caller owns the transaction;
/// body, version, membership, head and receipt will share that transaction.
final class RelationalCodec {
  RelationalCodec(this.database);
  final Database database;
  final catalog = BodyCatalog.instance;

  Object? put(String name, CanonicalValue value) {
    if (database.autocommit) {
      throw StateError('Relational writes require an owned transaction');
    }
    if (!catalog.fits(name, value)) {
      throw FormatException('Value does not match $name contract');
    }
    return _write(name, value);
  }

  Object? _write(String name, CanonicalValue value) {
    final m = catalog.model(name);
    if (m.scalar) {
      return switch (value) {
        CanonicalNull() => null,
        CanonicalBool(:final value) => value ? 1 : 0,
        CanonicalString(:final value) => value,
        CanonicalNumber(:final digits) => digits,
        _ => throw const FormatException('Invalid scalar'),
      };
    }
    final columns = <String>[];
    final values = <Object?>[];
    switch (m.kind) {
      case 'object':
      case 'tuple':
        final fields = value is CanonicalObject
            ? objectFields(value)
            : <String, CanonicalValue>{};
        for (final entry in m.fields.entries) {
          final key = entry.key;
          final v = value is CanonicalArray
              ? value.items[int.parse(key)]
              : fields[key];
          final state = v == null ? 0 : (v is CanonicalNull ? 1 : 2);
          columns.addAll([
            quoteIdentifier('${key}__state'),
            quoteIdentifier(key),
          ]);
          values.addAll([
            state,
            state == 2 ? _write(entry.value.model, v!) : null,
          ]);
        }
      case 'union':
        final branch = m.variants.indexWhere((v) => catalog.fits(v, value));
        if (branch < 0) throw const FormatException('No matching branch');
        columns.addAll(['variant', 'v$branch']);
        values.addAll([branch, _write(m.variants[branch], value)]);
      case 'array':
      case 'map':
        break;
      default:
        throw const FormatException('Invalid row contract');
    }
    final table = quoteIdentifier(m.table);
    database.execute(
      columns.isEmpty
          ? 'INSERT INTO $table DEFAULT VALUES'
          : 'INSERT INTO $table (${columns.join(',')}) VALUES (${List.filled(values.length, '?').join(',')})',
      values,
    );
    final row = database.lastInsertRowId;
    if (m.kind == 'array' || m.kind == 'map') {
      final sql =
          'INSERT INTO ${quoteIdentifier('${m.table}_items')} VALUES (?,?,?)';
      if (value is CanonicalArray) {
        for (var i = 0; i < value.items.length; i++) {
          final child = _write(m.item!, value.items[i]);
          database.execute(sql, [row, i, child]);
        }
      } else if (value is CanonicalObject) {
        for (final entry in value.fields) {
          final child = _write(m.item!, entry.value);
          database.execute(sql, [row, entry.key, child]);
        }
      }
    }
    return row;
  }

  CanonicalValue get(String name, Object? reference) {
    final value = _read(name, reference, <(String, int)>{});
    if (!catalog.fits(name, value)) {
      throw const FormatException('Stored value violates closed contract');
    }
    return value;
  }

  CanonicalValue _read(
    String name,
    Object? reference,
    Set<(String, int)> trail,
  ) {
    final m = catalog.model(name);
    if (m.scalar) {
      return switch ((m.kind, reference)) {
        ('null', null) => const CanonicalNull(),
        ('boolean', 0) => const CanonicalBool(false),
        ('boolean', 1) => const CanonicalBool(true),
        ('string', String text) => CanonicalString(text),
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
      final rows = database.select(
        'SELECT * FROM ${quoteIdentifier(m.table)} WHERE __row_id=?',
        [reference],
      );
      if (rows.length != 1) throw const FormatException('Missing body row');
      final row = rows.single;
      switch (m.kind) {
        case 'object':
        case 'tuple':
          final fields = <String, CanonicalValue>{};
          for (final entry in m.fields.entries) {
            final key = entry.key;
            final state = row['${key}__state'];
            final ref = row[key];
            if (state == 0 && !entry.value.required && ref == null) continue;
            if (state == 1 &&
                ref == null &&
                catalog.fits(entry.value.model, const CanonicalNull())) {
              fields[key] = const CanonicalNull();
            } else if (state == 2 && ref != null) {
              fields[key] = _read(entry.value.model, ref, trail);
            } else {
              throw const FormatException('Invalid stored field state');
            }
          }
          return m.kind == 'object'
              ? CanonicalObject(fields.entries)
              : CanonicalArray(
                  List.generate(
                    m.fields.length,
                    (i) =>
                        fields['$i'] ??
                        (throw const FormatException('Missing tuple element')),
                  ),
                );
        case 'union':
          final branch = row['variant'];
          if (branch is! int || branch < 0 || branch >= m.variants.length) {
            throw const FormatException('Invalid stored branch');
          }
          for (var i = 0; i < m.variants.length; i++) {
            if (i != branch && row['v$i'] != null) {
              throw const FormatException('Multiple stored branches');
            }
          }
          return _read(m.variants[branch], row['v$branch'], trail);
        case 'array':
        case 'map':
          final key = m.kind == 'array' ? 'ordinal' : 'name';
          final rows = database.select(
            'SELECT $key,item FROM ${quoteIdentifier('${m.table}_items')} WHERE owner=? ORDER BY $key',
            [reference],
          );
          final array = <CanonicalValue>[];
          final map = <MapEntry<String, CanonicalValue>>[];
          for (var i = 0; i < rows.length; i++) {
            final row = rows[i];
            final value = _read(m.item!, row['item'], trail);
            if (m.kind == 'array') {
              if (row[key] != i) {
                throw const FormatException('Noncontiguous collection');
              }
              array.add(value);
            } else {
              if (row[key] is! String) {
                throw const FormatException('Invalid map key');
              }
              map.add(MapEntry(row[key] as String, value));
            }
          }
          return m.kind == 'array'
              ? CanonicalArray(array)
              : CanonicalObject(map);
        default:
          throw const FormatException('Invalid stored row contract');
      }
    } finally {
      trail.remove(marker);
    }
  }
}
