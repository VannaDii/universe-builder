@TestOn('vm')
library;

import 'dart:convert';
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
}
