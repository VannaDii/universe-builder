@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_client/browser_archive_transfer.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

web.File selected(List<int> bytes) =>
    web.File([Uint8List.fromList(bytes).toJS].toJS, 'universe.ubarchive');
CanonicalObject progress(
  BeginArchiveUploadEngineRequest request,
  int next,
  int received,
) => CanonicalObject([
  MapEntry('upload_id', CanonicalString(request.uploadId.value)),
  MapEntry('digest', CanonicalString(request.digest)),
  MapEntry('bytes', CanonicalNumber('${request.bytes}')),
  MapEntry('next_ordinal', CanonicalNumber('$next')),
  MapEntry('received_bytes', CanonicalNumber('$received')),
]);

void main() {
  test('selected archive uploads exact bounded chunks and resumes only on an explicit retry', () async {
    const size = ReadMoveChunkEngineRequest.chunkBytes;
    final bytes = List.generate(size * 2 + 5, (i) => (i * 7 + i ~/ size) % 256);
    final file = selected(bytes), id = OperationId.generate();
    final methods = <String>[], writes = <int>[], received = <int>[];
    var next = 0, interrupted = false, reviews = 0;
    final retained = BytesBuilder(copy: false);
    final report = CanonicalObject([
      MapEntry('preview_id', CanonicalString(OperationId.generate().value)),
      MapEntry('digest', CanonicalString('a' * 64)),
    ]);
    Future<CanonicalValue> call(EngineRequest request) async {
      methods.add(request.method);
      switch (request) {
        case BeginArchiveUploadEngineRequest():
          expect(request.uploadId, id);
          expect(request.bytes, bytes.length);
          expect(request.digest, 'f' * 64);
          return progress(request, next, retained.length);
        case WriteArchiveChunkEngineRequest():
          expect(request.uploadId, id);
          expect(request.chunk.ordinal, next);
          expect(
            request.chunk.content,
            bytes.sublist(
              next * size,
              ((next + 1) * size).clamp(0, bytes.length),
            ),
          );
          writes.add(next);
          retained.add(request.chunk.content);
          next++;
          if (!interrupted) {
            interrupted = true;
            throw StateError('Response lost after chunk retained');
          }
          return CanonicalNull();
        case ReviewArchiveUploadEngineRequest():
          expect(request.uploadId, id);
          expect(request.name, 'Imported 記憶');
          expect(request.mode, ImportMode.restore);
          expect(retained.toBytes(), bytes);
          reviews++;
          return report;
        default:
          fail('Unexpected ${request.method}');
      }
    }

    Future<CanonicalValue> upload() => uploadBrowserArchive(
      digest: 'f' * 64,
      file: file,
      uploadId: id,
      name: 'Imported 記憶',
      mode: ImportMode.restore,
      call: call,
      onProgress: (count, total) {
        expect(total, bytes.length);
        received.add(count);
      },
    );
    await expectLater(upload(), throwsStateError);
    expect(writes, [0]);
    expect(reviews, 0);
    expect((await upload()).toText(), report.toText());
    expect(writes, [0, 1, 2]);
    expect(received.last, bytes.length);
    expect(reviews, 1);
    expect(methods, isNot(contains('accept_import')));
    expect(methods, isNot(contains('stage_move')));
  });

  test('cancellation stops before another chunk or review without undoing acknowledged upload', () async {
    const size = ReadMoveChunkEngineRequest.chunkBytes;
    var cancelled = false, writes = 0, reviews = 0;
    await expectLater(
      uploadBrowserArchive(
        digest: 'f' * 64,
        file: selected(List.filled(size + 5, 42)),
        uploadId: OperationId.generate(),
        name: 'Imported',
        mode: ImportMode.clone,
        isCancelled: () => cancelled,
        onProgress: (received, _) {
          if (received > 0) cancelled = true;
        },
        call: (request) async {
          if (request is BeginArchiveUploadEngineRequest) {
            return progress(request, 0, 0);
          }
          if (request is WriteArchiveChunkEngineRequest) {
            writes++;
            return CanonicalNull();
          }
          reviews++;
          return CanonicalNull();
        },
      ),
      throwsStateError,
    );
    expect(writes, 1);
    expect(reviews, 0);
  });

  test(
    'wrong package and impossible progress are rejected before chunk writes',
    () async {
      for (final bad in [
        'upload_id',
        'digest',
        'bytes',
        'next_ordinal',
        'received_bytes',
      ]) {
        var calls = 0;
        await expectLater(
          uploadBrowserArchive(
            digest: 'f' * 64,
            file: selected([1, 2, 3]),
            uploadId: OperationId.generate(),
            name: 'Imported',
            mode: ImportMode.restore,
            call: (request) async {
              calls++;
              final begin = request as BeginArchiveUploadEngineRequest;
              final fields = progress(begin, 0, 0).fields;
              return CanonicalObject([
                for (final field in fields)
                  if (field.key != bad) field,
                MapEntry(bad, switch (bad) {
                  'upload_id' => CanonicalString(OperationId.generate().value),
                  'digest' => CanonicalString('0' * 64),
                  'bytes' => CanonicalNumber('4'),
                  'next_ordinal' => CanonicalNumber('2'),
                  _ => CanonicalNumber('1'),
                }),
              ]);
            },
          ),
          throwsFormatException,
        );
        expect(calls, 1);
      }
    },
  );

  test('empty, oversized or unnamed packages make no service call', () async {
    var calls = 0;
    final oversized =
        {
              'size':
                  ReadMoveChunkEngineRequest.chunkBytes *
                      ReadMoveChunkEngineRequest.maxChunks +
                  1,
            }.jsify()
            as web.File;
    for (final file in [selected([]), oversized]) {
      await expectLater(
        uploadBrowserArchive(
          digest: 'f' * 64,
          file: file,
          uploadId: OperationId.generate(),
          name: 'Imported',
          mode: ImportMode.restore,
          call: (_) async {
            calls++;
            return CanonicalNull();
          },
        ),
        throwsFormatException,
      );
    }
    await expectLater(
      uploadBrowserArchive(
        digest: 'f' * 64,
        file: selected([1]),
        uploadId: OperationId.generate(),
        name: ' ',
        mode: ImportMode.restore,
        call: (_) async {
          calls++;
          return CanonicalNull();
        },
      ),
      throwsFormatException,
    );
    expect(calls, 0);
  });
}
