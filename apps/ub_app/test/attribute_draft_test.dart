@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/attribute_draft.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

void main() {
  test('attribute values recover and publish with their exact definition and evidence', () async {
    final root = Directory('/tmp').createTempSync('ub-attribute-workflow-');
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
            name: 'Attributes',
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
        universe: Selector('Attributes'),
        scope: scope,
      );
      final initial = SavedDraft.fromWire(
        await session.call(
          SaveDraftEngineRequest(
            universe: Selector('Attributes'),
            continuityId: scope.continuity,
            expectedVersion: BigInt.zero,
            content: DraftContent(
              baseRevision: RevisionId.parse(created.string('revision')),
              representedContext: scope.representedContext!,
              operations: [
                IntroduceInstanceOperation(
                  clientRef: 'person',
                  name: const ContextualName(
                    text: 'Mara',
                    validity: UnspecifiedValidity(),
                  ),
                  worldAssociations: [],
                ),
              ],
              rationale: 'Introduce Mara.',
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
      final entity = (await changes().readPublished(proposal, receipt)).single;
      final fresh = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final evidence = AttributeEvidence(
        attributeMode: AttributeMode.instance,
        polarity: Polarity.support,
        scope: Scope(
          context: RecordRef(
            universe: scope.universe,
            record: scope.representedContext!,
          ),
          applicability: const UniverseApplicability(),
        ),
        validity: const UnknownValidity(),
        persistence: PersistenceSemantics.unspecified,
        precision: Precision.exact,
        alternatives: [
          SequenceValue([const TextValue('alternative')]),
        ],
        basis: const AuthorDecisionBasis('Authored continuity fact.'),
      );
      final operation = AddNamedAttributeOperation(
        clientRef: 'writer-attribute',
        subject: RecordRef(
          universe: scope.universe,
          record: entity.identity.recordId,
        ),
        namespace: 'authored',
        key: 'account',
        valueShape: const SequenceShape(SimpleValueShape(SimpleShapeKind.text)),
        subjectTypes: [],
        multiplicity: Multiplicity.multiple,
        value: SequenceValue([
          const TextValue('first'),
          const TextValue('second'),
        ]),
        evidence: evidence,
      );
      final saved = await changes().saveContent(
        fresh,
        DraftContent(
          baseRevision: fresh.content.baseRevision,
          representedContext: fresh.content.representedContext,
          operations: [
            operation,
            CreateWorldOperation(
              clientRef: 'world',
              record: WorldRecord(selector: 'River'),
            ),
          ],
          rationale: 'An attributed account.',
        ),
      );
      final formScope = EditorFormScope(
        instance: instance,
        profile: author,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        attributeClientRef: operation.clientRef,
      );
      final fields = attributeFormFromDraft(saved, 0);
      UnfinishedAttributeForm form(String text) => UnfinishedAttributeForm(
        baseRevision: fields.baseRevision,
        representedContext: fields.representedContext,
        clientRef: fields.clientRef,
        draftVersion: fields.draftVersion,
        value: QualifierInput(
          kind: 'sequence',
          children: [
            QualifierInput(kind: 'text', value: text),
            const QualifierInput(kind: 'retain', originalKey: '1'),
          ],
        ),
      );
      final entered = form('記憶 😀\naccount');
      await session.saveAttributeForm(formScope, entered, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recovered = (await session.loadAttributeForm(formScope))!;
      expect(recovered.form.toWire().toText(), entered.toWire().toText());
      expect(
        (await session.saveAttributeForm(
          formScope,
          entered,
          BigInt.zero,
        )).generation,
        BigInt.one,
      );
      await expectLater(
        session.saveAttributeForm(formScope, form('competing'), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
      final replacement = replaceDraftAttribute(
        draft: saved,
        index: 0,
        form: recovered.form,
      );
      final exact = replacement.operations.first as AddNamedAttributeOperation;
      expect(exact.clientRef, operation.clientRef);
      expect(exact.subject, operation.subject);
      expect(exact.valueShape, operation.valueShape);
      expect(exact.subjectTypes, operation.subjectTypes);
      expect(exact.evidence.toWire().toText(), evidence.toWire().toText());
      expect(
        replacement.operations.last.toWire().toText(),
        saved.content.operations.last.toWire().toText(),
      );
      expect(replacement.rationale, saved.content.rationale);
      final updated = await changes().saveContent(saved, replacement);
      expect(
        () => replaceDraftAttribute(
          draft: updated,
          index: 0,
          form: recovered.form,
        ),
        throwsFormatException,
      );
      final authored = await changes().submit(updated);
      final checked = await changes().validate(authored) as EvaluatedValidation;
      await changes().approve(authored, checked);
      final published = await changes().publish(
        authored,
        checked.execution.runId,
      );
      final result = await changes().readPublished(authored, published);
      final fact = result
          .map((r) => r.payload)
          .whereType<PropositionRecord>()
          .single;
      expect(fact.subject, operation.subject);
      expect(
        fact.value,
        SequenceValue([TextValue('記憶 😀\naccount'), const TextValue('second')]),
      );
      final assertion = result
          .map((r) => r.payload)
          .whereType<AssertionRecord>()
          .single;
      expect(
        assertion.basis.toWire().toText(),
        evidence.basis.toWire().toText(),
      );
      expect(assertion.validity, const UnknownValidity());
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
