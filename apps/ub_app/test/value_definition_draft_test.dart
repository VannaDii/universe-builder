@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/value_definition_draft.dart';
import 'package:ub_app/property_draft.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_app/qualifier_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';

void main() {
  test('value-definition edits preserve every field shape, order and authored flag', () {
    final value = ValueDefinitionRecord(
      namespace: 'authored',
      key: 'account',
      labels: {'en': 'Account', '': 'Authored label 記憶 😀'},
      fields: [
        ValueDefinitionField(
          name: 'details 記憶 😀',
          shape: SequenceShape(SequenceShape(QuantityShape(UnitId.generate()))),
          required: true,
          allowsUnknown: true,
        ),
        const ValueDefinitionField(
          name: 'note',
          shape: SimpleValueShape(SimpleShapeKind.text),
          required: false,
          allowsUnknown: false,
        ),
      ],
    );
    final operation = DefineValueOperation(
      clientRef: RecordId.generate().value,
      record: value,
    );
    final other = CreateWorldOperation(
      clientRef: 'river',
      record: WorldRecord(selector: 'River'),
    );
    final draft = SavedDraft(
      version: BigInt.two,
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: RecordId.generate(),
        operations: [other, operation],
        rationale: 'Exact rationale',
      ),
    );
    final form = valueDefinitionFormFromDraft(draft, 1);
    final recovered = UnfinishedValueDefinitionForm.fromWire(form.toWire());
    expect(
      valueDefinitionOperation(recovered).toWire().toText(),
      operation.toWire().toText(),
    );
    final exact = valueDefinitionDraftRequest(
      draft: draft,
      form: recovered,
      universe: Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 1,
    );
    expect(exact.content.toWire().toText(), draft.content.toWire().toText());
    final changed = UnfinishedValueDefinitionForm(
      baseRevision: form.baseRevision,
      representedContext: form.representedContext,
      clientRef: form.clientRef,
      namespace: form.namespace,
      key: form.key,
      labels: form.labels,
      fields: form.fields.reversed,
      draftVersion: form.draftVersion,
    );
    final replaced = valueDefinitionDraftRequest(
      draft: draft,
      form: changed,
      universe: Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 1,
    );
    expect(
      (replaced.content.operations[1] as DefineValueOperation).record.fields
          .map((f) => f.name),
      ['note', 'details 記憶 😀'],
    );
    expect(
      replaced.content.operations.first.toWire().toText(),
      other.toWire().toText(),
    );
    expect(replaced.content.rationale, draft.content.rationale);
    expect(
      () => valueDefinitionDraftRequest(
        draft: SavedDraft(version: BigInt.from(3), content: draft.content),
        form: changed,
        universe: Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 1,
      ),
      throwsFormatException,
    );
  });
  test('incomplete value-definition rows recover exactly and competing writes cannot overwrite', () {
    final root = Directory('/tmp').createTempSync('ub-value-definition-cache-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedValueDefinitionForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      namespace: 'authored',
      key: 'incomplete',
      fields: [
        ValueDefinitionFieldInput(
          name: '記憶 😀',
          shape: ValueShapeInput(
            kind: 'sequence',
            item: ValueShapeInput(kind: 'quantity', unit: 'unfinished unit'),
          ),
          required: true,
        ),
        ValueDefinitionFieldInput(
          name: '記憶 😀',
          shape: ValueShapeInput(),
          allowsUnknown: true,
        ),
      ],
      labels: [
        const PropertyLabelInput(language: '', text: 'unfinished label'),
      ],
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
      expect(store.load(scope)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(() => valueDefinitionOperation(form), throwsFormatException);
      final changed = UnfinishedValueDefinitionForm(
        baseRevision: form.baseRevision,
        representedContext: form.representedContext,
        clientRef: form.clientRef,
        namespace: 'competing',
      );
      expect(
        () => store.save(scope, changed, BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
      final editScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: form.clientRef,
      );
      expect(store.load(editScope), isNull);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('value definition recovers, publishes and supplies structured and enumeration property choices', () async {
    final root = Directory('/tmp')
        .createTempSync('ub-value-definition-workflow-');
    final catalog = SqliteInstallationStore.create(root.path);
    final instance = catalog.instanceId,
        profile = InstallationAuthority(catalog).initializeAuthor();
    catalog.close();
    final server = await LocalSqliteEngineServer.start(
      root.path,
      compatibilitySocket: false,
    );
    AppSession? session;
    try {
      final device = DeviceConnection([
        '--installation',
        root.path,
        '--profile',
        profile.value,
        '--engine=/nonexistent/universe-engine',
      ]);
      session = await device.connect();
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            name: 'Value definitions',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final scope = EditorFormScope(
        instance: instance,
        profile: profile,
        universe: UniverseId.parse(created.string('universe_id')),
        continuity: ContinuityId.parse(created.string('continuity_id')),
        representedContext: RecordId.parse(created.string('context_id')),
      );
      SavedChanges changes() => SavedChanges(
        session: session!,
        universe: Selector('Value definitions'),
        scope: scope,
      );
      Future<List<RecordVersion>> publish(SavedDraft draft) async {
        final proposal = await changes().submit(draft);
        final validation =
            await changes().validate(proposal) as EvaluatedValidation;
        await changes().approve(proposal, validation);
        final receipt = await changes().publish(
          proposal,
          validation.execution.runId,
        );
        return changes().readPublished(proposal, receipt);
      }

      final form = UnfinishedValueDefinitionForm(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        namespace: 'authored',
        key: 'account',
        labels: [
          const PropertyLabelInput(language: 'en', text: 'Account 記憶 😀'),
        ],
        fields: [
          ValueDefinitionFieldInput(
            name: 'detail',
            shape: ValueShapeInput(kind: 'text'),
            required: true,
            allowsUnknown: true,
          ),
          ValueDefinitionFieldInput(
            name: 'entries',
            shape: ValueShapeInput(
              kind: 'sequence',
              item: ValueShapeInput(kind: 'integer'),
            ),
          ),
        ],
        rationale: 'Declare attributed account fields.',
      );
      await session.saveValueDefinitionForm(scope, form, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recovered = (await session.loadValueDefinitionForm(scope))!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      final initial = SavedDraft(
        version: BigInt.zero,
        content: DraftContent(
          baseRevision: form.baseRevision,
          representedContext: form.representedContext,
          operations: [],
          rationale: '',
        ),
      );
      final saved = SavedDraft.fromWire(
        await session.call(
          valueDefinitionDraftRequest(
            draft: initial,
            form: recovered,
            universe: Selector('Value definitions'),
            continuity: scope.continuity,
          ),
        ),
      );
      expect(
        valueDefinitionDraftRequest(
          draft: saved,
          form: recovered,
          universe: Selector('Value definitions'),
          continuity: scope.continuity,
        ).content.toWire().toText(),
        saved.content.toWire().toText(),
      );
      final published = (await publish(saved)).single;
      expect(
        published.payload.toWire().toText(),
        valueDefinitionOperation(form).record.toWire().toText(),
      );
      var next = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final context = await openDraftChoiceContext(changes(), next);
      final found = await searchDraftChoices(
        changes: changes(),
        context: context,
        kind: RecordKind.valueDefinition,
        query: 'Account',
      );
      expect(found.result.hits.single.label, 'Account 記憶 😀');
      final chosen = await selectDraftChoice(
        changes: changes(),
        context: context,
        hit: found.result.hits.single,
        kind: RecordKind.valueDefinition,
      );
      final id = valueDefinitionFromChoice(chosen);
      expect(
        valueDefinitionChoiceRecord(id.value),
        published.identity.recordId,
      );
      final enumInput = QualifierInput(
        kind: 'enum',
        definition: id.value,
        value: 'entry 記憶 😀',
      );
      final structuredInput = QualifierInput(
        kind: 'structured',
        definition: id.value,
        children: [
          const QualifierInput(
            key: 'note',
            kind: 'text',
            value: 'Authored note 記憶 😀',
          ),
        ],
      );
      final sequence = QualifierInput(
        kind: 'sequence',
        children: [enumInput, structuredInput],
      );
      final recoveredValues = QualifierInput.fromWire(sequence.toWire());
      expect(
        buildQualifierValue(recoveredValues, null).toWire().toText(),
        SequenceValue([
          EnumValue(id, 'entry 記憶 😀'),
          StructuredValue(id, {'note': const TextValue('Authored note 記憶 😀')}),
        ]).toWire().toText(),
      );
      expect(
        () => valueDefinitionChoiceRecord('unfinished definition'),
        throwsFormatException,
      );

      for (final kind in ['structured', 'enum']) {
        final property = UnfinishedPropertyForm(
          baseRevision: next.content.baseRevision,
          representedContext: form.representedContext,
          clientRef: RecordId.generate().value,
          namespace: 'authored',
          key: '$kind-account',
          shape: ValueShapeInput(kind: kind, definition: id.value),
          multiplicity: 'multiple',
          persistence: 'unspecified',
          rationale: 'Use the published $kind value definition.',
        );
        final draft = SavedDraft.fromWire(
          await session.call(
            propertyDraftRequest(
              draft: next,
              form: property,
              universe: Selector('Value definitions'),
              continuity: scope.continuity,
            ),
          ),
        );
        final record = (await publish(draft)).single.payload as PropertyRecord;
        expect(
          record.value,
          kind == 'structured' ? StructuredShape(id) : EnumShape(id),
        );
        next = await changes().rebase(
          (await changes().load())!,
          startNew: true,
        );
      }
      final revisionBase = next;
      final revisionScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: published.identity.recordId.value,
      );
      final sourceForm = valueDefinitionRevisionFormFromRecord(
        record: published,
        baseRevision: next.content.baseRevision,
        representedContext: scope.representedContext!,
      );
      final revisedFields = [...sourceForm.fields.reversed];
      final detail = revisedFields.last;
      revisedFields[revisedFields.length - 1] = ValueDefinitionFieldInput(
        name: detail.name,
        shape: detail.shape,
        required: false,
        allowsUnknown: detail.allowsUnknown,
      );
      final revisionForm = UnfinishedValueDefinitionForm.fromWire(
        CanonicalObject(
          sourceForm.toWire().fields.map(
            (e) => e.key == 'fields'
                ? MapEntry(
                    'fields',
                    CanonicalArray(revisedFields.map((f) => f.toWire())),
                  )
                : e.key == 'rationale'
                ? MapEntry(
                    'rationale',
                    CanonicalString(
                      'Reorder fields and make the detail optional.',
                    ),
                  )
                : e,
          ),
        ),
      );
      await session.saveValueDefinitionForm(
        revisionScope,
        revisionForm,
        BigInt.zero,
      );
      await session.close();
      session = await device.connect();
      final recoveredRevision = (await session.loadValueDefinitionForm(
        revisionScope,
      ))!.form;
      expect(
        recoveredRevision.toWire().toText(),
        revisionForm.toWire().toText(),
      );
      final revisionDraft = SavedDraft.fromWire(
        await session.call(
          valueDefinitionDraftRequest(
            draft: revisionBase,
            form: recoveredRevision,
            universe: const Selector('Value definitions'),
            continuity: scope.continuity,
          ),
        ),
      );
      final revisedValue = (await publish(revisionDraft)).single;
      expect(revisedValue.identity.recordId, published.identity.recordId);
      expect(
        revisedValue.payload.toWire().toText(),
        valueDefinitionRevisionOperation(revisionForm).replacement
            .toWire()
            .toText(),
      );
      final retainedValue = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Value definitions'),
        context: await openDraftChoiceContext(changes(), revisionBase),
        record: published.identity.recordId,
      );
      expect(retainedValue.toWire().toText(), published.toWire().toText());
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
