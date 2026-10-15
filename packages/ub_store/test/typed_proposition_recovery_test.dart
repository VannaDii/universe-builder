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
  typeClientRef: '\ufeffPending proposition',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
UnfinishedPropositionForm input(EditorFormScope s) {
  final ref = RecordRef(record: RecordId.generate(), universe: s.universe);
  return UnfinishedPropositionForm(
    baseRevision: RevisionId.generate(),
    representedContext: s.representedContext!,
    clientRef: s.typeClientRef!,
    subject: const ExpressionReferenceInput(
      record: '',
      universe: '\ufeffPending subject universe',
    ),
    predicate: const ExpressionReferenceInput(
      record: '\ufeffPending predicate',
    ),
    context: const ExpressionReferenceInput(
      record: 'disabled context',
      universe: 'pending context universe',
    ),
    roles: const [
      PropositionRoleInput(
        role: '\ufeffListener',
        record: '\ufeffPending participant',
      ),
      PropositionRoleInput(),
      PropositionRoleInput(
        role: '\ufeffListener',
        record: '\ufeffPending participant',
      ),
    ],
    quantification: 'undecided',
    hasValue: false,
    value: const QualifierInput(
      kind: 'pending',
      key: '\ufeffKey',
      value: '\ufeff9007199254740997',
      unit: 'disabled',
      originalKey: '',
      lowerInclusive: 'undecided',
      lower: QualifierInput(kind: 'rational', value: '3', denominator: '0'),
      children: [
        QualifierInput(key: 'repeat'),
        QualifierInput(key: 'repeat', value: '\ufeffValue\r\n\u0000😀'),
      ],
      temporal: TemporalValidityInput(
        kind: 'pending',
        calendar: 'disabled calendar',
        start: TemporalBoundInput(
          kind: 'unknown',
          value: 'disabled start',
          upper: '\ufeffUpper',
          amount: QualifierInput(
            kind: 'decimal',
            value: '0.0000000000000000001',
          ),
        ),
      ),
    ),
    original: PropositionRecord(
      subject: ref,
      predicate: RecordRef(record: RecordId.generate()),
      context: ref,
      quantification: Quantification.exists,
      roles: [
        PropositionRole('\ufeffListener', ref),
        PropositionRole('\ufeffListener', ref),
      ],
      value: StructuredValue(ValueDefinitionId.generate(), {
        '\ufeffField': SequenceValue([
          const RationalValue('9007199254740997', '3'),
          const TextValue('\ufeffAuthored\r\n\u0000😀'),
        ]),
      }),
    ),
    rationale: '\ufeffReason 記憶\r\n\u0000😀',
    draftVersion: maxU64,
  );
}

void legacy(String path, List<(EditorFormScope, BigInt, String)> entries) {
  protectedFile(path, create: true);
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE proposition_form(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, g, text) in entries) {
      db.execute('INSERT INTO proposition_form VALUES(?,?,?,?,?,?,?,?)', [
        ...binding(s),
        g.toString(),
        text,
      ]);
    }
  } finally {
    db.close();
  }
}

void main() {
  test('typed proposition recovery retains disabled recursive values, unresolved references, duplicate role order and original records', () {
    final root = Directory('/tmp').createTempSync('ub-typed-proposition-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = PropositionFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.close();
      store = PropositionFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db
              .select('PRAGMA table_info(proposition_form)')
              .map((r) => r['name']),
          isNot(contains('form_input')),
        );
        expect(
          db.select('SELECT count(*) AS n FROM proposition_role').single['n'],
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
  test('proposition conversion preserves isolated forms and generations while retaining save conflict rules', () {
    final root = Directory('/tmp').createTempSync('ub-proposition-conversion-'),
        s = scope(),
        second = scope();
    final path = '${root.path}/forms.sqlite',
        form = input(s),
        other = input(second);
    legacy(path, [
      (s, BigInt.from(19), form.toWire().toText()),
      (second, maxU64, other.toWire().toText()),
    ]);
    final store = PropositionFormRecoveryStore.open(path),
        competing = PropositionFormRecoveryStore.open(path);
    try {
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final changed = UnfinishedPropositionForm.fromWire(
        CanonicalObject(
          form.toWire().fields.map(
            (e) => MapEntry(
              e.key,
              e.key == 'rationale' ? CanonicalString('changed') : e.value,
            ),
          ),
        ),
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
    } finally {
      competing.close();
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('replacing a proposition clears superseded roles, recursive input and original rows while preserving empty defaults', () {
    final root = Directory('/tmp').createTempSync('ub-proposition-clear-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = PropositionFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.save(s, form, BigInt.one);
      final empty = UnfinishedPropositionForm(
        baseRevision: form.baseRevision,
        representedContext: s.representedContext!,
        clientRef: s.typeClientRef!,
      );
      store.save(s, empty, BigInt.two);
      store.close();
      store = PropositionFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), empty.toWire().toText());
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        for (final row in db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name!='proposition_form'",
        )) {
          expect(
            db.select('SELECT count(*) AS n FROM "${row['name']}"').single['n'],
            row['name'] == 'proposition_qualifier' ? 1 : 0,
            reason: row['name'] as String,
          );
        }
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('failed proposition conversion retains all original unfinished forms and rolls back typed rows', () {
    final root = Directory('/tmp').createTempSync('ub-proposition-rollback-'),
        s = scope(),
        second = scope();
    final path = '${root.path}/forms.sqlite', text = input(s).toWire().toText();
    legacy(path, [(s, BigInt.one, text), (second, BigInt.two, '{unfinished')]);
    try {
      expect(
        () => PropositionFormRecoveryStore.open(path),
        throwsA(isA<EditorRecoveryException>()),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 1);
        expect(
          db
              .select(
                'SELECT form_input FROM proposition_form ORDER BY generation',
              )
              .map((r) => r['form_input']),
          [text, '{unfinished'],
        );
        expect(
          db
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((r) => r['name']),
          ['proposition_form'],
        );
      } finally {
        db.close();
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
