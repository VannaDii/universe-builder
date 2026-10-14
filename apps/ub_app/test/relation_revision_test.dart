import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/relation_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('relation revision keeps source identity and all ordered role definitions through recovery and edits', () {
    final root = Directory('/tmp').createTempSync('ub-relation-revision-'),
        universe = UniverseId.generate(),
        context = RecordId.generate();
    final type = RecordId.generate();
    final payload = RelationRecord(
      namespace: 'authored',
      key: 'account',
      labels: {'en': 'Account', 'ja': '記憶 😀'},
      roles: [
        RoleDefinition(
          name: 'speaker',
          participantTypes: [type, type],
          multiplicity: Multiplicity.single,
          ordered: false,
        ),
        RoleDefinition(
          name: 'listeners',
          participantTypes: [],
          multiplicity: Multiplicity.multiple,
          ordered: true,
        ),
      ],
    );
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.relation,
      ),
      payload: payload,
    );
    UnfinishedRelationForm patch(
      UnfinishedRelationForm f,
      Map<String, CanonicalValue> changes,
    ) => UnfinishedRelationForm.fromWire(
      CanonicalObject(
        f.toWire().fields.map(
          (e) =>
              changes.containsKey(e.key) ? MapEntry(e.key, changes[e.key]!) : e,
        ),
      ),
    );
    final form = relationRevisionFormFromRecord(
      record: source,
      baseRevision: RevisionId.generate(),
      representedContext: context,
    );
    expect(
      relationRevisionOperation(form).replacement.toWire().toText(),
      payload.toWire().toText(),
    );
    final empty = SavedDraft(
      version: BigInt.one,
      content: DraftContent(
        baseRevision: form.baseRevision,
        representedContext: context,
        operations: [],
        rationale: 'Review relation definitions.',
      ),
    );
    final add = relationDraftRequest(
      draft: empty,
      form: form,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
    );
    final saved = SavedDraft(version: BigInt.two, content: add.content),
        pending = relationFormFromDraft(
          SavedDraft(version: BigInt.two, content: add.content),
          0,
        );
    final edit = relationDraftRequest(
      draft: saved,
      form: patch(pending, {
        'roles': CanonicalArray(pending.roles.reversed.map((r) => r.toWire())),
      }),
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final op = edit.content.operations.single as ReviseDefinitionOperation,
        next = op.replacement as RelationRecord;
    expect(op.record.record, source.identity.recordId);
    expect(op.expectedVersion, source.recordVersionId);
    expect(next.namespace, payload.namespace);
    expect(next.key, payload.key);
    expect(next.labels, payload.labels);
    expect(
      next.roles.map((r) => r.toWire().toText()),
      payload.roles.reversed.map((r) => r.toWire().toText()),
    );
    expect(
      () => relationRevisionOperation(
        patch(form, {'namespace': CanonicalString('other')}),
      ),
      throwsFormatException,
    );
    expect(
      () => relationRevisionOperation(
        patch(form, {'key': CanonicalString('other')}),
      ),
      throwsFormatException,
    );
    expect(
      () => relationDraftRequest(
        draft: SavedDraft(version: BigInt.from(3), content: saved.content),
        form: pending,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
    expect(
      () => relationDraftRequest(
        draft: saved,
        form: patch(pending, {
          'expected_record_version': CanonicalString(
            RecordVersionId.generate().value,
          ),
        }),
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
    expect(
      relationDraftRequest(
        draft: saved,
        form: form,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
      ).content.operations.length,
      1,
    );
    expect(
      () => relationDraftRequest(
        draft: saved,
        form: patch(form, {'roles': CanonicalArray([])}),
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
      ),
      throwsFormatException,
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: source.identity.recordId.value,
    );
    var store = RelationFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      final incomplete = patch(form, {
        'roles': CanonicalArray([
          RelationRoleInput(
            name: 'unfinished 記憶 😀',
            participantTypes: ['unfinished type'],
          ).toWire(),
        ]),
      });
      store.save(scope, incomplete, BigInt.zero);
      store.close();
      store = RelationFormRecoveryStore.open('${root.path}/forms.sqlite');
      expect(
        store.load(scope)!.form.toWire().toText(),
        incomplete.toWire().toText(),
      );
      expect(
        () => relationRevisionOperation(store.load(scope)!.form),
        throwsFormatException,
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
