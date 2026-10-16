@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/entity_draft.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/qualifier_draft.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/temporal_validity_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

void main() {
  test('published classification input and edits recover without replacing the entity', () async {
    final root = Directory('/tmp')
        .createTempSync('ub-classification-workflow-');
    final store = SqliteInstallationStore.create(root.path);
    final instance = store.instanceId;
    final author = InstallationAuthority(store).initializeAuthor();
    store.close();
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
        author.value,
        '--engine=/nonexistent/universe-engine',
      ]);
      session = await device.connect();
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            realWorld: false,
            name: 'Classification',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final scope = EditorFormScope(
        instance: instance,
        profile: author,
        universe: UniverseId.parse(created.string('universe_id')),
        continuity: ContinuityId.parse(created.string('continuity_id')),
        representedContext: RecordId.parse(created.string('context_id')),
      );
      SavedChanges changes() => SavedChanges(
        session: session!,
        universe: Selector('Classification'),
        scope: scope,
      );
      final initial = SavedDraft.fromWire(
        await session.call(
          SaveDraftEngineRequest(
            universe: Selector('Classification'),
            continuityId: scope.continuity,
            expectedVersion: BigInt.zero,
            content: DraftContent(
              baseRevision: RevisionId.parse(created.string('revision')),
              representedContext: scope.representedContext!,
              rationale: 'Introduce an entity and definitions.',
              operations: [
                IntroduceInstanceOperation(
                  clientRef: 'person',
                  name: const ContextualName(
                    text: 'Mara',
                    community: 'River',
                    validity: UnknownValidity(),
                  ),
                  worldAssociations: [],
                ),
                for (final key in ['person', 'traveler'])
                  IntroduceDefinitionOperation(
                    clientRef: 'type-$key',
                    namespace: 'authored',
                    key: key,
                    name: key,
                    parent: null,
                    applicability: const UniverseApplicability(),
                    classificationExecutable: true,
                  ),
              ],
            ),
          ),
        ),
      );
      final proposal = await changes().submit(initial);
      final validation =
          await changes().validate(proposal) as EvaluatedValidation;
      await changes().approve(proposal, validation);
      final receipt = await changes().publish(
        proposal,
        validation.execution.runId,
      );
      final records = await changes().readPublished(proposal, receipt);
      final entity = records.singleWhere((r) => r.payload is EntityRecord);
      final types = records
          .where((r) => r.payload is EntityTypeRecord)
          .toList();
      final fresh = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final choiceContext = await openDraftChoiceContext(changes(), fresh);
      final choices = await searchDraftChoices(
        changes: changes(),
        context: choiceContext,
        kind: null,
      );
      final hit = choices.result.hits.singleWhere(
        (h) => h.recordId == entity.identity.recordId,
      );
      final chosen = await selectDraftChoice(
        changes: changes(),
        context: choiceContext,
        hit: hit,
        kind: null,
      );
      expect(chosen.record, entity.identity.recordId);
      expect(chosen.universe, scope.universe);
      final summary = await readDraftChoiceSummary(
        changes: changes(),
        context: choiceContext,
        record: chosen.record,
        kind: null,
      );
      expect(summary.label, 'Mara');
      await expectLater(
        selectDraftChoice(
          changes: changes(),
          context: choiceContext,
          hit: hit,
          kind: RecordKind.proposition,
        ),
        throwsFormatException,
      );
      await expectLater(
        selectDraftChoice(
          changes: changes(),
          context: choiceContext,
          hit: SearchHit(
            recordId: hit.recordId,
            kind: RecordKind.proposition,
            label: hit.label,
            worldIds: hit.worldIds,
            scopeCategory: hit.scopeCategory,
          ),
          kind: null,
        ),
        throwsFormatException,
      );
      for (final universe in ['', chosen.universe!.value]) {
        for (final kind in ['entity_ref', 'record_ref', 'proposition_ref']) {
          final input = QualifierInput(
            kind: kind,
            value: chosen.record.value,
            universe: universe,
          );
          final recovered = QualifierInput.fromWire(input.toWire());
          final value = buildQualifierValue(recovered, null) as ReferenceValue;
          expect(value.record.record, chosen.record);
          expect(
            value.record.universe?.value,
            universe.isEmpty ? null : universe,
          );
        }
        final spatial = buildQualifierValue(
          QualifierInput.fromWire(
            QualifierInput(
              kind: 'spatial_contained_in',
              value: chosen.record.value,
              universe: universe,
            ).toWire(),
          ),
          null,
        ) as SpatialValue;
        expect((spatial.spatial as SpatialLink).target.record, chosen.record);
        expect(
          (spatial.spatial as SpatialLink).target.universe?.value,
          universe.isEmpty ? null : universe,
        );
        final relative = buildTemporalValidity(
          TemporalValidityInput.fromWire(
            TemporalValidityInput(
              kind: 'instant_relative',
              calendar: CalendarId.generate().value,
              relation: 'after',
              targetRecord: chosen.record.value,
              targetUniverse: universe,
            ).toWire(),
          ),
          null,
        ) as InstantValidity;
        expect((relative.at as RelativeTime).target.record, chosen.record);
        expect(
          (relative.at as RelativeTime).target.universe?.value,
          universe.isEmpty ? null : universe,
        );
      }
      final formScope = EditorFormScope(
        instance: instance,
        profile: author,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        entityClassificationRecord: entity.identity.recordId,
      );
      UnfinishedEntityForm form(String classification) => UnfinishedEntityForm(
        baseRevision: fresh.content.baseRevision,
        representedContext: fresh.content.representedContext,
        clientRef: entity.identity.recordId.value,
        expectedRecordVersion: entity.recordVersionId,
        name: '',
        classification: classification,
        worldRole: '',
        rationale: 'Classify the existing identity.',
      );
      await session.saveEntityForm(formScope, form(''), BigInt.zero);
      await session.close();
      session = await device.connect();
      final incomplete = (await session.loadEntityForm(formScope))!.form;
      expect(incomplete.classification, '');
      SaveDraftEngineRequest request(
        UnfinishedEntityForm fields,
        SavedDraft? old,
      ) => entityClassificationDraftRequest(
        universe: Selector('Classification'),
        universeId: scope.universe,
        continuity: scope.continuity,
        record: entity.identity.recordId,
        form: fields,
        previous: old,
      );
      expect(() => request(incomplete, fresh), throwsFormatException);
      await session.saveEntityForm(
        formScope,
        form(types.first.identity.recordId.value),
        BigInt.one,
      );
      final recovered = (await session.loadEntityForm(formScope))!.form;
      final saved = SavedDraft.fromWire(
        await session.call(request(recovered, fresh)),
      );
      expect(
        request(recovered, saved).content.toWire().toText(),
        saved.content.toWire().toText(),
      );
      expect(
        () => request(form(types.last.identity.recordId.value), saved),
        throwsFormatException,
      );
      final editScope = EditorFormScope(
        instance: instance,
        profile: author,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        entityClassificationRecord: entity.identity.recordId,
        entityOperationIndex: 0,
      );
      final fields = entityFormFromDraft(saved, 0);
      final edit = UnfinishedEntityForm(
        baseRevision: fields.baseRevision,
        representedContext: fields.representedContext,
        clientRef: fields.clientRef,
        expectedRecordVersion: fields.expectedRecordVersion,
        draftVersion: fields.draftVersion,
        name: '',
        classification: types.last.identity.recordId.value,
        worldRole: '',
        rationale: '',
      );
      await session.saveEntityForm(editScope, edit, BigInt.zero);
      await session.close();
      session = await device.connect();
      final pending = (await session.loadEntityForm(editScope))!.form;
      expect(pending.toWire().toText(), edit.toWire().toText());
      expect(
        (await session.loadEntityForm(formScope))!.form.toWire().toText(),
        recovered.toWire().toText(),
      );
      final edited = await changes().saveContent(
        saved,
        replaceDraftEntity(draft: saved, index: 0, form: pending),
      );
      expect(edited.content.rationale, saved.content.rationale);
      expect(
        () => replaceDraftEntity(draft: edited, index: 0, form: pending),
        throwsFormatException,
      );
      final refined = await changes().submit(edited);
      final checked = await changes().validate(refined) as EvaluatedValidation;
      await changes().approve(refined, checked);
      final committed = await changes().publish(
        refined,
        checked.execution.runId,
      );
      final result = (await changes().readPublished(refined, committed)).single;
      expect(result.identity.recordId, entity.identity.recordId);
      final payload = result.payload as EntityRecord;
      expect(payload.classification, types.last.identity.recordId);
      expect(
        payload.classificationResolution,
        ClassificationResolution.resolved,
      );
      expect(
        payload.names.map((n) => n.toWire().toText()),
        (entity.payload as EntityRecord).names.map((n) => n.toWire().toText()),
      );
      expect(
        payload.worldAssociations,
        (entity.payload as EntityRecord).worldAssociations,
      );
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });

  test(
    'contextual names recover and publish on the existing identity',
    () async {
      final root = Directory('/tmp').createTempSync('ub-name-workflow-');
      final store = SqliteInstallationStore.create(root.path);
      final instance = store.instanceId;
      final author = InstallationAuthority(store).initializeAuthor();
      store.close();
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
          author.value,
          '--engine=/nonexistent/universe-engine',
        ]);
        session = await device.connect();
        final created = WireFields(
          await session.call(
            const CreateUniverseEngineRequest(
              realWorld: false,
              name: 'Names',
              start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        final scope = EditorFormScope(
          instance: instance,
          profile: author,
          universe: UniverseId.parse(created.string('universe_id')),
          continuity: ContinuityId.parse(created.string('continuity_id')),
          representedContext: RecordId.parse(created.string('context_id')),
        );
        final changes = SavedChanges(
          session: session,
          universe: Selector('Names'),
          scope: scope,
        );
        final initial = SavedDraft.fromWire(
          await session.call(
            entityDraftRequest(
              universe: Selector('Names'),
              continuity: scope.continuity,
              previous: null,
              form: UnfinishedEntityForm(
                baseRevision: RevisionId.parse(created.string('revision')),
                representedContext: scope.representedContext!,
                clientRef: 'person',
                name: 'Mara',
                classification: '',
                worldRole: '',
                rationale: 'Introduce Mara.',
              ),
            ),
          ),
        );
        final proposal = await changes.submit(initial);
        final validation =
            await changes.validate(proposal) as EvaluatedValidation;
        await changes.approve(proposal, validation);
        final receipt = await changes.publish(
          proposal,
          validation.execution.runId,
        );
        final record = (await changes.readPublished(proposal, receipt)).single;
        final fresh = await changes.rebase(
          (await changes.load())!,
          startNew: true,
        );
        final nameScope = EditorFormScope(
          instance: instance,
          profile: author,
          universe: scope.universe,
          continuity: scope.continuity,
          representedContext: scope.representedContext,
          entityNameRecord: record.identity.recordId,
        );
        final form = UnfinishedEntityForm(
          baseRevision: fresh.content.baseRevision,
          representedContext: fresh.content.representedContext,
          clientRef: record.identity.recordId.value,
          expectedRecordVersion: record.recordVersionId,
          name: '記憶 😀',
          nameDetails: const EntityNameForm(
            language: '',
            community: 'River',
            role: 'pseudonym',
            validity: UnknownValidity(),
          ),
          classification: '',
          worldRole: '',
          rationale: 'A contextual name, same person.',
        );
        await session.saveEntityForm(nameScope, form, BigInt.zero);
        await session.close();
        session = await device.connect();
        final recovered = (await session.loadEntityForm(nameScope))!.form;
        expect(recovered.toWire().toText(), form.toWire().toText());
        expect(await session.loadEntityForm(scope), isNull);
        SaveDraftEngineRequest request(SavedDraft? previous) =>
            entityNameDraftRequest(
              universe: Selector('Names'),
              universeId: scope.universe,
              continuity: scope.continuity,
              record: record.identity.recordId,
              form: recovered,
              previous: previous,
            );
        final saved = SavedDraft.fromWire(await session.call(request(fresh)));
        expect(
          request(saved).content.toWire().toText(),
          saved.content.toWire().toText(),
        );
        expect(
          (saved.content.operations.single as AddNameOperation).expectedVersion,
          record.recordVersionId,
        );
        expect(
          () => request(
            SavedDraft(
              version: BigInt.one,
              content: DraftContent(
                baseRevision: RevisionId.generate(),
                representedContext: form.representedContext,
                operations: [],
                rationale: 'Other revision.',
              ),
            ),
          ),
          throwsFormatException,
        );
        final editScope = EditorFormScope(
          instance: instance,
          profile: author,
          universe: scope.universe,
          continuity: scope.continuity,
          representedContext: scope.representedContext,
          entityNameRecord: record.identity.recordId,
          entityOperationIndex: 0,
        );
        final fields = entityFormFromDraft(saved, 0);
        final editedForm = UnfinishedEntityForm(
          baseRevision: fields.baseRevision,
          representedContext: fields.representedContext,
          clientRef: fields.clientRef,
          expectedRecordVersion: fields.expectedRecordVersion,
          draftVersion: fields.draftVersion,
          name: '記憶 revised 😀',
          nameDetails: const EntityNameForm(
            language: '',
            community: null,
            role: 'pseudonym',
          ),
          classification: '',
          worldRole: '',
          rationale: '',
        );
        await session.saveEntityForm(editScope, editedForm, BigInt.zero);
        await session.close();
        session = await device.connect();
        final pending = (await session.loadEntityForm(editScope))!.form;
        expect(pending.toWire().toText(), editedForm.toWire().toText());
        expect(
          (await session.loadEntityForm(nameScope))!.form.toWire().toText(),
          form.toWire().toText(),
        );
        final editing = SavedChanges(
          session: session,
          universe: Selector('Names'),
          scope: scope,
        );
        final edited = await editing.saveContent(
          saved,
          replaceDraftEntity(draft: saved, index: 0, form: pending),
        );
        final exact = edited.content.operations.single as AddNameOperation;
        expect(
          exact.record,
          (saved.content.operations.single as AddNameOperation).record,
        );
        expect(exact.expectedVersion, record.recordVersionId);
        expect(exact.name.validity, const UnknownValidity());
        expect(edited.content.rationale, saved.content.rationale);
        expect(
          () => replaceDraftEntity(draft: edited, index: 0, form: pending),
          throwsFormatException,
        );
        final named = await editing.submit(edited);
        final checked = await editing.validate(named) as EvaluatedValidation;
        await editing.approve(named, checked);
        final published = await editing.publish(named, checked.execution.runId);
        final renamed = (await editing.readPublished(named, published)).single;
        expect(renamed.identity.recordId, record.identity.recordId);
        final entity = renamed.payload as EntityRecord;
        expect(entity.names.map((n) => n.text), ['Mara', editedForm.name]);
        expect(entity.names.last.language, '');
        expect(entity.names.last.community, isNull);
        expect(entity.names.last.role, 'pseudonym');
        expect(entity.names.last.validity, const UnknownValidity());
      } finally {
        await session?.close();
        await server.close();
        root.deleteSync(recursive: true);
      }
    },
  );
  test('qualifiers retain exact values and reject duplicate names and incomplete scalars', () {
    final original = <String, DomainValue>{
      'text': const TextValue('記憶 😀\naccount'),
      'flag': const BooleanValue(false),
      'integer': const IntegerValue('0001'),
      'decimal': const DecimalValue('1.00000000000000001'),
      'rational': const RationalValue('001', '03'),
      'quantity': QuantityValue(const DecimalValue('2.00'), UnitId.generate()),
      for (final kind in ValueReferenceKind.values)
        kind.wireName: ReferenceValue(
          kind,
          RecordRef(
            universe: UniverseId.generate(),
            record: RecordId.generate(),
          ),
        ),
      'local ref': ReferenceValue(
        ValueReferenceKind.parse('record_ref'),
        RecordRef(record: RecordId.generate()),
      ),
      'enum': EnumValue(ValueDefinitionId.generate(), '記憶 😀'),
      for (final relation in SpatialRelation.values)
        relation.wireName: SpatialValue(
          SpatialLink(
            relation,
            RecordRef(
              universe: UniverseId.generate(),
              record: RecordId.generate(),
            ),
          ),
        ),
      'coordinates': SpatialValue(
        SpatialCoordinates('authored grid', [
          const DecimalValue('1.000000000000000001'),
          const RationalValue('001', '03'),
        ]),
      ),
      'distance': SpatialValue(
        SpatialDistance(
          RecordRef(record: RecordId.generate()),
          const TextValue('one lifetime'),
          UnitId.generate(),
        ),
      ),
      'space': const SpatialValue(UnspecifiedSpace()),
      'range': RangeValue(
        lower: const RationalValue('001', '03'),
        upper: const DecimalValue('2.000000000000000001'),
        lowerInclusive: false,
        upperInclusive: true,
        unit: UnitId.generate(),
      ),
      'set': SetValue([
        const DecimalValue('1.000000000000000001'),
        const TextValue('記憶 😀'),
      ]),
      'fields': StructuredValue(ValueDefinitionId.generate(), {
        'nested': SequenceValue([
          const RationalValue('001', '03'),
          const TemporalValue(UnspecifiedTime()),
        ]),
      }),
      'structured': SequenceValue([
        const TextValue('first'),
        const BooleanValue(false),
      ]),
    };
    final rows = original.entries
        .map((q) => qualifierInput(q.key, q.value))
        .toList();
    final recovered = rows
        .map((q) => QualifierInput.fromWire(q.toWire()))
        .toList();
    expect(buildQualifiers(recovered, original), original);
    expect(
      buildQualifiers([
        const QualifierInput(
          key: 'renamed',
          kind: 'retain',
          originalKey: 'structured',
        ),
      ], original)['renamed'],
      original['structured'],
    );
    expect(buildQualifiers([], original), isEmpty);
    expect(
      buildQualifiers([
        const QualifierInput(key: 'flag', kind: 'boolean', value: 'false'),
      ], {})['flag'],
      const BooleanValue(false),
    );
    expect(
      () => buildQualifiers([
        const QualifierInput(key: 'x'),
        const QualifierInput(key: 'x'),
      ], {}),
      throwsFormatException,
    );
    expect(
      () => buildQualifiers([const QualifierInput(key: '')], {}),
      throwsFormatException,
    );
    expect(
      () => buildQualifiers([
        const QualifierInput(key: 'flag', kind: 'boolean'),
      ], {}),
      throwsFormatException,
    );
    expect(
      () => buildQualifiers([
        const QualifierInput(
          key: 'amount',
          kind: 'rational',
          value: '1',
          denominator: '0',
        ),
      ], {}),
      throwsFormatException,
    );
    expect(
      () => buildQualifiers([
        const QualifierInput(
          key: 'old',
          kind: 'retain',
          originalKey: 'missing',
        ),
      ], original),
      throwsFormatException,
    );
  });
  test('nested temporal amounts can be edited and recovered without a source value', () {
    final calendar = CalendarId.generate();
    final input = TemporalValidityInput(
      kind: 'instant_duration',
      calendar: calendar.value,
      start: const TemporalBoundInput(
        uncertaintyKind: 'typed',
        amount: QualifierInput(
          kind: 'sequence',
          children: [
            QualifierInput(kind: 'text', value: '記憶 😀'),
            QualifierInput(kind: 'rational', value: '001', denominator: '03'),
          ],
        ),
      ),
    );
    final recovered = TemporalValidityInput.fromWire(input.toWire());
    expect(
      buildTemporalValidity(recovered, null),
      InstantValidity(
        DurationTime(
          calendar,
          SequenceValue([
            const TextValue('記憶 😀'),
            const RationalValue('001', '03'),
          ]),
        ),
      ),
    );
    final approximate = TemporalValidityInput(
      start: input.start.copyWith(kind: 'approximate', value: 'Day 1'),
      end: const TemporalBoundInput(kind: 'unbounded'),
    );
    expect(
      buildTemporalValidity(approximate, null),
      IntervalValidity(
        ApproximateBound(
          'Day 1',
          SequenceValue([
            const TextValue('記憶 😀'),
            const RationalValue('001', '03'),
          ]),
        ),
        const UnboundedBound(),
      ),
    );
    expect(
      () => buildTemporalValidity(
        input.copyWith(
          start: const TemporalBoundInput(uncertaintyKind: 'typed'),
        ),
        null,
      ),
      throwsFormatException,
    );
  });
  test(
    'spatial edits preserve exact coordinates, targets and distance units',
    () {
      final target = RecordId.generate(),
          universe = UniverseId.generate(),
          unit = UnitId.generate();
      final coordinates = QualifierInput(
        key: 'coordinates',
        kind: 'spatial_coordinates',
        value: '記憶 😀 grid',
        children: [
          const QualifierInput(kind: 'decimal', value: '1.000000000000000001'),
          const QualifierInput(
            kind: 'rational',
            value: '001',
            denominator: '03',
          ),
        ],
      );
      expect(
        buildQualifiers([coordinates], {})['coordinates'],
        SpatialValue(
          SpatialCoordinates('記憶 😀 grid', [
            const DecimalValue('1.000000000000000001'),
            const RationalValue('001', '03'),
          ]),
        ),
      );
      final distance = QualifierInput(
        key: 'distance',
        kind: 'spatial_distance',
        value: target.value,
        universe: universe.value,
        unit: unit.value,
        lower: const QualifierInput(
          kind: 'decimal',
          value: '2.000000000000000001',
        ),
      );
      expect(
        buildQualifiers([
          QualifierInput.fromWire(distance.toWire()),
        ], {})['distance'],
        SpatialValue(
          SpatialDistance(
            RecordRef(universe: universe, record: target),
            const DecimalValue('2.000000000000000001'),
            unit,
          ),
        ),
      );
      for (final row in [
        const QualifierInput(key: 'distance', kind: 'spatial_distance'),
        QualifierInput(
          key: 'distance',
          kind: 'spatial_distance',
          value: target.value,
          lower: distance.lower,
        ),
        const QualifierInput(
          key: 'target',
          kind: 'spatial_contained_in',
          value: 'unfinished',
        ),
      ]) {
        expect(() => buildQualifiers([row], {}), throwsFormatException);
      }
    },
  );
  test('temporal qualifier edits require expression fields and retain exact amounts', () {
    final calendar = CalendarId.generate(), target = RecordId.generate();
    final row = QualifierInput(
      key: 'time',
      kind: 'temporal',
      temporal: TemporalValidityInput(
        kind: 'instant_relative',
        calendar: calendar.value,
        relation: 'after',
        targetRecord: target.value,
      ),
    );
    expect(
      buildQualifiers([row], {})['time'],
      TemporalValue(
        RelativeTime(
          calendar,
          TemporalRelation.after,
          RecordRef(record: target),
        ),
      ),
    );
    for (final input in [
      const QualifierInput(key: 'time', kind: 'temporal'),
      const QualifierInput(
        key: 'time',
        kind: 'temporal',
        temporal: TemporalValidityInput(),
      ),
      QualifierInput(
        key: 'time',
        kind: 'temporal',
        temporal: row.temporal!.copyWith(relation: ''),
      ),
    ]) {
      expect(() => buildQualifiers([input], {}), throwsFormatException);
    }
    final original = TemporalValue(
      DurationTime(calendar, SequenceValue([const TextValue('one lifetime')])),
    );
    expect(
      buildQualifiers(
        [qualifierInput('time', original)],
        {'time': original},
      )['time'],
      original,
    );
  });
  test(
    'range edits preserve typed bounds and require explicit inclusivity',
    () {
      final input = QualifierInput(
        key: 'range',
        kind: 'range',
        lower: const QualifierInput(kind: 'integer', value: '001'),
        upper: const QualifierInput(kind: 'integer', value: '003'),
        lowerInclusive: 'false',
        upperInclusive: 'true',
      );
      expect(
        buildQualifiers([QualifierInput.fromWire(input.toWire())], {})['range'],
        const RangeValue(
          lower: IntegerValue('001'),
          upper: IntegerValue('003'),
          lowerInclusive: false,
          upperInclusive: true,
        ),
      );
      for (final row in [
        const QualifierInput(key: 'range', kind: 'range'),
        QualifierInput(
          key: 'range',
          kind: 'range',
          lower: input.lower,
          upper: input.upper,
        ),
        QualifierInput(
          key: 'range',
          kind: 'range',
          lower: input.upper,
          upper: input.lower,
          lowerInclusive: 'true',
          upperInclusive: 'false',
        ),
      ]) {
        expect(() => buildQualifiers([row], {}), throwsFormatException);
      }
      final original = const RangeValue(
        lower: TemporalValue(UnspecifiedTime()),
        upper: TextValue('one lifetime'),
        lowerInclusive: true,
        upperInclusive: false,
      );
      expect(
        buildQualifiers(
          [qualifierInput('time', original)],
          {'time': original},
        )['time'],
        original,
      );
    },
  );
  test(
    'collection edits preserve order, retained children and field names',
    () {
      final opaque = const TemporalValue(UnspecifiedTime());
      final source = SequenceValue([
        const TextValue('first'),
        opaque,
        const BooleanValue(false),
      ]);
      final input = qualifierInput('list', source);
      final edited = QualifierInput(
        key: 'renamed list',
        kind: 'sequence',
        originalKey: 'list',
        children: [
          input.children[2],
          input.children[1],
          const QualifierInput(kind: 'text', value: 'new 😀'),
        ],
      );
      final recovered = QualifierInput.fromWire(edited.toWire());
      expect(
        buildQualifiers([recovered], {'list': source})['renamed list'],
        SequenceValue([
          const BooleanValue(false),
          opaque,
          const TextValue('new 😀'),
        ]),
      );
      final definition = ValueDefinitionId.generate();
      final structure = StructuredValue(definition, {'old': opaque});
      final changed = QualifierInput(
        key: 'fields',
        kind: 'structured',
        definition: definition.value,
        originalKey: 'fields',
        children: [
          const QualifierInput(
            key: 'renamed',
            kind: 'retain',
            originalKey: 'old',
          ),
        ],
      );
      expect(
        buildQualifiers([changed], {'fields': structure})['fields'],
        StructuredValue(definition, {'renamed': opaque}),
      );
      expect(
        () => buildQualifiers([
          QualifierInput(
            key: 'fields',
            kind: 'structured',
            definition: definition.value,
            children: [
              const QualifierInput(key: 'x'),
              const QualifierInput(key: 'x'),
            ],
          ),
        ], {}),
        throwsFormatException,
      );
      expect(
        buildQualifiers([
          const QualifierInput(key: 'empty', kind: 'set'),
        ], {})['empty'],
        SetValue([]),
      );
    },
  );
  test('reference and enumeration edits retain targets and exact input', () {
    final target = RecordId.generate(), universe = UniverseId.generate();
    final definition = ValueDefinitionId.generate();
    final inputs = [
      QualifierInput(
        key: 'target',
        kind: 'entity_ref',
        value: target.value,
        universe: universe.value,
      ),
      QualifierInput(
        key: 'entry',
        kind: 'enum',
        definition: definition.value,
        value: '記憶 😀',
      ),
    ];
    final values = buildQualifiers(inputs, {});
    expect(
      values['target'],
      ReferenceValue(
        ValueReferenceKind.parse('entity_ref'),
        RecordRef(universe: universe, record: target),
      ),
    );
    expect(values['entry'], EnumValue(definition, '記憶 😀'));
    for (final input in [
      const QualifierInput(
        key: 'target',
        kind: 'record_ref',
        value: 'unfinished',
      ),
      QualifierInput(
        key: 'target',
        kind: 'record_ref',
        value: target.value,
        universe: 'unfinished',
      ),
      const QualifierInput(
        key: 'entry',
        kind: 'enum',
        definition: 'unfinished',
        value: 'key',
      ),
    ]) {
      expect(() => buildQualifiers([input], {}), throwsFormatException);
    }
  });
  test(
    'temporal validity retains exact calendar notation and uncertain bounds',
    () {
      final calendar = CalendarId.generate();
      final originals = <Validity>[
        InstantValidity(
          IntervalTime(
            calendar,
            const UnknownBound(),
            const ExactBound('Day 90'),
          ),
        ),
        InstantValidity(
          ApproximateTime(calendar, 'Day 42', const RationalValue('001', '03')),
        ),
        InstantValidity(
          DurationTime(calendar, const DecimalValue('0.000000000000000001')),
        ),
        InstantValidity(
          DurationTime(calendar, const TextValue('one lifetime')),
        ),
        InstantValidity(
          ApproximateTime(calendar, 'Day 42', const TextValue('about a week')),
        ),
        InstantValidity(DurationTime(calendar, const BooleanValue(false))),
        InstantValidity(
          ApproximateTime(calendar, 'Day 43', const BooleanValue(true)),
        ),
        const PersistentValidity(
          ApproximateBound('Day 2', TextValue('記憶 😀\nabout a week')),
        ),
        const IntervalValidity(
          ApproximateBound('Day 1', BooleanValue(false)),
          UnboundedBound(),
        ),
        const InstantValidity(UnspecifiedTime()),
        for (final relation in TemporalRelation.values)
          InstantValidity(
            RelativeTime(
              calendar,
              relation,
              RecordRef(
                universe: UniverseId.generate(),
                record: RecordId.generate(),
              ),
            ),
          ),
        InstantValidity(
          RelativeTime(
            calendar,
            TemporalRelation.after,
            RecordRef(record: RecordId.generate()),
          ),
        ),

        InstantValidity(ExactTime(calendar, 'Day 42.0000000000000000001')),
        const IntervalValidity(UnknownBound(), UnboundedBound()),
        const IntervalValidity(
          UncertainBound('Day 1', 'Day 3'),
          ExactBound('Day 10'),
        ),
        CalendarIntervalValidity(
          calendar,
          const ExactBound('001.00'),
          const UnboundedBound(),
        ),
        const PersistentValidity(
          ApproximateBound('Day 3', RationalValue('001', '03')),
        ),
      ];
      for (final original in originals) {
        final input = temporalValidityInput(original);
        final recovered = TemporalValidityInput.fromWire(input.toWire());
        expect(buildTemporalValidity(recovered, original), original);
        if (original is InstantValidity) {
          final value = TemporalValue(original.at);
          final row = QualifierInput.fromWire(
            qualifierInput('time', value).toWire(),
          );
          expect(buildQualifiers([row], {'time': value})['time'], value);
        }
      }
      final relativeInput = TemporalValidityInput(
        kind: 'instant_relative',
        calendar: calendar.value,
        relation: 'unknown',
        targetRecord: RecordId.generate().value,
      );
      expect(
        () => buildTemporalValidity(relativeInput, null),
        throwsFormatException,
      );
      final unit = UnitId.generate();
      final original = PersistentValidity(
        ApproximateBound(
          'Day 4',
          QuantityValue(const DecimalValue('0.00001'), unit),
        ),
      );
      expect(
        buildTemporalValidity(temporalValidityInput(original), original),
        original,
      );
      final opaque = const PersistentValidity(
        ApproximateBound('Day 5', TextValue('about a week')),
      );
      expect(
        buildTemporalValidity(temporalValidityInput(opaque), opaque),
        opaque,
      );
      expect(
        () => buildTemporalValidity(const TemporalValidityInput(), null),
        throwsFormatException,
      );
      expect(
        () => buildTemporalValidity(
          const TemporalValidityInput(
            start: TemporalBoundInput(
              kind: 'approximate',
              value: 'Day 3',
              uncertaintyKind: 'rational',
              uncertainty: '1',
              denominator: '0',
            ),
          ),
          null,
        ),
        throwsFormatException,
      );
    },
  );
  test('amount edits preserve text and require an explicit boolean value', () {
    final calendar = CalendarId.generate();
    final input = TemporalValidityInput(
      kind: 'instant_duration',
      calendar: calendar.value,
      start: const TemporalBoundInput(
        uncertaintyKind: 'text',
        uncertainty: '記憶 😀\nabout a week',
      ),
    );
    expect(
      buildTemporalValidity(input, null),
      InstantValidity(
        DurationTime(calendar, const TextValue('記憶 😀\nabout a week')),
      ),
    );
    final falseInput = input.copyWith(
      start: input.start.copyWith(
        uncertaintyKind: 'boolean',
        uncertainty: 'false',
      ),
    );
    expect(
      buildTemporalValidity(falseInput, null),
      InstantValidity(DurationTime(calendar, const BooleanValue(false))),
    );
    expect(
      () => buildTemporalValidity(
        falseInput.copyWith(start: falseInput.start.copyWith(uncertainty: '')),
        null,
      ),
      throwsFormatException,
    );
    expect(
      () => buildTemporalValidity(
        input.copyWith(
          start: input.start.copyWith(unit: UnitId.generate().value),
        ),
        null,
      ),
      throwsFormatException,
    );
    final changed = input.copyWith(
      start: input.start.copyWith(uncertainty: 'another authored amount'),
    );
    expect(
      buildTemporalValidity(changed, buildTemporalValidity(input, null)),
      InstantValidity(
        DurationTime(calendar, const TextValue('another authored amount')),
      ),
    );
  });
  test('a name alone is enough; world associations need an explicit role', () {
    final base = RevisionId.generate(), context = RecordId.generate();
    final worlds = [WorldId.generate(), WorldId.generate()];
    UnfinishedEntityForm form({
      String name = '人物',
      String role = '',
      List<WorldId> selected = const [],
    }) => UnfinishedEntityForm(
      baseRevision: base,
      representedContext: context,
      clientRef: 'person',
      name: name,
      classification: '',
      worldRole: role,
      rationale: '',
      worlds: selected,
    );
    IntroduceInstanceOperation operation(UnfinishedEntityForm value) =>
        entityDraftRequest(
              universe: Selector('World'),
              continuity: ContinuityId.generate(),
              form: value,
              previous: null,
            ).content.operations.single
            as IntroduceInstanceOperation;
    expect(() => operation(form(name: ' ')), throwsFormatException);
    final minimal = operation(form());
    expect(minimal.name.text, '人物');
    expect(minimal.classification, isNull);
    expect(minimal.worldAssociations, isEmpty);
    expect(minimal.name.validity, isA<UnspecifiedValidity>());
    expect(() => operation(form(selected: worlds)), throwsFormatException);
    final associated = operation(
      form(selected: worlds, role: 'shared setting'),
    );
    expect(associated.worldAssociations.map((a) => a.world), worlds);
    expect(
      associated.worldAssociations.every(
        (a) =>
            a.role == 'shared setting' &&
            a.validity is UnspecifiedValidity &&
            a.qualifiers.isEmpty,
      ),
      isTrue,
    );
  });
  test('name details explicitly clear metadata and preserve identity and temporal values', () {
    final calendar = CalendarId.generate();
    final operation = IntroduceInstanceOperation(
      clientRef: 'person',
      name: const ContextualName(
        text: 'Mara',
        language: 'en',
        community: 'River',
        role: 'pseudonym',
        validity: UnknownValidity(),
      ),
      worldAssociations: [],
    );
    final draft = SavedDraft(
      version: BigInt.one,
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: RecordId.generate(),
        operations: [operation],
        rationale: 'Name details',
      ),
    );
    final initial = entityFormFromDraft(draft, 0);
    final details = EntityNameForm(
      language: '',
      community: null,
      role: '記憶 😀',
      temporalValidity: TemporalValidityInput(
        kind: 'instant',
        calendar: calendar.value,
        start: const TemporalBoundInput(value: 'Day 42.000000000000000001'),
      ),
    );
    final form = UnfinishedEntityForm(
      baseRevision: initial.baseRevision,
      representedContext: initial.representedContext,
      clientRef: initial.clientRef,
      name: initial.name,
      classification: '',
      worldRole: '',
      rationale: '',
      draftVersion: initial.draftVersion,
      nameDetails: EntityNameForm.fromWire(details.toWire()),
    );
    final changed =
        replaceDraftEntity(draft: draft, index: 0, form: form).operations.single
            as IntroduceInstanceOperation;
    expect(changed.clientRef, operation.clientRef);
    expect(changed.name.language, '');
    expect(changed.name.community, isNull);
    expect(changed.name.role, '記憶 😀');
    expect(
      changed.name.validity,
      InstantValidity(ExactTime(calendar, 'Day 42.000000000000000001')),
    );
  });
  test('entity name/classification edits retain authored metadata and associations', () {
    final original = IntroduceInstanceOperation(
      clientRef: 'writer-person',
      name: const ContextualName(
        text: 'Mara',
        language: 'en',
        community: 'River',
        role: 'pseudonym',
        validity: ConditionalValidity(),
      ),
      classification: RecordId.generate(),
      worldAssociations: [
        WorldAssociation(
          world: WorldId.generate(),
          role: 'home',
          validity: const UnknownValidity(),
          qualifiers: {'account': const TextValue('Firsthand')},
        ),
        WorldAssociation(
          world: WorldId.generate(),
          role: 'shared setting',
          validity: const UnspecifiedValidity(),
          qualifiers: {},
        ),
      ],
    );
    final draft = SavedDraft(
      version: BigInt.two,
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: RecordId.generate(),
        operations: [
          CreateWorldOperation(
            clientRef: 'setting',
            record: WorldRecord(selector: 'River'),
          ),
          original,
        ],
        rationale: 'Authored details',
      ),
    );
    final initial = entityFormFromDraft(draft, 1);
    final form = UnfinishedEntityForm(
      baseRevision: initial.baseRevision,
      representedContext: initial.representedContext,
      clientRef: initial.clientRef,
      name: 'Mara revised',
      classification: '',
      worldRole: '',
      rationale: '',
      draftVersion: initial.draftVersion,
    );
    final edited = replaceDraftEntity(draft: draft, index: 1, form: form);
    final operation = edited.operations[1] as IntroduceInstanceOperation;
    expect(operation.name.text, form.name);
    expect(operation.classification, isNull);
    expect(operation.clientRef, original.clientRef);
    expect(operation.name.language, original.name.language);
    expect(operation.name.community, original.name.community);
    expect(operation.name.role, original.name.role);
    expect(
      operation.name.validity.toWire().toText(),
      original.name.validity.toWire().toText(),
    );
    expect(
      operation.worldAssociations.map((a) => a.toWire().toText()),
      original.worldAssociations.map((a) => a.toWire().toText()),
    );
    expect(
      edited.operations.first.toWire().toText(),
      draft.content.operations.first.toWire().toText(),
    );
    expect(edited.rationale, draft.content.rationale);
    expect(
      () => replaceDraftEntity(
        draft: SavedDraft(version: BigInt.from(3), content: draft.content),
        index: 1,
        form: form,
      ),
      throwsFormatException,
    );
  });
  test('association edits retain row-specific details while addition and removal are explicit', () {
    final world = WorldId.generate(), other = WorldId.generate();
    final original = IntroduceInstanceOperation(
      clientRef: 'shared-person',
      name: const ContextualName(text: 'Mara', validity: UnspecifiedValidity()),
      worldAssociations: [
        WorldAssociation(
          world: world,
          role: 'home',
          validity: const ConditionalValidity(),
          qualifiers: {'account': const TextValue('Firsthand')},
        ),
        WorldAssociation(
          world: world,
          role: 'journey',
          validity: const UnknownValidity(),
          qualifiers: {},
        ),
      ],
    );
    final draft = SavedDraft(
      version: BigInt.two,
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: RecordId.generate(),
        operations: [original],
        rationale: 'Associations are not location.',
      ),
    );
    final initial = entityFormFromDraft(draft, 0);
    expect(initial.associations!.map((a) => a.originalOrdinal), [0, 1]);
    UnfinishedEntityForm form(List<EntityAssociationForm> rows) =>
        UnfinishedEntityForm(
          baseRevision: initial.baseRevision,
          representedContext: initial.representedContext,
          clientRef: initial.clientRef,
          name: initial.name,
          classification: initial.classification,
          worldRole: '',
          rationale: '',
          draftVersion: initial.draftVersion,
          associations: rows,
        );
    final updated = replaceDraftEntity(
      draft: draft,
      index: 0,
      form: form([
        EntityAssociationForm(
          world: other.value,
          role: 'past home',
          originalOrdinal: 0,
        ),
        EntityAssociationForm(world: world.value, role: 'setting'),
      ]),
    );
    final result = (updated.operations.single as IntroduceInstanceOperation)
        .worldAssociations;
    expect(result.map((a) => a.world), [other, world]);
    expect(result.map((a) => a.role), ['past home', 'setting']);
    expect(
      result.first.validity.toWire().toText(),
      original.worldAssociations.first.validity.toWire().toText(),
    );
    expect(
      result.first.qualifiers['account'],
      original.worldAssociations.first.qualifiers['account'],
    );
    expect(result.last.validity, isA<UnspecifiedValidity>());
    expect(result.last.qualifiers, isEmpty);
    for (final validity in <Validity>[
      const UnspecifiedValidity(),
      const UnknownValidity(),
      const ConditionalValidity(),
    ]) {
      final explicit = replaceDraftEntity(
        draft: draft,
        index: 0,
        form: form([
          EntityAssociationForm(
            world: world.value,
            role: 'home',
            originalOrdinal: 0,
            validity: validity,
          ),
        ]),
      );
      final row = (explicit.operations.single as IntroduceInstanceOperation)
          .worldAssociations
          .single;
      expect(row.validity, validity);
      expect(
        row.qualifiers['account'],
        original.worldAssociations.first.qualifiers['account'],
      );
    }
    expect(
      (replaceDraftEntity(
                draft: draft,
                index: 0,
                form: form([]),
              ).operations.single
              as IntroduceInstanceOperation)
          .worldAssociations,
      isEmpty,
    );
    expect(
      () => replaceDraftEntity(
        draft: draft,
        index: 0,
        form: form([EntityAssociationForm(world: world.value, role: '')]),
      ),
      throwsFormatException,
    );
    expect(
      () => replaceDraftEntity(
        draft: draft,
        index: 0,
        form: form([
          EntityAssociationForm(
            world: world.value,
            role: 'home',
            originalOrdinal: 2,
          ),
        ]),
      ),
      throwsFormatException,
    );
  });
  test('entity input recovers after disconnect and publishes once with other Changes intact', () async {
    final root = Directory('/tmp').createTempSync('ub-entity-workflow-');
    final store = SqliteInstallationStore.create(root.path);
    final instance = store.instanceId,
        author = InstallationAuthority(store).initializeAuthor();
    store.close();
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
        author.value,
        '--engine=/nonexistent/universe-engine',
      ]);
      session = await device.connect();
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            realWorld: false,
            name: 'Entity history',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final scope = EditorFormScope(
        instance: instance,
        profile: author,
        universe: UniverseId.parse(created.string('universe_id')),
        continuity: ContinuityId.parse(created.string('continuity_id')),
        representedContext: RecordId.parse(created.string('context_id')),
      );
      final form = UnfinishedEntityForm(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        clientRef: 'writer-person',
        name: '人物 😀',
        nameDetails: const EntityNameForm(
          language: 'en',
          community: '記憶 😀',
          role: '',
          validity: UnknownValidity(),
        ),
        classification: '',
        worldRole: '',
        rationale: 'Introduce a person.',
      );
      final prior = SavedDraft.fromWire(
        await session.call(
          SaveDraftEngineRequest(
            universe: Selector('Entity history'),
            continuityId: scope.continuity,
            expectedVersion: BigInt.zero,
            content: DraftContent(
              baseRevision: form.baseRevision,
              representedContext: form.representedContext,
              operations: [
                CreateWorldOperation(
                  clientRef: 'setting',
                  record: WorldRecord(selector: 'River'),
                ),
              ],
              rationale: 'Create the setting.',
            ),
          ),
        ),
      );
      await session.close();
      await session.saveEntityForm(scope, form, BigInt.zero);
      session = await device.connect();
      final recovered = (await session.loadEntityForm(scope))!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      final saved = SavedDraft.fromWire(
        await session.call(
          entityDraftRequest(
            universe: Selector('Entity history'),
            continuity: scope.continuity,
            form: recovered,
            previous: prior,
          ),
        ),
      );
      expect(saved.content.operations.length, 2);
      expect(
        saved.content.operations.first.toWire().toText(),
        prior.content.operations.single.toWire().toText(),
      );
      expect(
        saved.content.rationale,
        'Create the setting.\n\nIntroduce a person.',
      );
      expect(
        entityDraftRequest(
          universe: Selector('Entity history'),
          continuity: scope.continuity,
          form: recovered,
          previous: saved,
        ).content.toWire().toText(),
        saved.content.toWire().toText(),
      );
      final editScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        entityClientRef: 'writer-person',
      );
      final initial = entityFormFromDraft(saved, 1);
      final edit = UnfinishedEntityForm(
        baseRevision: initial.baseRevision,
        representedContext: initial.representedContext,
        clientRef: initial.clientRef,
        name: '人物 revised',
        classification: '',
        worldRole: '',
        rationale: '',
        draftVersion: initial.draftVersion,
      );
      await session.close();
      await session.saveEntityForm(editScope, edit, BigInt.zero);
      session = await device.connect();
      expect(
        (await session.loadEntityForm(scope))!.form.toWire().toText(),
        recovered.toWire().toText(),
      );
      final pending = (await session.loadEntityForm(editScope))!.form;
      final currentChanges = SavedChanges(
        session: session,
        universe: Selector('Entity history'),
        scope: scope,
      );
      final updated = await currentChanges.saveContent(
        saved,
        replaceDraftEntity(draft: saved, index: 1, form: pending),
      );
      expect(
        (updated.content.operations[1] as IntroduceInstanceOperation).clientRef,
        'writer-person',
      );
      final proposal = await currentChanges.submit(updated);
      final entity = proposal.compiledChanges
          .map((c) => c.next?.payload)
          .whereType<EntityRecord>()
          .single;
      expect(entity.names.single.text, edit.name);
      expect(entity.names.single.language, 'en');
      expect(entity.names.single.community, '記憶 😀');
      expect(entity.names.single.role, '');
      expect(entity.names.single.validity, const UnknownValidity());
      expect(
        entity.classificationResolution,
        ClassificationResolution.unclassified,
      );
      expect(entity.classification, isNull);
      expect(entity.worldAssociations, isEmpty);
      final validation =
          await currentChanges.validate(proposal) as EvaluatedValidation;
      await currentChanges.approve(proposal, validation);
      final receipt = await currentChanges.publish(
        proposal,
        validation.execution.runId,
      );
      expect(
        (await currentChanges.readPublished(proposal, receipt))
            .map((r) => r.payload)
            .whereType<EntityRecord>()
            .single
            .names
            .single
            .text,
        edit.name,
      );
      expect(
        (await currentChanges.publish(
          proposal,
          validation.execution.runId,
        )).revision,
        receipt.revision,
      );
      final worldRecord = proposal.compiledChanges
          .map((c) => c.next)
          .whereType<RecordVersion>()
          .singleWhere((r) => r.payload is WorldRecord);
      final world = WorldId.parse(
        'wld_${worldRecord.identity.recordId.value.substring(RecordId.prefix.length)}',
      );
      final fresh = await currentChanges.rebase(
        (await currentChanges.load())!,
        startNew: true,
      );
      final newEntity = SavedDraft.fromWire(
        await session.call(
          entityDraftRequest(
            universe: Selector('Entity history'),
            continuity: scope.continuity,
            form: UnfinishedEntityForm(
              baseRevision: fresh.content.baseRevision,
              representedContext: fresh.content.representedContext,
              clientRef: 'associated-person',
              name: 'Mara',
              classification: '',
              worldRole: '',
              rationale: '',
            ),
            previous: fresh,
          ),
        ),
      );
      final fields = entityFormFromDraft(newEntity, 0);
      final associated = await currentChanges.saveContent(
        newEntity,
        replaceDraftEntity(
          draft: newEntity,
          index: 0,
          form: UnfinishedEntityForm(
            baseRevision: fields.baseRevision,
            representedContext: fields.representedContext,
            clientRef: fields.clientRef,
            name: fields.name,
            classification: '',
            worldRole: '',
            rationale: '',
            draftVersion: fields.draftVersion,
            associations: [
              EntityAssociationForm(
                world: world.value,
                role: 'home',
                qualifiers: [
                  QualifierInput(key: 'account', value: '記憶 😀'),
                  QualifierInput(
                    key: 'space',
                    kind: 'spatial_coordinates',
                    value: 'authored grid',
                    children: [
                      QualifierInput(
                        kind: 'decimal',
                        value: '1.000000000000000001',
                      ),
                    ],
                  ),
                  QualifierInput(
                    key: 'time',
                    kind: 'temporal',
                    temporal: TemporalValidityInput(
                      kind: 'instant_unspecified',
                    ),
                  ),
                  QualifierInput(
                    key: 'range',
                    kind: 'range',
                    lower: QualifierInput(kind: 'integer', value: '001'),
                    upper: QualifierInput(kind: 'integer', value: '003'),
                    lowerInclusive: 'false',
                    upperInclusive: 'true',
                  ),
                  QualifierInput(
                    key: 'list',
                    kind: 'sequence',
                    children: [
                      QualifierInput(kind: 'text', value: 'first 😀'),
                      QualifierInput(
                        kind: 'set',
                        children: [
                          QualifierInput(
                            kind: 'decimal',
                            value: '1.000000000000000001',
                          ),
                          QualifierInput(kind: 'boolean', value: 'false'),
                        ],
                      ),
                    ],
                  ),
                  QualifierInput(
                    key: 'setting',
                    kind: 'record_ref',
                    value: worldRecord.identity.recordId.value,
                    universe: scope.universe.value,
                  ),
                  QualifierInput(
                    key: 'confirmed',
                    kind: 'boolean',
                    value: 'false',
                  ),
                ],
                temporalValidity: const TemporalValidityInput(
                  start: TemporalBoundInput(
                    kind: 'approximate',
                    value: '2040-01-01',
                    uncertaintyKind: 'typed',
                    amount: QualifierInput(
                      kind: 'sequence',
                      children: [
                        QualifierInput(kind: 'text', value: 'about a week'),
                        QualifierInput(kind: 'boolean', value: 'false'),
                      ],
                    ),
                  ),
                  end: TemporalBoundInput(kind: 'unbounded'),
                ),
              ),
            ],
          ),
        ),
      );
      await expectLater(
        currentChanges.submit(associated),
        throwsA(
          isA<InvalidArgumentError>().having(
            (e) => e.field,
            'field',
            'rationale',
          ),
        ),
      );
      final ready = await currentChanges.saveRationale(
        associated,
        'Associate Mara with River.',
      );
      final associatedProposal = await currentChanges.submit(ready);
      final associatedValidation = await currentChanges.validate(
        associatedProposal,
      ) as EvaluatedValidation;
      await currentChanges.approve(associatedProposal, associatedValidation);
      final associatedReceipt = await currentChanges.publish(
        associatedProposal,
        associatedValidation.execution.runId,
      );
      final published = (await currentChanges.readPublished(
        associatedProposal,
        associatedReceipt,
      )).map((r) => r.payload).whereType<EntityRecord>().single;
      expect(published.worldAssociations.single.world, world);
      expect(published.worldAssociations.single.role, 'home');
      expect(
        published.worldAssociations.single.qualifiers['account'],
        const TextValue('記憶 😀'),
      );
      expect(
        published.worldAssociations.single.qualifiers['setting'],
        ReferenceValue(
          ValueReferenceKind.parse('record_ref'),
          RecordRef(
            universe: scope.universe,
            record: worldRecord.identity.recordId,
          ),
        ),
      );
      expect(
        published.worldAssociations.single.qualifiers['list'],
        SequenceValue([
          const TextValue('first 😀'),
          SetValue([
            const DecimalValue('1.000000000000000001'),
            const BooleanValue(false),
          ]),
        ]),
      );
      expect(
        published.worldAssociations.single.qualifiers['range'],
        const RangeValue(
          lower: IntegerValue('001'),
          upper: IntegerValue('003'),
          lowerInclusive: false,
          upperInclusive: true,
        ),
      );
      expect(
        published.worldAssociations.single.qualifiers['time'],
        const TemporalValue(UnspecifiedTime()),
      );
      expect(
        published.worldAssociations.single.qualifiers['space'],
        SpatialValue(
          SpatialCoordinates('authored grid', [
            const DecimalValue('1.000000000000000001'),
          ]),
        ),
      );
      expect(
        published.worldAssociations.single.qualifiers['confirmed'],
        const BooleanValue(false),
      );
      expect(
        published.worldAssociations.single.validity,
        IntervalValidity(
          ApproximateBound(
            '2040-01-01',
            SequenceValue([
              const TextValue('about a week'),
              const BooleanValue(false),
            ]),
          ),
          UnboundedBound(),
        ),
      );
    } finally {
      try {
        await session?.close();
      } finally {
        try {
          await server.close();
        } finally {
          root.deleteSync(recursive: true);
        }
      }
    }
  });
}
