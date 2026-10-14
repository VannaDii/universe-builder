@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_app/source_anchor.dart';
import 'package:ub_app/source_draft.dart';

void main() {
  test(
    'source anchor edits retain identity and refuse a different draft version',
    () {
      final context = RecordId.generate();
      final source = VersionRef(
        record: RecordId.generate(),
        version: RecordVersionId.generate(),
      );
      AnchorRecord excerpt(String value) => sourceExcerptMatch(
        text: 'first second',
        excerpt: value,
        source: source,
        context: RecordRef(record: context),
      ).selected!;
      final draft = SavedDraft(
        version: BigInt.from(4),
        content: DraftContent(
          baseRevision: RevisionId.generate(),
          representedContext: context,
          operations: [
            AddSourceAnchorOperation(
              clientRef: 'anchor',
              record: excerpt('first'),
            ),
          ],
          rationale: 'Existing author decision.',
        ),
      );
      final before = sourceAnchorFormFromDraft(draft, 0);
      final edited = UnfinishedSourceForm(
        baseRevision: before.baseRevision,
        representedContext: context,
        clientRef: before.clientRef,
        text: 'second',
        anchorSource: source,
        draftVersion: before.draftVersion,
        staged: [
          AddSourceAnchorOperation(
            clientRef: 'anchor',
            record: excerpt('second'),
          ),
        ],
      );
      final recovered = UnfinishedSourceForm.fromWire(edited.toWire());
      final request = sourceDraftRequest(
        draft: draft,
        form: recovered,
        universe: const Selector('World'),
        continuity: ContinuityId.generate(),
        index: 0,
      );
      final result =
          request.content.operations.single as AddSourceAnchorOperation;
      expect(result.clientRef, 'anchor');
      expect(result.record.excerpt, 'second');
      expect(result.record.sourceVersion, source);
      expect(request.content.rationale, draft.content.rationale);
      expect(
        () => sourceDraftRequest(
          draft: SavedDraft(version: BigInt.from(5), content: draft.content),
          form: recovered,
          universe: const Selector('World'),
          continuity: ContinuityId.generate(),
          index: 0,
        ),
        throwsFormatException,
      );
    },
  );
  test('repeated excerpts require an explicit occurrence and retain UTF-8 positions', () {
    final source = VersionRef(
      record: RecordId.generate(),
      version: RecordVersionId.generate(),
    );
    final context = RecordRef(record: RecordId.generate());
    const text = '\uFEFFé 😀\r\n記憶 😀\r\n';
    final ambiguous = sourceExcerptMatch(
      text: text,
      excerpt: '😀',
      source: source,
      context: context,
    );
    expect(ambiguous.count, 2);
    expect(ambiguous.selected, isNull);
    final second = sourceExcerptMatch(
      text: text,
      excerpt: '😀',
      source: source,
      context: context,
      occurrence: 2,
    );
    expect(second.selected!.excerpt, '😀');
    final range = second.selected!.locator as ByteRangeLocator;
    expect(range.start, BigInt.from(19));
    expect(range.end, BigInt.from(23));
    expect(second.selected!.sourceVersion, source);
    expect(
      sourceExcerptMatch(
        text: text,
        excerpt: 'missing',
        source: source,
        context: context,
      ).count,
      0,
    );
    expect(
      sourceExcerptMatch(
        text: text,
        excerpt: '😀',
        source: source,
        context: context,
        occurrence: 3,
      ).selected,
      isNull,
    );
    expect(
      sourceExcerptMatch(
        text: 'aaa',
        excerpt: 'aa',
        source: source,
        context: context,
      ).count,
      2,
    );
  });
  test(
    'unfinished source text recovers exactly and competing saves stay explicit',
    () {
      final root = Directory.systemTemp.createTempSync('ub-source-form-');
      final path = '${root.path}/source.sqlite';
      final scope = EditorFormScope(
        instance: OperationId.generate(),
        profile: ProfileId.generate(),
        universe: UniverseId.generate(),
        continuity: ContinuityId.generate(),
        representedContext: RecordId.generate(),
      );
      final form = UnfinishedSourceForm(
        baseRevision: RevisionId.generate(),
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        label: 'Journal 記憶 😀',
        text: '\uFEFFAé😀\r\nZ',
        rationale: 'A recollection.',
      );
      var store = SourceFormRecoveryStore.open(path);
      try {
        final saved = store.save(scope, form, BigInt.zero);
        store.close();
        store = SourceFormRecoveryStore.open(path);
        expect(
          store.load(scope)!.form.toWire().toText(),
          form.toWire().toText(),
        );
        expect(
          store.save(scope, form, BigInt.zero).generation,
          saved.generation,
        );
        final changed = UnfinishedSourceForm(
          baseRevision: form.baseRevision,
          representedContext: form.representedContext,
          clientRef: form.clientRef,
          text: 'different',
        );
        expect(
          () => store.save(scope, changed, BigInt.zero),
          throwsA(isA<EditorRecoveryException>()),
        );
        expect(store.load(scope)!.form.text, form.text);
      } finally {
        store.close();
        root.deleteSync(recursive: true);
      }
    },
  );
}
