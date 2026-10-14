@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/appearance_draft.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/image_preview.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

void main() {
  test('selected images stage, create and revise exact timed appearances through reviewed publication', () async {
    final root = Directory('/tmp').createTempSync('ub-appearance-workflow-');
    final catalog = SqliteInstallationStore.create(root.path);
    final instance = catalog.instanceId;
    final profile = InstallationAuthority(catalog).initializeAuthor();
    catalog.close();
    final original = base64.decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwHwQBEPgD/U6VwW8AAAAASUVORK5CYII=',
    );
    final source = File('${root.path}/Portrait é.png')
      ..writeAsBytesSync(original);
    String? selectedPath;
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
      ], pickImagePath: () async => selectedPath);
      session = await device.connect();
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            name: 'Appearances',
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
        universe: const Selector('Appearances'),
        scope: scope,
      );
      Future<List<RecordVersion>> publish(SavedDraft draft) async {
        final Proposal proposal;
        try {
          proposal = await changes().submit(draft);
        } on ProtocolError catch (error) {
          fail('Appearance proposal failed: ${error.toWire().toText()}');
        }
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
          rationale: '',
        ),
      );
      final before = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Appearances'),
        context: await openDraftChoiceContext(changes(), initial),
        record: scope.representedContext!,
      );
      expect(await session.pickImage!(const Selector('Appearances')), isNull);
      selectedPath = source.path;
      final staged = (await session.pickImage!(const Selector('Appearances')))!;
      expect(staged.asset.originalName, 'Portrait é.png');
      expect(staged.asset.mediaType, 'image/png');
      expect(staged.asset.width, 2);
      expect(staged.asset.height, 1);
      expect(staged.previewBytes, isNotEmpty);
      expect(
        StagedImage.fromWire(staged.toWire()).toWire().toText(),
        staged.toWire().toText(),
      );
      expect(source.readAsBytesSync(), orderedEquals(original));
      final chronology =
          (before.payload as RepresentedContextRecord).chronology!;
      final form = UnfinishedAppearanceForm(
        baseRevision: initial.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        targetKind: 'entry',
        target: ExpressionReferenceInput(
          record: scope.representedContext!.value,
          universe: scope.universe.value,
        ),
        label: 'Before the reveal',
        physicalDescription: 'Green robes 記憶\r\n',
        atmosphere: 'Quiet',
        images: [
          AppearanceImageInput.staged(
            staged,
            scope.universe,
          ).copyWith(caption: 'Exact portrait 😀', purpose: 'appearance'),
        ],
        links: [
          AppearanceLinkInput(
            entry: ExpressionReferenceInput(
              record: scope.representedContext!.value,
              universe: scope.universe.value,
            ),
            relationship: 'complements',
            note: 'Mood only',
          ),
        ],
        validityKind: 'calendar_interval',
        calendar: chronology.calendar.value,
        start: (BigInt.parse(chronology.current) - BigInt.one).toString(),
        end: (BigInt.parse(chronology.current) + BigInt.one).toString(),
        rationale: 'Record an authored phase.',
      );
      expect(
        UnfinishedAppearanceForm.fromWire(form.toWire()).toWire().toText(),
        form.toWire().toText(),
      );
      expect(
        () => appearanceOperation(form.copyWith(targetKind: '')),
        throwsFormatException,
      );
      expect(
        () => appearanceOperation(
          form.copyWith(images: [form.images.single.copyWith(purpose: '')]),
        ),
        throwsFormatException,
      );
      final draft = SavedDraft.fromWire(
        await session.call(
          appearanceDraftRequest(
            draft: initial,
            form: form,
            universe: const Selector('Appearances'),
            continuity: scope.continuity,
          ),
        ),
      );
      expect(draft.content.operations, hasLength(2));
      expect(
        appearanceDraftRequest(
          draft: draft,
          form: form,
          universe: const Selector('Appearances'),
          continuity: scope.continuity,
        ).content.toWire().toText(),
        draft.content.toWire().toText(),
      );
      final pending = appearanceFormFromDraft(draft, 1);
      expect(
        () => appearanceDraftRequest(
          draft: SavedDraft(
            version: draft.version + BigInt.one,
            content: draft.content,
          ),
          form: pending,
          universe: const Selector('Appearances'),
          continuity: scope.continuity,
          index: 1,
        ),
        throwsFormatException,
      );
      final publishedRows = await publish(draft);
      final published = publishedRows.singleWhere(
        (row) => row.payload is AppearanceRecord,
      );
      expect(
        published.payload.toWire().toText(),
        (appearanceOperation(form) as CreateAppearanceOperation).record
            .toWire()
            .toText(),
      );
      var next = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final preview = await readImagePreview(
        session: session,
        universe: LibraryEntry(scope.universe, 'Appearances'),
        context: await openDraftChoiceContext(changes(), next),
        reference: RecordRef(universe: scope.universe, record: staged.assetId),
      );
      expect(preview.asset.toWire().toText(), staged.asset.toWire().toText());
      expect(preview.bytes, orderedEquals(staged.previewBytes));
      final detail = File('${root.path}/Detail.png')
        ..writeAsBytesSync(original);
      selectedPath = detail.path;
      final stagedDetail = (await session.pickImage!(
        const Selector('Appearances'),
      ))!;
      final revisionSource = appearanceFormFromRecord(
        record: published,
        baseRevision: next.content.baseRevision,
        representedContext: scope.representedContext!,
      );
      expect(
        (appearanceOperation(
          revisionSource.copyWith(validityKind: 'calendar_interval'),
        ) as ReviseAppearanceOperation).replacement.validity.toWire().toText(),
        (published.payload as AppearanceRecord).validity.toWire().toText(),
      );
      final revision = revisionSource.copyWith(
        rationale: 'Record the authored costume change.',
        physicalDescription: 'Silver robes 記憶\r\n',
        images: [
          revisionSource.images.single.copyWith(
            caption: 'Prior portrait retained',
          ),
          AppearanceImageInput.staged(
            stagedDetail,
            scope.universe,
          ).copyWith(caption: 'New detail', purpose: 'detail'),
        ],
      );
      final revisedDraft = SavedDraft.fromWire(
        await session.call(
          appearanceDraftRequest(
            draft: next,
            form: revision,
            universe: const Selector('Appearances'),
            continuity: scope.continuity,
          ),
        ),
      );
      final revised = (await publish(revisedDraft))
          .singleWhere((row) => row.payload is AppearanceRecord);
      expect(revised.identity.recordId, published.identity.recordId);
      expect(
        revised.payload.toWire().toText(),
        (appearanceOperation(revision) as ReviseAppearanceOperation).replacement
            .toWire()
            .toText(),
      );
      final retained = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Appearances'),
        context: await openDraftChoiceContext(changes(), next),
        record: published.identity.recordId,
      );
      expect(retained.toWire().toText(), published.toWire().toText());
      next = await changes().rebase((await changes().load())!, startNew: true);
      final after = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Appearances'),
        context: await openDraftChoiceContext(changes(), next),
        record: scope.representedContext!,
      );
      expect(after.toWire().toText(), before.toWire().toText());
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
