import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'postgres_values.dart';

String postgresIdentifier(String name) => '"${name.replaceAll('"', '""')}"';

/// PostgreSQL physical rows generated from the same normative body catalog as
/// SQLite. The caller provisions the namespace in an owned transaction. Kernel,
/// semantic projections and installation/workflow link tables are separate.
Iterable<String> postgresBodySchema(UniverseId universe) sync* {
  final catalog = BodyCatalog.instance;
  final schema = postgresUniverseSchema(universe);
  String table(String name) => '$schema.${postgresIdentifier(name)}';
  String type(BodyModel model) => switch (model.kind) {
    'string' => 'BYTEA',
    'integer' => 'TEXT',
    'boolean' || 'null' => 'BOOLEAN',
    _ => 'BIGINT',
  };
  String literal(CanonicalValue value) => switch (value) {
    CanonicalString(:final value) =>
      "decode('${postgresAuthoredText(value).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}', 'hex')",
    CanonicalNumber(:final digits) => "'$digits'",
    CanonicalBool(:final value) => value ? 'TRUE' : 'FALSE',
    CanonicalNull() => 'NULL',
    _ => throw const FormatException('Invalid catalog scalar'),
  };
  final foreign = <String>[];
  final tables = <String>[];
  String column(String owner, String name, BodyModel model) {
    final key = postgresIdentifier(name);
    if (!model.scalar) {
      foreign.add(
        'ALTER TABLE ${table(owner)} ADD FOREIGN KEY ($key) '
        'REFERENCES ${table(model.table)}(__row_id)',
      );
    }
    return '$key ${type(model)}';
  }

  for (final model in catalog.models.values.where((m) => !m.scalar)) {
    final columns = <String>[
      '__row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY',
    ];
    final checks = <String>[];
    if (model.kind == 'object' || model.kind == 'tuple') {
      for (final entry in model.fields.entries) {
        final child = catalog.model(entry.value.model);
        final state = postgresIdentifier('${entry.key}__state');
        final key = postgresIdentifier(entry.key);
        final nullable = catalog.fits(entry.value.model, const CanonicalNull());
        final states = [if (!entry.value.required) 0, if (nullable) 1, 2];
        columns.add(
          '$state SMALLINT NOT NULL CHECK($state IN (${states.join(',')}))',
        );
        columns.add(column(model.table, entry.key, child));
        checks.add(
          'CHECK(($state=2 AND $key IS NOT NULL) OR ($state IN (0,1) AND $key IS NULL))',
        );
        if (child.constant != null) {
          checks.add('CHECK($key=${literal(child.constant!)})');
        }
        if (child.enumeration != null) {
          checks.add(
            'CHECK($key IN (${child.enumeration!.map(literal).join(',')}))',
          );
        }
      }
    } else if (model.kind == 'union') {
      columns.add(
        'variant SMALLINT NOT NULL CHECK(variant BETWEEN 0 AND ${model.variants.length - 1})',
      );
      for (var i = 0; i < model.variants.length; i++) {
        final child = catalog.model(model.variants[i]);
        columns.add(column(model.table, 'v$i', child));
        checks.add('CHECK(variant=$i OR v$i IS NULL)');
        checks.add(
          child.kind == 'null'
              ? 'CHECK(v$i IS NULL)'
              : 'CHECK(variant!=$i OR v$i IS NOT NULL)',
        );
      }
    }
    tables.add(model.table);
    yield 'CREATE TABLE ${table(model.table)} (${[...columns, ...checks].join(',')})';
    if (model.kind == 'array' || model.kind == 'map') {
      final items = '${model.table}_items';
      final key = model.kind == 'array'
          ? 'ordinal BIGINT NOT NULL CHECK(ordinal>=0)'
          : 'name BYTEA NOT NULL';
      final item = column(items, 'item', catalog.model(model.item!));
      foreign.add(
        'ALTER TABLE ${table(items)} ADD FOREIGN KEY (owner) REFERENCES ${table(model.table)}(__row_id)',
      );
      tables.add(items);
      yield 'CREATE TABLE ${table(items)} (owner BIGINT NOT NULL,$key,$item,PRIMARY KEY(owner,${model.kind == 'array' ? 'ordinal' : 'name'}))';
    }
  }
  // Recursive catalog types require all target tables to exist first.
  yield* foreign;
  yield 'CREATE FUNCTION $schema.immutable_body() RETURNS trigger LANGUAGE plpgsql AS '
      r"'BEGIN RAISE EXCEPTION USING ERRCODE = ''55000'', MESSAGE = ''immutable typed body''; END'";
  for (final name in tables) {
    yield 'CREATE TRIGGER immutable_body BEFORE UPDATE OR DELETE ON ${table(name)} '
        'FOR EACH ROW EXECUTE FUNCTION $schema.immutable_body()';
  }
}
