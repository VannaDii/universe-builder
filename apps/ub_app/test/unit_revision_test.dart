import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/unit_draft.dart';
import 'package:ub_app/qualifier_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('unit revision retains exact conversion, base and authored validity through recovery and edits', () {
    final root = Directory('/tmp').createTempSync('ub-unit-revision-'),
        universe = UniverseId.generate(),
        context = RecordId.generate();
    final payload = UnitRecord(
      namespace: 'authored',
      key: 'measure',
      dimension: 'distance',
      symbol: 'm',
      labels: {'en': 'Measure', 'ja': '計量 😀'},
      base: UnitId.generate(),
      scaleToBase: const RationalValue('9007199254740997', '3'),
      validity: InstantValidity(
        DurationTime(
          CalendarId.generate(),
          SequenceValue([const TextValue('a lifetime 記憶 😀')]),
        ),
      ),
    );
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.unit,
      ),
      payload: payload,
    );
    UnfinishedUnitForm patch(
      UnfinishedUnitForm f,
      Map<String, CanonicalValue> changes,
    ) => UnfinishedUnitForm.fromWire(
      CanonicalObject(
        f.toWire().fields.map(
          (e) =>
              changes.containsKey(e.key) ? MapEntry(e.key, changes[e.key]!) : e,
        ),
      ),
    );
    final form = unitRevisionFormFromRecord(
      record: source,
      baseRevision: RevisionId.generate(),
      representedContext: context,
    );
    expect(
      unitRevisionOperation(form).replacement.toWire().toText(),
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
    var store = UnitFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = UnitFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      final empty = SavedDraft(
        version: BigInt.one,
        content: DraftContent(
          baseRevision: form.baseRevision,
          representedContext: context,
          operations: [],
          rationale: 'Review unit changes.',
        ),
      );
      final add = unitDraftRequest(
        draft: empty,
        form: recovered,
        universe: const Selector('Universe'),
        continuity: scope.continuity,
      );
      final saved = SavedDraft(version: BigInt.two, content: add.content),
          pending = unitFormFromDraft(
            SavedDraft(version: BigInt.two, content: add.content),
            0,
          );
      final edit = unitDraftRequest(
        draft: saved,
        form: patch(pending, {
          'scale': qualifierInput(
            'scale',
            const RationalValue('9007199254740999', '3'),
          ).toWire(),
        }),
        universe: const Selector('Universe'),
        continuity: scope.continuity,
        index: 0,
      );
      final op = edit.content.operations.single as ReviseDefinitionOperation,
          next = op.replacement as UnitRecord;
      expect(op.record.record, source.identity.recordId);
      expect(op.expectedVersion, source.recordVersionId);
      expect(next.scaleToBase, const RationalValue('9007199254740999', '3'));
      expect(next.namespace, payload.namespace);
      expect(next.key, payload.key);
      expect(next.dimension, payload.dimension);
      expect(next.symbol, payload.symbol);
      expect(next.labels, payload.labels);
      expect(next.base, payload.base);
      expect(
        next.validity.toWire().toText(),
        payload.validity.toWire().toText(),
      );
      expect(
        () => unitRevisionOperation(
          patch(form, {'namespace': CanonicalString('other')}),
        ),
        throwsFormatException,
      );
      expect(
        () => unitRevisionOperation(
          patch(form, {'key': CanonicalString('other')}),
        ),
        throwsFormatException,
      );
      expect(
        () => unitDraftRequest(
          draft: SavedDraft(version: BigInt.from(3), content: saved.content),
          form: pending,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => unitDraftRequest(
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
        'scale': const QualifierInput(
          kind: 'rational',
          value: 'unfinished',
          denominator: '',
        ).toWire(),
      });
      store.save(scope, incomplete, BigInt.one);
      expect(
        store.load(scope)!.form.toWire().toText(),
        incomplete.toWire().toText(),
      );
      expect(
        () => unitRevisionOperation(store.load(scope)!.form),
        throwsFormatException,
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
