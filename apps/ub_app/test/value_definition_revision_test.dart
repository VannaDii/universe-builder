import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/value_definition_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('value-definition revision preserves nested shapes, field order, flags and version through recovery', () {
    final root = Directory('/tmp')
            .createTempSync('ub-value-definition-revision-'),
        universe = UniverseId.generate(),
        context = RecordId.generate();
    final payload = ValueDefinitionRecord(
      namespace: 'authored',
      key: 'account',
      labels: {'en': 'Account', 'ja': '記憶 😀'},
      fields: [
        ValueDefinitionField(
          name: 'details',
          shape: SequenceShape(SequenceShape(QuantityShape(UnitId.generate()))),
          required: true,
          allowsUnknown: true,
        ),
        const ValueDefinitionField(
          name: 'note',
          required: false,
          allowsUnknown: false,
          shape: SimpleValueShape(SimpleShapeKind.text),
        ),
      ],
    );
    final source = RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: RecordKind.valueDefinition,
      ),
      payload: payload,
    );
    UnfinishedValueDefinitionForm patch(
      UnfinishedValueDefinitionForm f,
      Map<String, CanonicalValue> changes,
    ) => UnfinishedValueDefinitionForm.fromWire(
      CanonicalObject(
        f.toWire().fields.map(
          (e) =>
              changes.containsKey(e.key) ? MapEntry(e.key, changes[e.key]!) : e,
        ),
      ),
    );
    final form = valueDefinitionRevisionFormFromRecord(
      record: source,
      baseRevision: RevisionId.generate(),
      representedContext: context,
    );
    expect(
      valueDefinitionRevisionOperation(form).replacement.toWire().toText(),
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
    var store = ValueDefinitionFormRecoveryStore.open(
      '${root.path}/forms.sqlite',
    );
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = ValueDefinitionFormRecoveryStore.open(
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
          rationale: 'Review calendar changes.',
        ),
      );
      final add = valueDefinitionDraftRequest(
        draft: empty,
        form: recovered,
        universe: const Selector('Universe'),
        continuity: scope.continuity,
      );
      final saved = SavedDraft(version: BigInt.two, content: add.content),
          pending = valueDefinitionFormFromDraft(
            SavedDraft(version: BigInt.two, content: add.content),
            0,
          );
      final edit = valueDefinitionDraftRequest(
        draft: saved,
        form: patch(pending, {
          'fields': CanonicalArray(
            pending.fields.reversed.map((f) => f.toWire()),
          ),
        }),
        universe: const Selector('Universe'),
        continuity: scope.continuity,
        index: 0,
      );
      final op = edit.content.operations.single as ReviseDefinitionOperation,
          next = op.replacement as ValueDefinitionRecord;
      expect(op.record.record, source.identity.recordId);
      expect(op.expectedVersion, source.recordVersionId);
      expect(next.namespace, payload.namespace);
      expect(next.key, payload.key);
      expect(next.labels, payload.labels);
      expect(
        next.fields.map((f) => f.toWire().toText()),
        payload.fields.reversed.map((f) => f.toWire().toText()),
      );
      expect(
        () => valueDefinitionDraftRequest(
          draft: saved,
          form: patch(form, {
            'fields': CanonicalArray(
              form.fields.reversed.map((f) => f.toWire()),
            ),
          }),
          universe: const Selector('Universe'),
          continuity: scope.continuity,
        ),
        throwsFormatException,
      );
      expect(
        () => valueDefinitionRevisionOperation(
          patch(form, {'namespace': CanonicalString('other')}),
        ),
        throwsFormatException,
      );
      expect(
        () => valueDefinitionRevisionOperation(
          patch(form, {'key': CanonicalString('other')}),
        ),
        throwsFormatException,
      );
      expect(
        () => valueDefinitionDraftRequest(
          draft: SavedDraft(version: BigInt.from(3), content: saved.content),
          form: pending,
          universe: const Selector('Universe'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => valueDefinitionDraftRequest(
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
        'fields': CanonicalArray([
          ValueDefinitionFieldInput(
            name: 'unfinished 記憶 😀',
            shape: ValueShapeInput(
              kind: 'sequence',
              item: ValueShapeInput(kind: 'quantity', unit: 'unfinished unit'),
            ),
            required: true,
            allowsUnknown: true,
          ).toWire(),
        ]),
      });
      store.save(scope, incomplete, BigInt.one);
      expect(
        store.load(scope)!.form.toWire().toText(),
        incomplete.toWire().toText(),
      );
      expect(
        () => valueDefinitionRevisionOperation(store.load(scope)!.form),
        throwsFormatException,
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
