@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/unit_draft.dart';
import 'package:ub_app/property_draft.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';

void main() {
  test('unit edits preserve exact scale, base, labels and authored temporal validity', () {
    final validity = InstantValidity(
      DurationTime(
        CalendarId.generate(),
        SequenceValue([const TextValue('one lifetime 記憶 😀')]),
      ),
    );
    final unit = UnitRecord(
      namespace: 'authored',
      key: 'measure',
      dimension: 'distance',
      symbol: '記憶 😀',
      labels: {'en': 'Measure', 'ja': '記憶 😀'},
      base: UnitId.generate(),
      scaleToBase: const RationalValue('3', '2'),
      validity: validity,
    );
    final unspecifiedMetadata = UnfinishedUnitForm(
      baseRevision: RevisionId.generate(),
      representedContext: RecordId.generate(),
      clientRef: RecordId.generate().value,
      namespace: 'authored',
      key: 'undefined-metadata',
      validityChoice: 'unspecified',
    );
    expect(unitOperation(unspecifiedMetadata).record.dimension, '');
    expect(unitOperation(unspecifiedMetadata).record.symbol, '');
    final operation = DefineUnitOperation(
      clientRef: RecordId.generate().value,
      record: unit,
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
    final form = unitFormFromDraft(draft, 1);
    final recovered = UnfinishedUnitForm.fromWire(form.toWire());
    expect(
      unitOperation(recovered, original: unit).toWire().toText(),
      operation.toWire().toText(),
    );
    final request = unitDraftRequest(
      draft: draft,
      form: recovered,
      universe: Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 1,
    );
    expect(request.content.toWire().toText(), draft.content.toWire().toText());
    final stale = SavedDraft(version: BigInt.from(3), content: draft.content);
    expect(
      () => unitDraftRequest(
        draft: stale,
        form: form,
        universe: Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 1,
      ),
      throwsFormatException,
    );
    final edited = UnfinishedUnitForm.fromWire(
      CanonicalObject(
        form.toWire().fields.map(
          (entry) => switch (entry.key) {
            'has_scale' => const MapEntry('has_scale', CanonicalBool(false)),
            'has_base' => const MapEntry('has_base', CanonicalBool(false)),
            'validity_choice' => MapEntry(
              'validity_choice',
              CanonicalString('unknown'),
            ),
            _ => entry,
          },
        ),
      ),
    );
    final changed = unitOperation(edited, original: unit).record;
    expect(changed.scaleToBase, isNull);
    expect(changed.base, isNull);
    expect(changed.validity, const UnknownValidity());
    expect(changed.labels, unit.labels);
    expect(changed.symbol, unit.symbol);
  });

  test('unfinished unit input and inactive conversion fields recover without becoming canon', () {
    final root = Directory('/tmp').createTempSync('ub-unit-cache-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedUnitForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      namespace: '記憶 😀',
      hasBase: true,
      base: 'unfinished base',
      hasScale: true,
      scale: const QualifierInput(
        kind: 'rational',
        value: 'unfinished',
        denominator: 'unfinished denominator',
      ),
      validityChoice: 'temporal',
      temporalValidity: const TemporalValidityInput(
        kind: 'instant',
        calendar: 'unfinished calendar',
        start: TemporalBoundInput(value: 'unfinished 記憶 😀'),
      ),
      labels: [const PropertyLabelInput(text: 'unfinished label 😀')],
    );
    var store = UnitFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = UnitFormRecoveryStore.open('${root.path}/forms.sqlite');
      expect(store.load(scope)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(() => unitOperation(form), throwsFormatException);
      final inactive = UnfinishedUnitForm(
        baseRevision: form.baseRevision,
        representedContext: form.representedContext,
        clientRef: form.clientRef,
        namespace: 'authored',
        key: 'unit',
        dimension: 'distance',
        symbol: 'u',
        base: 'inactive invalid base',
        scale: form.scale,
        validityChoice: 'unspecified',
      );
      expect(unitOperation(inactive).record.base, isNull);
      expect(unitOperation(inactive).record.scaleToBase, isNull);
      expect(
        () => store.save(scope, inactive, BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });

  test('unit creation recovers, publishes exact conversion and supplies quantity property choices', () async {
    final root = Directory('/tmp').createTempSync('ub-unit-workflow-');
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
            name: 'Units',
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
        universe: Selector('Units'),
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

      final base = UnfinishedUnitForm(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        namespace: 'authored',
        key: 'pace',
        dimension: 'distance',
        symbol: 'p',
        labels: [const PropertyLabelInput(language: 'en', text: 'Pace 記憶 😀')],
        validityChoice: 'unspecified',
        rationale: 'Declare a fictional base unit.',
      );
      await session.saveUnitForm(scope, base, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recovered = (await session.loadUnitForm(scope))!;
      expect(recovered.form.toWire().toText(), base.toWire().toText());
      final initial = SavedDraft(
        version: BigInt.zero,
        content: DraftContent(
          baseRevision: base.baseRevision,
          representedContext: base.representedContext,
          operations: [],
          rationale: '',
        ),
      );
      final saved = SavedDraft.fromWire(
        await session.call(
          unitDraftRequest(
            draft: initial,
            form: recovered.form,
            universe: Selector('Units'),
            continuity: scope.continuity,
          ),
        ),
      );
      expect(
        unitDraftRequest(
          draft: saved,
          form: base,
          universe: Selector('Units'),
          continuity: scope.continuity,
        ).content.toWire().toText(),
        saved.content.toWire().toText(),
      );
      final publishedBase = (await publish(saved)).single;
      expect(
        publishedBase.payload.toWire().toText(),
        unitOperation(base).record.toWire().toText(),
      );
      var next = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final context = await openDraftChoiceContext(changes(), next);
      final found = await searchDraftChoices(
        changes: changes(),
        context: context,
        kind: RecordKind.unit,
        query: 'Pace',
      );
      expect(found.result.hits.single.label, 'Pace 記憶 😀');
      final chosen = await selectDraftChoice(
        changes: changes(),
        context: context,
        hit: found.result.hits.single,
        kind: RecordKind.unit,
      );
      final baseId = UnitId.parse(
        '${UnitId.prefix}${chosen.record.value.substring(RecordId.prefix.length)}',
      );
      final derived = UnfinishedUnitForm(
        baseRevision: next.content.baseRevision,
        representedContext: base.representedContext,
        clientRef: RecordId.generate().value,
        namespace: 'authored',
        key: 'stride',
        dimension: 'distance',
        symbol: 's',
        labels: [const PropertyLabelInput(language: 'en', text: 'Stride')],
        hasBase: true,
        base: baseId.value,
        hasScale: true,
        scale: const QualifierInput(
          kind: 'rational',
          value: '3',
          denominator: '2',
        ),
        validityChoice: 'unspecified',
        rationale: 'A stride is three halves of a pace.',
      );
      final derivedDraft = SavedDraft.fromWire(
        await session.call(
          unitDraftRequest(
            draft: next,
            form: derived,
            universe: Selector('Units'),
            continuity: scope.continuity,
          ),
        ),
      );
      final publishedDerived = (await publish(derivedDraft)).single;
      final record = publishedDerived.payload as UnitRecord;
      expect(record.base, baseId);
      expect(record.scaleToBase, const RationalValue('3', '2'));
      next = await changes().rebase((await changes().load())!, startNew: true);
      final unit = UnitId.parse(
        '${UnitId.prefix}${publishedDerived.identity.recordId.value.substring(RecordId.prefix.length)}',
      );
      final property = UnfinishedPropertyForm(
        baseRevision: next.content.baseRevision,
        representedContext: base.representedContext,
        clientRef: RecordId.generate().value,
        namespace: 'authored',
        key: 'walking-distance',
        shape: ValueShapeInput(kind: 'quantity', unit: unit.value),
        multiplicity: 'single',
        persistence: 'unspecified',
        hasUnitDimension: true,
        unitDimension: 'distance',
        rationale: 'Record authored walking distance.',
      );
      final propertyDraft = SavedDraft.fromWire(
        await session.call(
          propertyDraftRequest(
            draft: next,
            form: property,
            universe: Selector('Units'),
            continuity: scope.continuity,
          ),
        ),
      );
      final publishedProperty =
          (await publish(propertyDraft)).single.payload as PropertyRecord;
      expect(publishedProperty.value, QuantityShape(unit));
      expect(publishedProperty.unitDimension, 'distance');
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
