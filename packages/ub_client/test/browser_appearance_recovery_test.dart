@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_appearance_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser appearance recovery preserves named fields and ordered staged image rows across reopen', () async {
    final name = 'ub-appearance-test-${OperationId.generate().value}';
    var store = await BrowserAppearanceFormRecoveryStore.open(
      databaseName: name,
    );
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final asset = RecordId.generate();
    final metadata = ImageAssetRecord(
      contentDigest: 'a' * 64,
      mediaType: 'image/png',
      byteSize: BigInt.from(75),
      width: 2,
      height: 1,
      originalName: 'Portrait é.png',
    );
    final image = AppearanceImageInput(
      asset: ExpressionReferenceInput(
        record: asset.value,
        universe: scope.universe.value,
      ),
      caption: 'Mémoire 😀\r\n',
      purpose: '',
      preview: 'data:image/jpeg;base64,AQID',
      stagedOperation: AddImageAssetOperation(
        clientRef: asset.value,
        record: metadata,
      ),
    );
    final form = UnfinishedAppearanceForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      target: const ExpressionReferenceInput(record: 'unfinished target 記憶'),
      images: [
        const AppearanceImageInput(caption: 'Partial'),
        image,
        image,
      ],
      links: [
        const AppearanceLinkInput(note: 'Partial link'),
        const AppearanceLinkInput(note: 'Partial link'),
      ],
      start: '-9007199254740993',
      physicalDescription: 'Exact text\r\n',
      draftVersion: BigInt.parse('18446744073709551615'),
    );
    try {
      expect(
        (await store.save(scope, form, BigInt.zero)).generation,
        BigInt.one,
      );
      expect(
        (await store.save(scope, form, BigInt.zero)).generation,
        BigInt.one,
      );
      store.close();
      store = await BrowserAppearanceFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        form.toWire().toText(),
      );
      final reordered = form.copyWith(images: form.images.reversed);
      await store.save(scope, reordered, BigInt.one);
      expect(
        (await store.load(scope))!.form.toWire().toText(),
        reordered.toWire().toText(),
      );
      await expectLater(
        store.save(scope, form, BigInt.one),
        throwsA(isA<EditorRecoveryException>()),
      );
      final other = EditorFormScope(
        instance: scope.instance,
        profile: ProfileId.generate(),
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
      );
      expect(await store.load(other), isNull);
      final removed = form.copyWith(images: [], links: []);
      await store.save(scope, removed, BigInt.two);
      expect((await store.load(scope))!.form.images, isEmpty);
      expect((await store.load(scope))!.form.links, isEmpty);
    } finally {
      store.close();
      final done = Completer<void>();
      final request = web.window.indexedDB.deleteDatabase(name);
      request.onsuccess = ((web.Event _) => done.complete()).toJS;
      request.onerror = ((web.Event _) => done.completeError(
        StateError('Cleanup failed'),
      )).toJS;
      await done.future;
    }
  });
}
