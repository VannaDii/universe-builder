import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'relational.dart';

List<String> conversionColumns(Database db, String table) => [
  for (final row in db.select('PRAGMA table_info(${quoteIdentifier(table)})'))
    row['name'] as String,
];
bool sameConversionColumns(List<String> a, List<String> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

void conversionRows(Database db, String table, void Function(Row) accept) {
  final columns = conversionColumns(db, table);
  if (columns.isEmpty) throw FormatException('Missing conversion table $table');
  final read = db.prepare(
    'SELECT * FROM ${quoteIdentifier(table)} ORDER BY ${columns.map(quoteIdentifier).join(',')} LIMIT 2000001',
  );
  try {
    final rows = read.selectCursor();
    var count = 0;
    while (rows.moveNext()) {
      if (++count > 2000000) {
        throw const FormatException('Conversion row budget exceeded');
      }
      accept(rows.current);
    }
  } finally {
    read.close();
  }
}

bool _cell(Object? a, Object? b) {
  if (a is Uint8List && b is Uint8List) {
    return a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
  }
  return a.runtimeType == b.runtimeType && a == b;
}

void compareConversionRows(Database input, Database output, String table) {
  final columns = conversionColumns(input, table);
  if (!sameConversionColumns(columns, conversionColumns(output, table))) {
    throw FormatException('Unsupported columns in $table');
  }
  final sql =
      'SELECT * FROM ${quoteIdentifier(table)} ORDER BY ${columns.map(quoteIdentifier).join(',')}';
  final read = input.prepare(sql);
  try {
    final retained = output.prepare(sql);
    try {
      final source = read.selectCursor(), target = retained.selectCursor();
      while (true) {
        final a = source.moveNext(), b = target.moveNext();
        if (a != b ||
            a &&
                columns.any(
                  (column) =>
                      !_cell(source.current[column], target.current[column]),
                )) {
          throw FormatException('Retained scalar table differs: $table');
        }
        if (!a) break;
      }
    } finally {
      retained.close();
    }
  } finally {
    read.close();
  }
}
