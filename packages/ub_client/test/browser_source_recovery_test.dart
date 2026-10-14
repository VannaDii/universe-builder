@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_source_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser source recovery preserves text, staged anchors, exact offsets and source-versus-draft slots', () async {
    final name = 'ub-source-test-${OperationId.generate().value}';
    var store = await BrowserSourceFormRecoveryStore.open(databaseName: name);
    final universe = UniverseId.generate(), context = RecordId.generate();
    final instance = OperationId.generate(),
        profile = ProfileId.generate(),
        continuity = ContinuityId.generate();
    final source = VersionRef(
      universe: universe,
      record: RecordId.generate(),
      version: RecordVersionId.generate(),
    );
    EditorFormScope scope(String? editor) => EditorFormScope(
      instance: instance,
      profile: profile,
      universe: universe,
      continuity: continuity,
      representedContext: context,
      typeClientRef: editor,
    );
    final offset = BigInt.parse('9007199254740993');
    DomainOperation anchor(String ref, String excerpt) =>
        AddSourceAnchorOperation(
          clientRef: ref,
          record: AnchorRecord(
            sourceVersion: source,
            locator: ByteRangeLocator(offset, offset + BigInt.from(8)),
            excerptDigest: 'a' * 64,
            excerpt: excerpt,
            context: RecordRef(universe: universe, record: context),
          ),
        );
    final input = UnfinishedSourceForm(
      baseRevision: RevisionId.generate(),
      representedContext: context,
      clientRef: 'anchor-a',
      label: 'Mémoire 😀',
      text: 'é😀\r\ne\u0301\n',
      rationale: '',
      anchorSource: source,
      draftVersion: BigInt.parse('9007199254740993'),
      staged: [
        anchor('anchor-a', 'different excerpt'),
        anchor('anchor-b', 'other'),
        anchor('anchor-a', 'é😀\r\n'),
      ],
    );
    UnfinishedSourceForm form({
      List<DomainOperation>? operations,
      BigInt? draftVersion,
      String? text,
    }) => UnfinishedSourceForm(
      baseRevision: input.baseRevision,
      representedContext: context,
      clientRef: input.clientRef,
      label: input.label,
      text: text ?? input.text,
      rationale: input.rationale,
      anchorSource: source,
      draftVersion: draftVersion,
      staged: operations ?? input.staged,
    );
    try {
      await store.save(scope(input.clientRef), input, BigInt.zero);
      store.close();
      store = await BrowserSourceFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope(input.clientRef)))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(
          scope(input.clientRef),
          input,
          BigInt.zero,
        )).generation,
        BigInt.one,
      );
      final reversed = form(
        operations: input.staged.reversed.toList(),
        draftVersion: input.draftVersion,
        text: 'Changed text',
      );
      await expectLater(
        store.save(scope(input.clientRef), reversed, BigInt.zero),
        throwsA(
          isA<EditorRecoveryException>().having(
            (error) => error.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        (await store.load(scope(input.clientRef)))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      await store.save(scope(input.clientRef), reversed, BigInt.one);
      expect(
        (await store.load(scope(input.clientRef)))!.form.toWire().toText(),
        reversed.toWire().toText(),
      );
      final unstaged = form(operations: [], draftVersion: input.draftVersion);
      await store.save(scope(input.clientRef), unstaged, BigInt.two);
      expect(
        (await store.load(scope(input.clientRef)))!.form.toWire().toText(),
        unstaged.toWire().toText(),
      );
      final sourceInput = form();
      expect(await store.load(scope(source.version.value)), isNull);
      await store.save(scope(source.version.value), sourceInput, BigInt.zero);
      expect(
        (await store.load(scope(source.version.value)))!.form.toWire().toText(),
        sourceInput.toWire().toText(),
      );
      await expectLater(
        store.save(scope(source.version.value), input, BigInt.one),
        throwsFormatException,
      );
      await expectLater(
        store.save(scope(input.clientRef), sourceInput, BigInt.from(3)),
        throwsFormatException,
      );
      await expectLater(
        store.save(
          scope(input.clientRef),
          form(draftVersion: input.draftVersion, text: '\uD800'),
          BigInt.from(3),
        ),
        throwsA(
          isA<EditorRecoveryException>().having(
            (error) => error.failure,
            'failure',
            EditorRecoveryFailure.invalidText,
          ),
        ),
      );
      expect(
        (await store.load(scope(input.clientRef)))!.form.toWire().toText(),
        unstaged.toWire().toText(),
      );
    } finally {
      store.close();
      final deleted = Completer<void>();
      final request = web.window.indexedDB.deleteDatabase(name);
      request.onsuccess = ((web.Event _) => deleted.complete()).toJS;
      request.onerror = ((web.Event _) => deleted.completeError(
        StateError('Test cleanup failed'),
      )).toJS;
      await deleted.future;
    }
  });
}
