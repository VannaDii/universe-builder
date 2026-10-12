import 'package:test/test.dart' hide Description;
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalValue wire(String text) => CanonicalValue.parseWireJson(text);
final universeId = UniverseId.parse('unv_000000000000000000000001');
final recordId = RecordId.parse('rec_000000000000000000000001');
Envelope<ContextBrief> envelope({BigInt? requestId}) => Envelope(
  contractVersion: '3',
  requestId: requestId ?? BigInt.parse('18446744073709551615'),
  universeId: universeId,
  universe: const Selector('Cycle'),
  aliasMatched: true,
  authorizationScope: 'restricted',
  delivery: Delivery(complete: true),
  result: ContextBrief(
    records: [],
    requiredDependencies: [],
    coverage: Coverage.restricted,
  ),
);
void main() {
  test(
    'record pages preserve supplied historical digests and separate evidence',
    () {
      final version = RecordVersion(
        recordVersionId: RecordVersionId.parse('ver_000000000000000000000001'),
        identity: RecordIdentity(
          universeId: universeId,
          recordId: recordId,
          recordKind: RecordKind.world,
        ),
        payload: WorldRecord(selector: 'Earth'),
        payloadDigest: 'retained declared digest',
      );
      final source = [version];
      final page = Records(
        records: [],
        evidence: source,
        summaries: [
          RecordSummary(
            recordId: recordId,
            kind: RecordKind.world,
            label: 'Earth',
          ),
        ],
      );
      source.clear();
      final back = Records.fromWire(page.toWire());
      expect(back.records, isEmpty);
      expect(back.evidence.single.payloadDigest, 'retained declared digest');
      expect(back.evidence.single.verifiesDigest, isFalse);
      expect(back.summaries.single.label, 'Earth');
      expect(() => back.evidence.clear(), throwsUnsupportedError);
      expect(back.historyCoverage, isNull);
    },
  );
  test('delivery completeness does not upgrade evidence coverage or grant authority', () {
    final e = Envelope<ContextBrief>.fromWire(
      envelope().toWire((v) => v.toWire()),
      ContextBrief.fromWire,
    );
    expect(e.requestId, BigInt.parse('18446744073709551615'));
    expect(e.delivery.complete, isTrue);
    expect(e.result.coverage, Coverage.restricted);
    expect(e.aliasMatched, isTrue);
    expect(e.frame, isNull);
    expect(e.worldFocus, isNull);
    expect(e.toWire((v) => v.toWire()).toText(), contains('"frame":null'));
    expect(e.authorizationScope, 'restricted');
    expect(e.toWire((v) => v.toWire()).toText(), isNot(contains('approval')));
  });
  test('request id rejects floating rounded quoted negative and overflowing integers', () {
    final fields = envelope()
        .toWire((v) => v.toWire())
        .fields
        .where((e) => e.key != 'request_id');
    for (final v in ['-1', '1.0', '1e2', '18446744073709551616', '"1"']) {
      expect(
        () => Envelope<ContextBrief>.fromWire(
          CanonicalObject([...fields, MapEntry('request_id', wire(v))]),
          ContextBrief.fromWire,
        ),
        throwsFormatException,
      );
    }
    expect(() => envelope(requestId: -BigInt.one), throwsFormatException);
  });
  test('optional fields preserve serde nulls and required collections do not default', () {
    final delivery = Delivery.fromWire(wire('{"complete":false}'));
    expect(delivery.toWire().toText(), '{"complete":false,"cursor":null}');
    expect(
      () => Delivery.fromWire(wire('{"complete":false,"cursor":7}')),
      throwsFormatException,
    );
    expect(
      () => Description.fromWire(wire('{"fixture":false}')),
      throwsFormatException,
    );
    expect(
      () => ContextBrief.fromWire(wire('{"records":[],"coverage":"complete"}')),
      throwsFormatException,
    );
    expect(
      () => Records.fromWire(wire('{"records":[],"summaries":null}')),
      throwsFormatException,
    );
    expect(
      Records.fromWire(wire('{"records":[]}')).toWire().toText(),
      '{"records":[]}',
    );
  });
  test('visible represented context choices preserve kind and immutable authored labels', () {
    final labels = {'en': 'Remembered account'};
    final choice = RepresentedContextSummary(
      id: recordId,
      kind: const AuthoredContext('testimony'),
      labels: labels,
    );
    labels.clear();
    final back = RepresentedContextSummary.fromWire(choice.toWire());
    expect((back.kind as AuthoredContext).label, 'testimony');
    expect(back.labels['en'], 'Remembered account');
    expect(() => back.labels.clear(), throwsUnsupportedError);
  });
  test('required dependency manifests retain order even with empty visible record page', () {
    final ids = [recordId];
    final brief = ContextBrief(
      records: [],
      requiredDependencies: ids,
      coverage: Coverage.partial,
    );
    ids.clear();
    final back = ContextBrief.fromWire(brief.toWire());
    expect(back.records, isEmpty);
    expect(back.requiredDependencies, [recordId]);
    expect(back.coverage, Coverage.partial);
    expect(() => back.requiredDependencies.clear(), throwsUnsupportedError);
  });
  test(
    'history tombstones retain pinned revision continuity principal and reason',
    () {
      final h = HistoryEntry.fromWire(
        wire(
          '{"record_id":"rec_000000000000000000000001","revision":"rev_000000000000000000000001","continuity":"cont_000000000000000000000001","principal":"prn_000000000000000000000001","reason":"authored removal"}',
        ),
      );
      expect(h.record, isNull);
      expect(h.reason, 'authored removal');
      expect(h.toWire().toText(), contains('"record":null'));
      final page = Records(
        records: [],
        history: [h],
        historyCoverage: Coverage.restricted,
      );
      expect(
        Records.fromWire(page.toWire()).history.single.principal,
        h.principal,
      );
      expect(page.historyCoverage, Coverage.restricted);
    },
  );
  test('search scope categories and capability limitations remain distinct closed choices', () {
    for (final category in ScopeCategory.values) {
      final hit = SearchHit(
        recordId: recordId,
        kind: RecordKind.world,
        label: 'Earth',
        worldIds: [],
        scopeCategory: category,
      );
      expect(SearchHit.fromWire(hit.toWire()).scopeCategory, category);
    }
    for (final status in CapabilityStatus.values) {
      final capability = Capability(
        id: 'chronology',
        status: status,
        limitation: 'No implicit advancement',
      );
      expect(Capability.fromWire(capability.toWire()).status, status);
    }
    expect(() => ScopeCategory.fromName('visible'), throwsFormatException);
    expect(() => CapabilityStatus.fromName('available'), throwsFormatException);
  });
  test(
    'closed envelope nested delivery and result reject unrecognized fields',
    () {
      final e = envelope().toWire((v) => v.toWire());
      expect(
        () => Envelope<ContextBrief>.fromWire(
          CanonicalObject([
            ...e.fields,
            const MapEntry('approved', CanonicalBool(true)),
          ]),
          ContextBrief.fromWire,
        ),
        throwsFormatException,
      );
      expect(
        () =>
            Delivery.fromWire(wire('{"complete":true,"coverage":"complete"}')),
        throwsFormatException,
      );
      expect(
        () => SearchResults.fromWire(wire('{"hits":[],"cursor":"next"}')),
        throwsFormatException,
      );
    },
  );
}
