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
  attributeClientRef: '\ufeffPending attribute',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.attributeClientRef!,
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
  kind: 'pending',
  key: '\ufeffKey',
  value: '\ufeffValue\r\n\u0000😀',
  denominator: '',
  unit: 'disabled unit',
  originalKey: '',
  temporal: pendingTime,
  children: [
    QualifierInput(key: 'same'),
    QualifierInput(key: 'same'),
  ],
  lower: QualifierInput(kind: 'integer', value: '9007199254740997'),
);
UnfinishedAttributeForm input(EditorFormScope s) => UnfinishedAttributeForm(
  baseRevision: RevisionId.generate(),
  representedContext: s.representedContext!,
  clientRef: s.attributeClientRef!,
  draftVersion: maxU64,
  value: pendingValue,
  creationInput: AttributeCreationInput(
    subject: VersionRef(
      record: RecordId.generate(),
      version: RecordVersionId.generate(),
      universe: s.universe,
    ),
    operationRef: '',
    propertyRecord: '\ufeffPending property',
    propertyUniverse: 'disabled universe',
    relationship: true,
  ),
  roles: const [
    PropositionRoleInput(
      role: '\ufeffRole',
      record: '\ufeffPending',
      universe: '',
    ),
    PropositionRoleInput(),
    PropositionRoleInput(
      role: '\ufeffRole',
      record: '\ufeffPending',
      universe: '',
    ),
  ],
  evidenceInput: AttributeEvidenceInput(
    attributeMode: AttributeMode.initialValue,
    polarity: Polarity.refutation,
    precision: Precision.oneOf,
    persistence: PersistenceSemantics.conditionDependent,
    validity: InstantValidity(
      DurationTime(
        CalendarId.generate(),
        SequenceValue([
          const RationalValue('9007199254740997', '3'),
          const TextValue('\ufeffLifetime'),
        ]),
      ),
    ),
    temporalValidity: pendingTime,
    basis: const EvidenceBasisInput(
      kind: 'undecided',
      note: '\ufeffNote\r\n\u0000😀',
      anchorRecord: '',
      anchorUniverse: 'disabled universe',
      verified: true,
    ),
    scope: const ScopeInput(
      applicability: 'pending',
      worlds: ['\ufeffWorld', '', '\ufeffWorld'],
      contextRecord: '',
      contextUniverse: 'disabled universe',
      hasRealm: false,
      realmRecord: 'disabled realm',
      realmUniverse: 'disabled universe',
    ),
    alternatives: const [pendingValue, QualifierInput(), pendingValue],
  ),
);

void main() {
  test('typed attribute recovery retains nested evidence, explicit creation pin and ordered incomplete relation roles', () {
    final root = Directory('/tmp').createTempSync('ub-typed-attribute-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = AttributeFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.close();
      store = AttributeFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(attribute_form)').map((r) => r['name']),
          isNot(contains('value_input')),
        );
        expect(
          db.select('SELECT count(*) AS n FROM attribute_role').single['n'],
          3,
        );
        expect(
          db
              .select('SELECT count(*) AS n FROM attribute_alternative')
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
  test('attribute replacement retains absent versus empty roles and evidence while removing replaced value trees', () {
    final root = Directory('/tmp').createTempSync('ub-attribute-clear-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = AttributeFormRecoveryStore.open(path), generation = BigInt.zero;
    try {
      generation = store.save(s, form, generation).generation;
      generation = store.save(s, form, generation).generation;
      for (final explicitEmpty in [true, false]) {
        final changed = UnfinishedAttributeForm(
          baseRevision: form.baseRevision,
          representedContext: s.representedContext!,
          clientRef: s.attributeClientRef!,
          draftVersion: BigInt.zero,
          value: const QualifierInput(),
          roles: explicitEmpty ? [] : null,
          evidenceInput: explicitEmpty
              ? const AttributeEvidenceInput(alternatives: [])
              : null,
        );
        generation = store.save(s, changed, generation).generation;
        store.close();
        store = AttributeFormRecoveryStore.open(path);
        expect(
          store.load(s)!.form.toWire().toText(),
          changed.toWire().toText(),
        );
        final db = sqlite3.open(path, mode: OpenMode.readOnly);
        try {
          for (final row in db.select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name!='attribute_form'",
          )) {
            expect(
              db
                  .select('SELECT count(*) AS n FROM "${row['name']}"')
                  .single['n'],
              row['name'] == 'attribute_qualifier'
                  ? 1
                  : row['name'] == 'attribute_evidence' && explicitEmpty
                  ? 1
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
