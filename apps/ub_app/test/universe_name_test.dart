@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart' hide Description;
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/universe_name.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('rename retains aliases, private unfinished input and a publishable draft across restart', () async {
    final root = Directory('/tmp').createTempSync('ub-universe-name-');
    final device = DeviceConnection([
      '--installation',
      root.path,
    ], embeddedLocal: true);
    AppSession? session;
    try {
      session = await device.connect();
      final status = InstanceLibrary.fromWire(
        await session.call(const StatusEngineRequest()),
      );
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            name: 'Café campaign',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      await session.call(
        const CreateUniverseEngineRequest(
          name: 'Reserved',
          start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
        ),
      );
      final original = LibraryEntry(
        UniverseId.parse(created.string('universe_id')),
        created.string('name'),
      );
      final scope = EditorFormScope(
        instance: status.instance,
        profile: session.principal,
        universe: original.id,
        continuity: ContinuityId.parse(created.string('continuity_id')),
        representedContext: RecordId.parse(created.string('context_id')),
      );
      SavedChanges changes(String name) => SavedChanges(
        session: session!,
        universe: Selector(name),
        scope: scope,
      );
      final content = DraftContent(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        operations: [
          CreateWorldOperation(
            clientRef: RecordId.generate().value,
            record: WorldRecord(selector: 'Authored world'),
          ),
        ],
        rationale: 'Retain these changes.',
      );
      final draft = await changes(original.name).saveContent(
        SavedDraft(version: BigInt.zero, content: content),
        content,
      );
      final unfinished = UnfinishedSourceForm(
        baseRevision: content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'pending passage',
        label: 'Opening',
        text: '\ufeffExact recollection.\r\n記憶 😀\u0000',
      );
      final saved = await session.saveSourceForm(
        scope,
        unfinished,
        BigInt.zero,
      );
      const newName = 'Memoir 記憶 😀';
      final renamed = await renameUniverse(session, original, newName);
      expect(renamed.id, original.id);
      expect(renamed.name, newName);
      expect((await renameUniverse(session, original, newName)).name, newName);
      expect(
        (await changes(original.name).load())!.toWire().toText(),
        draft.toWire().toText(),
      );
      final alias = Envelope<Description>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(universe: Selector(original.name)),
          ),
        ),
        Description.fromWire,
      );
      expect(alias.universeId, original.id);
      expect(alias.aliasMatched, isTrue);
      await expectLater(
        renameUniverse(session, renamed, 'RESERVED'),
        throwsA(isA<ProtocolError>()),
      );
      expect(
        InstanceLibrary.fromWire(
          await session.call(const StatusEngineRequest()),
        ).universes.singleWhere((row) => row.id == original.id).name,
        newName,
      );
      final enrolled = WireFields(
        await session.call(const EnrollEngineRequest()),
        {'profile_id'},
      );
      final reader = ProfileId.parse(enrolled.string('profile_id'));
      await session.call(
        GrantEngineRequest(
          grant: GrantSpec(
            profileId: reader,
            universeId: original.id,
            propose: false,
            edit: false,
            protected: false,
          ),
        ),
      );
      await session.close();
      session = await DeviceConnection([
        '--installation',
        root.path,
        '--profile',
        reader.value,
      ], embeddedLocal: true).connect();
      await expectLater(
        renameUniverse(session, renamed, 'Unauthorized name'),
        throwsA(isA<ProtocolError>()),
      );
      await session.close();
      session = await device.connect();
      final recovered = await session.loadSourceForm(scope);
      expect(recovered!.generation, saved.generation);
      expect(recovered.form.toWire().toText(), unfinished.toWire().toText());
      expect(
        (await changes(newName).load())!.toWire().toText(),
        draft.toWire().toText(),
      );
      final proposal = await changes(newName)
          .submit((await changes(newName).load())!);
      final validation =
          await changes(newName).validate(proposal) as EvaluatedValidation;
      await changes(newName).approve(proposal, validation);
      final receipt = await changes(newName)
          .publish(proposal, validation.execution.runId);
      final published = await changes(original.name)
          .readPublished(proposal, receipt);
      expect(
        (published.single.payload as WorldRecord).selector,
        'Authored world',
      );
    } on ProtocolError catch (error) {
      fail(error.toWire().toText());
    } finally {
      await session?.close();
      root.deleteSync(recursive: true);
    }
  });
}
