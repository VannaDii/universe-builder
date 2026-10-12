import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_service/operation_compilation.dart';
import 'package:ub_store/ub_store.dart';

import 'event_compilation_test.dart' as events;
import 'instance_initialization_test.dart' as initialization;

import 'package:ub_service/src/operation_compilation.dart'
    show compileAllocatedOperations;

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
RecordVersionId ver(int n) => RecordVersionId.parse('ver_${suffix(n)}');
final u = UniverseId.parse('unv_${suffix(1)}'),
    revision = RevisionId.parse('rev_${suffix(1)}');
final cal = CalendarId.parse('cal_${suffix(1)}');
RecordRef ref(int n) => RecordRef(universe: u, record: id(n));
RecordVersion row(int n, RecordPayload p) => RecordVersion.build(
  recordVersionId: ver(n),
  identity: RecordIdentity(
    universeId: u,
    recordId: id(n),
    recordKind: p.recordKind,
  ),
  payload: p,
);
EntityRecord entity({
  RecordId? classification,
  ClassificationResolution? resolution,
}) => EntityRecord(
  names: [],
  classification: classification,
  classificationResolution:
      resolution ??
      (classification == null
          ? ClassificationResolution.unclassified
          : ClassificationResolution.resolved),
  worldAssociations: [],
  labels: {},
  metadata: {},
);
EntityTypeRecord type(
  int n, {
  int? parent,
  ParentResolution? resolution,
  String? key,
}) => EntityTypeRecord(
  namespace: 'test',
  key: key ?? 'type$n',
  name: 'Type$n',
  labels: {},
  parent: parent == null ? null : id(parent),
  parentResolution:
      resolution ??
      (parent == null ? ParentResolution.root : ParentResolution.resolved),
  applicability: const UniverseApplicability(),
  classificationExecutable: true,
);
List<Assignment> compile(
  List<RecordVersion> base,
  List<DomainOperation> operations,
) => compileOperations(
  universe: u,
  revision: revision,
  base: base,
  operations: operations,
);
RecordVersion decode(Assignment a) {
  a.next!.verify();
  return RecordVersion.fromWire(a.next!.toCanonical());
}

Matcher fails(String text, {String field = 'operations'}) => throwsA(
  isA<InvalidArgumentError>()
      .having((e) => e.field, 'field', field)
      .having((e) => e.message, 'message', contains(text)),
);
T patch<T extends RecordPayload>(T p, Map<String, CanonicalValue> edits) =>
    RecordPayload.fromWire(
      CanonicalObject([
        for (final f in p.toWire().fields)
          if (!edits.containsKey(f.key)) f,
        ...edits.entries,
      ]),
    ) as T;
PropositionRecord prop(int n, {int context = 3, int subject = 1}) =>
    PropositionRecord(
      subject: ref(subject),
      predicate: ref(2),
      context: ref(context),
      value: IntegerValue('$n'),
      quantification: Quantification.particular,
    );
final scope = Scope(
  context: ref(3),
  applicability: const UniverseApplicability(),
);
AssertionRecord assertion({
  Validity validity = const UnspecifiedValidity(),
  EvidenceBasis basis = const AuthorDecisionBasis('authored'),
  int target = 4,
}) => AssertionRecord(
  attributeMode: AttributeMode.instance,
  proposition: ref(target),
  polarity: Polarity.support,
  scope: scope,
  validity: validity,
  persistence: PersistenceSemantics.explicitInterval,
  precision: Precision.exact,
  basis: basis,
);
final interval = CalendarIntervalValidity(
  cal,
  const ExactBound('10'),
  const ExactBound('20'),
);
EpistemicAttitudeRecord attitude({
  int target = 4,
  EpistemicAttitudeKind kind = EpistemicAttitudeKind.believes,
  KnowledgeAcquisition? acquisition,
}) => EpistemicAttitudeRecord(
  holder: ref(1),
  proposition: ref(target),
  attitude: kind,
  validity: interval,
  basis: const AuthorDecisionBasis('firsthand'),
  acquisition: acquisition,
);
SceneRecord scene({
  String identity = 'Gate',
  BigInt? position,
  List<WorldAssociation> worlds = const [],
}) => SceneRecord(
  workVersion: VersionRef(universe: u, record: id(2), version: ver(2)),
  sceneId: identity,
  narrativePosition: position ?? BigInt.one,
  depictedEvents: [],
  worldAssociations: worlds,
);

void main() {
  test('unsupported entity merging remains explicit', () {
    expect(
      () => compile(
        [row(1, entity()), row(2, entity())],
        [
          MergeEntitiesOperation(
            source: ref(1),
            sourceVersion: ver(1),
            target: ref(2),
            targetVersion: ver(2),
            rationale: 'Same identity',
          ),
        ],
      ),
      throwsA(isA<UnsupportedSemanticsError>()),
    );
  });
  test('creation reserves identity, allocates fresh versions, and never mutates base', () {
    final base = [row(1, entity())], before = base.single.toWire().toText();
    final changes = compile(base, [
      CreateWorldOperation(
        clientRef: id(10).value,
        record: WorldRecord(selector: 'Earth'),
      ),
      CreateEntityOperation(clientRef: 'Person', record: entity()),
    ]);
    expect(changes, hasLength(2));
    expect(changes.first.recordId, id(10));
    for (final c in changes) {
      expect(c.expected, isNull);
      expect(decode(c).identity.universeId, u);
      expect(c.next!.versionId, isNot(ver(1)));
    }
    expect(base.single.toWire().toText(), before);
    expect(() => changes.clear(), throwsUnsupportedError);
    expect(
      () => compile(base, [
        CreateEntityOperation(clientRef: id(1).value, record: entity()),
      ]),
      fails('already exists'),
    );
    expect(
      () => compile([], [
        CreateEntityOperation(clientRef: 'same', record: entity()),
        CreateWorldOperation(
          clientRef: 'same',
          record: WorldRecord(selector: 'Earth'),
        ),
      ]),
      fails('duplicate'),
    );
    expect(
      () =>
          compile([], [CreateEntityOperation(clientRef: '', record: entity())]),
      fails('empty'),
    );
  });

  test('private source version allocations apply only to creations', () {
    final allocated = ver(100);
    final changes = compileAllocatedOperations(
      universe: u,
      revision: revision,
      base: [row(1, entity())],
      operations: [
        CreateWorldOperation(
          clientRef: id(10).value,
          record: WorldRecord(selector: 'Earth'),
        ),
        AddNameOperation(
          record: ref(1),
          expectedVersion: ver(1),
          name: const ContextualName(
            text: 'Alias',
            validity: UnspecifiedValidity(),
          ),
        ),
      ],
      versions: {id(10): allocated, id(1): allocated},
    );
    expect(changes.first.next!.versionId, allocated);
    expect(changes.last.next!.versionId, isNot(allocated));
    expect(changes.last.expected, ver(1));
  });

  test('edits require explicit local namespace and exact base version', () {
    final base = [row(1, entity())];
    for (final reference in [
      RecordRef(record: id(1)),
      RecordRef(universe: UniverseId.parse('unv_${suffix(2)}'), record: id(1)),
    ]) {
      expect(
        () => compile(base, [
          TombstoneRecordOperation(
            record: reference,
            expectedVersion: ver(1),
            rationale: '',
          ),
        ]),
        fails('explicit local'),
      );
    }
    expect(
      () => compile(base, [
        TombstoneRecordOperation(
          record: ref(1),
          expectedVersion: ver(99),
          rationale: '',
        ),
      ]),
      fails('version differs'),
    );
    expect(
      () => compile(base, [
        TombstoneRecordOperation(
          record: ref(2),
          expectedVersion: ver(2),
          rationale: '',
        ),
      ]),
      fails('unavailable'),
    );
    final deletion = compile(base, [
      TombstoneRecordOperation(
        record: ref(1),
        expectedVersion: ver(1),
        rationale: '',
      ),
    ]).single;
    expect(deletion.expected, ver(1));
    expect(deletion.next, isNull);
  });

  test('refinement sees candidate revisions, adoptions and tombstones in every order', () {
    final rows = [
      row(1, type(1)),
      row(2, type(2, parent: 1)),
      row(3, type(3)),
      row(4, entity(classification: id(1))),
    ];
    final refine = AddTypeMembershipOperation(
      record: ref(4),
      expectedVersion: ver(4),
      entityType: id(2),
    );
    expect(
      (decode(compile(rows, [refine]).single).payload as EntityRecord)
          .classification,
      id(2),
    );
    final disjoint = ReviseDefinitionOperation(
      record: ref(2),
      expectedVersion: ver(2),
      replacement: type(2, parent: 3),
    );
    for (final ops in [
      [refine, disjoint],
      [disjoint, refine],
    ]) {
      expect(() => compile(rows, ops), fails('descendant'));
    }
    final adopt = AdoptRecordVersionOperation(
      source: row(2, type(2, parent: 3)),
      expectedVersion: ver(2),
    );
    expect(() => compile(rows, [refine, adopt]), fails('descendant'));
    expect(
      () => compile(rows, [
        refine,
        TombstoneRecordOperation(
          record: ref(2),
          expectedVersion: ver(2),
          rationale: 'Remove',
        ),
      ]),
      fails('resolved definition'),
    );
    expect(
      () => compile(
        [
          row(
            4,
            entity(
              classification: id(1),
              resolution: ClassificationResolution.ambiguous,
            ),
          ),
          ...rows.take(3),
        ],
        [refine],
      ),
      fails('ambiguous classification'),
    );
    final circular = [
      row(1, type(1)),
      row(2, type(2, parent: 3)),
      row(3, type(3, parent: 2)),
      rows.last,
    ];
    expect(() => compile(circular, [refine]), fails('descendant'));
    final create = DefineTypeOperation(
      clientRef: id(5).value,
      record: type(5, parent: 1),
    );
    expect(
      (decode(
                compile(rows, [
                  AddTypeMembershipOperation(
                    record: ref(4),
                    expectedVersion: ver(4),
                    entityType: id(5),
                  ),
                  create,
                ]).last,
              ).payload
              as EntityRecord)
          .classification,
      id(5),
    );
  });

  test('definition corrections retain kind, namespace and key', () {
    final rows = [row(1, type(1))];
    final good = ReviseDefinitionOperation(
      record: ref(1),
      expectedVersion: ver(1),
      replacement: type(1, parent: 2),
    );
    expect(decode(compile(rows, [good]).single).payload, type(1, parent: 2));
    expect(
      () => compile(rows, [
        ReviseDefinitionOperation(
          record: ref(1),
          expectedVersion: ver(1),
          replacement: type(1, key: 'new'),
        ),
      ]),
      fails('namespace and key'),
    );
    expect(
      () => compile(rows, [
        ReviseDefinitionOperation(
          record: ref(1),
          expectedVersion: ver(1),
          replacement: entity(),
        ),
      ]),
      fails('same-kind'),
    );
  });

  test(
    'assertion creation reserves proposition and blocks forged initialization',
    () {
      final a = assertion();
      for (final op in [
        AssertPropositionOperation(
          clientRef: id(4).value,
          proposition: prop(1),
          assertion: a,
        ),
        RecordRelationOperation(
          clientRef: id(4).value,
          proposition: prop(1),
          assertion: a,
        ),
      ]) {
        final changes = compile([], [op]);
        expect(changes, hasLength(2));
        expect(changes.first.recordId, id(4));
        expect(decode(changes.last).payload, a);
      }
      expect(
        () => compile([], [
          AssertPropositionOperation(
            clientRef: 'claim',
            proposition: prop(1),
            assertion: a,
          ),
        ]),
        fails('reserve a rec_'),
      );
      expect(
        () => compile([], [
          AssertPropositionOperation(
            clientRef: id(5).value,
            proposition: prop(1),
            assertion: a,
          ),
        ]),
        fails('this batch'),
      );
      final forged = assertion(
        basis: InstanceInitializationBasis(
          VersionRef(record: id(1), version: ver(1)),
          VersionRef(record: id(2), version: ver(2)),
          revision,
        ),
      );
      expect(
        () => compile([], [
          AssertPropositionOperation(
            clientRef: id(4).value,
            proposition: prop(1),
            assertion: forged,
          ),
        ]),
        fails('initialize_instance'),
      );
    },
  );

  test(
    'event creation, revision and withdrawal include complete frozen effects',
    () {
      final changes = compile(
        [events.record(4, events.proposition)],
        [
          RecordEventOperation(
            clientRef: id(5).value,
            record: events.event(10, expansion: 'untrusted'),
          ),
        ],
      );
      expect(changes, hasLength(2));
      expect(
        (decode(changes.first).payload as EventRecord).expansionVersion,
        eventExpansionVersion,
      );
      verifyEventEffects(
        events.apply([events.record(4, events.proposition)], changes),
      );
      final base = events.base();
      final corrected = compile(base, [
        ReviseEventOperation(
          record: ref(5),
          expectedVersion: ver(5),
          replacement: events.event(12, expansion: null),
        ),
      ]);
      expect(corrected, hasLength(2));
      verifyEventEffects(events.apply(base, corrected));
      final removed = compile(base, [
        WithdrawEventOperation(
          record: ref(5),
          expectedVersion: ver(5),
          rationale: 'Historical correction',
        ),
      ]);
      expect(removed, hasLength(2));
      expect(removed.every((c) => c.next == null), isTrue);
      expect(
        () => compile(
          [
            events.record(
              5,
              events.event(10, occurrence: OccurrenceKind.planned),
            ),
          ],
          [
            WithdrawEventOperation(
              record: ref(5),
              expectedVersion: ver(5),
              rationale: 'Remove',
            ),
          ],
        ),
        fails('occurred'),
      );
      expect(
        () => compile(base, [
          WithdrawEventOperation(
            record: ref(5),
            expectedVersion: ver(5),
            rationale: '\u0085',
          ),
        ]),
        fails('explain'),
      );
      final derived = base.last;
      expect(
        () => compile(base, [
          TombstoneRecordOperation(
            record: RecordRef(universe: u, record: derived.identity.recordId),
            expectedVersion: derived.recordVersionId,
            rationale: 'Remove',
          ),
        ]),
        fails('only change through their event', field: 'event'),
      );
    },
  );

  test('explicit initialization is included after canonical operations', () {
    final rows = initialization.fixture();
    rows[rows.length - 1] = initialization.record(
      9,
      patch(rows.last.payload as EventRecord, {
        'expansionVersion': CanonicalString(eventExpansionVersion),
      }),
    );
    final changes = compile(rows, [initialization.operation()]);
    expect(changes, hasLength(2));
    final a = decode(changes.last).payload as AssertionRecord;
    expect(
      a.basis,
      isA<InstanceInitializationBasis>().having(
        (b) => b.sourceRevision,
        'base',
        revision,
      ),
    );
    for (final c in changes) {
      decode(c);
    }
  });

  test(
    'scene corrections preserve identity, edition and world associations',
    () {
      final old = scene(),
          next = scene(position: BigInt.two),
          rows = [row(5, scene())];
      expect(
        decode(
          compile(rows, [
            ReviseSceneOperation(
              record: ref(5),
              expectedVersion: ver(5),
              replacement: next,
              rationale: 'Reader order',
            ),
          ]).single,
        ).payload,
        next,
      );
      for (final replacement in [
        scene(identity: 'Another scene'),
        patch(old, {
          'workVersion': VersionRef(
            universe: u,
            record: id(3),
            version: ver(3),
          ).toCanonical(),
        }),
        scene(
          worlds: [
            WorldAssociation(
              world: WorldId.parse('wld_${suffix(3)}'),
              role: 'setting',
              validity: const UnspecifiedValidity(),
              qualifiers: {},
            ),
          ],
        ),
      ]) {
        expect(
          () => compile(rows, [
            ReviseSceneOperation(
              record: ref(5),
              expectedVersion: ver(5),
              replacement: replacement,
              rationale: 'Correction',
            ),
          ]),
          fails('preserves identity'),
        );
      }
      expect(
        () => compile(rows, [
          ReviseSceneOperation(
            record: ref(5),
            expectedVersion: ver(5),
            replacement: next,
            rationale: '',
          ),
        ]),
        fails('requires a reason'),
      );
    },
  );

  test(
    'communication correction retains authored calendars and requires reason',
    () {
      final old = CommunicationRecord(
            sender: ref(1),
            intendedRecipients: [ref(2)],
            actualRecipients: [],
            content: [ref(4)],
            sentAt: ExactTime(cal, '10'),
            receivedAt: ExactTime(cal, '12'),
            distorted: false,
          ),
          rows = <RecordVersion>[];
      rows.add(row(5, old));
      for (final field in ['sentAt', 'receivedAt']) {
        final bad = patch(old, {
          field: ExactTime(
            CalendarId.parse('cal_${suffix(2)}'),
            '10',
          ).encode(canonical: false),
        });
        expect(
          () => compile(rows, [
            ReviseCommunicationOperation(
              record: ref(5),
              expectedVersion: ver(5),
              replacement: bad,
              rationale: 'Correction',
            ),
          ]),
          fails('authored'),
        );
      }
      final missingReceipt = patch(old, {'receivedAt': const CanonicalNull()});
      expect(
        decode(
          compile(rows, [
            ReviseCommunicationOperation(
              record: ref(5),
              expectedVersion: ver(5),
              replacement: missingReceipt,
              rationale: 'Correction',
            ),
          ]).single,
        ).payload,
        missingReceipt,
      );
      expect(
        () => compile(rows, [
          ReviseCommunicationOperation(
            record: ref(5),
            expectedVersion: ver(5),
            replacement: old,
            rationale: '',
          ),
        ]),
        fails('Explain'),
      );
    },
  );

  test('attributed claim corrections change only value and retain stance and provenance', () {
    final old = attitude(), rows = [row(4, prop(1)), row(5, old)];
    final next = attitude(target: 6),
        creation = DefinePropositionOperation(
          clientRef: id(6).value,
          record: prop(2),
        );
    final edit = ReviseAttitudeOperation(
      record: ref(5),
      expectedVersion: ver(5),
      replacement: next,
      rationale: 'Corrected memory',
    );
    expect(decode(compile(rows, [edit, creation]).last).payload, next);
    for (final bad in [
      patch(next, {'holder': ref(2).toCanonical()}),
      patch(next, {'basis': const ImportedClaimBasis().toWire()}),
      patch(next, {'validity': const UnknownValidity().toWire()}),
      patch(next, {'attitude': CanonicalString('rejects')}),
    ]) {
      expect(
        () => compile(rows, [
          creation,
          ReviseAttitudeOperation(
            record: ref(5),
            expectedVersion: ver(5),
            replacement: bad,
            rationale: 'Correction',
          ),
        ]),
        throwsA(isA<InvalidArgumentError>()),
      );
    }
    expect(
      () => compile(rows, [
        edit,
        DefinePropositionOperation(
          clientRef: id(6).value,
          record: prop(2, subject: 2),
        ),
      ]),
      fails('value only'),
    );
  });

  test('knowledge duration and receipt interpretation cannot manufacture acquisition', () {
    final acquisition = KnowledgeAcquisition(
      truthContext: ref(3),
      time: ExactTime(cal, '12'),
      basis: CommunicationKnowledge(
        communication: ref(9),
        interpretation: ref(4),
      ),
    );
    final old = attitude(
          kind: EpistemicAttitudeKind.knows,
          acquisition: acquisition,
        ),
        rows = [row(4, prop(1)), row(5, old), row(6, prop(2))];
    final next = patch(old, {
      'validity': CalendarIntervalValidity(
        cal,
        const ExactBound('12'),
        const UnboundedBound(),
      ).toWire(),
    });
    expect(
      decode(
        compile(rows, [
          ReviseAttitudeOperation(
            record: ref(5),
            expectedVersion: ver(5),
            replacement: next,
            rationale: 'Duration correction',
          ),
        ]).single,
      ).payload,
      next,
    );
    expect(
      () => compile(rows, [
        ReviseAttitudeOperation(
          record: ref(5),
          expectedVersion: ver(5),
          replacement: patch(old, {'certainty': CanonicalString('certain')}),
          rationale: 'Correction',
        ),
      ]),
      fails('duration only'),
    );
    final corrected =
        decode(
              compile(rows, [
                ReviseInterpretationOperation(
                  record: ref(5),
                  expectedVersion: ver(5),
                  interpretation: ref(6),
                  rationale: 'Misunderstood message',
                ),
              ]).single,
            ).payload
            as EpistemicAttitudeRecord;
    expect(corrected.proposition, ref(6));
    expect(corrected.acquisition!.truthContext, ref(3));
    expect(
      (corrected.acquisition!.basis as CommunicationKnowledge).communication,
      ref(9),
    );
    final cleared =
        decode(
              compile(rows, [
                ReviseInterpretationOperation(
                  record: ref(5),
                  expectedVersion: ver(5),
                  rationale: 'Unresolved',
                ),
              ]).single,
            ).payload
            as EpistemicAttitudeRecord;
    expect(cleared.proposition, old.proposition);
    expect(
      (cleared.acquisition!.basis as CommunicationKnowledge).interpretation,
      isNull,
    );
    expect(
      () => compile(
        [...rows.take(2), row(6, prop(2, context: 10))],
        [
          ReviseInterpretationOperation(
            record: ref(5),
            expectedVersion: ver(5),
            interpretation: ref(6),
            rationale: 'Correction',
          ),
        ],
      ),
      fails('original acquisition context'),
    );
    expect(
      () => compile(
        [row(5, attitude(kind: EpistemicAttitudeKind.knows))],
        [
          ReviseInterpretationOperation(
            record: ref(5),
            expectedVersion: ver(5),
            rationale: 'Correction',
          ),
        ],
      ),
      fails('No justified receipt'),
    );
  });

  test(
    'item-power corrections retain item, properties, context and calendar',
    () {
      final old = ItemPowerRecord(
            item: ref(1),
            holderPredicate: ref(2),
            powerPredicate: ref(3),
            value: const BooleanValue(true),
            scope: scope,
            validity: interval,
          ),
          rows = <RecordVersion>[];
      rows.add(row(5, old));
      final next = patch(old, {'value': const BooleanValue(false).toWire()});
      expect(
        decode(
          compile(rows, [
            ReviseItemPowerOperation(
              record: ref(5),
              expectedVersion: ver(5),
              replacement: next,
              rationale: 'Corrected ability',
            ),
          ]).single,
        ).payload,
        next,
      );
      for (final key in ['item', 'holderPredicate', 'powerPredicate']) {
        expect(
          () => compile(rows, [
            ReviseItemPowerOperation(
              record: ref(5),
              expectedVersion: ver(5),
              replacement: patch(old, {key: ref(10).toCanonical()}),
              rationale: 'Correction',
            ),
          ]),
          fails('must retain'),
        );
      }
      expect(
        () => compile(rows, [
          ReviseItemPowerOperation(
            record: ref(5),
            expectedVersion: ver(5),
            replacement: patch(old, {
              'validity': const UnknownValidity().toWire(),
            }),
            rationale: 'Correction',
          ),
        ]),
        fails('authored calendar'),
      );
    },
  );

  test(
    'assertion ending is half-open, calendar-bound and semantically idempotent',
    () {
      final old = assertion(validity: interval),
          rows = [row(5, assertion(validity: interval))];
      for (final end in ['15', '20']) {
        final a =
            decode(
                  compile(rows, [
                    EndAssertionAtOperation(
                      record: ref(5),
                      expectedVersion: ver(5),
                      at: ExactTime(cal, end),
                      basis: const AuthorDecisionBasis('Ended'),
                    ),
                  ]).single,
                ).payload
                as AssertionRecord;
        expect(
          a.validity,
          CalendarIntervalValidity(
            cal,
            const ExactBound('10'),
            ExactBound(end),
          ),
        );
        expect(a.basis, const AuthorDecisionBasis('Ended'));
        expect(a.proposition, old.proposition);
      }
      expect(
        () => compile(rows, [
          EndAssertionAtOperation(
            record: ref(5),
            expectedVersion: ver(5),
            at: ExactTime(cal, '9'),
            basis: const ImportedClaimBasis(),
          ),
        ]),
        fails('within'),
      );
      expect(
        () => compile(rows, [
          EndAssertionAtOperation(
            record: ref(5),
            expectedVersion: ver(5),
            at: ExactTime(CalendarId.parse('cal_${suffix(2)}'), '20'),
            basis: const ImportedClaimBasis(),
          ),
        ]),
        fails('calendar'),
      );
      expect(
        () => compile(
          [row(5, assertion())],
          [
            EndAssertionAtOperation(
              record: ref(5),
              expectedVersion: ver(5),
              at: ExactTime(cal, '20'),
              basis: const ImportedClaimBasis(),
            ),
          ],
        ),
        throwsA(isA<UnsupportedSemanticsError>()),
      );
      expect(
        () => compile(rows, [
          RetractAssertionOperation(
            record: ref(5),
            expectedVersion: ver(5),
            rationale: ' ',
          ),
        ]),
        fails('explain'),
      );
    },
  );

  test(
    'story time changes use immutable authored chronology before review',
    () {
      final clock = const GregorianUniverseStart('2040-03-15T12:30:00+02:00')
          .build(cal)
          .$1;
      final old = RepresentedContextRecord(
            universe: u,
            kind: const ObjectiveContext(),
            chronology: clock,
            labels: {'en': 'Reality'},
          ),
          rows = <RecordVersion>[];
      rows.add(row(5, old));
      final edited =
          decode(
                compile(rows, [
                  SetStoryTimeOperation(
                    record: ref(5),
                    expectedVersion: ver(5),
                    value: '2040-03-14T12:30:00+02:00',
                    mode: TimeChangeKind.timeTravel,
                    reason: 'Time machine',
                  ),
                ]).single,
              ).payload
              as RepresentedContextRecord;
      expect(edited.chronology!.firstInteraction, clock.firstInteraction);
      expect(edited.chronology!.current, isNot(clock.current));
      expect(old.chronology!.current, clock.current);
      expect(
        () => compile(rows, [
          SetStoryTimeOperation(
            record: ref(5),
            expectedVersion: ver(5),
            value: '2040-03-14T12:30:00+02:00',
            mode: TimeChangeKind.elapsed,
            reason: 'Back',
          ),
        ]),
        fails('must move forward'),
      );
      expect(
        () => compile(
          [
            row(
              5,
              RepresentedContextRecord(
                universe: u,
                kind: const ObjectiveContext(),
                labels: {},
              ),
            ),
          ],
          [
            SetStoryTimeOperation(
              record: ref(5),
              expectedVersion: ver(5),
              value: '0',
              mode: TimeChangeKind.elapsed,
              reason: 'Start',
            ),
          ],
        ),
        fails('starting chronology'),
      );
    },
  );

  test(
    'adoption validates source digest and target, then freezes a fresh version',
    () {
      final source = row(1, WorldRecord(selector: 'Earth'));
      final adopted = compile([], [
        AdoptRecordVersionOperation(source: source),
      ]).single;
      expect(adopted.expected, isNull);
      expect(decode(adopted).payload, source.payload);
      expect(adopted.next!.versionId, isNot(source.recordVersionId));
      expect(
        () => compile([source], [AdoptRecordVersionOperation(source: source)]),
        fails('target version changed'),
      );
      final forged = RecordVersion(
        recordVersionId: source.recordVersionId,
        identity: source.identity,
        payload: source.payload,
        payloadDigest: 'bad',
      );
      expect(
        () => compile([], [AdoptRecordVersionOperation(source: forged)]),
        fails('digest'),
      );
      expect(
        decode(
          compile(
            [source],
            [
              AdoptRecordVersionOperation(
                source: source,
                expectedVersion: ver(1),
              ),
            ],
          ).single,
        ).payload,
        source.payload,
      );
    },
  );

  test(
    'world aliases, work bindings and saga roles retain stable identities',
    () {
      final world = WorldRecord(selector: 'Earth', aliases: ['Terra']);
      final renamed =
          decode(
                compile(
                  [row(1, world)],
                  [
                    RenameWorldSelectorOperation(
                      record: ref(1),
                      expectedVersion: ver(1),
                      newSelector: 'Home',
                    ),
                  ],
                ).single,
              ).payload
              as WorldRecord;
      expect(renamed.aliases, ['Terra', 'Earth']);
      expect(renamed.selector, 'Home');
      final alias =
          decode(
                compile(
                  [row(1, world)],
                  [
                    AddWorldAliasOperation(
                      record: ref(1),
                      expectedVersion: ver(1),
                      alias: 'Home',
                    ),
                  ],
                ).single,
              ).payload
              as WorldRecord;
      expect(alias.selector, 'Earth');
      expect(alias.aliases, ['Terra', 'Home']);
      final saga = SagaRecord(
        title: 'Series',
        labels: {},
        memberships: [
          SagaMembership(work: ref(2), role: 'main', order: BigInt.one),
          SagaMembership(work: ref(2), role: 'prequel', order: BigInt.one),
        ],
      );
      final corrected =
          decode(
                compile(
                  [row(1, saga)],
                  [
                    SetSagaMembershipOperation(
                      record: ref(1),
                      expectedVersion: ver(1),
                      membership: SagaMembership(
                        work: ref(2),
                        role: 'main',
                        order: BigInt.two,
                      ),
                    ),
                  ],
                ).single,
              ).payload
              as SagaRecord;
      expect(corrected.memberships, hasLength(2));
      expect(corrected.memberships.first.order, BigInt.two);
      expect(corrected.memberships.last.role, 'prequel');
      expect(
        () => compile(
          [row(1, saga)],
          [
            SetSagaMembershipOperation(
              record: ref(1),
              expectedVersion: ver(1),
              membership: SagaMembership(
                work: RecordRef(record: id(2)),
                role: 'main',
              ),
            ),
          ],
        ),
        fails('this universe'),
      );
      final edition = WorkVersionRecord(
        work: ref(2),
        versionLabel: 'first',
        binding: const UnboundWork(),
      );
      final binding = BoundWork(
        ContinuityId.parse('cont_${suffix(1)}'),
        revision,
      );
      final bound =
          decode(
                compile(
                  [row(1, edition)],
                  [
                    SetWorkBindingOperation(
                      record: ref(1),
                      expectedVersion: ver(1),
                      binding: binding,
                    ),
                  ],
                ).single,
              ).payload
              as WorkVersionRecord;
      expect(bound.binding, binding);
      expect(bound.work, edition.work);
      expect(bound.versionLabel, 'first');
    },
  );

  test('pack upgrade preserves key and requires a changed version', () {
    final old = DomainPackRecord(
      key: 'campaign',
      version: '1',
      dependencies: {},
      capabilities: [],
      records: [],
    );
    final next = DomainPackRecord(
      key: 'campaign',
      version: '2',
      dependencies: {},
      capabilities: [],
      records: [],
    );
    expect(
      decode(
        compile(
          [row(1, old)],
          [
            UpgradePackOperation(
              record: ref(1),
              expectedVersion: ver(1),
              replacement: next,
            ),
          ],
        ).single,
      ).payload,
      next,
    );
    expect(
      () => compile(
        [row(1, old)],
        [
          UpgradePackOperation(
            record: ref(1),
            expectedVersion: ver(1),
            replacement: old,
          ),
        ],
      ),
      fails('change version'),
    );
  });

  test(
    'narrative creation accepts only matching source/context/narrative kinds',
    () {
      final context = RepresentedContextRecord(
        universe: u,
        kind: const ObjectiveContext(),
        labels: {},
      );
      expect(
        decode(
          compile([], [
            RecordNarrativeReferenceOperation(
              clientRef: id(1).value,
              record: RecordKind.representedContext,
              payload: context,
            ),
          ]).single,
        ).payload,
        context,
      );
      expect(
        () => compile([], [
          RecordNarrativeReferenceOperation(
            clientRef: 'bad',
            record: RecordKind.entity,
            payload: entity(),
          ),
        ]),
        fails('narrative reference kind'),
      );
      expect(
        () => compile([], [
          RecordNarrativeReferenceOperation(
            clientRef: 'bad',
            record: RecordKind.source,
            payload: context,
          ),
        ]),
        fails('narrative reference kind'),
      );
    },
  );
}
