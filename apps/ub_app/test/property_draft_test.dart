@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/property_draft.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';

void main() {
  test(
    'all authored value shapes round trip without changing nested references',
    () {
      final unit = UnitId.generate(), definition = ValueDefinitionId.generate();
      final type = RecordId.generate();
      final shapes = <ValueShape>[
        ...SimpleShapeKind.values.map(SimpleValueShape.new),
        QuantityShape(unit),
        const RangeShape(null),
        RangeShape(unit),
        EntityRefShape([type, type]),
        EntityRefShape([]),
        EnumShape(definition),
        StructuredShape(definition),
        SequenceShape(SequenceShape(QuantityShape(unit))),
      ];
      for (final shape in shapes) {
        final input = ValueShapeInput.fromWire(valueShapeInput(shape).toWire());
        expect(
          buildValueShape(input).toWire().toText(),
          shape.toWire().toText(),
        );
      }
      final incomplete = ValueShapeInput(
        kind: 'sequence',
        unit: 'hidden invalid unit',
        item: ValueShapeInput(kind: 'quantity', unit: 'unfinished 記憶 😀'),
      );
      expect(
        ValueShapeInput.fromWire(incomplete.toWire()).toWire().toText(),
        incomplete.toWire().toText(),
      );
      expect(() => buildValueShape(incomplete), throwsFormatException);
      expect(
        buildValueShape(
          ValueShapeInput(kind: 'text', unit: 'inactive unfinished unit'),
        ),
        const SimpleValueShape(SimpleShapeKind.text),
      );
    },
  );

  test('property edits retain every field and reject stale edits', () {
    final property = PropertyRecord(
      namespace: 'authored',
      key: 'account',
      labels: {'ja': '記憶 😀', 'en': 'Account', '': 'Authored label'},
      subjectTypes: [RecordId.generate(), RecordId.generate()],
      value: SequenceShape(StructuredShape(ValueDefinitionId.generate())),
      multiplicity: Multiplicity.multiple,
      persistence: PersistenceSemantics.conditionDependent,
      unitDimension: '',
      inverse: 'inverse 記憶 😀',
      exclusive: true,
      symmetric: true,
      transitive: true,
    );
    final op = DefinePropertyOperation(
      clientRef: RecordId.generate().value,
      record: property,
    );
    final other = CreateWorldOperation(
      clientRef: 'world',
      record: WorldRecord(selector: 'River'),
    );
    final draft = SavedDraft(
      version: BigInt.two,
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: RecordId.generate(),
        operations: [other, op],
        rationale: 'Original rationale.',
      ),
    );
    final form = propertyFormFromDraft(draft, 1);
    final restored = UnfinishedPropertyForm.fromWire(form.toWire());
    expect(propertyOperation(restored).toWire().toText(), op.toWire().toText());
    final request = propertyDraftRequest(
      draft: draft,
      form: restored,
      universe: Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 1,
    );
    expect(request.content.toWire().toText(), draft.content.toWire().toText());
    final concurrent = SavedDraft(
      version: BigInt.from(3),
      content: draft.content,
    );
    expect(
      () => propertyDraftRequest(
        draft: concurrent,
        form: form,
        universe: Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 1,
      ),
      throwsFormatException,
    );
    final duplicate = UnfinishedPropertyForm.fromWire(
      CanonicalObject(
        form.toWire().fields.map(
          (entry) => entry.key == 'labels'
              ? MapEntry(
                  'labels',
                  CanonicalArray([
                    const PropertyLabelInput(
                      language: 'en',
                      text: 'First',
                    ).toWire(),
                    const PropertyLabelInput(
                      language: 'en',
                      text: 'Second',
                    ).toWire(),
                  ]),
                )
              : entry,
        ),
      ),
    );
    expect(duplicate.labels.length, 2);
    expect(() => propertyOperation(duplicate), throwsFormatException);
  });

  test('pending property forms recover exactly in separate creation and edit slots', () {
    final root = Directory('/tmp').createTempSync('ub-property-cache-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedPropertyForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      namespace: '記憶 😀',
      key: 'unfinished',
      labels: [
        const PropertyLabelInput(language: '', text: 'unfinished label 😀'),
        const PropertyLabelInput(
          language: '',
          text: 'another unfinished label',
        ),
      ],
      shape: ValueShapeInput(
        kind: 'sequence',
        item: ValueShapeInput(
          kind: 'enum',
          definition: 'unfinished definition',
        ),
      ),
      subjectTypes: ['unfinished type', 'unfinished type'],
      hasInverse: true,
      inverse: 'unfinished inverse',
      hasUnitDimension: true,
      unitDimension: '',
      rationale: '記憶 😀\nDecision',
    );
    final path = '${root.path}/forms.sqlite';
    var store = PropertyFormRecoveryStore.open(path);
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = PropertyFormRecoveryStore.open(path);
      expect(store.load(scope)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      final changed = UnfinishedPropertyForm(
        baseRevision: form.baseRevision,
        representedContext: form.representedContext,
        clientRef: form.clientRef,
        key: 'competing',
        shape: ValueShapeInput(),
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
      store.save(editScope, changed, BigInt.zero);
      expect(store.load(scope)!.form.toWire().toText(), form.toWire().toText());
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });

  test('property form recovers through the client and publishes to the named property picker', () async {
    final root = Directory('/tmp').createTempSync('ub-property-workflow-');
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
            name: 'Properties',
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
        universe: Selector('Properties'),
        scope: scope,
      );
      final form = UnfinishedPropertyForm(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        namespace: 'authored',
        key: 'account',
        labels: [
          const PropertyLabelInput(language: 'en', text: 'Account 記憶 😀'),
        ],
        shape: ValueShapeInput(
          kind: 'sequence',
          item: ValueShapeInput(kind: 'text'),
        ),
        multiplicity: 'multiple',
        persistence: 'unspecified',
        rationale: 'Declare attributed accounts.',
      );
      await session.savePropertyForm(scope, form, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recovered = (await session.loadPropertyForm(scope))!.form;
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
      final request = propertyDraftRequest(
        draft: initial,
        form: recovered,
        universe: Selector('Properties'),
        continuity: scope.continuity,
      );
      final saved = SavedDraft.fromWire(await session.call(request));
      final retry = propertyDraftRequest(
        draft: saved,
        form: recovered,
        universe: Selector('Properties'),
        continuity: scope.continuity,
      );
      expect(retry.content.toWire().toText(), saved.content.toWire().toText());
      final proposal = await changes().submit(saved);
      final validation =
          await changes().validate(proposal) as EvaluatedValidation;
      await changes().approve(proposal, validation);
      final receipt = await changes().publish(
        proposal,
        validation.execution.runId,
      );
      final published = await changes().readPublished(proposal, receipt);
      final property = published.single;
      expect(
        property.payload.toWire().toText(),
        propertyOperation(form).record.toWire().toText(),
      );
      final next = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final context = await openDraftChoiceContext(changes(), next);
      final choices = await searchDraftChoices(
        changes: changes(),
        context: context,
        kind: RecordKind.property,
        query: 'Account',
      );
      expect(choices.result.hits.single.label, 'Account 記憶 😀');
      expect(
        (await selectDraftChoice(
          changes: changes(),
          context: context,
          hit: choices.result.hits.single,
          kind: RecordKind.property,
        )).record,
        property.identity.recordId,
      );
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
