@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/installation.dart' show protectedFile;

final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  typeClientRef: '\ufeffPending relation',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
UnfinishedRelationForm input(EditorFormScope s, {bool editing = true}) {
  final participant = RecordId.generate();
  return UnfinishedRelationForm(
    baseRevision: RevisionId.generate(),
    representedContext: s.representedContext!,
    clientRef: s.typeClientRef!,
    namespace: '\ufeffAuthored 記憶',
    key: '\ufeffPending key',
    rationale: '\ufeffReason 😀\r\n\u0000',
    draftVersion: editing ? maxU64 : null,
    labels: const [
      PropertyLabelInput(language: '\ufeffen', text: '\ufeffName'),
      PropertyLabelInput(),
      PropertyLabelInput(
        language: '\ufeffen',
        text: 'Repeated unfinished language',
      ),
    ],
    roles: [
      RelationRoleInput(
        name: '\ufeffParticipant',
        multiplicity: 'still choosing',
        ordered: true,
        participantTypes: ['\ufeffPending type', '', 'Repeated', 'Repeated'],
      ),
      RelationRoleInput(),
      RelationRoleInput(
        name: '\ufeffParticipant',
        multiplicity: 'different unfinished choice',
        ordered: false,
        participantTypes: ['Other'],
      ),
    ],
    revisionTarget: editing
        ? const ExpressionReferenceInput(
            record: '',
            universe: '\ufeffUnfinished universe',
          )
        : null,
    expectedRecordVersion: editing ? RecordVersionId.generate() : null,
    original: editing
        ? RelationRecord(
            namespace: '\ufeffOriginal namespace',
            key: '\ufeffOriginal key',
            labels: {'\ufeffen': '\ufeffOriginal name', '': '', 'ja': '記憶 😀'},
            roles: [
              RoleDefinition(
                name: '\ufeffFirst',
                participantTypes: [participant, participant],
                multiplicity: Multiplicity.single,
                ordered: false,
              ),
              RoleDefinition(
                name: '\ufeffSecond',
                participantTypes: [],
                multiplicity: Multiplicity.multiple,
                ordered: true,
              ),
            ],
          )
        : null,
  );
}

UnfinishedRelationForm cleared(UnfinishedRelationForm form) =>
    UnfinishedRelationForm.fromWire(
      CanonicalObject([
        for (final e in form.toWire().fields)
          MapEntry(
            e.key,
            {'roles', 'labels'}.contains(e.key) ? CanonicalArray([]) : e.value,
          ),
      ]),
    );
void legacy(String path, List<(EditorFormScope, BigInt, String)> entries) {
  protectedFile(path, createNew: true);
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE relation_form(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, g, text) in entries) {
      db.execute('INSERT INTO relation_form VALUES(?,?,?,?,?,?,?,?)', [
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
  test('typed relation recovery retains ordered incomplete roles, participant lists and original definitions after restart', () {
    final root = Directory('/tmp').createTempSync('ub-typed-relation-');
    final path = '${root.path}/forms.sqlite', s = scope(), form = input(s);
    var store = RelationFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.close();
      store = RelationFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(relation_form)').map((r) => r['name']),
          isNot(contains('form_input')),
        );
        expect(
          db
              .select(
                "SELECT is_ordered,multiplicity_text FROM relation_role WHERE list_kind='input' ORDER BY ordinal",
              )
              .map((r) => [r['is_ordered'], r['multiplicity_text']]),
          [
            [1, 'still choosing'],
            [0, ''],
            [0, 'different unfinished choice'],
          ],
        );
        expect(
          db
              .select(
                "SELECT CAST(participant_input AS BLOB) AS type FROM relation_participant WHERE list_kind='input' AND role_ordinal=0 ORDER BY ordinal",
              )
              .map((r) => r['type']),
          form.roles.first.participantTypes.map(utf8.encode),
        );
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('relation conversion preserves profiles, optional states and generations while removing replaced input rows', () {
    final root = Directory('/tmp').createTempSync('ub-relation-conversion-');
    final path = '${root.path}/forms.sqlite', s = scope(), second = scope();
    final form = input(s), other = input(second, editing: false);
    legacy(path, [
      (s, BigInt.from(19), form.toWire().toText()),
      (second, maxU64, other.toWire().toText()),
    ]);
    var store = RelationFormRecoveryStore.open(path);
    final competing = RelationFormRecoveryStore.open(path);
    try {
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final changed = cleared(form);
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
      store.close();
      store = RelationFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), changed.toWire().toText());
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 2);
        for (final table in ['label', 'role', 'participant']) {
          expect(
            db.select(
              "SELECT count(*) AS n FROM relation_$table WHERE profile=? AND list_kind='input'",
              [s.profile.value],
            ).single['n'],
            0,
          );
        }
        expect(
          db.select(
            "SELECT count(*) AS n FROM relation_role WHERE profile=? AND list_kind='original'",
            [s.profile.value],
          ).single['n'],
          form.original!.roles.length,
        );
      } finally {
        db.close();
      }
    } finally {
      competing.close();
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('failed relation conversion rolls back every typed child and retains original unfinished input', () {
    final root = Directory('/tmp').createTempSync('ub-relation-rollback-');
    final path = '${root.path}/forms.sqlite',
        s = scope(),
        second = scope(),
        text = input(s).toWire().toText();
    legacy(path, [(s, BigInt.one, text), (second, BigInt.two, '{unfinished')]);
    try {
      expect(
        () => RelationFormRecoveryStore.open(path),
        throwsA(isA<EditorRecoveryException>()),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 1);
        expect(
          db
              .select(
                'SELECT form_input FROM relation_form ORDER BY generation',
              )
              .map((r) => r['form_input']),
          [text, '{unfinished'],
        );
        expect(
          db
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((r) => r['name']),
          ['relation_form'],
        );
      } finally {
        db.close();
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
