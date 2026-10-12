@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart' hide Description;
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final cases = CanonicalValue.parseJson(
    File('../../fixtures/dart-contracts/read-responses.json')
        .readAsStringSync(),
  ) as CanonicalArray;
  for (final (index, raw) in cases.items.indexed) {
    final f = {for (final e in (raw as CanonicalObject).fields) e.key: e.value};
    final type = (f['type']! as CanonicalString).value;
    test('owning Rust read response $index:$type', () {
      final input = CanonicalValue.parseWireJson(
        (f['input_raw']! as CanonicalString).value,
      );
      final output = switch (type) {
        'Delivery' => Delivery.fromWire(input).toWire(),
        'Capability' => Capability.fromWire(input).toWire(),
        'WorldSummary' => WorldSummary.fromWire(input).toWire(),
        'RepresentedContextSummary' => RepresentedContextSummary.fromWire(
          input,
        ).toWire(),
        'ContinuitySummary' => ContinuitySummary.fromWire(input).toWire(),
        'Description' => Description.fromWire(input).toWire(),
        'OpenedContext' => OpenedContext.fromWire(input).toWire(),
        'SearchHit' => SearchHit.fromWire(input).toWire(),
        'SearchResults' => SearchResults.fromWire(input).toWire(),
        'Records' => Records.fromWire(input).toWire(),
        'RecordSummary' => RecordSummary.fromWire(input).toWire(),
        'HistoryEntry' => HistoryEntry.fromWire(input).toWire(),
        'ContextBrief' => ContextBrief.fromWire(input).toWire(),
        'CapabilityStatus' => CanonicalString(
          CapabilityStatus.fromName((input as CanonicalString).value).wireName,
        ),
        'ScopeCategory' => CanonicalString(
          ScopeCategory.fromName((input as CanonicalString).value).wireName,
        ),
        'Envelope' => Envelope<ContextBrief>.fromWire(
          input,
          ContextBrief.fromWire,
        ).toWire((v) => v.toWire()),
        _ => throw StateError('Unknown fixture'),
      };
      expect(output.toText(), (f['canonical_utf8']! as CanonicalString).value);
    });
  }
}
