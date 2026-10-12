import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

final recordId = RecordId.parse('rec_000000000000000000000001');
final verId = RecordVersionId.parse('ver_000000000000000000000001');
final identity = RecordVersion(
  recordVersionId: verId,
  identity: RecordIdentity(
    universeId: UniverseId.parse('unv_000000000000000000000001'),
    recordId: recordId,
    recordKind: RecordKind.world,
  ),
  payload: WorldRecord(selector: 'Earth'),
  payloadDigest: 'retained digest',
);
final receipt = InitializationReceipt(
  instance: recordId,
  start: RecordId.parse('rec_000000000000000000000002'),
  property: RecordId.parse('rec_000000000000000000000003'),
  definition: verId,
  assertion: RecordVersionId.parse('ver_000000000000000000000002'),
  revision: RevisionId.parse('rev_000000000000000000000001'),
  sourceRevision: RevisionId.parse('rev_000000000000000000000002'),
);
EffectiveObject object({
  Iterable<ObjectEvidence> candidates = const [],
  Iterable<ObjectConflict> conflicts = const [],
}) => EffectiveObject(
  identity: identity,
  ancestry: [],
  ancestryComplete: false,
  sharedAttributes: [],
  instanceFacts: [],
  initialValueCandidates: candidates,
  initializationReceipts: [receipt],
  initializationHistoryCoverage: Coverage.restricted,
  behavioralRequirements: [],
  rules: [],
  dependencies: [],
  conflicts: conflicts,
  unknowns: ['Ancestry unresolved'],
  coverage: Coverage.partial,
);
State state({
  Iterable<EffectiveObject> objects = const [],
  Chronology? chronology,
  Iterable<DerivedFact> derived = const [],
}) => State(
  objects: objects,
  derived: derived,
  epistemic: [],
  chronology: chronology,
  unresolvedAssertionIds: [recordId],
  assertions: [identity],
  propositions: [],
  completeness: [],
  coverage: Coverage.restricted,
  unsupportedCapabilities: ['descriptive_rule'],
);
CanonicalValue wire(String raw) => CanonicalValue.parseWireJson(raw);
void main() {
  test('applicability retains three states and never selects an authored candidate', () {
    for (final applies in [null, false, true]) {
      final candidate = ObjectEvidence(
        record: identity,
        applicability: applies,
        unknowns: ['Temporal applicability unresolved'],
      );
      final conflict = ObjectConflict(
        applicability: applies,
        predicate: recordId,
        assertions: [verId],
        initialValues: true,
      );
      final back = EffectiveObject.fromWire(
        object(candidates: [candidate], conflicts: [conflict]).toWire(),
      );
      expect(back.initialValueCandidates.single.applicability, applies);
      expect(back.conflicts.single.applicability, applies);
      expect(back.initialValueCandidates.single.unknowns, [
        'Temporal applicability unresolved',
      ]);
      expect(back.instanceFacts, isEmpty);
      expect(back.sharedAttributes, isEmpty);
      expect(back.ancestryComplete, isFalse);
      expect(back.coverage, Coverage.partial);
      expect(back.initializationHistoryCoverage, Coverage.restricted);
    }
    expect(
      () => ObjectEvidence.fromWire(
        wire(
          '{"record":${identity.toWire().toText()},"applicability":"unknown","unknowns":[]}',
        ),
      ),
      throwsFormatException,
    );
  });
  test('omitted contextual names remain unavailable projection rather than missing identity', () {
    final value = object().toWire();
    final absent = CanonicalObject(
      value.fields.where((e) => e.key != 'contextual_names'),
    );
    final back = EffectiveObject.fromWire(absent);
    expect(back.contextualNames, isEmpty);
    expect(back.identity.recordVersionId, verId);
    expect(back.unknowns, ['Ancestry unresolved']);
    expect(back.toWire().toText(), contains('"contextual_names":[]'));
    expect(
      () => EffectiveObject.fromWire(
        CanonicalObject([
          ...absent.fields,
          const MapEntry('contextual_names', CanonicalNull()),
        ]),
      ),
      throwsFormatException,
    );
  });
  test('receipt preserves selected definitions assertions and distinct admission/source revisions', () {
    final back = InitializationReceipt.fromWire(receipt.toWire());
    expect(back, receipt);
    expect(back.revision, isNot(back.sourceRevision));
    final admitted = back.admittedAt(
      RevisionId.parse('rev_000000000000000000000003'),
    );
    expect(admitted.sourceRevision, receipt.sourceRevision);
    expect(admitted.assertion, receipt.assertion);
    expect(admitted.definition, receipt.definition);
    expect(admitted.start, receipt.start);
    expect(admitted.revision, isNot(receipt.revision));
    expect(
      () => InitializationReceipt.fromWire(
        CanonicalObject([
          ...receipt.toWire().fields,
          const MapEntry('approved', CanonicalBool(true)),
        ]),
      ),
      throwsFormatException,
    );
  });
  test('state retains authored clock coordinates and unresolved assertions without clock advancement', () {
    final clock = Chronology(
      calendar: CalendarId.parse('cal_000000000000000000000001'),
      system: FictionalClock('day', 30),
      firstInteraction: '-9007199254740993',
      current: '9007199254740993',
    );
    final back = State.fromWire(
      state(objects: [object()], chronology: clock).toWire(),
    );
    expect(back.chronology!.current, clock.current);
    expect(back.chronology!.firstInteraction, clock.firstInteraction);
    expect(back.unresolvedAssertionIds, [recordId]);
    expect(back.assertions.single.payloadDigest, 'retained digest');
    expect(back.coverage, Coverage.restricted);
    expect(back.completeness, isEmpty);
    expect(back.unsupportedCapabilities, ['descriptive_rule']);
    expect(State.fromWire(state().toWire()).chronology, isNull);
  });
  test('derived values retain exact numeric strings and ordered evidence references', () {
    final evidence = [verId, receipt.assertion];
    final fact = DerivedFact(
      subject: RecordRef(record: recordId),
      predicate: RecordRef(record: receipt.property),
      value: DecimalValue('9007199254740993.00'),
      evidence: evidence,
      rule: recordId,
    );
    evidence.clear();
    final back = State.fromWire(state(derived: [fact]).toWire()).derived.single;
    expect((back.value as DecimalValue).digits, '9007199254740993.00');
    expect(back.evidence, [verId, receipt.assertion]);
    expect(back.rule, recordId);
    expect(() => back.evidence.clear(), throwsUnsupportedError);
  });
  test('evidence and state collections snapshot input and reject hidden inferred fields', () {
    final unknowns = ['Temporal applicability unresolved'];
    final candidate = ObjectEvidence(record: identity, unknowns: unknowns);
    unknowns.clear();
    final candidates = [candidate];
    final obj = object(candidates: candidates);
    candidates.clear();
    final objects = [obj];
    final page = state(objects: objects);
    objects.clear();
    expect(page.objects.single.initialValueCandidates.single.unknowns, [
      'Temporal applicability unresolved',
    ]);
    expect(() => page.objects.clear(), throwsUnsupportedError);
    expect(() => obj.initializationReceipts.clear(), throwsUnsupportedError);
    expect(() => candidate.unknowns.clear(), throwsUnsupportedError);
    expect(
      () => State.fromWire(
        CanonicalObject([
          ...page.toWire().fields,
          const MapEntry('selected_value', CanonicalNull()),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => State.fromWire(
        CanonicalObject(
          page.toWire().fields.where((e) => e.key != 'completeness'),
        ),
      ),
      throwsFormatException,
    );
  });
}
