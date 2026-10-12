import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test(
    'private move discovery round trips exact cursor and operation identity',
    () {
      final operation = OperationId.generate();
      for (final request in [
        const ListMovesEngineRequest(),
        ListMovesEngineRequest(after: operation, limit: 1),
        GetMoveEngineRequest(operationId: operation),
        BeginArchiveUploadEngineRequest(
          uploadId: operation,
          digest: 'a' * 64,
          bytes: 8589934592,
        ),
        WriteArchiveChunkEngineRequest(
          uploadId: operation,
          chunk: MoveArchiveChunk(ordinal: 0, content: [0, 255]),
        ),
        ReviewArchiveUploadEngineRequest(
          uploadId: operation,
          name: 'Exact é😀',
          mode: ImportMode.restore,
        ),
        ReadMoveChunkEngineRequest(
          universeId: UniverseId.generate(),
          operationId: operation,
          targetInstance: OperationId.generate(),
          ordinal: 32767,
        ),
        StageMoveEngineRequest(
          universeId: UniverseId.generate(),
          operationId: operation,
          targetInstance: OperationId.generate(),
        ),
      ]) {
        expect(
          EngineRequest.decode(request.toWire().toBytes()).toWire().toText(),
          request.toWire().toText(),
        );
        expect(
          () => Request.fromTool(request.method, request.toWire()),
          throwsA(isA<InvalidArgumentError>()),
        );
      }
    },
  );
  test('move chunks preserve bounded bytes and reject malformed replies and ordinals', () {
    final chunk = MoveArchiveChunk(
      ordinal: 32767,
      content: Uint8List.fromList(
        List.generate(ReadMoveChunkEngineRequest.chunkBytes, (i) => i % 256),
      ),
    );
    expect(MoveArchiveChunk.fromWire(chunk.toWire()).content, chunk.content);
    expect(chunk.toWire().toBytes().length, lessThan(maxFrameBytes));
    for (final ordinal in [-1, 32768]) {
      expect(
        () => ReadMoveChunkEngineRequest.validateOrdinal(ordinal),
        throwsFormatException,
      );
    }
    for (final content in [
      <int>[],
      List<int>.filled(ReadMoveChunkEngineRequest.chunkBytes + 1, 0),
    ]) {
      expect(
        () => MoveArchiveChunk(ordinal: 0, content: content),
        throwsFormatException,
      );
    }
    for (final raw in [
      '{"ordinal":0,"content":""}',
      '{"ordinal":0,"content":"YQ"}',
      '{"ordinal":0,"content":"YQ==\\n"}',
      '{"ordinal":0,"content":"YQ==","path":"private"}',
      '{"ordinal":0.0,"content":"YQ=="}',
      '{"ordinal":32768,"content":"YQ=="}',
    ]) {
      expect(
        () => MoveArchiveChunk.fromWire(CanonicalValue.parseWireJson(raw)),
        throwsFormatException,
      );
    }
  });
  test(
    'chunk requests reject extra fields and nonintegral or excessive ordinals',
    () {
      final request = ReadMoveChunkEngineRequest(
        universeId: UniverseId.generate(),
        operationId: OperationId.generate(),
        targetInstance: OperationId.generate(),
        ordinal: 0,
      );
      for (final ordinal in [
        '-1',
        '0.0',
        '0e0',
        '32768',
        '18446744073709551616',
      ]) {
        expect(
          () => EngineRequest.fromWire(
            CanonicalObject([
              for (final field in request.toWire().fields)
                if (field.key == 'ordinal')
                  MapEntry('ordinal', CanonicalNumber(ordinal))
                else
                  field,
            ]),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => EngineRequest.fromWire(
          CanonicalObject([
            ...request.toWire().fields,
            MapEntry('path', CanonicalString('private')),
          ]),
        ),
        throwsFormatException,
      );
    },
  );
  test('archive upload refuses unbounded sizes, malformed digests and caller paths', () {
    final id = OperationId.generate();
    for (final bytes in [
      '0',
      '-1',
      '1.0',
      '1e0',
      '8589934593',
      '18446744073709551616',
    ]) {
      expect(
        () => EngineRequest.fromWire(
          CanonicalValue.parseWireJson(
            '{"method":"begin_archive_upload","upload_id":"${id.value}","digest":"${'a' * 64}","bytes":$bytes}',
          ),
        ),
        throwsFormatException,
      );
    }
    for (final digest in ['bad', 'A' * 64, 'a' * 65]) {
      expect(
        () => BeginArchiveUploadEngineRequest(
          uploadId: id,
          digest: digest,
          bytes: 1,
        ).validate(),
        throwsFormatException,
      );
    }
    for (final request in [
      BeginArchiveUploadEngineRequest(uploadId: id, digest: 'a' * 64, bytes: 1),
      WriteArchiveChunkEngineRequest(
        uploadId: id,
        chunk: MoveArchiveChunk(ordinal: 0, content: [0]),
      ),
      ReviewArchiveUploadEngineRequest(
        uploadId: id,
        name: 'Target',
        mode: ImportMode.restore,
      ),
    ]) {
      expect(
        () => EngineRequest.fromWire(
          CanonicalObject([
            ...request.toWire().fields,
            MapEntry('path', CanonicalString('private')),
          ]),
        ),
        throwsFormatException,
      );
    }
  });
  test('move staging refuses caller paths and malformed identities', () {
    final request = StageMoveEngineRequest(
      universeId: UniverseId.generate(),
      operationId: OperationId.generate(),
      targetInstance: OperationId.generate(),
    );
    for (final key in ['path', 'destination', 'receipt']) {
      expect(
        () => EngineRequest.fromWire(
          CanonicalObject([
            ...request.toWire().fields,
            MapEntry(key, CanonicalString('private')),
          ]),
        ),
        throwsFormatException,
      );
    }
    for (final key in ['universe_id', 'operation_id', 'target_instance']) {
      expect(
        () => EngineRequest.fromWire(
          CanonicalObject([
            for (final field in request.toWire().fields)
              if (field.key == key)
                MapEntry(key, CanonicalString('bad'))
              else
                field,
          ]),
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'move discovery refuses extra fields and invalid page or identity tokens',
    () {
      for (final raw in [
        '{"method":"list_moves","limit":0}',
        '{"method":"list_moves","limit":101}',
        '{"method":"list_moves","limit":1.0}',
        '{"method":"list_moves","limit":1e0}',
        '{"method":"list_moves","limit":-1}',
        '{"method":"list_moves","limit":18446744073709551616}',
        '{"method":"list_moves","after":"bad"}',
        '{"method":"list_moves","path":"private"}',
        '{"method":"get_move","operation_id":"bad"}',
        '{"method":"get_move","operation_id":"op_000000000000000000000001","receipt":{}}',
        '{"method":"status","after":null}',
      ]) {
        expect(
          () => EngineRequest.fromWire(CanonicalValue.parseWireJson(raw)),
          throwsFormatException,
        );
      }
      expect(
        () => const ListMovesEngineRequest(limit: 0).validate(),
        throwsFormatException,
      );
    },
  );
}
