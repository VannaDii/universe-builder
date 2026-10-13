import 'dart:convert';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'record_browser.dart';

Future<({ImageAssetRecord asset, Uint8List bytes})> readImagePreview({
  required AppSession session,
  required LibraryEntry universe,
  required OpenedContext context,
  required RecordRef reference,
}) async {
  if (reference.universe != null && reference.universe != universe.id) {
    throw const FormatException('Image outside this opened universe.');
  }
  // Read metadata through the same permission-filtered route as dossiers before
  // requesting bytes. The service rechecks the current authority on both calls.
  final row = await readContextRecord(
    session: session,
    universe: universe,
    context: context,
    record: reference.record,
  );
  if (row.identity.universeId != universe.id ||
      row.payload is! ImageAssetRecord) {
    throw const FormatException('Image asset unavailable.');
  }
  final asset = row.payload as ImageAssetRecord;
  final response = WireFields(
    await session.call(
      ImagePreviewEngineRequest(
        universe: Selector(universe.name),
        contextId: context.contextId,
        asset: reference.record,
      ),
    ),
    {'asset_id', 'metadata', 'preview'},
  );
  final metadata = response.require('metadata');
  if (metadata is! CanonicalObject ||
      response.string('asset_id') != reference.record.value) {
    throw const FormatException('Image preview metadata differs.');
  }
  final returned = ImageAssetRecord.fromWire(
    CanonicalObject([
      MapEntry('record_kind', CanonicalString(RecordKind.imageAsset.wireName)),
      ...metadata.fields,
    ]),
  );
  if (returned.toWire().toText() != asset.toWire().toText()) {
    throw const FormatException('Image preview metadata differs.');
  }
  final preview = response.string('preview');
  const prefix = 'data:image/jpeg;base64,';
  const maxBytes = 512 * 1024; // Existing service preview limit.
  if (!preview.startsWith(prefix) ||
      preview.length > prefix.length + ((maxBytes + 2) ~/ 3) * 4) {
    throw const FormatException('Unsupported image preview.');
  }
  final bytes = base64.decode(preview.substring(prefix.length));
  if (bytes.isEmpty || bytes.length > maxBytes) {
    throw const FormatException('Unsupported image preview.');
  }
  return (asset: asset, bytes: bytes);
}
