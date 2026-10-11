@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final cases = CanonicalValue.parseJson(
    File('../../fixtures/dart-domain/operations.json').readAsStringSync(),
  ) as CanonicalArray;
  final covered = <DomainOperationKind>{};
  for (var i = 0; i < cases.items.length; i++) {
    final fields = {
      for (final e in (cases.items[i] as CanonicalObject).fields)
        e.key: e.value,
    };
    final input = fields['input']!;
    final operation = DomainOperation.fromWire(input);
    covered.add(operation.kind);
    test('Rust operation parity: ${operation.kind.wireName}:$i', () {
      expect(
        operation.toWire().toText(),
        (fields['canonical'] as CanonicalString).value,
      );
      expect(
        CanonicalString(operation.authority.name).toText(),
        (fields['authority'] as CanonicalString).value,
      );
      expect(
        DomainOperation.fromWire(operation.toWire()).toWire().toText(),
        operation.toWire().toText(),
      );
      expect(
        () => DomainOperation.fromWire(
          CanonicalObject([
            ...(input as CanonicalObject).fields,
            const MapEntry('unauthorized_field', CanonicalBool(true)),
          ]),
        ),
        throwsFormatException,
      );
    });
  }
  test('operation fixture coverage includes every current typed variant', () {
    expect(covered, DomainOperationKind.values.toSet());
  });
}
