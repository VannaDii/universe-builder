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
  typeClientRef: '\ufeffPending action',
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
  targetRecord: 'disabled target',
  start: TemporalBoundInput(
    kind: 'unknown',
    value: 'disabled start',
    upper: '\ufeffUpper',
    amount: QualifierInput(kind: 'rational', value: '3', denominator: '0'),
  ),
);
const pendingValue = QualifierInput(
  kind: 'undecided',
  key: '\ufeffKey',
  value: '\ufeffValue\r\n\u0000😀',
  unit: 'disabled unit',
  originalKey: '',
  temporal: pendingTime,
  children: [
    QualifierInput(key: 'same'),
    QualifierInput(key: 'same'),
  ],
  lower: QualifierInput(kind: 'integer', value: '9007199254740997'),
);
UnfinishedActionForm input(EditorFormScope s) {
  final ref = RecordRef(record: RecordId.generate(), universe: s.universe),
      world = WorldId.generate();
  final originalRequirement = AttributeRequirement(
    '\ufeffTraveler',
    ref,
    StructuredValue(ValueDefinitionId.generate(), {
      '\ufeffField': const RationalValue('9007199254740997', '3'),
    }),
  );
  final originalSlot = EffectSlot(
    slot: '\ufeffChange',
    order: 0,
    presence: EffectPresence.required,
    target: EffectTarget('\ufeffTraveler', ref),
    condition: AttributeEqualsEffect(
      '\ufeffTraveler',
      ref,
      const IntegerValue('9007199254740997'),
    ),
    change: SetEffect(
      Polarity.refutation,
      const RationalValue('9007199254740997', '3'),
    ),
    lifetime: TicksEffect(ConsequenceInteger('9007199254740997')),
  );
  final requirement = ActionRequirementInput(
    role: '\ufeffPending role',
    predicate: const ExpressionReferenceInput(
      record: '',
      universe: 'disabled universe',
    ),
    value: pendingValue,
    original: originalRequirement,
  );
  final slot = ActionSlotInput(
    fields: {
      '\ufeffKey': '\ufeffValue\r\n\u0000😀',
      '': '',
      'order': '9007199254740997?',
      'disabled': 'retained',
    },
    target: const ExpressionReferenceInput(
      record: '\ufeffPending target',
      universe: '',
    ),
    condition: requirement,
    value: pendingValue,
    original: originalSlot,
  );
  return UnfinishedActionForm(
    baseRevision: RevisionId.generate(),
    representedContext: s.representedContext!,
    clientRef: s.typeClientRef!,
    namespace: '\ufeffAuthored',
    key: '\ufeffAction',
    rationale: '\ufeffReason\r\n\u0000😀',
    labels: const [
      PropertyLabelInput(language: '\ufeffen', text: '\ufeffName'),
      PropertyLabelInput(),
      PropertyLabelInput(language: '\ufeffen', text: 'Repeated'),
    ],
    requirements: [requirement, const ActionRequirementInput(), requirement],
    slots: [slot, ActionSlotInput(), slot],
    scope: const ScopeInput(
      applicability: 'pending',
      worlds: ['\ufeffWorld', '', '\ufeffWorld'],
      contextRecord: '',
      contextUniverse: 'pending',
      hasRealm: false,
      realmRecord: 'disabled realm',
      realmUniverse: 'disabled universe',
    ),
    validity: pendingTime,
    original: ActionDefinitionRecord(
      namespace: '\ufeffOriginal',
      key: '\ufeffAction',
      labels: {'\ufeffen': '\ufeffName', '': '', 'ja': '記憶😀'},
      requirements: [originalRequirement, originalRequirement],
      consequenceContract: ConsequenceContract([originalSlot]),
      scope: Scope(
        context: ref,
        applicability: WorldsApplicability([world, world]),
        realm: RecordRef(record: ref.record),
      ),
      validity: InstantValidity(
        DurationTime(
          CalendarId.generate(),
          SequenceValue([const TextValue('\ufeffLifetime')]),
        ),
      ),
    ),
    revisionTarget: const ExpressionReferenceInput(
      record: '',
      universe: '\ufeffPending universe',
    ),
    expectedRecordVersion: RecordVersionId.generate(),
    draftVersion: maxU64,
  );
}

void main() {
  test('typed action recovery retains incomplete requirements, slot fields, nested values and all original contract metadata', () {
    final root = Directory('/tmp').createTempSync('ub-typed-action-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = ActionFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.close();
      store = ActionFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(action_form)').map((r) => r['name']),
          isNot(contains('form_input')),
        );
        expect(
          db
              .select('SELECT count(*) AS n FROM action_requirement_item')
              .single['n'],
          3,
        );
        expect(
          db.select('SELECT count(*) AS n FROM action_slot').single['n'],
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
  test('action replacement distinguishes absent from empty contracts and removes superseded originals and input trees', () {
    final root = Directory('/tmp').createTempSync('ub-action-clear-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = ActionFormRecoveryStore.open(path), generation = BigInt.zero;
    try {
      generation = store.save(s, form, generation).generation;
      generation = store.save(s, form, generation).generation;
      for (final explicitEmpty in [true, false]) {
        final empty = UnfinishedActionForm(
          baseRevision: form.baseRevision,
          representedContext: s.representedContext!,
          clientRef: s.typeClientRef!,
          slots: explicitEmpty ? [] : null,
        );
        generation = store.save(s, empty, generation).generation;
        store.close();
        store = ActionFormRecoveryStore.open(path);
        expect(store.load(s)!.form.toWire().toText(), empty.toWire().toText());
        final db = sqlite3.open(path, mode: OpenMode.readOnly);
        try {
          for (final row in db.select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name!='action_form'",
          )) {
            expect(
              db
                  .select('SELECT count(*) AS n FROM "${row['name']}"')
                  .single['n'],
              row['name'] == 'action_temporal'
                  ? 1
                  : row['name'] == 'action_bound'
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
