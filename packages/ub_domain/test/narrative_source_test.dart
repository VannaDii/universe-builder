import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalObject replace(
  CanonicalObject object,
  Map<String, CanonicalValue> changes,
) => CanonicalObject(
  {for (final e in object.fields) e.key: e.value, ...changes}.entries,
);

void main() {
  final universe = UniverseId.parse('unv_000000000000000000000001');
  RecordRef ref(int n) => RecordRef(
    universe: universe,
    record: RecordId.parse('rec_${n.toString().padLeft(24, '0')}'),
  );
  VersionRef pin(int n) => VersionRef(
    universe: universe,
    record: ref(n).record,
    version: RecordVersionId.parse('ver_${n.toString().padLeft(24, '0')}'),
  );
  final continuity = ContinuityId.parse('cont_000000000000000000000001');
  final revision = RevisionId.parse('rev_000000000000000000000001');
  final max = BigInt.parse('18446744073709551615');
  final precise = BigInt.parse('9007199254740993');
  test(
    'bindings preserve pinned branches and segment order without merging',
    () {
      final bindings = <WorkBinding>[
        const UnboundWork(),
        BoundWork(continuity, revision),
        SegmentedWork([
          WorkSegment(
            segment: 'flashback',
            continuity: continuity,
            revision: revision,
          ),
          WorkSegment(
            segment: 'flashback',
            continuity: continuity,
            revision: revision,
          ),
        ]),
      ];
      for (final binding in bindings) {
        expect(WorkBinding.fromWire(binding.toWire()), binding);
        final version = WorkVersionRecord(
          work: ref(1),
          versionLabel: 'Author edition',
          binding: binding,
        );
        expect(RecordPayload.fromWire(version.toWire()), version);
      }
      expect((bindings.last as SegmentedWork).segments, hasLength(2));
      expect(
        () => (bindings.last as SegmentedWork).segments.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => WorkBinding.fromWire(
          CanonicalValue.parseJson(
            '{"kind":"bound","continuity":"${continuity.value}"}',
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => WorkBinding.fromWire(
          CanonicalValue.parseJson(
            '{"kind":"unbound","revision":"${revision.value}"}',
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test('scene reader position, depicted occurrences and explicit disclosures remain independent', () {
    final disclosed = [ref(3)];
    final scene = SceneRecord(
      workVersion: pin(2),
      sceneId: 'Earlier memory',
      disclosedRecords: disclosed,
      viewpoint: ref(4),
      narrativePosition: precise,
      depictedEvents: [ref(5)],
      narrationFrame: ref(6),
      worldAssociations: [],
    );
    disclosed.clear();
    expect(RecordPayload.fromWire(scene.toWire()), scene);
    expect(scene.narrativePosition, precise);
    expect(
      scene.toWire().toText(),
      contains('"narrativePosition":9007199254740993'),
    );
    expect(scene.disclosedRecords, [ref(3)]);
    expect(scene.depictedEvents, [ref(5)]);
    expect(scene.viewpoint, ref(4));
    expect(() => scene.disclosedRecords.clear(), throwsUnsupportedError);
    final bare = SceneRecord(
      workVersion: pin(2),
      sceneId: 'No disclosure',
      depictedEvents: [ref(5)],
      worldAssociations: [],
    );
    expect(bare.toWire().toText(), isNot(contains('"disclosedRecords"')));
    expect(bare.toWire().toText(), contains('"viewpoint":null'));
    expect(bare.toWire().toText(), contains('"narrativePosition":null'));
    expect(
      () => SceneRecord.fromWire(
        replace(bare.toWire(), {'disclosedRecords': const CanonicalNull()}),
      ),
      throwsFormatException,
    );
  });
  test('works and sagas retain authored membership without creating a private head', () {
    final work = WorkRecord(
      kind: WorkKind.seriesChapter,
      title: 'Campaign account',
      labels: {},
      sourceRefs: [ref(7)],
      versions: [ref(2).record],
      worldAssociations: [],
    );
    final saga = SagaRecord(
      title: 'Collected accounts',
      labels: {},
      memberships: [
        SagaMembership(work: ref(1), role: 'chapter', order: max),
        SagaMembership(work: ref(1), role: 'appendix'),
      ],
    );
    expect(RecordPayload.fromWire(work.toWire()), work);
    expect(RecordPayload.fromWire(saga.toWire()), saga);
    expect(saga.memberships.last.order, isNull);
    expect(saga.toWire().toText(), contains('18446744073709551615'));
    expect(work.toWire().toText(), contains('"kind":"series_chapter"'));
    final passage = PassageRecord(
      workVersion: pin(2),
      passageId: 'Quoted passage',
      anchor: ref(8),
    );
    expect(RecordPayload.fromWire(passage.toWire()), passage);
    expect(() => work.versions.clear(), throwsUnsupportedError);
    expect(() => saga.memberships.clear(), throwsUnsupportedError);
  });
  final source = SourceRecord(
    label: 'Attributed account',
    externalId: 'https://example.invalid/author-supplied',
    origin: const OriginMetadata(externallyAssertedAuthor: 'Narrator'),
    versions: [ref(7).record],
  );
  SourceVersionRecord sourceVersion(BigInt bytes) => SourceVersionRecord(
    source: ref(9),
    contentDigest: 'retained content digest',
    mediaType: 'text/plain',
    byteSize: bytes,
    importActor: PrincipalId.parse('prn_000000000000000000000001'),
    importTime: '2026-10-11T00:00:00Z',
    decoding: DecodingDescriptor(
      encoding: 'UTF-8',
      representation: 'decoded',
      byteLength: bytes,
    ),
    origin: source.origin,
  );
  test('source metadata retains attribution separately from editorial import and content digest', () {
    final version = sourceVersion(max);
    expect(RecordPayload.fromWire(source.toWire()), source);
    expect(RecordPayload.fromWire(version.toWire()), version);
    expect(version.byteSize, max);
    expect(version.decoding.byteLength, max);
    expect(version.contentDigest, 'retained content digest');
    expect(version.digest, payloadDigest('source_version', version.toWire()));
    expect(version.digest, isNot(version.contentDigest));
    expect(version.origin.externallyAssertedAuthor, 'Narrator');
    expect(version.toWire().toText(), contains('18446744073709551615'));
    final defaultOrigin = OriginMetadata.fromWire(
      CanonicalValue.parseJson('{}'),
    );
    expect(defaultOrigin.toWire().toText(), '{"originNote":null}');
    expect(
      () => OriginMetadata.fromWire(
        CanonicalValue.parseJson('{"verified":true}'),
      ),
      throwsFormatException,
    );
    expect(() => source.versions.clear(), throwsUnsupportedError);
  });
  test('anchor byte ranges stay exact and structural paths preserve authored Unicode', () {
    final range = ByteRangeLocator(precise, max);
    final path = StructuralPathLocator(['Chapter 🌲', 'Déjà vu', 'Chapter 🌲']);
    for (final locator in [range, path]) {
      expect(AnchorLocator.fromWire(locator.toWire()), locator);
      final anchor = AnchorRecord(
        sourceVersion: pin(7),
        locator: locator,
        excerptDigest: 'retained excerpt digest',
        excerpt: 'Author’s exact words 🌲',
        context: ref(10),
      );
      expect(RecordPayload.fromWire(anchor.toWire()), anchor);
      expect(anchor.excerpt, 'Author’s exact words 🌲');
    }
    expect(
      range.toWire().toText(),
      '{"end":18446744073709551615,"kind":"byte_range","start":9007199254740993}',
    );
    expect(() => path.path.clear(), throwsUnsupportedError);
    // These DTOs do not promote an excerpt or checksum into factual entailment.
    final unspecifiedContext = AnchorRecord(
      sourceVersion: pin(7),
      locator: range,
      excerptDigest: 'digest',
      excerpt: 'account',
    );
    expect(unspecifiedContext.toWire().toText(), contains('"context":null'));
  });
  test(
    'all u64 fields reject overflow, negatives, fractions and string coercion',
    () {
      for (final text in ['-1', '18446744073709551616', '1.5', '"1"']) {
        final value = CanonicalValue.parseJson(text);
        expect(
          () => SourceVersionRecord.fromWire(
            replace(sourceVersion(BigInt.zero).toWire(), {'byteSize': value}),
          ),
          throwsFormatException,
        );
        expect(
          () => AnchorLocator.fromWire(
            CanonicalObject([
              MapEntry('kind', CanonicalString('byte_range')),
              MapEntry('start', value),
              const MapEntry('end', CanonicalNumber('0')),
            ]),
          ),
          throwsFormatException,
        );
        expect(
          () => SagaMembership.fromWire(
            CanonicalObject([
              MapEntry('work', ref(1).toCanonical()),
              MapEntry('role', CanonicalString('chapter')),
              MapEntry('order', value),
            ]),
          ),
          throwsFormatException,
        );
      }
      expect(() => sourceVersion(max + BigInt.one), throwsFormatException);
      expect(
        () => ByteRangeLocator(-BigInt.one, BigInt.zero),
        throwsFormatException,
      );
      expect(
        () => DecodingDescriptor(
          encoding: 'UTF-8',
          representation: 'text',
          byteLength: max + BigInt.one,
        ),
        throwsFormatException,
      );
    },
  );
}
