@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/mcp.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test(
    'event-effect inputs use event and slot without query framing fields',
    () {
      final value = CanonicalValue.parseWireJson(
        '{"event":{"record":"rec_000000000000000000000001"},"slot":"stock"}',
      );
      expect(EventEffectRef.fromWire(value).slot, 'stock');
      expect(
        EvidenceBasis.fromWire(
          CanonicalValue.parseWireJson(
            '{"kind":"event_effect","event":{"record":"rec_000000000000000000000001"},"slot":"stock"}',
          ),
        ),
        isA<EventEffectBasis>(),
      );
    },
  );
  test(
    'embedded discovery matches every maintained schema and description',
    () {
      final source = CanonicalValue.parseWireJson(
        File('../../contracts/tools.json').readAsStringSync(),
      );
      expect(mcpToolSchemas(advanced: true).toText(), source.toText());
    },
  );
}
