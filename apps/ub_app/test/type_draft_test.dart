@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/type_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

void main() {
  test('type completion requires explicit choices and retains unresolved or empty applicability', () {
    final revision = RevisionId.generate(), context = RecordId.generate();
    final continuity = ContinuityId.generate();
    UnfinishedTypeForm form({
      String parent = '',
      String applicability = '',
      bool? executable,
    }) => UnfinishedTypeForm(
      baseRevision: revision,
      representedContext: context,
      clientRef: 'person',
      namespace: 'authored',
      key: 'person',
      name: '人物',
      parentChoice: parent,
      applicabilityChoice: applicability,
      classificationExecutable: executable,
      rationale: '',
    );
    SaveDraftEngineRequest request(UnfinishedTypeForm value) =>
        typeDraftRequest(
          universe: Selector('World'),
          continuity: continuity,
          form: value,
          previous: null,
        );
    expect(() => request(form()), throwsFormatException);
    expect(() => request(form(parent: 'none')), throwsFormatException);
    expect(
      () => request(form(parent: 'none', applicability: 'universe_wide')),
      throwsFormatException,
    );
    final unresolved =
        request(
              form(
                parent: 'none',
                applicability: 'unspecified',
                executable: false,
              ),
            ).content.operations.single
            as IntroduceDefinitionOperation;
    expect(unresolved.parent, isNull);
    expect(unresolved.applicability, isA<UnspecifiedApplicability>());
    expect(unresolved.classificationExecutable, isFalse);
    final nowhere =
        request(form(parent: 'none', applicability: 'worlds', executable: true))
                .content
                .operations
                .single
            as IntroduceDefinitionOperation;
    expect((nowhere.applicability as WorldsApplicability).worldIds, isEmpty);
  });

  test('recovered type input appends to other Changes and publishes exact definition semantics', () async {
    final root = Directory('/tmp').createTempSync('ub-type-workflow-');
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
            name: 'Type history',
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
      final form = UnfinishedTypeForm(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        clientRef: 'writer-person',
        namespace: 'authored',
        key: 'person',
        name: '人物',
        parentChoice: 'none',
        applicabilityChoice: 'universe_wide',
        classificationExecutable: true,
        rationale: 'Declare the person type.',
      );
      final existing = SavedDraft.fromWire(
        await session.call(
          SaveDraftEngineRequest(
            universe: Selector('Type history'),
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
      // Incomplete/pending input remains writable when the service link closes.
      await session.saveTypeForm(scope, form, BigInt.zero);
      session = await device.connect();
      final recovered = (await session.loadTypeForm(scope))!.form;
      final request = typeDraftRequest(
        universe: Selector('Type history'),
        continuity: scope.continuity,
        form: recovered,
        previous: existing,
      );
      final saved = SavedDraft.fromWire(await session.call(request));
      expect(saved.content.operations.length, 2);
      expect(
        saved.content.operations.first.toWire().toText(),
        existing.content.operations.single.toWire().toText(),
      );
      expect(
        saved.content.rationale,
        'Create the setting.\n\nDeclare the person type.',
      );
      expect(
        typeDraftRequest(
          universe: Selector('Type history'),
          continuity: scope.continuity,
          form: recovered,
          previous: saved,
        ).content.toWire().toText(),
        saved.content.toWire().toText(),
      );
      final changes = SavedChanges(
        session: session,
        universe: Selector('Type history'),
        scope: scope,
      );
      final proposal = await changes.submit(saved);
      final definition = proposal.compiledChanges
          .map((change) => change.next?.payload)
          .whereType<EntityTypeRecord>()
          .single;
      expect(definition.namespace, 'authored');
      expect(definition.key, 'person');
      expect(definition.name, '人物');
      expect(definition.parent, isNull);
      expect(definition.parentResolution, ParentResolution.root);
      expect(definition.applicability, isA<UniverseApplicability>());
      expect(definition.classificationExecutable, isTrue);
      final validation =
          await changes.validate(proposal) as EvaluatedValidation;
      await changes.approve(proposal, validation);
      final receipt = await changes.publish(
        proposal,
        validation.execution.runId,
      );
      expect(
        (await changes.readPublished(proposal, receipt))
            .map((record) => record.payload)
            .whereType<EntityTypeRecord>()
            .single
            .name,
        '人物',
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
