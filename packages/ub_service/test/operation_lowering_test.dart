import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/operation_compilation.dart';

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
final universe = UniverseId.parse('unv_${suffix(1)}');
RecordRef ref(int n) => RecordRef(universe: universe, record: id(n));
RecordVersion record(int n, RecordPayload p) => RecordVersion.build(
  recordVersionId: RecordVersionId.parse('ver_${suffix(n)}'),
  identity: RecordIdentity(
    universeId: universe,
    recordId: id(n),
    recordKind: p.recordKind,
  ),
  payload: p,
);
AttributeEvidence evidence({
  EvidenceBasis basis = const ImportedClaimBasis(),
}) => AttributeEvidence(
  attributeMode: AttributeMode.instance,
  polarity: Polarity.support,
  scope: Scope(context: ref(99), applicability: const UniverseApplicability()),
  validity: const UnknownValidity(),
  persistence: PersistenceSemantics.unspecified,
  precision: Precision.unresolved,
  alternatives: [const TextValue('alternative')],
  basis: basis,
);
AddNamedAttributeOperation attribute(
  String client, {
  EvidenceBasis basis = const ImportedClaimBasis(),
  ValueShape shape = const SimpleValueShape(SimpleShapeKind.text),
}) => AddNamedAttributeOperation(
  clientRef: client,
  subject: ref(4),
  namespace: 'test',
  key: 'hazard',
  valueShape: shape,
  subjectTypes: [id(1)],
  multiplicity: Multiplicity.multiple,
  value: TextValue('Hazard $client'),
  evidence: evidence(basis: basis),
);
PropertyRecord property({
  Map<String, String> labels = const {},
  ValueShape shape = const SimpleValueShape(SimpleShapeKind.text),
  Multiplicity multiplicity = Multiplicity.multiple,
  PersistenceSemantics persistence = PersistenceSemantics.unspecified,
  List<RecordId>? types,
  bool exclusive = false,
  String? dimension,
}) => PropertyRecord(
  namespace: 'test',
  key: 'hazard',
  labels: labels,
  subjectTypes: types ?? [id(1)],
  value: shape,
  multiplicity: multiplicity,
  persistence: persistence,
  exclusive: exclusive,
  symmetric: false,
  transitive: false,
  unitDimension: dimension,
);
List<DomainOperation> lower(
  List<DomainOperation> operations, {
  List<RecordVersion> base = const [],
}) => lowerAuthoringOperations(
  universe: universe,
  base: base,
  operations: operations,
);
final denied = throwsA(
  isA<InvalidArgumentError>().having((e) => e.field, 'field', 'operations'),
);
void main() {
  test('definition introductions preserve authored ancestry and executable classification', () {
    for (final parent in [null, id(1)]) {
      final op = IntroduceDefinitionOperation(
        clientRef: 'definition',
        namespace: 'test',
        key: 'type',
        name: 'Named type',
        parent: parent,
        applicability: const ConditionalApplicability(),
        classificationExecutable: false,
      );
      final d = (lower([op]).single as DefineTypeOperation).record;
      expect(d.name, 'Named type');
      expect(d.parent, parent);
      expect(d.classificationExecutable, isFalse);
      expect(
        d.parentResolution,
        parent == null ? ParentResolution.root : ParentResolution.resolved,
      );
      expect(d.applicability, const ConditionalApplicability());
      expect(d.labels, isEmpty);
    }
  });
  test('instance introductions preserve contextual names and explicit world associations', () {
    final name = ContextualName(
      text: 'Alias',
      language: 'en',
      community: 'narrator',
      role: 'pseudonym',
      validity: const UnknownValidity(),
    );
    final world = WorldAssociation(
      world: WorldId.parse('wld_${suffix(20)}'),
      role: 'origin',
      validity: const UnspecifiedValidity(),
      qualifiers: {},
    );
    for (final type in [null, id(1)]) {
      final op = IntroduceInstanceOperation(
        clientRef: id(4).value,
        name: name,
        classification: type,
        worldAssociations: [world],
      );
      final e = (lower([op]).single as CreateEntityOperation).record;
      expect(e.names.single.toWire().toText(), name.toWire().toText());
      expect(
        e.worldAssociations.single.toWire().toText(),
        world.toWire().toText(),
      );
      expect(e.classification, type);
      expect(
        e.classificationResolution,
        type == null
            ? ClassificationResolution.unclassified
            : ClassificationResolution.resolved,
      );
      expect(e.labels, isEmpty);
      expect(e.metadata, isEmpty);
    }
  });
  test('blank authored names follow existing whitespace rules without trimming content', () {
    for (final name in ['', '\u0085\u3000']) {
      expect(
        () => lower([
          IntroduceDefinitionOperation(
            clientRef: 'd',
            namespace: 'test',
            key: 'type',
            name: name,
            applicability: const UniverseApplicability(),
            classificationExecutable: true,
          ),
        ]),
        denied,
      );
      expect(
        () => lower([
          IntroduceInstanceOperation(
            clientRef: 'i',
            name: ContextualName(
              text: name,
              validity: const UnspecifiedValidity(),
            ),
            worldAssociations: [],
          ),
        ]),
        denied,
      );
    }
    final op = IntroduceInstanceOperation(
      clientRef: 'i',
      name: const ContextualName(
        text: '\ufeff',
        validity: UnspecifiedValidity(),
      ),
      worldAssociations: [],
    );
    expect(
      (lower([op]).single as CreateEntityOperation).record.names.single.text,
      '\ufeff',
    );
  });
  test('same-batch attributes share one definition and retain exact submitted evidence', () {
    final inputs = [attribute('first'), attribute('second')],
        result = lower([attribute('first'), attribute('second')]);
    expect(result.length, 3);
    expect(result.whereType<DefinePropertyOperation>().length, 1);
    final definition = result.first as DefinePropertyOperation,
        assertions = result.whereType<AssertPropositionOperation>().toList();
    for (var n = 0; n < assertions.length; n++) {
      final a = assertions[n];
      expect(
        a.proposition.predicate,
        RecordRef(
          universe: universe,
          record: RecordId.parse(definition.clientRef),
        ),
      );
      expect(a.proposition.subject, ref(4));
      expect(a.proposition.quantification, Quantification.particular);
      expect(a.assertion.proposition.record.value, a.clientRef);
      expect(a.assertion.establishedBy, isNull);
      expect(a.assertion.validity, inputs[n].evidence.validity);
      expect(a.assertion.precision, inputs[n].evidence.precision);
      expect(a.assertion.alternatives, inputs[n].evidence.alternatives);
      expect(a.assertion.basis, inputs[n].evidence.basis);
      expect(a.proposition.value, inputs[n].value);
    }
    expect(assertions[0].clientRef, isNot(assertions[1].clientRef));
    expect(() => result.clear(), throwsUnsupportedError);
    final explicit =
        lower([attribute(id(50).value)]).last as AssertPropositionOperation;
    expect(explicit.clientRef, id(50).value);
  });
  test('existing definitions retain labels but cannot silently change semantic fields', () {
    final existing = record(10, property(labels: {'en': 'Hazard'}));
    final result = lower([attribute('new')], base: [existing]);
    expect(result.length, 1);
    expect(
      (result.single as AssertPropositionOperation).proposition.predicate,
      ref(10),
    );
    for (final p in [
      property(shape: const SimpleValueShape(SimpleShapeKind.boolean)),
      property(multiplicity: Multiplicity.single),
      property(persistence: PersistenceSemantics.explicitInterval),
      property(types: []),
      property(exclusive: true),
      property(dimension: 'length'),
    ]) {
      expect(() => lower([attribute('new')], base: [record(10, p)]), denied);
    }
    expect(existing.payload, property(labels: {'en': 'Hazard'}));
    expect(
      () => lower([attribute('new')], base: [existing, record(11, property())]),
      denied,
    );
  });
  test('explicit same-batch property references work in either order and require reserved identity', () {
    final definition = DefinePropertyOperation(
      clientRef: id(10).value,
      record: property(labels: {'en': 'Hazard'}),
    );
    for (final ops in <List<DomainOperation>>[
      [definition, attribute('value')],
      [attribute('value'), definition],
    ]) {
      final result = lower(ops);
      expect(result.whereType<DefinePropertyOperation>().length, 1);
      expect(
        result
            .whereType<AssertPropositionOperation>()
            .single
            .proposition
            .predicate,
        ref(10),
      );
    }
    expect(
      () => lower([
        DefinePropertyOperation(clientRef: 'friendly', record: property()),
        attribute('value'),
      ]),
      denied,
    );
    final unnamed = DefinePropertyOperation(
      clientRef: 'friendly',
      record: property(),
    );
    expect(lower([unnamed]).single, same(unnamed));
    expect(
      () => lower([
        definition,
        DefinePropertyOperation(clientRef: id(11).value, record: property()),
        attribute('value'),
      ]),
      denied,
    );
  });
  test(
    'client references remain unique across lowered and retained operations',
    () {
      expect(() => lower([attribute('same'), attribute('same')]), denied);
      expect(() => lower([attribute('')]), denied);
      expect(
        () => lower([
          attribute('same'),
          DefinePropertyOperation(clientRef: 'same', record: property()),
        ]),
        denied,
      );
      expect(
        lower([attribute(' ')]).whereType<AssertPropositionOperation>().length,
        1,
      );
    },
  );
  test(
    'named attributes cannot manufacture event or initialization provenance',
    () {
      expect(
        () => lower([
          attribute('value', basis: EventEffectBasis(ref(20), 'effect')),
        ]),
        denied,
      );
      final source = VersionRef(
        universe: universe,
        record: id(20),
        version: RecordVersionId.parse('ver_${suffix(20)}'),
      );
      expect(
        () => lower([
          attribute(
            'value',
            basis: InstanceInitializationBasis(
              source,
              source,
              RevisionId.parse('rev_${suffix(1)}'),
            ),
          ),
        ]),
        denied,
      );
    },
  );
  test('refinement lowering preserves its exact expected version without admitting classification', () {
    final version = RecordVersionId.parse('ver_${suffix(4)}');
    final op = RefineClassificationOperation(
      record: ref(4),
      expectedVersion: version,
      entityType: id(2),
    );
    final result = lower([op]).single as AddTypeMembershipOperation;
    expect(result.record, op.record);
    expect(result.expectedVersion, version);
    expect(result.entityType, id(2));
    final retained = CreateWorldOperation(
      clientRef: 'world',
      record: WorldRecord(selector: 'new-world'),
    );
    expect(lower([retained]).single, same(retained));
  });
}
