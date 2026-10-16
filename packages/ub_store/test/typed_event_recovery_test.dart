@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  typeClientRef: '\ufeffPending event',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
const pendingTime = TemporalValidityInput(
  kind: 'pending',
  calendar: '\ufeffCalendar',
  relation: 'before?',
  targetRecord: 'disabled target',
  start: TemporalBoundInput(
    kind: 'unknown',
    value: 'disabled start',
    upper: '\ufeffUpper',
    amount: QualifierInput(kind: 'rational', value: '3', denominator: '0'),
  ),
);
const pendingValue = QualifierInput(
  kind: 'pending',
  key: '\ufeffKey',
  value: '\ufeffValue\r\n\u0000😀',
  unit: 'disabled unit',
  originalKey: '',
  lower: QualifierInput(kind: 'integer', value: '9007199254740997'),
  children: [
    QualifierInput(key: 'same'),
    QualifierInput(key: 'same'),
  ],
  temporal: pendingTime,
);
UnfinishedEventForm input(EditorFormScope s) {
  final ref = RecordRef(record: RecordId.generate(), universe: s.universe),
      world = WorldId.generate(),
      calendar = CalendarId.generate();
  final effect = EntityEffect(
    slot: '\ufeffChange',
    proposition: ref,
    polarity: Polarity.refutation,
    validity: InstantValidity(
      DurationTime(
        calendar,
        SequenceValue([const TextValue('\ufeffA lifetime')]),
      ),
    ),
    scope: Scope(
      context: ref,
      applicability: WorldsApplicability([world, world]),
      realm: RecordRef(record: ref.record),
    ),
    order: maxU64,
  );
  final originals = <Operand>[
    const VariableOperand('\ufeffVariable'),
    RecordOperand(ref),
    const ValueOperand(RationalValue('9007199254740997', '3')),
    const FrameTimeOperand(),
    const EventParticipantOperand('\ufeffWitness'),
    const EventRefOperand(),
  ];
  final condition = ExpressionInput(
    kind: 'pending expression',
    strings: {'\ufeffKey': '\ufeffValue\r\n\u0000😀', '': ''},
    flags: {'\ufeffTrue': true, 'false': false, 'undecided': null},
    references: {
      '\ufeffReference': const ExpressionReferenceInput(
        record: '',
        universe: '\ufeffUniverse',
      ),
    },
    operands: {
      for (var i = 0; i < originals.length; i++)
        'operand$i': OperandInput(
          kind: 'pending',
          name: '\ufeffName',
          reference: const ExpressionReferenceInput(
            record: 'disabled',
            universe: '',
          ),
          value: pendingValue,
          original: originals[i],
        ),
    },
    roles: const [
      ExpressionRoleInput(role: '\ufeffRole', operand: OperandInput()),
      ExpressionRoleInput(
        role: '\ufeffRole',
        operand: OperandInput(kind: 'different', value: pendingValue),
      ),
    ],
    children: {
      '\ufeffChild': ExpressionInput(
        kind: 'pending child',
        flags: {'unset': null},
        value: pendingValue,
      ),
    },
    items: [
      ExpressionInput(),
      ExpressionInput(kind: 'repeated'),
      ExpressionInput(kind: 'repeated'),
    ],
    value: pendingValue,
    original: AllExpr([
      const LiteralExpr(true),
      const NotExpr(LiteralExpr(false)),
    ]),
  );
  final effectInput = EventEffectInput(
    slot: '\ufeffPending slot',
    propositionRecord: '',
    propositionUniverse: 'disabled universe',
    polarity: 'pending',
    order: '9007199254740997?',
    scope: const ScopeInput(
      applicability: 'undecided',
      worlds: ['\ufeffWorld', '', '\ufeffWorld'],
      contextRecord: '',
      contextUniverse: 'pending',
      hasRealm: false,
      realmRecord: 'disabled realm',
      realmUniverse: 'disabled',
    ),
    validity: pendingTime,
    original: effect,
  );
  return UnfinishedEventForm(
    baseRevision: RevisionId.generate(),
    representedContext: s.representedContext!,
    clientRef: s.typeClientRef!,
    label: '\ufeffEvent',
    occurrence: 'undecided',
    description: '\ufeffDescription\r\n\u0000😀',
    actionRecord: '',
    actionUniverse: 'disabled action',
    time: pendingTime,
    participants: const [
      EventParticipantInput(record: '\ufeffPending', role: '\ufeffWitness'),
      EventParticipantInput(),
      EventParticipantInput(record: '\ufeffPending', role: '\ufeffWitness'),
    ],
    worlds: const ['\ufeffWorld', '', '\ufeffWorld'],
    regionRecord: '',
    regionUniverse: 'disabled region',
    sequence: '\ufeffSequence',
    occurrenceId: '\ufeffOccurrence',
    preconditions: [condition, condition],
    effects: [effectInput, const EventEffectInput(), effectInput],
    original: EventRecord(
      occurrence: const DescriptiveOccurrence('\ufeffReported'),
      action: ref,
      worlds: [world, world],
      region: RecordRef(record: ref.record),
      time: ApproximateTime(
        calendar,
        '\ufeffCoordinate',
        const RationalValue('1', '3'),
      ),
      sequence: '\ufeffSequence',
      occurrenceId: '',
      participants: [
        EventParticipant(ref, '\ufeffWitness'),
        EventParticipant(ref, '\ufeffWitness'),
      ],
      preconditions: [const LiteralExpr(true)],
      effects: [effect, effect],
      labels: {'\ufeffen': '\ufeffName', '': '', 'ja': '記憶😀'},
      expansionVersion: '\ufeffExpansion',
      basis: SourceAnchorBasis(ref, false),
    ),
    revisionTarget: const ExpressionReferenceInput(
      record: '',
      universe: '\ufeffPending',
    ),
    expectedRecordVersion: RecordVersionId.generate(),
    draftVersion: maxU64,
    rationale: '\ufeffReason\r\n\u0000😀',
  );
}

void main() {
  test('typed event recovery preserves incomplete effects, recursive preconditions, original operands and exact record metadata', () {
    final root = Directory('/tmp').createTempSync('ub-typed-event-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = EventFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.close();
      store = EventFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(event_form)').map((r) => r['name']),
          isNot(contains('form_input')),
        );
        expect(
          db.select('SELECT count(*) AS n FROM event_effect').single['n'],
          3,
        );
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('event replacement preserves absent versus empty lists and removes superseded expressions effects and original rows', () {
    final root = Directory('/tmp').createTempSync('ub-event-clear-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = EventFormRecoveryStore.open(path), generation = BigInt.zero;
    try {
      generation = store.save(s, form, generation).generation;
      generation = store.save(s, form, generation).generation;
      for (final explicitEmpty in [true, false]) {
        final empty = UnfinishedEventForm(
          baseRevision: form.baseRevision,
          representedContext: s.representedContext!,
          clientRef: s.typeClientRef!,
          effects: explicitEmpty ? [] : null,
          preconditions: explicitEmpty ? [] : null,
        );
        generation = store.save(s, empty, generation).generation;
        store.close();
        store = EventFormRecoveryStore.open(path);
        expect(store.load(s)!.form.toWire().toText(), empty.toWire().toText());
        final db = sqlite3.open(path, mode: OpenMode.readOnly);
        try {
          for (final row in db.select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name!='event_form'",
          )) {
            expect(
              db
                  .select('SELECT count(*) AS n FROM "${row['name']}"')
                  .single['n'],
              row['name'] == 'event_temporal'
                  ? 1
                  : row['name'] == 'event_bound'
                  ? 2
                  : 0,
              reason: row['name'] as String,
            );
          }
          expect(db.select('PRAGMA foreign_key_check'), isEmpty);
        } finally {
          db.close();
        }
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
