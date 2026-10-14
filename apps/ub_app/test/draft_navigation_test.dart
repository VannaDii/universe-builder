import 'package:test/test.dart';
import 'package:ub_app/draft_navigation.dart';
import 'package:ub_app/navigation_location.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test(
    'operation links refuse changed versions, contexts and missing positions',
    () {
      final context = RecordId.generate();
      final version = BigInt.parse('18446744073709551615');
      final operation = AddWorldAliasOperation(
        record: RecordRef(record: RecordId.generate()),
        expectedVersion: RecordVersionId.generate(),
        alias: 'Earlier name 記憶',
      );
      SavedDraft saved({
        BigInt? atVersion,
        RecordId? inContext,
        bool empty = false,
      }) => SavedDraft(
        version: atVersion ?? version,
        content: DraftContent(
          baseRevision: RevisionId.generate(),
          representedContext: inContext ?? context,
          operations: empty ? [] : [operation],
          rationale: '',
        ),
      );
      final location = LibraryLocation(
        universe: UniverseId.generate(),
        continuity: ContinuityId.generate(),
        context: context,
        draftVersion: version,
        operationIndex: 0,
      );
      final draft = saved();
      expect(draftForLocation(draft, location), same(draft));
      expect(
        () =>
            draftForLocation(saved(atVersion: version - BigInt.one), location),
        throwsFormatException,
      );
      expect(
        () => draftForLocation(saved(inContext: RecordId.generate()), location),
        throwsFormatException,
      );
      expect(
        () => draftForLocation(saved(empty: true), location),
        throwsFormatException,
      );
      expect(() => draftForLocation(null, location), throwsFormatException);
    },
  );
}
