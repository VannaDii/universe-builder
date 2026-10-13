import 'package:test/test.dart';
import 'package:ub_app/world_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test(
    'published-world rename retains its version, other work and exact retry',
    () {
      final universeId = UniverseId.generate(),
          continuity = ContinuityId.generate();
      final form = UnfinishedWorldForm(
        baseRevision: RevisionId.generate(),
        representedContext: RecordId.generate(),
        record: RecordId.generate(),
        expectedRecordVersion: RecordVersionId.generate(),
        selector: ' River delta ',
        settingType: '',
        rationale: 'Keep the earlier name.',
      );
      final other = CreateWorldOperation(
        clientRef: 'other',
        record: WorldRecord(selector: 'Mountain'),
      );
      final before = SavedDraft(
        version: BigInt.from(7),
        content: DraftContent(
          baseRevision: form.baseRevision,
          representedContext: form.representedContext,
          operations: [other],
          rationale: 'Existing rationale',
        ),
      );
      SaveDraftEngineRequest rename(SavedDraft? previous) =>
          renameWorldDraftRequest(
            universe: Selector('History'),
            universeId: universeId,
            continuity: continuity,
            form: form,
            previous: previous,
          );
      final request = rename(before);
      final operation =
          request.content.operations.last as RenameWorldSelectorOperation;
      expect(
        operation.record,
        RecordRef(universe: universeId, record: form.record),
      );
      expect(operation.expectedVersion, form.expectedRecordVersion);
      expect(operation.newSelector, ' River delta ');
      expect(request.expectedVersion, before.version);
      expect(
        request.content.operations.first.toWire().toText(),
        other.toWire().toText(),
      );
      expect(
        request.content.rationale,
        'Existing rationale\n\nKeep the earlier name.',
      );
      final saved = SavedDraft(
        version: BigInt.from(8),
        content: request.content,
      );
      expect(
        rename(saved).content.toWire().toText(),
        saved.content.toWire().toText(),
      );
      expect(
        () => rename(
          SavedDraft(
            version: BigInt.one,
            content: DraftContent(
              baseRevision: RevisionId.generate(),
              representedContext: form.representedContext,
              operations: [],
              rationale: '',
            ),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'published-world alias retains its version, other work and exact retry',
    () {
      final universeId = UniverseId.generate(),
          continuity = ContinuityId.generate();
      final form = UnfinishedWorldForm(
        baseRevision: RevisionId.generate(),
        representedContext: RecordId.generate(),
        record: RecordId.generate(),
        expectedRecordVersion: RecordVersionId.generate(),
        selector: ' River delta ',
        settingType: '',
        rationale: 'Keep the earlier name.',
      );
      final other = CreateWorldOperation(
        clientRef: 'other',
        record: WorldRecord(selector: 'Mountain'),
      );
      final before = SavedDraft(
        version: BigInt.from(7),
        content: DraftContent(
          baseRevision: form.baseRevision,
          representedContext: form.representedContext,
          operations: [other],
          rationale: 'Existing rationale',
        ),
      );
      SaveDraftEngineRequest alias(SavedDraft? previous) =>
          worldAliasDraftRequest(
            universe: Selector('History'),
            universeId: universeId,
            continuity: continuity,
            form: form,
            previous: previous,
          );
      final request = alias(before);
      final operation =
          request.content.operations.last as AddWorldAliasOperation;
      expect(
        operation.record,
        RecordRef(universe: universeId, record: form.record),
      );
      expect(operation.expectedVersion, form.expectedRecordVersion);
      expect(operation.alias, ' River delta ');
      expect(request.expectedVersion, before.version);
      expect(
        request.content.operations.first.toWire().toText(),
        other.toWire().toText(),
      );
      expect(
        request.content.rationale,
        'Existing rationale\n\nKeep the earlier name.',
      );
      final saved = SavedDraft(
        version: BigInt.from(8),
        content: request.content,
      );
      expect(
        alias(saved).content.toWire().toText(),
        saved.content.toWire().toText(),
      );
      expect(
        () => alias(
          SavedDraft(
            version: BigInt.one,
            content: DraftContent(
              baseRevision: RevisionId.generate(),
              representedContext: form.representedContext,
              operations: [],
              rationale: '',
            ),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'world field edits preserve external references and unexposed details',
    () {
      final world = CreateWorldOperation(
        clientRef: 'writer/world:river',
        record: WorldRecord(
          selector: 'River',
          aliases: ['Old river', '古河'],
          settingType: '',
          labels: {'en': '', 'fr': 'Rivière'},
          metadata: {'source note': const TextValue('Keep\r\nexact')},
        ),
      );
      final other = CreateWorldOperation(
        clientRef: 'mountain',
        record: WorldRecord(selector: 'Mountain'),
      );
      final draft = DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: RecordId.generate(),
        operations: [other, world],
        rationale: 'Keep this rationale',
      );
      DraftContent edit(String name, String type, String label) =>
          editWorldDraftFields(
            draft: draft,
            index: 1,
            selector: name,
            settingType: type,
            englishLabel: label,
          );
      expect(edit('River', '', '').toWire().toText(), draft.toWire().toText());
      final changed = edit(' River delta ', 'Historical', 'River delta');
      final operation = changed.operations.last as CreateWorldOperation;
      expect(operation.clientRef, world.clientRef);
      expect(operation.record.selector, ' River delta ');
      expect(operation.record.aliases, world.record.aliases);
      expect(operation.record.labels, {'en': 'River delta', 'fr': 'Rivière'});
      expect(
        operation.record.metadata['source note']!.toWire().toText(),
        world.record.metadata['source note']!.toWire().toText(),
      );
      expect(
        changed.operations.first.toWire().toText(),
        other.toWire().toText(),
      );
      expect(changed.baseRevision, draft.baseRevision);
      expect(changed.representedContext, draft.representedContext);
      expect(changed.rationale, draft.rationale);
      expect(world.record.selector, 'River');
      expect(() => edit(' \n ', '', ''), throwsFormatException);
    },
  );

  test('completed worlds preserve exact fields and existing changes', () {
    final revision = RevisionId.generate();
    final context = RecordId.generate();
    final continuity = ContinuityId.generate();
    UnfinishedWorldForm form(String name, {RecordId? record}) =>
        UnfinishedWorldForm(
          baseRevision: revision,
          representedContext: context,
          record: record ?? RecordId.generate(),
          selector: name,
          settingType: 'Historical',
          rationale: 'Research pending',
          aliases: ['Old name'],
          labels: {'en': '', 'fr': 'Un monde'},
        );
    SaveDraftEngineRequest request(
      UnfinishedWorldForm value, [
      SavedDraft? previous,
    ]) => worldDraftRequest(
      universe: Selector('History'),
      continuity: continuity,
      form: value,
      previous: previous,
    );
    expect(() => request(form('  ')), throwsFormatException);
    final first = request(form(' River '));
    final old = SavedDraft(version: BigInt.one, content: first.content);
    final next = form('Mountain');
    final appended = request(next, old);
    expect(appended.expectedVersion, BigInt.one);
    expect(appended.content.operations, hasLength(2));
    expect(
      appended.content.operations.first.toWire().toText(),
      first.content.operations.single.toWire().toText(),
    );
    final world =
        (appended.content.operations.last as CreateWorldOperation).record;
    expect(world.labels, {'fr': 'Un monde'});
    expect(world.aliases, ['Old name']);
    expect(
      (first.content.operations.single as CreateWorldOperation).record.selector,
      ' River ',
    );
    final saved = SavedDraft(version: BigInt.two, content: appended.content);
    expect(
      request(next, saved).content.toWire().toText(),
      saved.content.toWire().toText(),
    );
    expect(
      () => request(form('Changed', record: next.record), saved),
      throwsFormatException,
    );
    final other = SavedDraft(
      version: BigInt.one,
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        operations: [],
        rationale: '',
      ),
    );
    expect(() => request(next, other), throwsFormatException);
  });
}
