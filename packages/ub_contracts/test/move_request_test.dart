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
