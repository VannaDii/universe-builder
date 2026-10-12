import 'dart:math' show min;
import 'dart:typed_data';

import 'wire.dart';

/// The existing local IPC format: a four-byte big-endian payload length,
/// followed by bounded raw JSON bytes. DTO decoding remains a separate step.
Uint8List encodeLengthPrefixedFrame(Uint8List body) {
  if (body.length > maxFrameBytes) {
    throw const FormatException('Frame too large');
  }
  final result = Uint8List(body.length + 4);
  ByteData.sublistView(result).setUint32(0, body.length, Endian.big);
  result.setRange(4, result.length, body);
  return result;
}

/// Consume fragmented or coalesced transport chunks without retaining a queue
/// of frames. Payload allocation follows the checked header, and yielding each
/// complete frame preserves downstream backpressure. An incomplete final frame
/// fails rather than becoming a successful disconnect or partial DTO.
Stream<Uint8List> decodeLengthPrefixedFrames(Stream<Uint8List> chunks) async* {
  final header = Uint8List(4);
  var headerUsed = 0, bodyUsed = 0;
  Uint8List? body;
  await for (final chunk in chunks) {
    var offset = 0;
    while (offset < chunk.length) {
      if (body == null) {
        final count = min(4 - headerUsed, chunk.length - offset);
        header.setRange(headerUsed, headerUsed + count, chunk, offset);
        headerUsed += count;
        offset += count;
        if (headerUsed != 4) continue;
        final length = ByteData.sublistView(header).getUint32(0, Endian.big);
        if (length > maxFrameBytes) {
          throw const FormatException('Frame too large');
        }
        body = Uint8List(length);
        headerUsed = 0;
        bodyUsed = 0;
        if (length == 0) {
          yield body;
          body = null;
        }
      } else {
        final count = min(body.length - bodyUsed, chunk.length - offset);
        body.setRange(bodyUsed, bodyUsed + count, chunk, offset);
        bodyUsed += count;
        offset += count;
        if (bodyUsed == body.length) {
          yield body;
          body = null;
          bodyUsed = 0;
        }
      }
    }
  }
  if (headerUsed != 0 || body != null) {
    throw const FormatException('Incomplete frame');
  }
}
