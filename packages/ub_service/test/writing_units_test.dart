import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;

UnitRecord unit({
  String key = 'metre',
  String symbol = 'm',
  Map<String, String> labels = const {},
}) => UnitRecord(
  namespace: 'test',
  key: key,
  dimension: 'length',
  symbol: symbol,
  labels: labels,
  validity: const UnspecifiedValidity(),
);
WritingUnit declaration({
  String name = 'metre',
  String dimension = 'length',
  String symbol = 'm',
  bool introduce = false,
}) => WritingUnit(
  name: name,
  dimension: dimension,
  symbol: symbol,
  introduce: introduce,
);

void main() {
  test('explicit introductions compile into canonical unit records without conversion', () {
    final compiled = compileWritingUnits([
      declaration(name: 'league', symbol: 'lg', introduce: true),
      declaration(name: 'day', dimension: 'time', symbol: 'd', introduce: true),
    ], []);
    expect(compiled.clarifications, isEmpty);
    expect(compiled.unchanged, isEmpty);
    expect(compiled.additions, [
      'Explicit unit: league; dimension length; symbol lg; no conversion declared. Use private contract review.',
      'Explicit unit: day; dimension time; symbol d; no conversion declared. Use private contract review.',
    ]);
    final ids = compiled.operations
        .cast<DefineUnitOperation>()
        .map((op) => RecordId.parse(op.clientRef))
        .toList();
    expect(ids.toSet(), hasLength(2));
    final records = f.compile([], compiled.operations).map(f.decode).toList();
    expect(records.map((r) => r.identity.recordId), ids);
    expect(records.map((r) => (r.payload as UnitRecord).key), [
      'league',
      'day',
    ]);
    for (final row in records) {
      final definition = row.payload as UnitRecord;
      expect(definition.namespace, 'authoring');
      expect(definition.base, isNull);
      expect(definition.scaleToBase, isNull);
      expect(definition.validity, isA<UnspecifiedValidity>());
      expect(definition.labels, isEmpty);
      final rebound = resolveWritingUnit(records, definition.symbol);
      expect(rebound.toRecordId(), row.identity.recordId);
    }
  });

  test('existing declarations require exact authored dimension and symbol', () {
    final rows = [
      f.row(1, unit(labels: {'en': 'meter'})),
    ];
    final existing = compileWritingUnits([
      declaration(),
      declaration(name: 'meter'),
    ], rows);
    expect(existing.operations, isEmpty);
    expect(existing.clarifications, isEmpty);
    expect(existing.unchanged, [
      'Authored unit: metre',
      'Authored unit: meter',
    ]);
    for (final request in [
      declaration(introduce: true),
      declaration(dimension: 'distance'),
      declaration(symbol: 'M'),
      declaration(name: 'missing'),
      declaration(name: 'm'),
    ]) {
      final result = compileWritingUnits([request], rows);
      expect(result.operations, isEmpty);
      expect(
        result.clarifications.single,
        contains('no duplicate or conversion is inferred'),
      );
    }
    final ambiguous = compileWritingUnits(
      [declaration()],
      [...rows, f.row(2, unit())],
    );
    expect(ambiguous.operations, isEmpty);
    expect(ambiguous.clarifications, hasLength(1));
    // Declarations bind by key/label, while value lookup also admits symbols.
    final sameSymbol = compileWritingUnits([
      declaration(name: 'm', introduce: true),
    ], rows);
    expect(sameSymbol.operations, hasLength(1));
    expect(
      () => resolveWritingUnit([
        ...rows,
        ...f.compile(rows, sameSymbol.operations).map(f.decode),
      ], 'm'),
      throwsFormatException,
    );
  });

  test(
    'blank or repeated declarations clarify without inventing definitions',
    () {
      final result = compileWritingUnits([
        declaration(name: '\u2003', introduce: true),
        declaration(name: 'league', dimension: '\u0085', introduce: true),
        declaration(name: 'league', symbol: '\u3000', introduce: true),
        declaration(name: 'league', introduce: true),
        declaration(name: 'league', introduce: true),
      ], []);
      expect(result.operations, hasLength(1));
      expect(result.additions, hasLength(1));
      expect(result.clarifications, hasLength(4));
      // Nonempty names are preserved verbatim; no selector normalization.
      final exact = compileWritingUnits([
        declaration(name: 'league', introduce: true),
        declaration(name: 'League', introduce: true),
        declaration(name: ' league ', introduce: true),
      ], []);
      expect(exact.operations, hasLength(3));
      expect(exact.clarifications, isEmpty);
    },
  );

  test('unit lookup uses only visible exact names, symbols and labels', () {
    final rows = [
      f.row(1, unit(labels: {'en': 'meter', 'alias': 'm'})),
    ];
    for (final name in ['metre', 'meter', 'm']) {
      expect(resolveWritingUnit(rows, name).toRecordId(), f.id(1));
    }
    for (final name in ['Metre', ' metre ', 'unknown']) {
      expect(
        () => resolveWritingUnit(rows, name),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('ambiguity or absence cannot imply conversion'),
          ),
        ),
      );
    }
    final hidden = f.row(2, unit(key: 'secret', symbol: 'm'));
    expect(
      () => resolveWritingUnit([...rows, hidden], 'm'),
      throwsFormatException,
    );
    expect(() => resolveWritingUnit(rows, 'secret'), throwsFormatException);
    expect(resolveWritingUnit(rows, 'm').toRecordId(), f.id(1));
  });
}
