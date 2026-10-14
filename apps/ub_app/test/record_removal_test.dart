import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/record_removal_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test(
    'record removal recovers exact reason with unchanged target and version',
    () {
      final root = Directory('/tmp').createTempSync('ub-recordRemoval-form-'),
          universe = UniverseId.generate(),
          context = RecordId.generate();
      final payload = WorldRecord(selector: 'Discarded world 記憶 😀');
      final source = RecordVersion.build(
        recordVersionId: RecordVersionId.generate(),
        identity: RecordIdentity(
          universeId: universe,
          recordId: RecordId.generate(),
          recordKind: RecordKind.world,
        ),
        payload: payload,
      );
      final scope = EditorFormScope(
        instance: OperationId.generate(),
        profile: ProfileId.generate(),
        universe: universe,
        continuity: ContinuityId.generate(),
        representedContext: context,
        typeClientRef: source.identity.recordId.value,
      );
      final form = recordRemovalFormFromRecord(
        record: source,
        baseRevision: RevisionId.generate(),
        representedContext: context,
      ).copyWith(rationale: 'Correct the recorded recordRemoval.');
      var store = RecordRemovalFormRecoveryStore.open(
        '${root.path}/forms.sqlite',
      );
      try {
        store.save(scope, form, BigInt.zero);
        store.close();
        store = RecordRemovalFormRecoveryStore.open(
          '${root.path}/forms.sqlite',
        );
        final recovered = store.load(scope)!.form;
        expect(recovered.toWire().toText(), form.toWire().toText());
        final empty = SavedDraft(
          version: BigInt.one,
          content: DraftContent(
            baseRevision: form.baseRevision,
            representedContext: context,
            operations: [],
            rationale: '',
          ),
        );
        final add = recordRemovalDraftRequest(
          draft: empty,
          form: recovered,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        );
        final saved = SavedDraft(version: BigInt.two, content: add.content),
            pending = recordRemovalFormFromDraft(
              SavedDraft(version: BigInt.two, content: add.content),
              0,
            );
        expect(
          recordRemovalOperation(pending).toWire().toText(),
          recordRemovalOperation(form).toWire().toText(),
        );
        final edited = recordRemovalDraftRequest(
          draft: saved,
          form: pending.copyWith(rationale: 'Remove unresolved recordRemoval.'),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        );
        final op = edited.content.operations.single as TombstoneRecordOperation;
        expect(op.record.record, source.identity.recordId);
        expect(op.expectedVersion, source.recordVersionId);
        expect(op.rationale, 'Remove unresolved recordRemoval.');
        expect(
          () => recordRemovalDraftRequest(
            draft: SavedDraft(version: BigInt.from(3), content: saved.content),
            form: pending,
            universe: const Selector('Universe'),
            continuity: scope.continuity,
            index: 0,
          ),
          throwsFormatException,
        );
        final changedPin = UnfinishedRecordRemovalForm.fromWire(
          CanonicalObject(
            pending.toWire().fields.map(
              (e) => e.key == 'expected_record_version'
                  ? MapEntry(
                      e.key,
                      CanonicalString(RecordVersionId.generate().value),
                    )
                  : e,
            ),
          ),
        );
        expect(
          () => recordRemovalDraftRequest(
            draft: saved,
            form: changedPin,
            universe: const Selector('Universe'),
            continuity: scope.continuity,
            index: 0,
          ),
          throwsFormatException,
        );
        expect(
          recordRemovalDraftRequest(
            draft: saved,
            form: form,
            universe: const Selector('Universe'),
            continuity: scope.continuity,
          ).content.operations.length,
          1,
        );
        expect(
          () => recordRemovalDraftRequest(
            draft: saved,
            form: form.copyWith(rationale: 'Different reason'),
            universe: const Selector('Universe'),
            continuity: scope.continuity,
          ),
          throwsFormatException,
        );
        final incomplete = form.copyWith(rationale: '');
        store.save(scope, incomplete, BigInt.one);
        expect(
          store.load(scope)!.form.toWire().toText(),
          incomplete.toWire().toText(),
        );
        expect(() => recordRemovalOperation(incomplete), throwsFormatException);
      } finally {
        store.close();
        root.deleteSync(recursive: true);
      }
    },
  );
}
