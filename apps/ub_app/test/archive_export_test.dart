@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart' hide Description;
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/local_backup_files.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/world_browser.dart';
import 'package:ub_client/browser_engine.dart';
import 'package:ub_client/loopback_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/sqlite.dart';

void main() {
  test('native and browser selected archives retain dependencies and omit private workflow', () async {
    final root = Directory('/tmp').createTempSync('ub-selected-export-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    // Initialize the profile before starting its HTTP service.
    AppSession? session = await DeviceConnection([
      '--installation',
      root.path,
    ], embeddedLocal: true).connect();
    final created = WireFields(
      await session.call(
        const CreateUniverseEngineRequest(
          name: 'Export 記憶 😀',
          start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
        ),
      ),
      {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
    );
    final universe = LibraryEntry(
      UniverseId.parse(created.string('universe_id')),
      created.string('name'),
    );
    final status = InstanceLibrary.fromWire(
      await session.call(const StatusEngineRequest()),
    );
    final scope = EditorFormScope(
      instance: status.instance,
      profile: session.principal,
      universe: universe.id,
      continuity: ContinuityId.parse(created.string('continuity_id')),
      representedContext: RecordId.parse(created.string('context_id')),
    );
    final changes = SavedChanges(
      session: session,
      universe: Selector(universe.name),
      scope: scope,
    );
    Future<List<RecordVersion>> publish(SavedDraft draft) async {
      final proposal = await changes.submit(draft);
      final validation =
          await changes.validate(proposal) as EvaluatedValidation;
      await changes.approve(proposal, validation);
      return changes.readPublished(
        proposal,
        await changes.publish(proposal, validation.execution.runId),
      );
    }

    var draft = SavedDraft(
      version: BigInt.zero,
      content: DraftContent(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        operations: [],
        rationale: 'Export fixture',
      ),
    );
    draft = await changes.saveContent(
      draft,
      DraftContent(
        baseRevision: draft.content.baseRevision,
        representedContext: scope.representedContext!,
        operations: [
          CreateWorldOperation(
            clientRef: RecordId.generate().value,
            record: WorldRecord(selector: 'Required setting'),
          ),
          CreateWorldOperation(
            clientRef: RecordId.generate().value,
            record: WorldRecord(selector: 'Omitted setting'),
          ),
        ],
        rationale: 'Create settings',
      ),
    );
    final worlds = await publish(draft);
    final world = worlds.singleWhere(
      (r) => (r.payload as WorldRecord).selector == 'Required setting',
    );
    draft = await changes.rebase((await changes.load())!, startNew: true);
    draft = await changes.saveContent(
      draft,
      DraftContent(
        baseRevision: draft.content.baseRevision,
        representedContext: scope.representedContext!,
        operations: [
          CreateWorkOperation(
            clientRef: RecordId.generate().value,
            record: WorkRecord(
              kind: WorkKind.novel,
              title: 'Selected chronicle',
              labels: {},
              sourceRefs: [],
              versions: [],
              worldAssociations: [
                WorldAssociation(
                  world: WorldId.parse(
                    world.identity.recordId.value.replaceFirst('rec_', 'wld_'),
                  ),
                  role: 'Setting',
                  validity: const UnknownValidity(),
                  qualifiers: {},
                ),
              ],
            ),
          ),
        ],
        rationale: 'Associate the work with its setting',
      ),
    );
    final work = (await publish(draft)).single;
    await session.close();
    session = null;
    final server = await LocalSqliteEngineServer.start(
      root.path,
      compatibilitySocket: false,
    );
    LoopbackEngineClient? native;
    BrowserEngineClient? browser;
    final http = HttpClient();
    try {
      session = await DeviceConnection([
        '--installation',
        root.path,
        '--profile',
        scope.profile.value,
        '--engine=/nonexistent',
      ]).connect();
      native = await LoopbackEngineClient.connect(
        endpoint: server.httpEndpoint,
        hello: EngineHello(
          protocolVersion: protocolVersion,
          profileId: session.principal,
          credential: Credential(
            ProfileCredentialStore.read(
              root: root.path,
              profile: session.principal,
            ),
          ),
          clientName: 'Archive export regression',
        ),
      );
      Future<void> checkArchive(
        String path,
        CanonicalObject manifest, {
        required bool filtered,
      }) async {
        final fields = Map.fromEntries(manifest.fields);
        expect((fields['includes_workflow'] as CanonicalBool).value, false);
        expect((fields['complete'] as CanonicalBool).value, !filtered);
        if (filtered) {
          expect(
            BigInt.parse(fields['omitted_records']!.toText()),
            greaterThan(BigInt.zero),
          );
        }
        final archive = OwnedSqliteDatabase.stageLogicalArchive(
          path,
          root.path,
        );
        try {
          expect(archive.manifest.toText(), manifest.toText());
        } finally {
          archive.close();
        }
        final name = 'Clone ${filtered ? "selection" : "canon"}';
        final review = Map.fromEntries(
          (await session!.call(
            PreviewImportEngineRequest(
              source: path,
              name: name,
              mode: ImportMode.clone,
            ),
          ) as CanonicalObject).fields,
        );
        final admitted = Map.fromEntries(
          (await session!.call(
            AcceptImportEngineRequest(
              previewId: OperationId.parse(wireString(review['preview_id']!)),
              digest: wireString(review['digest']!),
            ),
          ) as CanonicalObject).fields,
        );
        final description = Envelope<Description>.fromWire(
          await session!.call(
            ToolEngineRequest(
              request: DescribeSummaryRequest(universe: Selector(name)),
            ),
          ),
          Description.fromWire,
        ).result;
        final continuity = description.continuities.single;
        final opened = await openAuthorReadContext(
          session!,
          LibraryEntry(
            UniverseId.parse(wireString(admitted['universe_id']!)),
            name,
          ),
          continuity,
          continuity.representedContexts.single,
        );
        final described = Envelope<Description>.fromWire(
          await session!.call(
            ToolEngineRequest(
              request: DescribeWorldsRequest(
                universe: Selector(name),
                contextId: opened.contextId,
              ),
            ),
          ),
          Description.fromWire,
        ).result;
        expect(
          described.worlds.map((w) => w.name.value),
          filtered
              ? ['Required setting']
              : containsAll(['Required setting', 'Omitted setting']),
        );
      }

      final files = LocalBackupFiles(
        root: root.path,
        call: session.call,
        saveFile: (source) async {
          final destination = '${root.path}/selected.sqlite';
          await File(source).copy(destination);
          return destination;
        },
        openFile: (_) async => false,
        downloadArchive:
            (
              entry,
              destination, {
              required recordIds,
              required completeHistory,
            }) => native!.downloadArchive(
              universe: Selector(entry.name),
              destination: destination,
              recordIds: recordIds,
              completeHistory: completeHistory,
            ),
      );
      final exported = await files.exportArchive(
        universe,
        recordIds: [work.identity.recordId],
        completeHistory: false,
      );
      expect(exported.message, contains('Import it as a named clone'));
      await checkArchive(
        exported.savedPath!,
        exported.manifest,
        filtered: true,
      );
      expect(Directory('${root.path}/client-files').listSync(), isEmpty);
      final cancelled = LocalBackupFiles(
        root: root.path,
        call: session.call,
        saveFile: (_) async => null,
        openFile: (_) async => false,
      );
      expect(
        (await cancelled.exportArchive(
          universe,
          recordIds: [],
          completeHistory: false,
        )).message,
        contains('cancelled'),
      );
      expect(Directory('${root.path}/client-files').listSync(), isEmpty);
      Cookie? cookie;
      final grant = Map.fromEntries(
        (await native.createBrowserSession()).fields,
      );
      browser = await BrowserEngineClient.connect(
        enrollmentToken: wireString(grant['enrollment_token']!),
        abort: () {},
        post: (path, bytes, csrf) async {
          final request = await http.postUrl(server.httpEndpoint.resolve(path));
          request.headers.contentType = ContentType.json;
          request.headers.set('origin', server.httpEndpoint.origin);
          if (cookie != null) request.cookies.add(cookie!);
          if (csrf != null) request.headers.set('x-ub-csrf', csrf);
          request.add(bytes);
          final response = await request.close();
          if (response.cookies.isNotEmpty) cookie = response.cookies.first;
          final output = BytesBuilder();
          await for (final part in response) {
            output.add(part);
          }
          return BrowserEngineResponse(
            status: response.statusCode,
            bytes: output.takeBytes(),
          );
        },
      );
      final prepared = await browser.prepareArchiveDownload(
        Selector(universe.name),
        recordIds: [work.identity.recordId],
        completeHistory: false,
      );
      expect(
        (Map.fromEntries(prepared.manifest.fields)['complete'] as CanonicalBool)
            .value,
        false,
      );
      final request = await http.getUrl(
        server.httpEndpoint.resolve(prepared.path),
      );
      request.cookies.add(cookie!);
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      final browserFile = File('${root.path}/browser.sqlite');
      protectedFile(browserFile.path, createNew: true);
      await response.pipe(browserFile.openWrite());
      final archive = OwnedSqliteDatabase.stageLogicalArchive(
        browserFile.path,
        root.path,
      );
      try {
        expect(archive.digest, prepared.digest);
        expect(archive.manifest.toText(), exported.manifest.toText());
      } finally {
        archive.close();
      }
      final canonPath = '${root.path}/canon.sqlite';
      final canon = await native.downloadArchive(
        universe: Selector(universe.name),
        destination: canonPath,
        completeHistory: false,
      );
      await checkArchive(canonPath, canon, filtered: false);
      final complete = await native.downloadArchive(
        universe: Selector(universe.name),
        destination: '${root.path}/complete.sqlite',
      );
      expect(
        (Map.fromEntries(complete.fields)['includes_workflow'] as CanonicalBool)
            .value,
        true,
      );
    } finally {
      await browser?.close();
      http.close(force: true);
      await native?.close();
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
