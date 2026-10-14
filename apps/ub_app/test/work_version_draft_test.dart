import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/work_version_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('edition edits retain explicit binding kinds and independent ordered segment pins', () {
    final work = RecordRef(
      universe: UniverseId.generate(),
      record: RecordId.generate(),
    );
    final a = WorkSegment(
      segment: 'Opening 記憶 😀',
      continuity: ContinuityId.generate(),
      revision: RevisionId.generate(),
    );
    final b = WorkSegment(
      segment: 'Alternative',
      continuity: ContinuityId.generate(),
      revision: RevisionId.generate(),
    );
    for (final binding in [
      const UnboundWork(),
      BoundWork(a.continuity, a.revision),
      SegmentedWork([a, a, b]),
      SegmentedWork([]),
    ]) {
      final record = WorkVersionRecord(
        work: work,
        versionLabel: 'Edition 記憶 😀',
        binding: binding,
      );
      final draft = SavedDraft(
        version: BigInt.from(6),
        content: DraftContent(
          baseRevision: RevisionId.generate(),
          representedContext: RecordId.generate(),
          operations: [
            RecordNarrativeReferenceOperation(
              clientRef: 'edition',
              record: RecordKind.workVersion,
              payload: record,
            ),
          ],
          rationale: 'Retain draft rationale.',
        ),
      );
      final form = UnfinishedWorkVersionForm.fromWire(
        workVersionFormFromDraft(draft, 0).toWire(),
      );
      expect(
        workVersionOperation(form).payload.toWire().toText(),
        record.toWire().toText(),
      );
      final changed = form.copyWith(
        versionLabel: 'Revised edition',
        segments: form.segments.reversed.toList(),
      );
      final request = workVersionDraftRequest(
        draft: draft,
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      );
      final next =
          (request.content.operations.single
                      as RecordNarrativeReferenceOperation)
                  .payload
              as WorkVersionRecord;
      expect(next.versionLabel, 'Revised edition');
      expect(next.work, record.work);
      expect(request.content.rationale, draft.content.rationale);
      if (binding is SegmentedWork) {
        expect(
          (next.binding as SegmentedWork).segments.map(
            (s) => s.toWire().toText(),
          ),
          binding.segments.reversed.map((s) => s.toWire().toText()),
        );
      } else {
        expect(next.binding, record.binding);
      }
      final unboundForm = form.copyWith(bindingKind: 'unbound');
      final unboundRecord =
          workVersionOperation(unboundForm).payload as WorkVersionRecord;
      expect(unboundRecord.binding, const UnboundWork());
      expect(
        unboundForm.segments.map((s) => s.toWire().toText()),
        form.segments.map((s) => s.toWire().toText()),
      );
      expect(
        () => workVersionDraftRequest(
          draft: SavedDraft(version: BigInt.from(7), content: draft.content),
          form: form,
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
          index: 0,
        ),
        throwsFormatException,
      );
    }
  });
  test('unfinished editions recover without selecting unbound or manufacturing canon pins', () {
    final root = Directory('/tmp').createTempSync('ub-work-version-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedWorkVersionForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      versionLabel: 'unfinished 記憶 😀',
      work: ExpressionReferenceInput(
        record: RecordId.generate().value,
        universe: scope.universe.value,
      ),
      revision: 'unfinished pin',
      segments: [const WorkSegmentInput(segment: 'Opening')],
    );
    var store = WorkVersionFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = WorkVersionFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.bindingKind, isEmpty);
      expect(recovered.segments.single.revision, isEmpty);
      expect(() => workVersionOperation(recovered), throwsFormatException);
      expect(
        () => workVersionOperation(recovered.copyWith(bindingKind: 'bound')),
        throwsFormatException,
      );
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(
          scope,
          form.copyWith(bindingKind: 'unbound'),
          BigInt.zero,
        ),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
