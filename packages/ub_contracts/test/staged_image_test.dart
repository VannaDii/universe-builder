import 'dart:convert';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final id = RecordId.generate();
  final asset = ImageAssetRecord(
    contentDigest: 'a' * 64,
    mediaType: 'image/png',
    byteSize: BigInt.from(75),
    width: 2,
    height: 1,
    originalName: 'Portrait é.png',
  );
  final operation = AddImageAssetOperation(clientRef: id.value, record: asset);
  CanonicalObject response({
    String? assetId,
    String preview = 'data:image/jpeg;base64,AQID',
    bool canonical = false,
    List<DomainOperation>? operations,
    ImageAssetRecord? metadata,
  }) => CanonicalObject([
    MapEntry('canonical', CanonicalBool(canonical)),
    MapEntry('asset_id', CanonicalString(assetId ?? id.value)),
    MapEntry('preview', CanonicalString(preview)),
    MapEntry(
      'metadata',
      CanonicalObject(
        (metadata ?? asset).toWire().fields.where(
          (field) => field.key != 'record_kind',
        ),
      ),
    ),
    MapEntry(
      'operations',
      CanonicalArray((operations ?? [operation]).map((op) => op.toWire())),
    ),
  ]);
  test('staged image decoder binds exact metadata, operation and bounded preview', () {
    final staged = StagedImage.fromWire(response());
    expect(staged.assetId, id);
    expect(staged.previewBytes, [1, 2, 3]);
    expect(staged.toWire().toText(), response().toText());
    expect(
      () => StagedImage.fromWire(response(assetId: RecordId.generate().value)),
      throwsFormatException,
    );
    expect(
      () => StagedImage.fromWire(response(canonical: true)),
      throwsFormatException,
    );
    expect(
      () => StagedImage.fromWire(response(operations: [])),
      throwsFormatException,
    );
    expect(
      () => StagedImage.fromWire(response(operations: [operation, operation])),
      throwsFormatException,
    );
    expect(
      () => StagedImage.fromWire(
        response(
          metadata: ImageAssetRecord(
            contentDigest: asset.contentDigest,
            mediaType: asset.mediaType,
            byteSize: asset.byteSize,
            width: 3,
            height: asset.height,
            originalName: asset.originalName,
          ),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () =>
          StagedImage.fromWire(response(preview: 'data:image/png;base64,AQID')),
      throwsFormatException,
    );
    expect(
      () => decodeImagePreviewBytes('data:image/jpeg;base64,'),
      throwsFormatException,
    );
    expect(
      () => decodeImagePreviewBytes(
        'data:image/jpeg;base64,${base64.encode(List.filled(512 * 1024 + 1, 0))}',
      ),
      throwsFormatException,
    );
  });
  test('unfinished appearance keeps incomplete ordered images and links without filling choices', () {
    final form = UnfinishedAppearanceForm(
      baseRevision: RevisionId.generate(),
      representedContext: RecordId.generate(),
      clientRef: RecordId.generate().value,
      images: [
        const AppearanceImageInput(caption: 'Unselected 記憶\r\n'),
        AppearanceImageInput.staged(
          StagedImage.fromWire(response()),
          UniverseId.generate(),
        ),
        const AppearanceImageInput(caption: 'Unselected 記憶\r\n'),
      ],
      links: [
        const AppearanceLinkInput(note: 'Partial'),
        const AppearanceLinkInput(note: 'Partial'),
      ],
      start: 'incomplete-bound',
      draftVersion: BigInt.parse('18446744073709551615'),
    );
    final decoded = UnfinishedAppearanceForm.fromWire(form.toWire());
    expect(decoded.toWire().toText(), form.toWire().toText());
    expect(decoded.targetKind, isEmpty);
    expect(decoded.images.first.purpose, isEmpty);
    expect(decoded.images[1].stagedOperation!.clientRef, id.value);
    expect(
      decoded.images[1]
          .copyWith(asset: const ExpressionReferenceInput(record: 'different'))
          .stagedOperation,
      isNull,
    );
    expect(decoded.startUnbounded, isFalse);
  });
}
