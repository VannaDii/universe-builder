@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('appearance recovery preserves partial fields, repeated ordered images and staging across reopen', () {
    final root = Directory('/tmp').createTempSync('ub-appearance-forms-');
    final path = '${root.path}/forms.sqlite';
    var store = AppearanceFormRecoveryStore.open(path);
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
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      store.close();
      store = AppearanceFormRecoveryStore.open(path);
      expect(store.load(scope)!.form.toWire().toText(), form.toWire().toText());
      final reordered = form.copyWith(images: form.images.reversed);
      store.save(scope, reordered, BigInt.one);
      expect(
        store.load(scope)!.form.toWire().toText(),
        reordered.toWire().toText(),
      );
      expect(
        () => store.save(scope, form, BigInt.one),
        throwsA(isA<EditorRecoveryException>()),
      );
      final other = EditorFormScope(
        instance: scope.instance,
        profile: ProfileId.generate(),
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
      );
      expect(store.load(other), isNull);
      final removed = form.copyWith(images: [], links: []);
      store.save(scope, removed, BigInt.two);
      expect(store.load(scope)!.form.images, isEmpty);
      expect(store.load(scope)!.form.links, isEmpty);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
