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
  test('published binding changes retain identity and expected version through draft edits', () {
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        base = RevisionId.generate();
    final record = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.workVersion,
      ),
      payload: WorkVersionRecord(
        work: RecordRef(universe: universe, record: RecordId.generate()),
        versionLabel: 'Published edition 記憶 😀',
        binding: BoundWork(ContinuityId.generate(), RevisionId.generate()),
      ),
    );
    final opened = workBindingFormFromRecord(
      record: record,
      baseRevision: base,
      representedContext: context,
    );
    final form = UnfinishedWorkVersionForm.fromWire(
      opened.copyWith(bindingKind: 'unbound').toWire(),
    );
    final draft = SavedDraft(
      version: BigInt.from(2),
      content: DraftContent(
        baseRevision: base,
        representedContext: context,
        operations: [],
        rationale: 'Binding correction.',
      ),
    );
    final request = workVersionDraftRequest(
      draft: draft,
      form: form,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
    );
    final operation =
        request.content.operations.single as SetWorkBindingOperation;
    expect(operation.record.record, record.identity.recordId);
    expect(operation.record.universe, universe);
    expect(operation.expectedVersion, record.recordVersionId);
    expect(operation.binding, const UnboundWork());
    expect(() => workVersionOperation(form), throwsFormatException);
    final saved = SavedDraft(version: BigInt.from(3), content: request.content);
    expect(
      workVersionDraftRequest(
        draft: saved,
        form: form,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
      ).content.operations.length,
      1,
    );
    final editable = workVersionFormFromDraft(saved, 0);
    final changed = editable.copyWith(
      bindingKind: 'segments',
      segments: [
        WorkSegmentInput(
          segment: 'Opening',
          continuity: ContinuityId.generate().value,
          revision: RevisionId.generate().value,
        ),
      ],
    );
    final edit = workVersionDraftRequest(
      draft: saved,
      form: changed,
      universe: const Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 0,
    );
    final next = edit.content.operations.single as SetWorkBindingOperation;
    expect(next.record, operation.record);
    expect(next.expectedVersion, operation.expectedVersion);
    expect(next.binding is SegmentedWork, isTrue);
    expect(
      () => workVersionDraftRequest(
        draft: SavedDraft(version: BigInt.from(4), content: saved.content),
        form: changed,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
    final alteredPin = UnfinishedWorkVersionForm.fromWire(
      CanonicalObject(
        changed.toWire().fields.map(
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
      () => workVersionDraftRequest(
        draft: saved,
        form: alteredPin,
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      ),
      throwsFormatException,
    );
  });
  test('published binding recovery stays scoped to the selected edition', () {
    final root = Directory('/tmp').createTempSync('ub-work-binding-form-');
    final universe = UniverseId.generate(),
        recordId = RecordId.generate(),
        context = RecordId.generate();
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: recordId.value,
    );
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: recordId,
        recordKind: RecordKind.workVersion,
      ),
      payload: WorkVersionRecord(
        work: RecordRef(universe: universe, record: RecordId.generate()),
        versionLabel: 'Edition',
        binding: const UnboundWork(),
      ),
    );
    final form =
        workBindingFormFromRecord(
          record: source,
          baseRevision: RevisionId.generate(),
          representedContext: context,
        ).copyWith(
          bindingKind: 'bound',
          continuity: 'unfinished continuity',
          revision: 'unfinished revision 記憶 😀',
        );
    var store = WorkVersionFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = WorkVersionFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.expectedRecordVersion, source.recordVersionId);
      expect(recovered.bindingTarget!.record, recordId.value);
      expect(() => workBindingOperation(recovered), throwsFormatException);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
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
