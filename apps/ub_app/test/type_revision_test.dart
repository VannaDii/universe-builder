import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/type_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('type revisions retain explicit parent resolution, blank name and all labels through recovery', () {
    final root = Directory('/tmp').createTempSync('ub-type-revision-'),
        universe = UniverseId.generate(),
        context = RecordId.generate();
    var store = TypeFormRecoveryStore.open('${root.path}/types.sqlite');
    try {
      for (final resolution in ParentResolution.values) {
        final source = RecordVersion.build(
          recordVersionId: RecordVersionId.generate(),
          identity: RecordIdentity(
            universeId: universe,
            recordId: RecordId.generate(),
            recordKind: RecordKind.entityType,
          ),
          payload: EntityTypeRecord(
            namespace: 'authored',
            key: 'person',
            name: '',
            labels: {'ja': '人物 記憶 😀', '': 'Original'},
            parent: resolution == ParentResolution.resolved
                ? RecordId.generate()
                : null,
            parentResolution: resolution,
            applicability: const ConditionalApplicability(),
            classificationExecutable: false,
          ),
        );
        final form = typeRevisionFormFromRecord(
          record: source,
          baseRevision: RevisionId.generate(),
          representedContext: context,
        );
        expect(
          typeRevisionOperation(form).replacement.toWire().toText(),
          source.payload.toWire().toText(),
        );
        final scope = EditorFormScope(
          instance: OperationId.generate(),
          profile: ProfileId.generate(),
          universe: universe,
          continuity: ContinuityId.generate(),
          representedContext: context,
          typeClientRef: source.identity.recordId.value,
        );
        store.save(scope, form, BigInt.zero);
        store.close();
        store = TypeFormRecoveryStore.open('${root.path}/types.sqlite');
        final recovered = store.load(scope)!.form;
        expect(recovered.toWire().toText(), form.toWire().toText());
        final request = typeDraftRequest(
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          form: recovered,
          previous: null,
        );
        final saved = SavedDraft(version: BigInt.two, content: request.content),
            pending = typeFormFromDraft(
              SavedDraft(version: BigInt.two, content: request.content),
              0,
            );
        UnfinishedTypeForm edit({String? key, RecordVersionId? expected}) =>
            UnfinishedTypeForm(
              baseRevision: pending.baseRevision,
              representedContext: context,
              clientRef: pending.clientRef,
              namespace: pending.namespace,
              key: key ?? pending.key,
              name: 'Revised person',
              parentChoice: pending.parentChoice,
              parentResolution: pending.parentResolution,
              applicabilityChoice: pending.applicabilityChoice,
              classificationExecutable: pending.classificationExecutable,
              labels: pending.labels,
              worlds: pending.worlds,
              rationale: '',
              revisionTarget: pending.revisionTarget,
              expectedRecordVersion: expected ?? pending.expectedRecordVersion,
              original: pending.original,
              draftVersion: pending.draftVersion,
            );
        final edited = replaceDraftType(draft: saved, index: 0, form: edit());
        final op = edited.operations.single as ReviseDefinitionOperation,
            next = op.replacement as EntityTypeRecord;
        expect(op.record.record, source.identity.recordId);
        expect(op.expectedVersion, source.recordVersionId);
        expect(next.name, 'Revised person');
        expect(next.labels, (source.payload as EntityTypeRecord).labels);
        expect(next.parentResolution, resolution);
        expect(next.applicability, isA<ConditionalApplicability>());
        expect(next.classificationExecutable, isFalse);
        expect(
          () => typeRevisionOperation(edit(key: 'other')),
          throwsFormatException,
        );
        expect(
          () => replaceDraftType(
            draft: saved,
            index: 0,
            form: edit(expected: RecordVersionId.generate()),
          ),
          throwsFormatException,
        );
        expect(
          () => replaceDraftType(
            draft: SavedDraft(version: BigInt.from(3), content: saved.content),
            index: 0,
            form: edit(),
          ),
          throwsFormatException,
        );
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
