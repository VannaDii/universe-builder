import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalValue replace(
  CanonicalValue value,
  List<Object> path,
  CanonicalValue next,
) {
  if (path.isEmpty) return next;
  final key = path.first;
  if (value is CanonicalObject) {
    return CanonicalObject(
      value.fields.map(
        (e) => MapEntry(
          e.key,
          e.key == key
              ? replace(e.value, path.skip(1).toList(), next)
              : e.value,
        ),
      ),
    );
  }
  final array = value as CanonicalArray;
  return CanonicalArray(
    array.items.indexed.map(
      (e) => e.$1 == key ? replace(e.$2, path.skip(1).toList(), next) : e.$2,
    ),
  );
}

Uint8List retained(String text) => Uint8List.fromList(utf8.encode(text));
CanonicalValue base({Uint8List? bytes}) {
  final raw = bytes ?? retained('Ié🌲');
  return CanonicalValue.parseJson('''{
    "kind":"source_assessment",
    "proposal":{"proposal_id":"prp_000000000000000000000001","version":1,"digest":"${'a' * 64}"},
    "base_frame":{"universe":"unv_000000000000000000000001","continuity":"cont_000000000000000000000001","revision":"rev_000000000000000000000001","context":{"record":"rec_000000000000000000000001"},"time":{"kind":"timeless"},"perspective":"author"},
    "assessor":{"principal":"prn_000000000000000000000001","method":"human_review","tool":null,"assessed_at":"2026-10-02T20:00:00Z"},
    "sources":[{"key":"passage","source_version":{"universe":"unv_000000000000000000000001","record":"rec_000000000000000000000002","version":"ver_000000000000000000000002"},"blob_digest":"${sha256.convert(raw)}","byte_size":${raw.length},"representation":"exact-utf8-v1","ranges":[{"start":0,"end":${raw.length}}],"work_edition":null,"passage_id":null}],
    "dependencies":[],"declared_inventory":[],"inventory_declaration":{"kind":"no_material_claims","exclusions":[],"rationale":"No material claims"},"claim_mappings":[],"unresolved":[],"conclusion":"consistent_with_declared_inventory"
  }''');
}

void main() {
  test(
    'strict decode verifies accounting without silently authenticating sources',
    () {
      final body = SourceAssessmentV1.decode(base().toBytes());
      body.verifySourceBytes((_) => retained('Ié🌲'));
      expect(body.inventoryDigest().value, canonicalDigest(CanonicalArray([])));
      expect(
        body.bindFrozenProposal(body.proposal, body.baseFrame),
        body.digest(),
      );
      expect(
        () => body.bindFrozenProposal(
          ProposalRef(
            proposalId: body.proposal.proposalId,
            version: BigInt.two,
            digest: body.proposal.digest,
          ),
          body.baseFrame,
        ),
        throwsFormatException,
      );
      final altered = Frame.fromWire(
        replace(body.baseFrame.toWire(), [
          'perspective',
        ], CanonicalString('reader')),
      );
      expect(
        () => body.bindFrozenProposal(body.proposal, altered),
        throwsFormatException,
      );
    },
  );
  for (final timestamp in [
    '0000-02-29T00:00:00Z',
    '2000-02-29t23:59:60z',
    '2026-10-02 20:00:00.123456789012345Z',
    '2026-10-02T20:00:00+00:00',
    '2026-10-02T20:00:00-00:00',
    '2026-10-02T20:00:00−00:00',
  ]) {
    test('locked UTC timestamp accepted: $timestamp', () {
      SourceAssessmentV1.fromWire(
        replace(base(), [
          'assessor',
          'assessed_at',
        ], CanonicalString(timestamp)),
      ).validate();
    });
  }
  for (final timestamp in [
    '1900-02-29T00:00:00Z',
    '2026-04-31T00:00:00Z',
    '2026-01-00T00:00:00Z',
    '2026-13-01T00:00:00Z',
    '2026-01-01T24:00:00Z',
    '2026-01-01T00:60:00Z',
    '2026-01-01T00:00:61Z',
    '2026-01-01T00:00:00.Z',
    '2026-01-01T00:00:00+01:00',
    '2026-01-01T00:00:00+00:60',
    '2026-01-01T00:00:00Z\n',
    ' 2026-01-01T00:00:00Z',
  ]) {
    test('invalid or non-UTC timestamp rejected: $timestamp', () {
      expect(
        SourceAssessmentV1.fromWire(
          replace(base(), [
            'assessor',
            'assessed_at',
          ], CanonicalString(timestamp)),
        ).validate,
        throwsFormatException,
      );
    });
  }
  test(
    'import rejects oversized raw input duplicate keys and invalid UTF-8',
    () {
      expect(
        () => SourceAssessmentV1.decode(
          retained('${' ' * (1024 * 1024)}${base().toText()}'),
        ),
        throwsFormatException,
      );
      expect(
        () => SourceAssessmentV1.decode(
          retained(
            base().toText().replaceFirst(
              '"kind":"source_assessment"',
              '"kind":"source_assessment","kind":"source_assessment"',
            ),
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => SourceAssessmentV1.decode(Uint8List.fromList([0xff])),
        throwsFormatException,
      );
    },
  );
  test(
    'bytes must be present exact and UTF-8 even with matching SHA and size',
    () {
      final body = SourceAssessmentV1.fromWire(base());
      expect(() => body.verifySourceBytes((_) => null), throwsFormatException);
      expect(
        () => body.verifySourceBytes((_) => retained('Ié🌳')),
        throwsFormatException,
      );
      expect(
        () => body.verifySourceBytes((_) => retained('Ié')),
        throwsFormatException,
      );
      final invalid = Uint8List.fromList([0xff]);
      expect(
        () =>
            SourceAssessmentV1.fromWire(base(bytes: invalid))
                .verifySourceBytes((_) => invalid),
        throwsFormatException,
      );
    },
  );
  test('source and exclusion byte ranges cannot split Unicode code points', () {
    final tree = base();
    final split = replace(tree, [
      'sources',
      0,
      'ranges',
      0,
      'start',
    ], const CanonicalNumber('2'));
    SourceAssessmentV1.fromWire(split).validate();
    expect(
      () =>
          SourceAssessmentV1.fromWire(split)
              .verifySourceBytes((_) => retained('Ié🌲')),
      throwsFormatException,
    );
    final exclusion = CanonicalValue.parseJson(
      '{"source_key":"passage","range":{"start":1,"end":2},"reason":"formatting"}',
    );
    final withExclusion = replace(tree, [
      'inventory_declaration',
      'exclusions',
    ], CanonicalArray([exclusion]));
    SourceAssessmentV1.fromWire(withExclusion).validate();
    expect(
      () =>
          SourceAssessmentV1.fromWire(withExclusion)
              .verifySourceBytes((_) => retained('Ié🌲')),
      throwsFormatException,
    );
  });
  test(
    'method text range and declaration constraints reject invalid accounting',
    () {
      for (final (path, value) in <(List<Object>, CanonicalValue)>[
        (['assessor', 'method'], CanonicalString('external_model_review')),
        (['sources'], CanonicalArray([])),
        (['sources', 0, 'ranges'], CanonicalArray([])),
        (['sources', 0, 'key'], CanonicalString(' \u0085\u3000')),
        (['sources', 0, 'key'], CanonicalString('é' * 8193)),
        (['sources', 0, 'ranges', 0, 'end'], const CanonicalNumber('8')),
        (['sources', 0, 'ranges', 0, 'start'], const CanonicalNumber('7')),
        (
          ['inventory_declaration', 'kind'],
          CanonicalString('material_inventory_declared'),
        ),
        (['conclusion'], CanonicalString('unresolved')),
        (['conclusion'], CanonicalString('inconsistent')),
        (
          ['base_frame', 'context'],
          CanonicalValue.parseJson(
            '{"record":"rec_000000000000000000000001","universe":"unv_000000000000000000000002"}',
          ),
        ),
      ]) {
        expect(
          SourceAssessmentV1.fromWire(replace(base(), path, value)).validate,
          throwsFormatException,
          reason: path.toString(),
        );
      }
      SourceAssessmentV1.fromWire(
        replace(base(), ['sources', 0, 'key'], CanonicalString('\ufeff')),
      ).validate();
    },
  );
}
