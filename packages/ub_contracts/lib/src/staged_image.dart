import 'dart:convert';
import 'dart:typed_data';

import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';

/// An original retained by the service, still outside canon. The operation is
/// added to an authored proposal; staging never submits or publishes it.
final class StagedImage {
  StagedImage._({required this.operation, required this.preview});
  final AddImageAssetOperation operation;
  final String preview;
  RecordId get assetId => RecordId.parse(operation.clientRef);
  ImageAssetRecord get asset => operation.record;
  Uint8List get previewBytes => decodeImagePreviewBytes(preview);

  factory StagedImage.fromWire(CanonicalValue value) {
    final fields = WireFields(value, {
      'canonical',
      'asset_id',
      'metadata',
      'preview',
      'operations',
    });
    if (fields.boolean('canonical')) {
      throw const FormatException('Image staging must remain outside canon.');
    }
    final id = RecordId.parse(fields.string('asset_id'));
    final operations = fields
        .array('operations')
        .map(DomainOperation.fromWire)
        .toList();
    if (operations.length != 1 ||
        operations.single is! AddImageAssetOperation) {
      throw const FormatException('Image staging operation unavailable.');
    }
    final operation = operations.single as AddImageAssetOperation;
    final metadata = fields.require('metadata');
    if (metadata is! CanonicalObject || operation.clientRef != id.value) {
      throw const FormatException('Image staging metadata differs.');
    }
    final asset = ImageAssetRecord.fromWire(
      CanonicalObject([
        MapEntry(
          'record_kind',
          CanonicalString(RecordKind.imageAsset.wireName),
        ),
        ...metadata.fields,
      ]),
    );
    if (asset.toWire().toText() != operation.record.toWire().toText()) {
      throw const FormatException('Image staging metadata differs.');
    }
    final preview = fields.string('preview');
    decodeImagePreviewBytes(preview);
    return StagedImage._(operation: operation, preview: preview);
  }

  CanonicalObject toWire() => CanonicalObject([
    const MapEntry('canonical', CanonicalBool(false)),
    MapEntry('asset_id', CanonicalString(assetId.value)),
    MapEntry(
      'metadata',
      CanonicalObject(
        asset.toWire().fields.where((field) => field.key != 'record_kind'),
      ),
    ),
    MapEntry('preview', CanonicalString(preview)),
    MapEntry('operations', CanonicalArray([operation.toWire()])),
  ]);
}

/// Matches the existing service JPEG-preview limit. Original image content
/// remains on the service; clients only decode the bounded display preview.
Uint8List decodeImagePreviewBytes(String preview) {
  const prefix = 'data:image/jpeg;base64,';
  const maxBytes = 512 * 1024;
  if (!preview.startsWith(prefix) ||
      preview.length > prefix.length + ((maxBytes + 2) ~/ 3) * 4) {
    throw const FormatException('Unsupported image preview.');
  }
  final bytes = base64.decode(preview.substring(prefix.length));
  if (bytes.isEmpty || bytes.length > maxBytes) {
    throw const FormatException('Unsupported image preview.');
  }
  return bytes;
}
