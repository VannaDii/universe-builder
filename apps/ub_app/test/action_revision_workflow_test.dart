@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/action_draft.dart';
import 'package:ub_app/property_draft.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';

void main() {
  test('action revision recovers and publishes exact declarations with retained history and story clock', () async {
    final root = Directory('/tmp')
        .createTempSync('ub-action-revision-workflow-');
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
            realWorld: false,
            name: 'Actions',
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
        universe: Selector('Actions'),
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

      final initial = SavedDraft(
        version: BigInt.zero,
        content: DraftContent(
          baseRevision: RevisionId.parse(created.string('revision')),
          representedContext: scope.representedContext!,
          operations: [],
          rationale: 'Declare the journey resource.',
        ),
      );
      final propertyForm = UnfinishedPropertyForm(
        baseRevision: initial.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        namespace: 'authored',
        key: 'energy',
        shape: ValueShapeInput(kind: 'integer'),
        multiplicity: 'single',
        persistence: 'unspecified',
        rationale: 'Declare energy.',
      );
      final propertyDraft = SavedDraft.fromWire(
        await session.call(
          propertyDraftRequest(
            draft: initial,
            form: propertyForm,
            universe: const Selector('Actions'),
            continuity: scope.continuity,
          ),
        ),
      );
      final property = (await publish(propertyDraft)).single;
      var next = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final predicate = RecordRef(
        record: property.identity.recordId,
        universe: scope.universe,
      );
      final record = ActionDefinitionRecord(
        namespace: 'authored',
        key: 'journey',
        labels: {'en': 'Journey 記憶 😀'},
        requirements: [
          AttributeRequirement(
            'traveler',
            predicate,
            IntegerValue('9007199254740993'),
          ),
        ],
        scope: Scope(
          context: RecordRef(
            record: scope.representedContext!,
            universe: scope.universe,
          ),
          applicability: const UniverseApplicability(),
        ),
        validity: const UnspecifiedValidity(),
        consequenceContract: ConsequenceContract([
          EffectSlot(
            slot: 'set',
            order: 0,
            presence: EffectPresence.required,
            target: EffectTarget('traveler', predicate),
            condition: const AlwaysEffect(),
            change: SetEffect(
              Polarity.support,
              IntegerValue('9007199254740994'),
            ),
            lifetime: TicksEffect(ConsequenceInteger('9007199254740995')),
          ),
          EffectSlot(
            slot: 'delta',
            order: 1,
            presence: EffectPresence.optional,
            target: EffectTarget('witness', predicate),
            condition: AttributeEqualsEffect(
              'traveler',
              predicate,
              IntegerValue('9007199254740993'),
            ),
            change: DeltaEffect(
              unit: null,
              delta: ConsequenceDecimal('-1'),
              minimum: ConsequenceDecimal('0'),
              maximum: ConsequenceDecimal('9007199254740999'),
            ),
            lifetime: const UntilChangedEffect(),
          ),
        ]),
      );
      final sourceDraft = await changes().saveContent(
        next,
        DraftContent(
          baseRevision: next.content.baseRevision,
          representedContext: scope.representedContext!,
          operations: [
            DefineActionOperation(
              clientRef: RecordId.generate().value,
              record: record,
            ),
          ],
          rationale: 'Declare a journey without executing it.',
        ),
      );
      final published = (await publish(sourceDraft)).single;
      next = await changes().rebase((await changes().load())!, startNew: true);
      final beforeContext = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Actions'),
        context: await openDraftChoiceContext(changes(), next),
        record: scope.representedContext!,
      );
      final revisionBase = next;
      final revisionScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: published.identity.recordId.value,
      );
      final sourceForm = actionRevisionFormFromRecord(
        record: published,
        baseRevision: next.content.baseRevision,
        representedContext: scope.representedContext!,
      );
      final revisionForm = UnfinishedActionForm.fromWire(
        CanonicalObject(
          sourceForm.toWire().fields.map(
            (e) => e.key == 'slots'
                ? MapEntry(
                    'slots',
                    CanonicalArray(
                      sourceForm.slots!.reversed.map((slot) => slot.toWire()),
                    ),
                  )
                : e.key == 'rationale'
                ? MapEntry(
                    'rationale',
                    CanonicalString('Reorder the declared consequence slots.'),
                  )
                : e,
          ),
        ),
      );
      await session.saveActionForm(revisionScope, revisionForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recovered = (await session.loadActionForm(revisionScope))!.form;
      expect(recovered.toWire().toText(), revisionForm.toWire().toText());
      final revisionDraft = SavedDraft.fromWire(
        await session.call(
          actionDraftRequest(
            draft: revisionBase,
            form: recovered,
            universe: const Selector('Actions'),
            continuity: scope.continuity,
          ),
        ),
      );
      final revised = (await publish(revisionDraft)).single;
      expect(revised.identity.recordId, published.identity.recordId);
      expect(
        revised.payload.toWire().toText(),
        actionRevisionOperation(revisionForm).replacement.toWire().toText(),
      );
      final retained = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Actions'),
        context: await openDraftChoiceContext(changes(), revisionBase),
        record: published.identity.recordId,
      );
      expect(retained.toWire().toText(), published.toWire().toText());
      next = await changes().rebase((await changes().load())!, startNew: true);
      final afterContext = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Actions'),
        context: await openDraftChoiceContext(changes(), next),
        record: scope.representedContext!,
      );
      expect(afterContext.toWire().toText(), beforeContext.toWire().toText());
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
