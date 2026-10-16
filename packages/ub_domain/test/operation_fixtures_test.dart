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
  // These operations were added after the retained Rust fixture corpus.
  final extensions = CanonicalValue.parseJson('''[
    {
      "kind":"create_secret","client_ref":"Hidden inheritance é🌲",
      "record":{
        "scope":[{"record":"rec_000000000000000000000001"}],
        "fictionalKnowers":[{"record":"rec_000000000000000000000002"}],
        "readerDisclosed":false,"concealment":"Sealed letter",
        "validity":{"kind":"unspecified"}
      }
    },
    {
      "kind":"revise_secret",
      "record":{"record":"rec_000000000000000000000003"},
      "expected_version":"ver_000000000000000000000004",
      "replacement":{
        "scope":[{"record":"rec_000000000000000000000001"}],
        "fictionalKnowers":[],"readerDisclosed":true,"concealment":null,
        "validity":{"kind":"unknown"}
      }
    }
    ,{
      "kind":"define_universe_policy",
      "client_ref":"rec_000000000000000000000005",
      "key":"Historical fiction","real_world":true,"activate":true,
      "expected_root_version":"ver_000000000000000000000006"
    }
  ]''') as CanonicalArray;
  for (final input in extensions.items.cast<CanonicalObject>()) {
    final operation = DomainOperation.fromWire(input);
    covered.add(operation.kind);
    test('Dart operation extension: ${operation.kind.wireName}', () {
      expect(operation.toWire().toText(), input.toText());
      expect(operation.authority, operation is DefineUniversePolicyOperation
          ? OperationAuthority.definition : OperationAuthority.ordinary);
      expect(
        DomainOperation.fromWire(operation.toWire()).toWire().toText(),
        input.toText(),
      );
      expect(
        () => DomainOperation.fromWire(
          CanonicalObject([
            ...input.fields,
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
