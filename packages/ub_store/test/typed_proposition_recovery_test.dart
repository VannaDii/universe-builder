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
}
