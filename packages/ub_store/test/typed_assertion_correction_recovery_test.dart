@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/src/ownership.dart';

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

void legacy(String path, List<(EditorFormScope, BigInt, String)> entries) {
  protectedFile(path, create: true);
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE assertion_correction_form(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, g, text) in entries) {
      db.execute(
        'INSERT INTO assertion_correction_form VALUES(?,?,?,?,?,?,?,?)',
        [...binding(s), g.toString(), text],
      );
    }
  } finally {
    db.close();
  }
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
  test('correction conversion preserves isolated forms, generations and conflicting edit handling', () {
    final root = Directory('/tmp').createTempSync('ub-correction-conversion-'),
        s = scope(),
        second = scope();
    final path = '${root.path}/forms.sqlite',
        form = input(s),
        other = input(second);
    legacy(path, [
      (s, BigInt.from(19), form.toWire().toText()),
      (second, maxU64, other.toWire().toText()),
    ]);
    final store = AssertionCorrectionFormRecoveryStore.open(path),
        competing = AssertionCorrectionFormRecoveryStore.open(path);
    try {
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final changed = form.copyWith(rationale: 'changed');
      expect(
        store.save(s, changed, BigInt.from(19)).generation,
        BigInt.from(20),
      );
      expect(
        () => competing.save(s, form, BigInt.from(19)),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        () => store.save(second, other, maxU64),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.generationExhausted,
          ),
        ),
      );
    } finally {
      competing.close();
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test(
    'failed correction conversion rolls back all input and original rows',
    () {
      final root = Directory('/tmp').createTempSync('ub-correction-rollback-'),
          s = scope(),
          second = scope();
      final path = '${root.path}/forms.sqlite',
          text = input(s).toWire().toText();
      legacy(path, [
        (s, BigInt.one, text),
        (second, BigInt.two, '{unfinished'),
      ]);
      try {
        expect(
          () => AssertionCorrectionFormRecoveryStore.open(path),
          throwsA(isA<EditorRecoveryException>()),
        );
        final db = sqlite3.open(path, mode: OpenMode.readOnly);
        try {
          expect(db.select('PRAGMA user_version').single.values.single, 1);
          expect(
            db
                .select(
                  'SELECT form_input FROM assertion_correction_form ORDER BY generation',
                )
                .map((r) => r['form_input']),
            [text, '{unfinished'],
          );
          expect(
            db
                .select("SELECT name FROM sqlite_master WHERE type='table'")
                .map((r) => r['name']),
            ['assertion_correction_form'],
          );
        } finally {
          db.close();
        }
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );
}
