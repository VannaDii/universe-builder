import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalValue json(String value) => CanonicalValue.parseJson(value);
final ref = RecordRef(record: RecordId.parse('rec_000000000000000000000001'));
final version = RecordVersionId.parse('ver_000000000000000000000001');
final universe = UniverseId.parse('unv_000000000000000000000001');
const validity = UnspecifiedValidity();

void main() {
  test(
    'typed creation keeps bare operation DTO separate from stored payload',
    () {
      final operation = DomainOperation.fromWire(
        json('''{
      "kind":"create_entity", "client_ref":"friendly name", "record":{
        "names":[], "classificationResolution":"unclassified",
        "worldAssociations":[], "labels":{}, "metadata":{}
      }
    }'''),
      ) as CreateEntityOperation;
      expect(operation.clientRef, 'friendly name');
      expect(operation.record.recordKind, RecordKind.entity);
      expect(operation.authority, OperationAuthority.ordinary);
      expect(
        operation.record.toWire().toText(),
        contains('"record_kind":"entity"'),
      );
      expect(operation.toWire().toText(), isNot(contains('record_kind')));
      final fields = operation.toWire().fields;
      expect(
        () => DomainOperation.fromWire(
          CanonicalObject([
            ...fields.where((e) => e.key != 'record'),
            MapEntry('record', operation.record.toWire()),
          ]),
        ),
        throwsFormatException,
      );
    },
  );

  test('exact expected versions and reference kinds remain distinct', () {
    final operation = InitializeInstanceOperation(
      clientRef: 'new initialization',
      instance: ref,
      start: ref,
      definition: VersionRef(record: ref.record, version: version),
      scope: Scope(applicability: const UniverseApplicability(), context: ref),
      validity: validity,
    );
    final back = DomainOperation.fromWire(
      operation.toWire(),
    ) as InitializeInstanceOperation;
    expect(back.definition.version, version);
    expect(back.instance, ref);
    expect(back.authority, OperationAuthority.ordinary);
    expect(
      () => DomainOperation.fromWire(
        json('''{
      "kind":"retract_assertion","record":{"record":"${ref.record.value}"},
      "rationale":"correction"
    }'''),
      ),
      throwsFormatException,
    );
    expect(
      () => DomainOperation.fromWire(
        json('''{
      "kind":"retract_assertion","record":{"record":"${ref.record.value}"},
      "expected_version":"${ref.record.value}","rationale":"correction"
    }'''),
      ),
      throwsFormatException,
    );
  });

  test(
    'authority labels preserve historical definition and privileged families',
    () {
      expect(
        SetStoryTimeOperation(
          record: ref,
          expectedVersion: version,
          value: 'authored coordinate',
          mode: TimeChangeKind.timeTravel,
          reason: 'explicit travel',
        ).authority,
        OperationAuthority.historical,
      );
      expect(
        RefineClassificationOperation(
          record: ref,
          expectedVersion: version,
          entityType: ref.record,
        ).authority,
        OperationAuthority.ordinary,
      );
      expect(
        IntroduceDefinitionOperation(
          clientRef: 'root',
          namespace: 'homebrew',
          key: 'root',
          name: 'Root',
          applicability: const UniverseApplicability(),
          classificationExecutable: false,
        ).authority,
        OperationAuthority.definition,
      );
      expect(
        TombstoneRecordOperation(
          record: ref,
          expectedVersion: version,
          rationale: 'reviewed removal',
        ).authority,
        OperationAuthority.privileged,
      );
    },
  );

  test(
    'optional interpretation encodes explicit null and never resolves a target',
    () {
      final operation = ReviseInterpretationOperation(
        record: ref,
        expectedVersion: version,
        rationale: 'uncertain interpretation',
      );
      final wire = operation.toWire().toText();
      expect(wire, contains('"interpretation":null'));
      expect(
        (DomainOperation.fromWire(
          operation.toWire(),
        ) as ReviseInterpretationOperation).interpretation,
        isNull,
      );
      expect(
        () => DomainOperation.fromWire(json(wire.replaceAll('null', 'false'))),
        throwsFormatException,
      );
    },
  );

  test('incremental evidence preserves explicit truth limits and immutable alternatives', () {
    final alternatives = <DomainValue>[const TextValue('remembered')];
    final evidence = AttributeEvidence(
      attributeMode: AttributeMode.instance,
      polarity: Polarity.support,
      scope: Scope(
        applicability: const UnspecifiedApplicability(),
        context: ref,
      ),
      validity: const UnknownValidity(),
      persistence: PersistenceSemantics.explicitInterval,
      precision: Precision.oneOf,
      alternatives: alternatives,
      basis: const AuthorDecisionBasis('recollection, uncorroborated'),
    );
    alternatives.clear();
    final back = AttributeEvidence.fromWire(evidence.toWire());
    expect(back.alternatives, hasLength(1));
    expect(back.validity, isA<UnknownValidity>());
    expect(back.basis, isA<AuthorDecisionBasis>());
    expect(() => back.alternatives.clear(), throwsUnsupportedError);
    expect(back.toWire().toText(), isNot(contains('establishedBy')));
  });

  test('list inputs are copied and maintain authored order and duplicates', () {
    final types = [ref.record, ref.record];
    final operation = AddNamedAttributeOperation(
      clientRef: 'attribute',
      subject: ref,
      namespace: 'local',
      key: 'detail',
      valueShape: const SimpleValueShape(SimpleShapeKind.text),
      subjectTypes: types,
      multiplicity: Multiplicity.multiple,
      value: const TextValue('value'),
      evidence: AttributeEvidence(
        attributeMode: AttributeMode.instance,
        polarity: Polarity.support,
        scope: Scope(
          applicability: const UniverseApplicability(),
          context: ref,
        ),
        validity: validity,
        persistence: PersistenceSemantics.persistentUntilChanged,
        precision: Precision.exact,
        basis: const AuthorDecisionBasis('authored'),
      ),
    );
    types.clear();
    final back = DomainOperation.fromWire(
      operation.toWire(),
    ) as AddNamedAttributeOperation;
    expect(back.subjectTypes, [ref.record, ref.record]);
    expect(() => back.subjectTypes.clear(), throwsUnsupportedError);
  });

  test('saga operation preserves exact u64 positions on VM and web', () {
    final operation = SetSagaMembershipOperation(
      record: ref,
      expectedVersion: version,
      membership: SagaMembership(
        work: ref,
        role: 'volume',
        order: BigInt.parse('18446744073709551615'),
      ),
    );
    final back = DomainOperation.fromWire(
      operation.toWire(),
    ) as SetSagaMembershipOperation;
    expect(back.membership.order, BigInt.parse('18446744073709551615'));
  });

  test('record version preserves declared digest and leaves adoption to service admission', () {
    final payload = DomainOperation.fromWire(
      json('''{
      "kind":"create_world","client_ref":"world","record":{
        "selector":"Example", "labels":{}
      }
    }'''),
    ) as CreateWorldOperation;
    final identity = RecordIdentity(
      universeId: universe,
      recordId: ref.record,
      recordKind: RecordKind.world,
    );
    final built = RecordVersion.build(
      recordVersionId: version,
      identity: identity,
      payload: payload.record,
    );
    expect(built.verifiesDigest, isTrue);
    final declared = RecordVersion(
      recordVersionId: version,
      identity: identity,
      payload: payload.record,
      payloadDigest: 'unverified declared value',
    );
    final operation = AdoptRecordVersionOperation(source: declared);
    final back = DomainOperation.fromWire(
      operation.toWire(),
    ) as AdoptRecordVersionOperation;
    expect(back.source.payloadDigest, declared.payloadDigest);
    expect(back.source.verifiesDigest, isFalse);
    expect(back.expectedVersion, isNull);
    expect(back.authority, OperationAuthority.privileged);
    expect(
      () => RecordVersion.build(
        recordVersionId: version,
        identity: RecordIdentity(
          universeId: universe,
          recordId: ref.record,
          recordKind: RecordKind.entity,
        ),
        payload: payload.record,
      ),
      throwsFormatException,
    );
  });

  test('unknown variants and authority injection are rejected', () {
    expect(
      () => DomainOperation.fromWire(json('{"kind":"publish_without_review"}')),
      throwsFormatException,
    );
    expect(
      () => DomainOperation.fromWire(
        json('''{
      "kind":"revise_interpretation","record":{"record":"${ref.record.value}"},
      "expected_version":"${version.value}","rationale":"reason","authority":"ordinary"
    }'''),
      ),
      throwsFormatException,
    );
  });
}
