import 'package:test/test.dart';
import 'package:ub_client/archive_transfer.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('explicit retry resumes an acknowledged upload without admitting it', () async {
    final move = StageMoveEngineRequest(
      universeId: UniverseId.generate(),
      operationId: OperationId.generate(),
      targetInstance: OperationId.generate(),
    );
    final uploadId = OperationId.generate();
    final reads = <int>[];
    final writes = <int>[];
    var retained = 0, interrupted = false, reviews = 0;
    const chunkSize = ReadMoveChunkEngineRequest.chunkBytes;
    final stage = CanonicalValue.parseWireJson(
      '{"digest":"${'a' * 64}","bytes":${chunkSize + 3}}',
    );
    final preview = CanonicalValue.parseWireJson(
      '{"preview_id":"${uploadId.value}"}',
    );
    Future<CanonicalValue> source(EngineRequest request) async {
      if (request is StageMoveEngineRequest) {
        expect(request, same(move));
        return stage;
      }
      final read = request as ReadMoveChunkEngineRequest;
      expect(read.operationId, move.operationId);
      expect(read.targetInstance, move.targetInstance);
      reads.add(read.ordinal);
      return MoveArchiveChunk(
        ordinal: read.ordinal,
        content: List.filled(read.ordinal == 0 ? chunkSize : 3, 42),
      ).toWire();
    }

    Future<CanonicalValue> target(EngineRequest request) async {
      switch (request) {
        case BeginArchiveUploadEngineRequest():
          expect(request.uploadId, uploadId);
          expect(request.bytes, chunkSize + 3);
          return CanonicalValue.parseWireJson('{"next_ordinal":$retained}');
        case WriteArchiveChunkEngineRequest():
          expect(request.uploadId, uploadId);
          expect(request.chunk.ordinal, retained);
          writes.add(request.chunk.ordinal);
          retained++;
          if (!interrupted) {
            interrupted = true;
            // The target retained the first chunk before its response was lost.
            throw StateError('Disposable interrupted response');
          }
          return CanonicalNull();
        case ReviewArchiveUploadEngineRequest():
          expect(request.mode, ImportMode.restore);
          expect(request.name, 'Target name');
          expect(retained, 2);
          reviews++;
          return preview;
        default:
          fail('Unexpected target request ${request.method}');
      }
    }

    Future<CanonicalValue> prepare() => prepareMoveTransfer(
      source: source,
      target: target,
      move: move,
      uploadId: uploadId,
      name: 'Target name',
    );
    await expectLater(prepare(), throwsStateError);
    expect(reviews, 0);
    expect(await prepare(), same(preview));
    expect(reads, [0, 1]);
    expect(writes, [0, 1]);
    // A completed retry reuses the retained review, without streaming again.
    expect(await prepare(), same(preview));
    expect(reads, [0, 1]);
    expect(reviews, 2);
  });
}
