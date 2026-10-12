import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart' show InvalidArgumentError;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/provenance_checks.dart';

import 'operation_compilation_test.dart' as f;
import 'knowledge_boundaries_test.dart' as knowledge;
import 'resource_checks_test.dart' as stock;

final version = VersionRef(universe: f.u, record: f.id(10), version: f.ver(10));
final anchor = AnchorRecord(
  sourceVersion: version,
  locator: ByteRangeLocator(BigInt.zero, BigInt.one),
  excerptDigest: 'not-yet-verified',
  excerpt: 'x',
);
PassageRecord passage({RecordRef? citation}) =>
    PassageRecord(workVersion: version, passageId: 'scene-1', anchor: citation);
List<RecordPayload> claims(bool verified) => [
  f.patch(stock.assertion(12, 5, 20), {
    'basis': SourceAnchorBasis(f.ref(1), verified).toWire(),
  }),
  f.patch(knowledge.attitude(), {
    'basis': SourceAnchorBasis(f.ref(1), verified).toWire(),
  }),
  ObservationRecord(
    observer: f.ref(1),
    observed: f.ref(1),
    sensoryAccess: true,
    time: ExactTime(stock.cal, '12'),
    basis: SourceAnchorBasis(f.ref(1), verified),
  ),
];

void main() {
  test('passage cannot cite an entity as a source anchor', () {
    expect(
      () => validateProvenanceLinks(passage(citation: f.ref(1)), {
        f.id(1): f.entity(),
      }),
      throwsA(isA<InvalidArgumentError>()),
    );
    expect(
      () => validateProvenanceLinks(passage(citation: f.ref(1)), {}),
      throwsA(isA<InvalidArgumentError>()),
    );
  });
  test(
    'writer verification flags cannot promote entities to source evidence',
    () {
      for (final verified in [true, false]) {
        for (final claim in claims(verified)) {
          expect(
            () => validateProvenanceLinks(claim, {f.id(1): f.entity()}),
            throwsA(isA<InvalidArgumentError>()),
          );
        }
      }
    },
  );
  test('typed citation failures retain the provenance repair field', () {
    try {
      validateProvenanceLinks(passage(citation: f.ref(1)), {});
      fail('Expected citation failure');
    } on InvalidArgumentError catch (error) {
      expect(error.field, 'provenance.anchor');
      expect(error.message, contains('anchor record'));
    }
  });
  test('real anchor links are accepted without claiming retained excerpt verification', () {
    final records = {f.id(1): anchor};
    validateProvenanceLinks(passage(citation: f.ref(1)), records);
    for (final verified in [true, false]) {
      for (final claim in claims(verified)) {
        validateProvenanceLinks(claim, records);
      }
    }
    expect(anchor.excerptDigest, 'not-yet-verified');
  });
  test('omitted passage citations and other bases do not invent citation obligations', () {
    validateProvenanceLinks(passage(), {});
    validateProvenanceLinks(stock.assertion(12, 5, 20), {});
    validateProvenanceLinks(knowledge.attitude(), {});
    validateProvenanceLinks(f.entity(), {});
  });
}
