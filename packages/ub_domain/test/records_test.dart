import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final universe = UniverseId.parse('unv_000000000000000000000001');
  RecordRef ref(int n) => RecordRef(
    universe: universe,
    record: RecordId.parse('rec_${n.toString().padLeft(24, '0')}'),
  );
  final proposition = PropositionRecord(
    predicate: ref(1),
    subject: ref(2),
    roles: [PropositionRole('owner', ref(3))],
    value: IntegerValue('00012'),
    quantification: Quantification.particular,
    context: ref(4),
  );
  final assertion = AssertionRecord(
    attributeMode: AttributeMode.instance,
    proposition: ref(5),
    polarity: Polarity.support,
    scope: Scope(
      applicability: WorldsApplicability([
        WorldId.parse('wld_000000000000000000000001'),
      ]),
      context: ref(4),
    ),
    validity: const IntervalValidity(UnknownBound(), UnboundedBound()),
    persistence: PersistenceSemantics.persistentUntilChanged,
    precision: Precision.oneOf,
    alternatives: [IntegerValue('12'), IntegerValue('7')],
    basis: SourceAnchorBasis(ref(6), false),
    establishedBy: EventEffectRef(ref(7), 'authored slot'),
  );
  test(
    'typed proposition and assertion preserve every independent authored field',
    () {
      expect(RecordPayload.fromWire(proposition.toWire()), proposition);
      expect(RecordPayload.fromWire(assertion.toWire()), assertion);
      expect(proposition.value, IntegerValue('00012'));
      expect(assertion.polarity, Polarity.support);
      expect(assertion.precision, Precision.oneOf);
      expect(assertion.basis, SourceAnchorBasis(ref(6), false));
      expect(assertion.establishedBy, EventEffectRef(ref(7), 'authored slot'));
      expect(() => proposition.roles.clear(), throwsUnsupportedError);
      expect(() => assertion.alternatives.clear(), throwsUnsupportedError);
    },
  );
  test(
    'record digests retain wire encoding independently from scope comparison',
    () {
      expect(assertion.toCanonical().toText(), assertion.toWire().toText());
      expect(assertion.toWire().toText(), contains('"world_ids"'));
      expect(assertion.toWire().toText(), isNot(contains('"worldIds"')));
      expect(assertion.scope.toCanonical().toText(), contains('"worldIds"'));
      expect(assertion.digest, payloadDigest('assertion', assertion.toWire()));
      final derivation = AssertionRecord(
        attributeMode: assertion.attributeMode,
        proposition: assertion.proposition,
        polarity: assertion.polarity,
        scope: assertion.scope,
        validity: assertion.validity,
        persistence: assertion.persistence,
        precision: assertion.precision,
        basis: DerivationBasis([], null),
      );
      expect(derivation.toWire().toText(), contains('"evaluator":null'));
      expect(
        derivation.basis.toCanonical().toText(),
        isNot(contains('"evaluator"')),
      );
    },
  );
  test('optional record fields normalize serde defaults without accepting null vectors', () {
    final bare = PropositionRecord(
      predicate: ref(1),
      subject: ref(2),
      quantification: Quantification.exists,
      context: ref(4),
    );
    final fields = bare.toWire().fields;
    final explicit = CanonicalObject([
      ...fields,
      const MapEntry('value', CanonicalNull()),
      MapEntry('roles', CanonicalArray([])),
    ]);
    expect(PropositionRecord.fromWire(explicit), bare);
    expect(bare.toWire().toText(), isNot(contains('"roles"')));
    expect(bare.toWire().toText(), isNot(contains('"value"')));
    expect(
      () => PropositionRecord.fromWire(
        CanonicalObject([...fields, const MapEntry('roles', CanonicalNull())]),
      ),
      throwsFormatException,
    );
  });
  test(
    'records reject unknown fields, wrong discriminators and unknown families',
    () {
      expect(
        () => PropositionRecord.fromWire(
          CanonicalObject([
            ...proposition.toWire().fields,
            const MapEntry('invented', CanonicalBool(true)),
          ]),
        ),
        throwsFormatException,
      );
      expect(
        () => AssertionRecord.fromWire(proposition.toWire()),
        throwsFormatException,
      );
      expect(
        () => RecordPayload.fromWire(
          CanonicalValue.parseJson('{"record_kind":"invented"}'),
        ),
        throwsFormatException,
      );
      expect(
        () => AttributeMode.fromWire(CanonicalString('initial')),
        throwsFormatException,
      );
      expect(
        () => Quantification.fromWire(CanonicalString('some')),
        throwsFormatException,
      );
    },
  );
}
