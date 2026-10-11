@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

// Consume the existing functional fixtures in place. The oracle checks byte
// encoding, not structural validity of every example record.
void main() {
  final root = Directory.current.path.endsWith('packages/ub_domain')
      ? '../..'
      : '.';
  final oracle = jsonDecode(
    File('$root/docs/decisions/relational-storage/canonical-oracle.json')
        .readAsStringSync(),
  ) as List<dynamic>;
  for (final raw in oracle) {
    final item = raw as Map<String, dynamic>;
    test('normative canonical oracle: ${item['name']}', () {
      final value = CanonicalValue.parseJson(jsonEncode(item['value']));
      expect(value.toText(), item['canonical']);
      final payload = item['value'] as Map<String, dynamic>;
      expect(
        payloadDigest(payload['record_kind'] as String, value),
        item['digest'],
      );
      expect(CanonicalValue.parse(value.toBytes()).toBytes(), value.toBytes());
    });
    if ((item['name'] as String).startsWith('value:')) {
      test('typed wire value preserves payload oracle: ${item['name']}', () {
        final payload = Map<String, dynamic>.from(
          item['value'] as Map<String, dynamic>,
        );
        final metadata = Map<String, dynamic>.from(
          payload['metadata'] as Map<String, dynamic>,
        );
        final value = DomainValue.fromWire(
          CanonicalValue.parseJson(jsonEncode(metadata['specimen'])),
        );
        // The schema oracle includes non-executable examples (such as a
        // quantity containing text). This case checks encoding parity only.
        metadata['specimen'] = jsonDecode(value.toWire().toText());
        payload['metadata'] = metadata;
        final canonical = CanonicalValue.parseJson(jsonEncode(payload));
        expect(canonical.toText(), item['canonical']);
        expect(payloadDigest('entity', canonical), item['digest']);
      });
    }
  }

  final historical = jsonDecode(
    File('$root/fixtures/normalized-foundation/historical-digests.json')
        .readAsStringSync(),
  ) as List<dynamic>;
  final originals = <String, Map<String, dynamic>>{
    for (final raw in jsonDecode(
      File('$root/fixtures/action-consequences/payload-digests.json')
          .readAsStringSync(),
    ) as List<dynamic>)
      (raw as Map<String, dynamic>)['name'] as String: raw,
  };
  for (final raw in historical) {
    final item = raw as Map<String, dynamic>;
    test('historical payload: ${item['name']}', () {
      final value = CanonicalValue.parseJson(jsonEncode(item['payload']));
      expect(value.toText(), item['canonical_utf8']);
      final payload = item['payload'] as Map<String, dynamic>;
      final kind = payload['record_kind'] as String;
      expect(payloadDigest(kind, value), item['normative_digest']);
      final original = originals[item['name']]!;
      final sourceValue = CanonicalValue.parseJson(
        jsonEncode(original['payload']),
      );
      expect(sourceValue.toText(), original['canonical_utf8']);
      expect(payloadDigest('$kind:v1:v1', sourceValue), item['source_digest']);
    });
  }
}
