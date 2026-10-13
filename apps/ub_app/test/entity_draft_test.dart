@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/entity_draft.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

void main() {
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
      final changes = SavedChanges(
        session: session,
        universe: Selector('Entity history'),
        scope: scope,
      );
      final proposal = await changes.submit(saved);
      final entity = proposal.compiledChanges
          .map((c) => c.next?.payload)
          .whereType<EntityRecord>()
          .single;
      expect(entity.names.single.text, form.name);
      expect(
        entity.classificationResolution,
        ClassificationResolution.unclassified,
      );
      expect(entity.classification, isNull);
      expect(entity.worldAssociations, isEmpty);
      final validation =
          await changes.validate(proposal) as EvaluatedValidation;
      await changes.approve(proposal, validation);
      final receipt = await changes.publish(
        proposal,
        validation.execution.runId,
      );
      expect(
        (await changes.readPublished(proposal, receipt))
            .map((r) => r.payload)
            .whereType<EntityRecord>()
            .single
            .names
            .single
            .text,
        form.name,
      );
      expect(
        (await changes.publish(proposal, validation.execution.runId)).revision,
        receipt.revision,
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
