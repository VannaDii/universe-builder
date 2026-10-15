import 'dart:typed_data';

import 'package:postgres/postgres.dart';
import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'postgres_schema.dart';
import 'postgres_values.dart';

typedef _ReadBatch = ({
  Map<(String, int), Map<String, dynamic>> rows,
  Map<(String, int), List<Map<String, dynamic>>> items,
});

final class _PendingWrite {
  _PendingWrite(this.model, this.columns, this.values, this.items, this.depth);
  final BodyModel model;
  final List<String> columns;
  final List<Object?> values;
  final List<MapEntry<Object, Object?>> items;
  final int depth;
  int? id;
}

final class _WriteBatchFull implements Exception {
  const _WriteBatchFull();
}

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

  /// Stage bounded groups of typed bodies, allocating new PostgreSQL-owned
  /// pointers. Children precede parents, so ordinary immediate FKs stay enabled.
  /// A broad valid body falls back to the original writer without a new limit.
  Future<List<Object?>> putMany(
    String name,
    List<CanonicalValue> values,
  ) async {
    if (values.length > 50) {
      throw RangeError('Body write batch exceeds 50 roots');
    }
    for (final value in values) {
      if (!_catalog.fits(name, value)) {
        throw FormatException('Value does not match $name contract');
      }
    }
    final pending = <_PendingWrite>[];
    var work = 0, bytes = 0;
    Object? scalar(CanonicalValue value) {
      final result = _scalar(value);
      if (result is Uint8List) bytes += result.length;
      if (result is String) bytes += result.length;
      if (bytes > 16 * 1024 * 1024) throw const _WriteBatchFull();
      return result;
    }

    Object? stage(String name, CanonicalValue value) {
      if (++work > 10000) throw const _WriteBatchFull();
      final model = _catalog.model(name);
      if (model.scalar) return scalar(value);
      final columns = <String>[], cells = <Object?>[];
      final items = <MapEntry<Object, Object?>>[];
      if (model.kind == 'object' || model.kind == 'tuple') {
        final fields = value is CanonicalObject
            ? objectFields(value)
            : <String, CanonicalValue>{};
        for (final entry in model.fields.entries) {
          final child = value is CanonicalArray
              ? value.items[int.parse(entry.key)]
              : fields[entry.key];
          final state = child == null
              ? 0
              : child is CanonicalNull
              ? 1
              : 2;
          columns.addAll(['${entry.key}__state', entry.key]);
          cells.addAll([
            state,
            state == 2 ? stage(entry.value.model, child!) : null,
          ]);
        }
      } else if (model.kind == 'union') {
        final branch = model.variants.indexWhere(
          (v) => _catalog.fits(v, value),
        );
        if (branch < 0) throw const FormatException('No matching branch');
        columns.addAll([
          'variant',
          for (var i = 0; i < model.variants.length; i++) 'v$i',
        ]);
        cells.addAll([
          branch,
          for (var i = 0; i < model.variants.length; i++)
            i == branch ? stage(model.variants[i], value) : null,
        ]);
      } else if (model.kind == 'array') {
        final array = value as CanonicalArray;
        for (var i = 0; i < array.items.length; i++) {
          items.add(MapEntry(i, stage(model.item!, array.items[i])));
        }
      } else if (model.kind == 'map') {
        for (final entry in (value as CanonicalObject).fields) {
          final key = scalar(CanonicalString(entry.key)) as Uint8List;
          items.add(MapEntry(key, stage(model.item!, entry.value)));
        }
      }
      var depth = 0;
      for (final cell in [...cells, ...items.map((e) => e.value)]) {
        if (cell is _PendingWrite && cell.depth >= depth) {
          depth = cell.depth + 1;
        }
      }
      final row = _PendingWrite(model, columns, cells, items, depth);
      pending.add(row);
      return row;
    }

    late List<Object?> roots;
    try {
      roots = [for (final value in values) stage(name, value)];
    } on _WriteBatchFull {
      return [for (final value in values) await put(name, value)];
    }
    final byTable = <String, List<_PendingWrite>>{};
    final byDepth = <(int, String), List<_PendingWrite>>{};
    for (final row in pending) {
      (byTable[row.model.table] ??= []).add(row);
      (byDepth[(row.depth, row.model.table)] ??= []).add(row);
    }
    // Reserve identities through the owning table's own sequence. These are
    // fresh storage pointers, never copied from the imported package.
    for (final entry in byTable.entries) {
      final ids = await _session.execute(
        "SELECT nextval(pg_get_serial_sequence(\$1::text,'__row_id')::regclass) "
        'FROM generate_series(1,\$2::integer)',
        parameters: [_table(entry.key), entry.value.length],
      );
      for (var i = 0; i < entry.value.length; i++) {
        entry.value[i].id = ids[i].single as int;
      }
    }
    Object? resolve(Object? cell) => cell is _PendingWrite ? cell.id! : cell;
    final groups = byDepth.entries.toList()
      ..sort((a, b) => a.key.$1.compareTo(b.key.$1));
    for (final group in groups) {
      final rows = group.value;
      await _insertValues(
        group.key.$2,
        ['__row_id', ...rows.first.columns],
        [
          for (final row in rows) [row.id!, ...row.values.map(resolve)],
        ],
        overrideIdentity: true,
      );
      final items = <List<Object?>>[
        for (final row in rows)
          for (final item in row.items)
            [row.id!, item.key, resolve(item.value)],
      ];
      if (items.isNotEmpty) {
        await _insertValues('${group.key.$2}_items', [
          'owner',
          rows.first.model.kind == 'array' ? 'ordinal' : 'name',
          'item',
        ], items);
      }
    }
    return roots.map(resolve).toList();
  }

  Future<void> _insertValues(
    String table,
    List<String> columns,
    List<List<Object?>> rows, {
    bool overrideIdentity = false,
  }) async {
    final limit = (60000 ~/ columns.length).clamp(1, 64);
    for (var offset = 0; offset < rows.length; offset += limit) {
      final end = (offset + limit).clamp(0, rows.length);
      final parameters = <Object?>[];
      final tuples = <String>[];
      for (final row in rows.getRange(offset, end)) {
        tuples.add(
          '(${row.map((value) {
            parameters.add(value);
            return '\$${parameters.length}';
          }).join(',')})',
        );
      }
      await _session.execute(
        'INSERT INTO ${_table(table)} (${columns.map(postgresIdentifier).join(',')}) '
        '${overrideIdentity ? 'OVERRIDING SYSTEM VALUE ' : ''}VALUES ${tuples.join(',')}',
        parameters: parameters,
      );
    }
  }

  Object? _scalar(CanonicalValue value) => switch (value) {
    CanonicalNull() => null,
    CanonicalBool(:final value) => value,
    CanonicalString(:final value) => postgresAuthoredText(value),
    CanonicalNumber(:final digits) => digits,
    _ => throw const FormatException('Invalid scalar'),
  };

  Future<Object?> _write(String name, CanonicalValue value) async {
    final model = _catalog.model(name);
    if (model.scalar) {
      return _scalar(value);
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

  /// Fetch bounded groups of immutable bodies without a round trip per node.
  /// The original reader remains the fallback for unusually broad graphs.
  Future<List<CanonicalValue>> getMany(
    String name,
    List<Object?> references,
  ) async {
    if (references.length > 50) {
      throw RangeError('Body read batch exceeds 50 roots');
    }
    final batch = await _prefetch(name, references);
    if (batch == null) {
      return [for (final reference in references) await get(name, reference)];
    }
    final values = <CanonicalValue>[];
    for (final reference in references) {
      final value = await _read(name, reference, <(String, int)>{}, batch);
      if (!_catalog.fits(name, value)) {
        throw const FormatException('Stored value violates closed contract');
      }
      values.add(value);
    }
    return values;
  }

  Future<_ReadBatch?> _prefetch(String name, List<Object?> references) async {
    final rows = <(String, int), Map<String, dynamic>>{};
    final items = <(String, int), List<Map<String, dynamic>>>{};
    final seen = <(String, int)>{};
    var pending = <String, Set<int>>{};
    var overflow = false;
    void enqueue(String model, Object? reference) {
      if (_catalog.model(model).scalar || reference is! int) return;
      if (!seen.add((model, reference))) return;
      // This is a cache bound, not an admission limit. Fallback still uses the
      // existing cycle, nesting, type and closed-contract checks.
      if (seen.length > 10000) {
        overflow = true;
        return;
      }
      (pending[model] ??= <int>{}).add(reference);
    }

    for (final reference in references) {
      enqueue(name, reference);
    }
    while (pending.isNotEmpty && !overflow) {
      final current = pending;
      pending = {};
      for (final entry in current.entries) {
        final model = _catalog.model(entry.key);
        final ids = entry.value.toList();
        final fetched = await _session.execute(
          'SELECT * FROM ${_table(model.table)} WHERE __row_id=ANY(\$1::bigint[])',
          parameters: [ids],
        );
        for (final result in fetched) {
          final row = result.toColumnMap();
          rows[(entry.key, row['__row_id'] as int)] = row;
          if (model.kind == 'object' || model.kind == 'tuple') {
            for (final field in model.fields.entries) {
              if (row['${field.key}__state'] == 2) {
                enqueue(field.value.model, row[field.key]);
              }
            }
          } else if (model.kind == 'union') {
            final branch = row['variant'];
            if (branch is int &&
                branch >= 0 &&
                branch < model.variants.length) {
              enqueue(model.variants[branch], row['v$branch']);
            }
          }
        }
        if (model.kind == 'array' || model.kind == 'map') {
          final key = model.kind == 'array' ? 'ordinal' : 'name';
          for (final id in ids) {
            items[(entry.key, id)] = [];
          }
          final fetchedItems = await _session.execute(
            'SELECT owner,$key,item FROM ${_table('${model.table}_items')} '
            'WHERE owner=ANY(\$1::bigint[]) ORDER BY owner,$key',
            parameters: [ids],
          );
          for (final result in fetchedItems) {
            final row = result.toColumnMap();
            items[(entry.key, row['owner'] as int)]!.add(row);
            enqueue(model.item!, row['item']);
          }
        }
        if (overflow) break;
      }
    }
    return overflow ? null : (rows: rows, items: items);
  }

  Future<CanonicalValue> _read(
    String name,
    Object? reference,
    Set<(String, int)> trail, [
    _ReadBatch? batch,
  ]) async {
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
      final rows = batch == null
          ? (await _session.execute(
              'SELECT * FROM ${_table(model.table)} WHERE __row_id=\$1',
              parameters: [reference],
            )).map((row) => row.toColumnMap()).toList()
          : [?batch.rows[marker]];
      if (rows.length != 1) throw const FormatException('Missing body row');
      final row = rows.single;
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
            fields[entry.key] = await _read(
              entry.value.model,
              ref,
              trail,
              batch,
            );
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
        return await _read(
          model.variants[branch],
          row['v$branch'],
          trail,
          batch,
        );
      }
      if (model.kind == 'array' || model.kind == 'map') {
        final key = model.kind == 'array' ? 'ordinal' : 'name';
        final rows = batch == null
            ? (await _session.execute(
                'SELECT $key,item FROM ${_table('${model.table}_items')} WHERE owner=\$1 ORDER BY $key',
                parameters: [reference],
              )).map((row) => row.toColumnMap()).toList()
            : batch.items[marker]!;
        final array = <CanonicalValue>[],
            map = <MapEntry<String, CanonicalValue>>[];
        for (var i = 0; i < rows.length; i++) {
          final row = rows[i];
          final value = await _read(model.item!, row['item'], trail, batch);
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
