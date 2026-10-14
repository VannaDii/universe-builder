@TestOn('vm')
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:ub_app/fixture_workspace.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/fixture.dart';

final class _Transport implements FixtureTransport {
  final fixture = DisposableFixture();
  var next = BigInt.zero;
  bool loseReply = false;
  final calls = <Request>[];
  @override
  Future<Response> call(Request request) async {
    calls.add(request);
    final response = fixture.handle(next += BigInt.one, request);
    if (loseReply && request is CreateProposalRequest) {
      loseReply = false;
      throw StateError('simulated disconnect after admission');
    }
    return response;
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('fixture exploration clears stale scope and world focus never becomes draft applicability', () async {
    final transport = _Transport();
    final workspace = FixtureWorkspace(transport);
    expect(() => workspace.review('Unopened', 'known'), throwsStateError);
    workspace.selectScope('The Ashen Cycle', 'Aster');
    await workspace.open();
    final context = workspace.context;
    expect(
      workspace.hits.map((h) => h.label),
      contains('Mara — seal custodian'),
    );
    final draft = workspace.review(
      '  Lantern House 記憶\r\n',
      'explicit_absence',
    );
    final entity =
        (draft.request.operations.single as CreateEntityOperation).record;
    expect(entity.labels['en'], '  Lantern House 記憶\r\n');
    expect(entity.worldAssociations, isEmpty);
    expect(
      (entity.metadata['draft_value_state'] as TextValue).text,
      'explicit_absence',
    );
    expect(draft.request.world, isNull);
    expect(transport.calls.whereType<CreateProposalRequest>(), isEmpty);
    final saved = await workspace.save(draft);
    expect(saved.canonical, isFalse);
    expect(saved.submission, Submission.draft);
    expect(saved.compiledChanges, isEmpty);
    expect(saved.worldScope, isNull);
    workspace.selectScope('The Glass Archive', null);
    expect(workspace.context, isNull);
    expect(workspace.hits, isEmpty);
    await expectLater(workspace.save(draft), throwsStateError);
    await workspace.open();
    expect(workspace.context, isNot(context));
    expect(workspace.hits.map((h) => h.label), contains('Iven — archivist'));
    expect(
      workspace.hits.map((h) => h.label),
      isNot(contains('Mara — seal custodian')),
    );
    workspace.selectScope('The Ashen Cycle', null);
    await workspace.open();
    expect(workspace.hits.map((h) => h.label), isNot(contains(draft.label)));
  });
  test(
    'uncertain save retries the frozen review and recovers one exact proposal',
    () async {
      final transport = _Transport();
      final workspace = FixtureWorkspace(transport);
      await workspace.open();
      for (final state in ['unspecified', 'explicit_absence', 'known']) {
        final draft = workspace.review('Lamp', state);
        transport.loseReply = true;
        await expectLater(workspace.save(draft), throwsStateError);
        expect(workspace.busy, isFalse);
        final recovered = await workspace.save(draft);
        final repeated = await workspace.save(draft);
        expect(repeated.toWire().toText(), recovered.toWire().toText());
        final attempts = transport.calls
            .whereType<CreateProposalRequest>()
            .where((r) => r.idempotencyKey == draft.key)
            .toList();
        expect(attempts.length, 3);
        expect(attempts.map((r) => r.toWire().toText()).toSet().length, 1);
        expect(
          (recovered.operations.single as CreateEntityOperation)
              .record
              .metadata['draft_value_state']!
              .toWire()
              .toText(),
          TextValue(state).toWire().toText(),
        );
      }
      expect(() => workspace.review('  ', 'known'), throwsFormatException);
      expect(() => workspace.review('Lamp', 'false'), throwsFormatException);
    },
  );
}
