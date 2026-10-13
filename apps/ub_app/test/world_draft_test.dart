import 'package:test/test.dart';
import 'package:ub_app/world_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
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
