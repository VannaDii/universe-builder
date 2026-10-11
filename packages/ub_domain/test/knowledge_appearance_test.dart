import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalObject replace(
  CanonicalObject object,
  Map<String, CanonicalValue> changes,
) => CanonicalObject(
  {for (final e in object.fields) e.key: e.value, ...changes}.entries,
);

void main() {
  RecordRef ref(int n) =>
      RecordRef(record: RecordId.parse('rec_${n.toString().padLeft(24, '0')}'));
  const time = UnspecifiedTime();
  const validity = UnknownValidity();
  const evidence = AuthorDecisionBasis('Authored account');
  test(
    'all five attitudes remain authored alternatives without truth promotion',
    () {
      for (final kind in EpistemicAttitudeKind.values) {
        final record = EpistemicAttitudeRecord(
          holder: ref(1),
          proposition: ref(2),
          attitude: kind,
          validity: validity,
          basis: evidence,
        );
        expect(RecordPayload.fromWire(record.toWire()), record);
        expect(record.attitude, kind);
        expect(record.acquisition, isNull);
        expect(record.toWire().toText(), isNot(contains('"acquisition"')));
        expect(record.toWire().toText(), contains('"certainty":null'));
      }
      expect(
        () => EpistemicAttitudeKind.fromName('verified'),
        throwsFormatException,
      );
    },
  );
  test('knowledge acquisition retains explicit truth context, receipt and interpretation', () {
    final acquisition = KnowledgeAcquisition(
      truthContext: ref(3),
      time: time,
      basis: CommunicationKnowledge(communication: ref(4)),
    );
    final record = EpistemicAttitudeRecord(
      acquisition: acquisition,
      holder: ref(1),
      proposition: ref(2),
      attitude: EpistemicAttitudeKind.knows,
      certainty: 'author stated',
      validity: validity,
      basis: evidence,
    );
    expect(RecordPayload.fromWire(record.toWire()), record);
    expect(acquisition.world, isNull);
    expect(acquisition.toWire().toText(), isNot(contains('"world"')));
    expect(acquisition.toWire().toText(), contains('"interpretation":null'));
    final explicit = KnowledgeAcquisition(
      truthContext: ref(3),
      time: time,
      world: ref(5),
      basis: CommunicationKnowledge(
        communication: ref(4),
        interpretation: ref(2),
      ),
    );
    expect(KnowledgeAcquisition.fromWire(explicit.toWire()).world, ref(5));
    expect(
      (KnowledgeAcquisition.fromWire(explicit.toWire()).basis
              as CommunicationKnowledge)
          .interpretation,
      ref(2),
    );
    for (final mode in KnowledgeMode.values) {
      final policy = KnowledgePolicy(context: ref(3), mode: mode);
      expect(KnowledgePolicy.fromWire(policy.toWire()).mode, mode);
    }
    expect(
      KnowledgeBasis.fromWire(const AuthorEstablishedKnowledge().toWire()),
      isA<AuthorEstablishedKnowledge>(),
    );
    expect(
      () => KnowledgeBasis.fromWire(
        CanonicalValue.parseJson(
          '{"kind":"author_established","verified":true}',
        ),
      ),
      throwsFormatException,
    );
  });
  test('observation keeps sensory access independent of interpretation', () {
    final record = ObservationRecord(
      observer: ref(1),
      observed: ref(6),
      sensoryAccess: false,
      time: time,
      interpretation: ref(2),
      basis: evidence,
    );
    expect(RecordPayload.fromWire(record.toWire()), record);
    expect(record.sensoryAccess, isFalse);
    expect(record.interpretation, ref(2));
    final uninterpreted = ObservationRecord(
      observer: ref(1),
      observed: ref(6),
      sensoryAccess: true,
      time: time,
      basis: evidence,
    );
    expect(uninterpreted.toWire().toText(), contains('"interpretation":null'));
    expect(
      () => ObservationRecord.fromWire(
        replace(record.toWire(), {'sensoryAccess': CanonicalString('true')}),
      ),
      throwsFormatException,
    );
  });
  test('intended recipients do not become actual receipt and duplicates remain ordered', () {
    final intended = [ref(1), ref(2), ref(1)];
    final record = CommunicationRecord(
      sender: ref(3),
      intendedRecipients: intended,
      actualRecipients: [ref(2)],
      content: [ref(4), ref(4)],
      sentAt: time,
      distorted: true,
    );
    intended.clear();
    expect(RecordPayload.fromWire(record.toWire()), record);
    expect(record.intendedRecipients, [ref(1), ref(2), ref(1)]);
    expect(record.actualRecipients, [ref(2)]);
    expect(record.distorted, isTrue);
    expect(record.receivedAt, isNull);
    expect(record.toWire().toText(), contains('"receivedAt":null'));
    expect(() => record.content.clear(), throwsUnsupportedError);
    expect(
      () => CommunicationRecord.fromWire(
        replace(record.toWire(), {'actualRecipients': const CanonicalNull()}),
      ),
      throwsFormatException,
    );
  });
  test('memory and fictional secrecy retain uncertainty and do not confer application grants', () {
    final memory = MemoryRecord(
      holder: ref(1),
      content: ref(2),
      alleged: ref(6),
      accessibility: 'partial',
      altered: true,
      validity: validity,
    );
    final secret = SecretRecord(
      scope: [ref(2)],
      fictionalKnowers: [ref(1)],
      readerDisclosed: false,
      validity: validity,
    );
    expect(RecordPayload.fromWire(memory.toWire()), memory);
    expect(RecordPayload.fromWire(secret.toWire()), secret);
    expect(memory.alleged, ref(6));
    expect(memory.altered, isTrue);
    expect(memory.validity, const UnknownValidity());
    expect(secret.readerDisclosed, isFalse);
    expect(secret.toWire().toText(), contains('"concealment":null'));
    expect(() => secret.fictionalKnowers.clear(), throwsUnsupportedError);
    expect(
      () => SecretRecord.fromWire(
        replace(secret.toWire(), {'grant': CanonicalString('owner')}),
      ),
      throwsFormatException,
    );
  });
  test('completeness distinguishes an explicit empty objective set from observer knowledge', () {
    for (final kind in [
      const ObjectiveCompleteness(),
      ObserverCompleteness(ref(1).record),
    ]) {
      final record = CompletenessRecord(
        subject: ref(1),
        predicate: 'siblings',
        members: [],
        completeness: kind,
        validity: validity,
        scope: Scope(
          applicability: const UniverseApplicability(),
          context: ref(3),
        ),
      );
      expect(RecordPayload.fromWire(record.toWire()), record);
      expect(record.members, isEmpty);
      expect(() => record.members.clear(), throwsUnsupportedError);
    }
    expect(
      const ObjectiveCompleteness().toWire().toText(),
      '"objective_reality"',
    );
    expect(const ObjectiveCompleteness().toCanonical().toText(), '"objective"');
    final observer = ObserverCompleteness(ref(1).record);
    expect(
      observer.toWire().toText(),
      '{"observer_known":{"observer":"${ref(1).record.value}"}}',
    );
    expect(
      observer.toCanonical().toText(),
      '{"kind":"observer_known","observer":"${ref(1).record.value}"}',
    );
    expect(
      () => CompletenessKind.fromWire(observer.toCanonical()),
      throwsFormatException,
    );
  });
  test('visual references preserve purpose, relationship and snake-case record fields', () {
    for (final target in [
      const UniverseAppearance(),
      EntryAppearance(ref(1)),
    ]) {
      final images = [
        AppearanceImage(
          asset: ref(7),
          caption: 'Authored reference 🌲',
          purpose: ImagePurpose.inspiration,
        ),
      ];
      final record = AppearanceRecord(
        target: target,
        label: 'Dossier',
        physicalDescription: 'Later appearance',
        atmosphere: 'Authored atmosphere',
        images: images,
        links: [
          AppearanceLink(
            entry: ref(2),
            relationship: AppearanceRelationship.detailOf,
            note: 'Reference detail',
          ),
        ],
        validity: validity,
      );
      images.clear();
      expect(RecordPayload.fromWire(record.toWire()), record);
      expect(record.images.single.purpose, ImagePurpose.inspiration);
      expect(record.toWire().toText(), contains('"physical_description"'));
      expect(record.toWire().toText(), contains('"relationship":"detail_of"'));
      expect(() => record.images.clear(), throwsUnsupportedError);
    }
    expect(
      () => AppearanceTarget.fromWire(
        CanonicalValue.parseJson(
          '{"kind":"universe","entry":${ref(1).toCanonical().toText()}}',
        ),
      ),
      throwsFormatException,
    );
  });
  test(
    'image descriptors preserve u64 sizes and enforce u32 dimension boundaries',
    () {
      final max = BigInt.parse('18446744073709551615');
      final image = ImageAssetRecord(
        contentDigest: 'content checksum',
        mediaType: 'image/png',
        byteSize: max,
        width: 4294967295,
        height: 0,
        originalName: 'Reference 🌲.png',
      );
      expect(RecordPayload.fromWire(image.toWire()), image);
      expect(image.byteSize, max);
      expect(image.digest, isNot(image.contentDigest));
      expect(image.toWire().toText(), contains('"width":4294967295'));
      for (final token in ['4294967296', '-1', '1.5', '"1"']) {
        expect(
          () => ImageAssetRecord.fromWire(
            replace(image.toWire(), {'width': CanonicalValue.parseJson(token)}),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => ImageAssetRecord(
          contentDigest: 'checksum',
          mediaType: 'image/png',
          byteSize: BigInt.one,
          width: -1,
          height: 1,
          originalName: 'x',
        ),
        throwsFormatException,
      );
    },
  );
}
