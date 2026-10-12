import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/proposal_authorization.dart';
import 'package:ub_store/ub_store.dart';

import 'operation_compilation_test.dart' as fixtures;

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
WorldId world(int n) => WorldId.parse('wld_${suffix(n)}');
final u = fixtures.u, continuity = ContinuityId.parse('cont_${suffix(1)}');
RecordRef ref(int n) => RecordRef(universe: u, record: id(n));
RecordVersion row(int n, RecordPayload p) => fixtures.row(n, p);
StoredVersion stored(RecordVersion r) => StoredVersion(
  versionId: r.recordVersionId,
  identity: r.identity,
  payload: r.payload.toWire(),
  digest: r.payloadDigest,
);
Assignment change(RecordVersion r) =>
    Assignment(recordId: r.identity.recordId, next: stored(r));
WorldAssociation association(int n) => WorldAssociation(
  world: world(n),
  role: 'setting',
  validity: const UnspecifiedValidity(),
  qualifiers: {},
);
EntityRecord entity({
  List<int> worlds = const [],
  Map<String, DomainValue> metadata = const {},
  Map<String, String> labels = const {},
}) => EntityRecord(
  names: [],
  classificationResolution: ClassificationResolution.unclassified,
  worldAssociations: worlds.map(association),
  labels: labels,
  metadata: metadata,
);
PropositionRecord prop({
  int subject = 1,
  int predicate = 2,
  int context = 3,
  DomainValue? value,
  List<PropositionRole> roles = const [],
}) => PropositionRecord(
  subject: ref(subject),
  predicate: ref(predicate),
  context: ref(context),
  value: value,
  roles: roles,
  quantification: Quantification.particular,
);
Scope scope(List<int> worlds) => Scope(
  context: ref(3),
  applicability: WorldsApplicability(worlds.map(world)),
);
AssertionRecord assertion({List<int> worlds = const [], int target = 4}) =>
    AssertionRecord(
      attributeMode: AttributeMode.instance,
      proposition: ref(target),
      polarity: Polarity.support,
      scope: scope(worlds),
      validity: const UnspecifiedValidity(),
      persistence: PersistenceSemantics.unspecified,
      precision: Precision.exact,
      basis: const AuthorDecisionBasis('authored'),
    );
final denied = throwsA(isA<PolicyDeniedError>());
void boundaries(
  List<RecordVersion> base,
  List<Assignment> changes,
  GrantLimits limits,
) => checkWriteBoundaries(
  base: base,
  changes: changes,
  continuity: continuity,
  limits: limits,
);

void main() {
  test('world identities, direct associations and declaration scopes stay explicit', () {
    expect(recordWorld(id(1)), world(1));
    expect(recordWorlds(row(1, WorldRecord(selector: 'Earth'))), {world(1)});
    expect(recordWorlds(row(1, entity(worlds: [1, 2, 1]))), {
      world(1),
      world(2),
    });
    expect(recordWorlds(row(1, assertion(worlds: [2]))), {world(2)});
    expect(recordWorlds(row(1, prop())), isEmpty);
    expect(recordWorlds(row(1, fixtures.type(1))), isEmpty);
    final work = WorkRecord(
      kind: WorkKind.novel,
      title: 'Book',
      labels: {},
      sourceRefs: [],
      versions: [],
      worldAssociations: [association(2)],
    );
    expect(recordWorlds(row(1, work)), {world(2)});
    expect(
      recordWorlds(row(1, entity(labels: {'world': world(1).value}))),
      isEmpty,
    );
  });

  test('old and new worlds are both required for a reassignment', () {
    final old = row(1, entity(worlds: [1])), next = row(1, entity(worlds: [2]));
    final footprint = writeFootprint(base: [old], changes: [change(next)]);
    expect(footprint.worlds, {world(1), world(2)});
    expect(footprint.shared, isFalse);
    expect(footprint.protected, isFalse);
    expect(
      footprint.toWire().toText(),
      '{"protected":false,"shared":false,"worlds":["${world(1).value}","${world(2).value}"]}',
    );
    expect(() => footprint.worlds.clear(), throwsUnsupportedError);
    final removal = writeFootprint(
      base: [old],
      changes: [Assignment(recordId: id(1))],
    );
    expect(removal.worlds, {world(1)});
    expect(removal.protected, isTrue);
  });

  test('shared writes remain shared even when dependencies lead to a granted world', () {
    final base = [
      row(1, entity(worlds: [1])),
      row(3, entity(worlds: [2])),
    ];
    final footprint = writeFootprint(
      base: base,
      changes: [change(row(4, prop()))],
    );
    expect(footprint.shared, isTrue);
    expect(footprint.worlds, {world(1), world(2)});
    expect(footprint.protected, isFalse);
    final protected = writeFootprint(
      base: base,
      changes: [change(row(5, fixtures.type(5)))],
    );
    expect(protected.shared, isTrue);
    expect(protected.protected, isTrue);
    final empty = writeFootprint(base: [], changes: []);
    expect(empty.worlds, isEmpty);
    expect(empty.shared, isFalse);
    expect(empty.protected, isFalse);
  });

  test('candidate dependencies take precedence and cycles terminate', () {
    final first = row(
      1,
      entity(
        worlds: [1],
        metadata: {'text': ReferenceValue(ValueReferenceKind.entity, ref(2))},
      ),
    );
    final second = row(
      2,
      entity(
        worlds: [2],
        metadata: {'cycle': ReferenceValue(ValueReferenceKind.entity, ref(1))},
      ),
    );
    final next = row(2, entity(worlds: [3]));
    final footprint = writeFootprint(
      base: [first, second],
      changes: [change(first), change(next)],
    );
    expect(footprint.worlds, {world(1), world(2), world(3)});
    expect(footprint.shared, isFalse);
    final cycle = writeFootprint(
      base: [first, second],
      changes: [change(first)],
    );
    expect(cycle.worlds, {world(1), world(2)});
    expect(cycle.shared, isFalse);
  });

  test(
    'malformed reference footprints conservatively require shared authority',
    () {
      final foreign = RecordRef(
        universe: UniverseId.parse('unv_${suffix(2)}'),
        record: id(2),
      );
      for (final target in [foreign, RecordRef(record: id(2))]) {
        final changed = row(
          1,
          entity(
            worlds: [1],
            metadata: {
              'reference': ReferenceValue(ValueReferenceKind.entity, target),
            },
          ),
        );
        expect(
          writeFootprint(base: [], changes: [change(changed)]).shared,
          isTrue,
        );
        expect(
          () => recordDependencies(stored(changed)),
          throwsFormatException,
        );
      }
    },
  );

  test('typed dependency traversal ignores prose and respects typed value-map names', () {
    final r = row(
      1,
      entity(
        labels: {'parent': id(2).value},
        metadata: {
          'text': ReferenceValue(ValueReferenceKind.entity, ref(3)),
          'world': TextValue(world(2).value),
        },
      ),
    );
    expect(recordDependencies(stored(r)), {id(3)});
    expect(() => recordDependencies(stored(r)).clear(), throwsUnsupportedError);
    final exact = row(
      4,
      SceneRecord(
        workVersion: VersionRef(
          universe: u,
          record: id(3),
          version: fixtures.ver(99),
        ),
        sceneId: 'Scene',
        depictedEvents: [],
        worldAssociations: [],
      ),
    );
    expect(recordDependencies(stored(exact)), {id(3)});
  });

  test(
    'visibility hides wrong worlds and every transitively dependent record',
    () {
      final records = [
        row(1, entity(worlds: [1])),
        row(2, entity(worlds: [2])),
        row(3, entity()),
        row(4, prop()),
        row(5, assertion(worlds: [1])),
      ];
      expect(visibleRecordIds(records: records, worldScope: {world(1)}), {
        id(1),
        id(3),
      });
      expect(
        visibleRecordIds(records: records, worldScope: {world(1), world(2)}),
        records.map((r) => r.identity.recordId).toSet(),
      );
      expect(
        visibleRecordIds(records: records, worldScope: null),
        records.map((r) => r.identity.recordId).toSet(),
      );
    },
  );

  test(
    'missing dependencies and archived-only pins hide scoped dependents',
    () {
      final records = [
        row(1, entity(worlds: [1])),
        row(4, prop()),
        row(5, assertion(worlds: [1])),
      ];
      expect(visibleRecordIds(records: records, worldScope: {world(1)}), {
        id(1),
      });
      final scene = row(
        6,
        SceneRecord(
          workVersion: VersionRef(
            universe: u,
            record: id(9),
            version: fixtures.ver(9),
          ),
          sceneId: 'Pinned',
          depictedEvents: [],
          worldAssociations: [],
        ),
      );
      expect(
        visibleRecordIds(records: [...records, scene], worldScope: {world(1)}),
        {id(1)},
      );
      expect(visibleRecordIds(records: [scene], worldScope: null), {id(6)});
    },
  );

  test('private source and universe appearance are hidden even in all listed worlds', () {
    final source = row(
      1,
      SourceRecord(
        label: 'Private memory',
        origin: const OriginMetadata(),
        versions: [],
      ),
    );
    final appearance = row(
      2,
      AppearanceRecord(
        target: const UniverseAppearance(),
        label: 'Universe',
        physicalDescription: '',
        atmosphere: '',
        images: [],
        links: [],
        validity: const UnspecifiedValidity(),
      ),
    );
    final dependent = row(
      3,
      RepresentedContextRecord(
        universe: u,
        kind: SourceContext(ref(1)),
        labels: {},
      ),
    );
    expect(
      visibleRecordIds(
        records: [source, appearance, dependent],
        worldScope: {world(1), world(2)},
      ),
      isEmpty,
    );
    expect(
      visibleRecordIds(
        records: [source, appearance, dependent],
        worldScope: null,
      ),
      {id(1), id(2), id(3)},
    );
  });

  test('visibility closes cycles and rejects malformed namespaces instead of leaking IDs', () {
    final first = row(
      1,
      entity(
        worlds: [1],
        metadata: {'link': ReferenceValue(ValueReferenceKind.entity, ref(2))},
      ),
    );
    final second = row(
      2,
      entity(
        worlds: [2],
        metadata: {'link': ReferenceValue(ValueReferenceKind.entity, ref(1))},
      ),
    );
    expect(
      visibleRecordIds(records: [first, second], worldScope: {world(1)}),
      isEmpty,
    );
    final malformed = row(3, prop(subject: 1, context: 2));
    final bad = fixtures.patch(malformed.payload as PropositionRecord, {
      'subject': RecordRef(record: id(1)).toCanonical(),
    });
    expect(
      () => visibleRecordIds(records: [row(3, bad)], worldScope: {world(1)}),
      throwsFormatException,
    );
  });

  test(
    'continuity restrictions distinguish absent and explicitly empty grants',
    () {
      boundaries([], [], GrantLimits());
      boundaries([], [], GrantLimits(continuities: [continuity]));
      expect(
        () => boundaries([], [], GrantLimits(continuities: [])),
        throwsA(
          isA<NotFoundOrNotAccessibleError>().having(
            (e) => e.message,
            'message',
            'resource',
          ),
        ),
      );
    },
  );

  test(
    'entity writes require named entity coverage and no predicate restriction',
    () {
      final records = [row(1, entity())],
          changes = [
            change(row(1, entity(worlds: [1]))),
          ];
      boundaries(records, changes, GrantLimits(entities: [id(1)]));
      expect(
        () => boundaries(records, changes, GrantLimits(entities: [])),
        denied,
      );
      expect(
        () => boundaries(
          records,
          changes,
          GrantLimits(entities: [id(1)], predicates: [id(2)]),
        ),
        denied,
      );
      expect(
        () => boundaries([], [
          change(row(2, WorldRecord(selector: 'Earth'))),
        ], GrantLimits(entities: [id(2)])),
        denied,
      );
    },
  );

  test('proposition and assertion writes cover subject, roles, referenced values and predicate', () {
    final claim = prop(
      roles: [PropositionRole('recipient', ref(6))],
      value: ReferenceValue(ValueReferenceKind.entity, ref(7)),
    );
    final records = [
      row(1, entity()),
      row(2, entity()),
      row(3, entity()),
      row(4, claim),
      row(5, assertion()),
      row(6, entity()),
      row(7, entity()),
    ];
    final changes = [
      change(row(5, assertion(worlds: [1]))),
    ];
    boundaries(
      records,
      changes,
      GrantLimits(
        entities: [id(1), id(2), id(3), id(6), id(7)],
        predicates: [id(2)],
      ),
    );
    for (final missing in [1, 2, 3, 6, 7]) {
      expect(
        () => boundaries(
          records,
          changes,
          GrantLimits(
            entities: [
              for (final n in [1, 2, 3, 6, 7])
                if (n != missing) id(n),
            ],
            predicates: [id(2)],
          ),
        ),
        denied,
      );
    }
    expect(
      () => boundaries(records, changes, GrantLimits(predicates: [])),
      denied,
    );
    boundaries(records, changes, GrantLimits(predicates: [id(2)]));
  });

  test('both old and replacement claim boundaries are enforced on corrections and deletion', () {
    final records = [
      row(1, entity()),
      row(2, entity()),
      row(3, entity()),
      row(4, prop(subject: 1)),
    ];
    final edits = [change(row(4, prop(subject: 2)))];
    expect(
      () => boundaries(records, edits, GrantLimits(entities: [id(2), id(3)])),
      denied,
    );
    boundaries(records, edits, GrantLimits(entities: [id(1), id(2), id(3)]));
    expect(
      () => boundaries(records, [
        Assignment(recordId: id(4)),
      ], GrantLimits(entities: [id(2), id(3)])),
      denied,
    );
    expect(
      () => boundaries(
        [row(5, assertion())],
        [change(row(5, assertion()))],
        GrantLimits(predicates: [id(2)]),
      ),
      denied,
    );
  });
}
