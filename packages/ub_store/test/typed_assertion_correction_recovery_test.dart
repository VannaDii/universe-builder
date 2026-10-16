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
  typeClientRef: '\ufeffCorrection',
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
  targetUniverse: '',
  targetRecord: 'disabled target',
  start: TemporalBoundInput(
    kind: 'approximate',
    value: '\ufeffStart',
    upper: 'disabled upper',
    uncertainty: '9007199254740997',
    denominator: '',
    amount: QualifierInput(
      kind: 'sequence',
      children: [
        QualifierInput(key: 'same', value: '\ufeffFirst'),
        QualifierInput(key: 'same', value: 'Second\r\n\u0000😀'),
      ],
    ),
  ),
  end: TemporalBoundInput(kind: 'unknown', value: 'disabled end'),
);
const pendingValue = QualifierInput(
  kind: 'pending kind',
  key: '\ufeffKey',
  value: '\ufeffValue',
  denominator: '',
  unit: 'pending unit',
  originalKey: '',
  temporal: pendingTime,
  lowerInclusive: '',
  upperInclusive: 'unfinished',
  lower: QualifierInput(kind: 'rational', value: '3', denominator: '0'),
  children: [
    QualifierInput(key: 'repeat'),
    QualifierInput(key: 'repeat'),
  ],
);
UnfinishedAssertionCorrectionForm input(EditorFormScope s) {
  final ref = RecordRef(record: RecordId.generate(), universe: s.universe),
      world = WorldId.generate(),
      calendar = CalendarId.generate();
  return UnfinishedAssertionCorrectionForm(
    baseRevision: RevisionId.generate(),
    representedContext: s.representedContext!,
    clientRef: s.typeClientRef!,
    target: const ExpressionReferenceInput(
      record: '',
      universe: '\ufeffPending universe',
    ),
    expectedRecordVersion: RecordVersionId.generate(),
    original: AssertionRecord(
      attributeMode: AttributeMode.instance,
      proposition: ref,
      polarity: Polarity.support,
      scope: Scope(
        applicability: WorldsApplicability([world, world]),
        context: ref,
        realm: RecordRef(record: RecordId.generate()),
      ),
      validity: InstantValidity(
        DurationTime(
          calendar,
          SequenceValue([const TextValue('\ufeffA lifetime')]),
        ),
      ),
      persistence: PersistenceSemantics.persistentUntilChanged,
      precision: Precision.oneOf,
      alternatives: [
        SequenceValue([
          const IntegerValue('9007199254740997'),
          const RationalValue('3', '2'),
        ]),
        StructuredValue(ValueDefinitionId.generate(), {
          '\ufeffKey': const TextValue('\ufeffAuthored\r\n\u0000😀'),
        }),
      ],
      basis: DerivationBasis([
        VersionRef(record: ref.record, version: RecordVersionId.generate()),
      ], '\ufeffEvaluator'),
      establishedBy: EventEffectRef(ref, '\ufeffSlot'),
    ),
    proposition: const ExpressionReferenceInput(
      record: '\ufeffUnfinished proposition',
      universe: '',
    ),
    evidence: AttributeEvidenceInput(
      attributeMode: AttributeMode.shared,
      polarity: Polarity.refutation,
      precision: Precision.range,
      persistence: PersistenceSemantics.conditionDependent,
      basis: const EvidenceBasisInput(
        kind: 'undecided',
        note: '\ufeffNote',
        anchorRecord: '',
        anchorUniverse: 'disabled',
        verified: true,
      ),
      scope: const ScopeInput(
        applicability: 'pending',
        worlds: ['\ufeffWorld', '', '\ufeffWorld'],
        contextRecord: '',
        contextUniverse: 'pending universe',
        hasRealm: false,
        realmRecord: 'disabled realm',
        realmUniverse: 'disabled universe',
      ),
      validity: CalendarIntervalValidity(
        calendar,
        const ApproximateBound('\ufeffStart', RationalValue('1', '3')),
        const UnboundedBound(),
      ),
      temporalValidity: pendingTime,
      alternatives: const [pendingValue, QualifierInput(), pendingValue],
    ),
    rationale: '\ufeffReason\r\n記憶😀\u0000',
    draftVersion: maxU64,
  );
}

Map<String, int> domainCounts(Database db) => {
  for (final row in db.select(
    "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'r_%'",
  ))
    row['name'] as String:
        db.select('SELECT count(*) AS n FROM "${row['name']}"').single['n']
            as int,
};
void main() {
  test('typed correction recovery retains the original assertion and incomplete evidence values exactly after restart', () {
    final root = Directory('/tmp').createTempSync('ub-typed-correction-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = AssertionCorrectionFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.close();
      store = AssertionCorrectionFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db
              .select('PRAGMA table_info(assertion_correction_form)')
              .map((r) => r['name']),
          isNot(contains('form_input')),
        );
        expect(
          db
              .select(
                'SELECT count(*) AS n FROM assertion_correction_alternative',
              )
              .single['n'],
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
  test('correction replacement preserves absent versus empty evidence and removes superseded value trees', () {
    final root = Directory('/tmp').createTempSync('ub-correction-optional-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = AssertionCorrectionFormRecoveryStore.open(path),
        generation = BigInt.zero;
    try {
      generation = store.save(s, form, generation).generation;
      Map<String, int>? counts;
      for (final evidence in [
        const AttributeEvidenceInput(),
        const AttributeEvidenceInput(alternatives: []),
        const AttributeEvidenceInput(
          basis: EvidenceBasisInput(),
          scope: ScopeInput(),
          alternatives: [],
        ),
      ]) {
        final changed = form.copyWith(evidence: evidence);
        generation = store.save(s, changed, generation).generation;
        store.close();
        store = AssertionCorrectionFormRecoveryStore.open(path);
        expect(
          store.load(s)!.form.toWire().toText(),
          changed.toWire().toText(),
        );
        final db = sqlite3.open(path, mode: OpenMode.readOnly);
        try {
          for (final table in [
            'correction_qualifier',
            'correction_child',
            'correction_temporal',
            'correction_bound',
            'assertion_correction_world',
            'assertion_correction_alternative',
          ]) {
            expect(
              db.select('SELECT count(*) AS n FROM $table').single['n'],
              0,
            );
          }
          if (counts == null) {
            counts = domainCounts(db);
          } else {
            expect(domainCounts(db), counts);
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
