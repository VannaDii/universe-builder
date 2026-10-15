import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'relational.dart';
import 'schema.g.dart';

final _catalog = BodyCatalog.instance;
String recoveryPayloadModel(String kind) =>
    _catalog.model('Payload').variants.singleWhere((name) {
      final field = _catalog.model(name).fields['record_kind'];
      if (field == null) return false;
      final value = _catalog.model(field.model).constant;
      return value is CanonicalString && value.value == kind;
    });

/// Reuses the normative closed models for original records in private forms.
/// Each written tree is owned by one form and removed only when it is replaced.
final class RecoveryDomainSchema {
  RecoveryDomainSchema(Iterable<String> roots) {
    final tables = <String>{}, visited = <String>{};
    void visit(String name) {
      if (!visited.add(name)) return;
      final model = _catalog.model(name);
      if (model.scalar) return;
      tables.add(model.table);
      if (model.kind == 'array' || model.kind == 'map') {
        tables.add('${model.table}_items');
      }
      for (final field in model.fields.values) {
        visit(field.model);
      }
      for (final variant in model.variants) {
        visit(variant);
      }
      if (model.item != null) visit(model.item!);
    }

    for (final root in roots) {
      visit(root);
    }
    statements = RegExp(r'CREATE TABLE "([^"\n]+)" \([\s\S]*?\) STRICT;')
        .allMatches(sqliteSchema)
        .where((m) => tables.contains(m.group(1)))
        .map((m) => m.group(0)!)
        .toList();
    if (statements.length != tables.length) {
      throw StateError('Missing recovery domain table');
    }
  }
  late final List<String> statements;
  bool matches(Database db) => statements.every((statement) {
    final name = RegExp(r'CREATE TABLE "([^"\n]+)"')
        .firstMatch(statement)!
        .group(1)!;
    final rows = db.select(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
      [name],
    );
    return rows.length == 1 &&
        rows.single['sql'] == statement.substring(0, statement.length - 1);
  });
  // Recovery replaces private original snapshots. Normative canon remains
  // append-only; these rows are owned exclusively by this one saved form.
  void deleteOwned(Database db, String name, Object? id) {
    final m = _catalog.model(name);
    if (m.scalar || id == null) return;
    final table = quoteIdentifier(m.table);
    final r = db.select('SELECT * FROM $table WHERE __row_id=?', [id]).single;
    final children = <(String, Object?)>[];
    switch (m.kind) {
      case 'object':
      case 'tuple':
        for (final e in m.fields.entries) {
          if (r['${e.key}__state'] == 2) {
            children.add((e.value.model, r[e.key]));
          }
        }
      case 'union':
        final branch = r['variant'] as int;
        children.add((m.variants[branch], r['v$branch']));
      case 'array':
      case 'map':
        final items = quoteIdentifier('${m.table}_items');
        for (final item in db.select('SELECT item FROM $items WHERE owner=?', [
          id,
        ])) {
          children.add((m.item!, item['item']));
        }
        db.execute('DELETE FROM $items WHERE owner=?', [id]);
    }
    db.execute('DELETE FROM $table WHERE __row_id=?', [id]);
    for (final (model, child) in children) {
      deleteOwned(db, model, child);
    }
  }
}
