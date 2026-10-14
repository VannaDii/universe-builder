import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/calendar_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('calendar revision preserves explicit epoch, ordered conversions and version through recovery', () {
    final root = Directory('/tmp').createTempSync('ub-calendar-revision-'),
        universe = UniverseId.generate(),
        context = RecordId.generate();
    final target = CalendarId.generate();
    final payload = CalendarRecord(
      namespace: 'authored',
      key: 'regional',
      labels: {'en': 'Regional', 'ja': '記憶 😀'},
      epoch: '',
      unitStructure: {'month': '30 days', 'year': '12 months 記憶 😀'},
      conversions: [
        CalendarConversion(target: target, valid: false),
        CalendarConversion(target: target, expression: '', valid: true),
        CalendarConversion(
          target: target,
          expression: 'authored mapping',
          valid: false,
        ),
      ],
    );
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.calendar,
      ),
      payload: payload,
    );
    UnfinishedCalendarForm patch(
      UnfinishedCalendarForm f,
      Map<String, CanonicalValue> changes,
    ) => UnfinishedCalendarForm.fromWire(
      CanonicalObject(
        f.toWire().fields.map(
          (e) =>
              changes.containsKey(e.key) ? MapEntry(e.key, changes[e.key]!) : e,
        ),
      ),
    );
    final form = calendarRevisionFormFromRecord(
      record: source,
      baseRevision: RevisionId.generate(),
      representedContext: context,
    );
    expect(
      calendarRevisionOperation(form).replacement.toWire().toText(),
      payload.toWire().toText(),
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: universe,
      continuity: ContinuityId.generate(),
      representedContext: context,
      typeClientRef: source.identity.recordId.value,
    );
    var store = CalendarFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = CalendarFormRecoveryStore.open('${root.path}/forms.sqlite');
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
      final add = calendarDraftRequest(
        draft: empty,
        form: recovered,
        universe: const Selector('Universe'),
        continuity: scope.continuity,
      );
      final saved = SavedDraft(version: BigInt.two, content: add.content),
          pending = calendarFormFromDraft(
            SavedDraft(version: BigInt.two, content: add.content),
            0,
          );
      final edit = calendarDraftRequest(
        draft: saved,
        form: patch(pending, {
          'conversions': CanonicalArray(
            pending.conversions.reversed.map((c) => c.toWire()),
          ),
          'has_epoch': const CanonicalBool(false),
        }),
        universe: const Selector('Universe'),
        continuity: scope.continuity,
        index: 0,
      );
      final op = edit.content.operations.single as ReviseDefinitionOperation,
          next = op.replacement as CalendarRecord;
      expect(op.record.record, source.identity.recordId);
      expect(op.expectedVersion, source.recordVersionId);
      expect(next.epoch, isNull);
      expect(next.namespace, payload.namespace);
      expect(next.key, payload.key);
      expect(next.labels, payload.labels);
      expect(next.unitStructure, payload.unitStructure);
      expect(
        next.conversions.map((c) => c.toWire().toText()),
        payload.conversions.reversed.map((c) => c.toWire().toText()),
      );
      expect(
        () => calendarDraftRequest(
          draft: saved,
          form: patch(form, {'epoch': CanonicalString('another epoch')}),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        ),
        throwsFormatException,
      );
      expect(
        () => calendarRevisionOperation(
          patch(form, {'namespace': CanonicalString('other')}),
        ),
        throwsFormatException,
      );
      expect(
        () => calendarRevisionOperation(
          patch(form, {'key': CanonicalString('other')}),
        ),
        throwsFormatException,
      );
      expect(
        () => calendarDraftRequest(
          draft: SavedDraft(version: BigInt.from(3), content: saved.content),
          form: pending,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => calendarDraftRequest(
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
        'epoch': CanonicalString('unfinished epoch 記憶 😀'),
        'conversions': CanonicalArray([
          const CalendarConversionInput(
            target: 'unfinished reference',
            hasExpression: true,
            expression: 'unfinished mapping',
            valid: true,
          ).toWire(),
        ]),
      });
      store.save(scope, incomplete, BigInt.one);
      expect(
        store.load(scope)!.form.toWire().toText(),
        incomplete.toWire().toText(),
      );
      expect(
        () => calendarRevisionOperation(store.load(scope)!.form),
        throwsFormatException,
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
