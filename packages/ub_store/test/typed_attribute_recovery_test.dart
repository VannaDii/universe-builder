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
void legacy(
  String path,
  int version,
  List<(EditorFormScope, UnfinishedAttributeForm, BigInt)> entries, {
  bool broken = false,
}) {
  protectedFile(path, create: true);
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE attribute_form(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,base_revision TEXT NOT NULL,draft_version TEXT NOT NULL,value_input TEXT NOT NULL${version >= 2 ? ',evidence_input TEXT' : ''}${version >= 3 ? ',creation_input TEXT' : ''}${version >= 4 ? ',roles_input TEXT' : ''},PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=$version',
    );
    for (final (s, f, g) in entries) {
      db.execute(
        'INSERT INTO attribute_form VALUES(${List.filled(9 + version, '?').join(',')})',
        [
          ...binding(s),
          g.toString(),
          f.baseRevision.value,
          f.draftVersion.toString(),
          broken && s == entries.last.$1
              ? '{unfinished'
              : f.value.toWire().toText(),
          if (version >= 2) f.evidenceInput?.toWire().toText(),
          if (version >= 3) f.creationInput?.toWire().toText(),
          if (version >= 4)
            f.roles == null
                ? null
                : CanonicalArray(f.roles!.map((r) => r.toWire())).toText(),
        ],
      );
    }
  } finally {
    db.close();
  }
}

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
  test('attribute v4 conversion preserves isolated forms, generations, retries and conflicting save handling', () {
    final root = Directory('/tmp').createTempSync('ub-attribute-conversion-'),
        s = scope(),
        second = scope();
    final path = '${root.path}/forms.sqlite',
        form = input(s),
        other = input(second);
    legacy(path, 4, [(s, form, BigInt.from(19)), (second, other, maxU64)]);
    final store = AttributeFormRecoveryStore.open(path),
        competing = AttributeFormRecoveryStore.open(path);
    try {
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final changed = UnfinishedAttributeForm(
        baseRevision: form.baseRevision,
        representedContext: s.representedContext!,
        clientRef: s.attributeClientRef!,
        draftVersion: BigInt.one,
        value: const QualifierInput(),
      );
      expect(
        store.save(s, changed, BigInt.from(19)).generation,
        BigInt.from(20),
      );
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
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
    } finally {
      competing.close();
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  for (final version in [1, 2, 3, 4]) {
    test(
      'failed attribute v$version conversion rolls back added columns and typed values',
      () {
        final root = Directory('/tmp')
                .createTempSync('ub-attribute-v$version-rollback-'),
            s = scope(),
            second = scope();
        final path = '${root.path}/forms.sqlite', form = input(s);
        legacy(path, version, [
          (s, form, BigInt.one),
          (second, input(second), BigInt.two),
        ], broken: true);
        try {
          expect(
            () => AttributeFormRecoveryStore.open(path),
            throwsA(isA<EditorRecoveryException>()),
          );
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            expect(
              db.select('PRAGMA user_version').single.values.single,
              version,
            );
            expect(
              db.select('PRAGMA table_info(attribute_form)').length,
              9 + version,
            );
            expect(
              db
                  .select(
                    'SELECT value_input FROM attribute_form ORDER BY generation',
                  )
                  .map((r) => r['value_input']),
              [form.value.toWire().toText(), '{unfinished'],
            );
            expect(
              db
                  .select("SELECT name FROM sqlite_master WHERE type='table'")
                  .map((r) => r['name']),
              ['attribute_form'],
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
}
