import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/pack_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('pack upgrade preserves exact dependency versions, ordered members and private recovery', () {
    final root = Directory('/tmp').createTempSync('ub-pack-revision-'),
        universe = UniverseId.generate(),
        context = RecordId.generate();
    final member = RecordId.generate();
    final payload = DomainPackRecord(
      key: 'authored-kit',
      version: '1 記憶 😀',
      dependencies: {'foundation': 'exact 記憶 😀'},
      capabilities: ['assertion.qualified.v1', 'assertion.qualified.v1'],
      records: [member, context, member],
    );
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.domainPack,
      ),
      payload: payload,
    );
    UnfinishedPackForm patch(
      UnfinishedPackForm f,
      Map<String, CanonicalValue> changes,
    ) => UnfinishedPackForm.fromWire(
      CanonicalObject(
        f.toWire().fields.map(
          (e) =>
              changes.containsKey(e.key) ? MapEntry(e.key, changes[e.key]!) : e,
        ),
      ),
    );
    final form = packRevisionFormFromRecord(
      record: source,
      baseRevision: RevisionId.generate(),
      representedContext: context,
    ).copyWith(version: '2 記憶 😀');
    expect(packRevisionOperation(form).replacement.version, '2 記憶 😀');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: source.identity.recordId.value,
    );
    var store = PackFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = PackFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      final empty = SavedDraft(
        version: BigInt.one,
        content: DraftContent(
          baseRevision: form.baseRevision,
          representedContext: context,
          operations: [],
          rationale: 'Review calendar changes.',
        ),
      );
      final add = packDraftRequest(
        draft: empty,
        form: recovered,
        universe: const Selector('Universe'),
        continuity: scope.continuity,
      );
      final saved = SavedDraft(version: BigInt.two, content: add.content),
          pending = packFormFromDraft(
            SavedDraft(version: BigInt.two, content: add.content),
            0,
          );
      final edit = packDraftRequest(
        draft: saved,
        form: patch(pending, {
          'records': CanonicalArray(
            pending.records.reversed.map(CanonicalString.new),
          ),
        }),
        universe: const Selector('Universe'),
        continuity: scope.continuity,
        index: 0,
      );
      final op = edit.content.operations.single as UpgradePackOperation,
          next = op.replacement;
      expect(op.record.record, source.identity.recordId);
      expect(op.expectedVersion, source.recordVersionId);
      expect(next.key, payload.key);
      expect(next.version, '2 記憶 😀');
      expect(next.dependencies, payload.dependencies);
      expect(next.capabilities, payload.capabilities);
      expect(next.records, payload.records.reversed);
      expect(
        () => packDraftRequest(
          draft: saved,
          form: form.copyWith(version: '3'),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        ),
        throwsFormatException,
      );
      expect(
        () => packRevisionOperation(form.copyWith(key: 'other')),
        throwsFormatException,
      );
      expect(
        () => packRevisionOperation(form.copyWith(version: payload.version)),
        throwsFormatException,
      );
      expect(
        () => packDraftRequest(
          draft: SavedDraft(version: BigInt.from(3), content: saved.content),
          form: pending,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => packDraftRequest(
          draft: saved,
          form: patch(pending, {
            'expected_record_version': CanonicalString(
              RecordVersionId.generate().value,
            ),
          }),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      final incomplete = patch(form, {
        'records': CanonicalArray([CanonicalString('unfinished record 記憶 😀')]),
      });
      store.save(scope, incomplete, BigInt.one);
      expect(
        store.load(scope)!.form.toWire().toText(),
        incomplete.toWire().toText(),
      );
      expect(
        () => packRevisionOperation(store.load(scope)!.form),
        throwsFormatException,
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
