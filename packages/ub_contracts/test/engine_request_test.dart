import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalValue wire(String raw) => CanonicalValue.parseWireJson(raw);
final universe = const Selector('Cycle');
final max = BigInt.parse('18446744073709551615');
final continuity = ContinuityId.parse('cont_000000000000000000000001');
final revision = RevisionId.parse('rev_000000000000000000000001');
final record = RecordId.parse('rec_000000000000000000000001');
final ref = ProposalRef(
  proposalId: ProposalId.parse('prp_000000000000000000000001'),
  version: max,
  digest: 'retained digest',
);
void main() {
  test('private review and approval retain exact frozen candidate and validation run', () {
    final approve = ApproveEngineRequest(
      universe: universe,
      proposalReference: ref,
      validationRun: ValidationRunId.parse('val_000000000000000000000001'),
    );
    final back = EngineRequest.decode(
      approve.toWire().toBytes(),
    ) as ApproveEngineRequest;
    expect(back.proposalReference, ref);
    expect(back.validationRun, approve.validationRun);
    final review = ReviewEngineRequest(
      universe: universe,
      proposalReference: ref,
    );
    expect(
      (EngineRequest.fromWire(
        review.toWire(),
      ) as ReviewEngineRequest).proposalReference,
      ref,
    );
    expect(
      () => Request.fromTool('approve', approve.toWire()),
      throwsA(isA<InvalidArgumentError>()),
    );
    expect(
      () => EngineRequest.fromWire(
        CanonicalObject([
          ...approve.toWire().fields,
          const MapEntry('approved', CanonicalBool(true)),
        ]),
      ),
      throwsFormatException,
    );
  });
  test('draft save carries exact optimistic version while author actions stay private nested decisions', () {
    final content = DraftContent(
      baseRevision: revision,
      representedContext: record,
      operations: [],
      rationale: 'Authored draft',
      proposal: ref,
    );
    final save = SaveDraftEngineRequest(
      universe: universe,
      continuityId: continuity,
      expectedVersion: max,
      content: content,
    );
    final back =
        EngineRequest.fromWire(save.toWire()) as SaveDraftEngineRequest;
    expect(back.expectedVersion, max);
    expect(back.content.proposal, ref);
    expect(back.content.baseRevision, revision);
    final action = AuthorWritingEngineRequest(
      universe: universe,
      action: InspectWritingAction(candidate: ref),
    );
    expect(
      (EngineRequest.fromWire(
        action.toWire(),
      ) as AuthorWritingEngineRequest).action,
      isA<InspectWritingAction>(),
    );
  });
  test('adoption selection pins both continuities and revisions with immutable authored record order', () {
    final ids = [
      record,
      RecordId.parse('rec_000000000000000000000002'),
      record,
    ];
    final source = ContinuityId.parse('cont_000000000000000000000002');
    final sourceRevision = RevisionId.parse('rev_000000000000000000000002');
    final request = PrepareAdoptionEngineRequest(
      universe: universe,
      target: continuity,
      targetRevision: revision,
      source: source,
      sourceRevision: sourceRevision,
      recordIds: ids,
    );
    ids.clear();
    final back = EngineRequest.fromWire(
      request.toWire(),
    ) as PrepareAdoptionEngineRequest;
    expect(back.target, continuity);
    expect(back.targetRevision, revision);
    expect(back.source, source);
    expect(back.sourceRevision, sourceRevision);
    expect(back.recordIds, [
      record,
      RecordId.parse('rec_000000000000000000000002'),
      record,
    ]);
    expect(() => back.recordIds.clear(), throwsUnsupportedError);
  });
  test('recovery and purge contracts preserve paths selections and explicit confirmation without execution', () {
    const path = r'C:\authored data\é\backup.ub';
    final backup = BackupEngineRequest(universe: universe, destination: path);
    expect(
      (EngineRequest.fromWire(
        backup.toWire(),
      ) as BackupEngineRequest).destination,
      path,
    );
    final export = ExportLogicalEngineRequest.fromWire(
      wire(
        '{"method":"export_logical","universe":"Cycle","destination":"/test/backup.ub","record_ids":[]}',
      ),
    );
    expect(export.recordIds, isEmpty);
    expect(export.completeHistory, isFalse);
    expect(export.toWire().toText(), contains('"complete_history":false'));
    final purge = PurgeEngineRequest(
      universe: universe,
      digest: 'exact preview digest',
      confirmation: 'explicit confirmation',
    );
    expect(
      (EngineRequest.fromWire(purge.toWire()) as PurgeEngineRequest).digest,
      'exact preview digest',
    );
    expect(
      () => EngineRequest.fromWire(
        CanonicalObject(
          purge.toWire().fields.where((e) => e.key != 'confirmation'),
        ),
      ),
      throwsFormatException,
    );
    final import = AcceptImportEngineRequest(
      previewId: OperationId.parse('op_000000000000000000000001'),
      digest: 'exact import digest',
    );
    expect(
      (EngineRequest.fromWire(
        import.toWire(),
      ) as AcceptImportEngineRequest).digest,
      import.digest,
    );
  });
  test('universe creation retains explicit authored clock start without inferred calendar or current time', () {
    final start = FictionalUniverseStart(
      calendarName: 'Story calendar',
      initialTick: '-9007199254740993',
      tickLabel: 'day',
      ticksPerMonth: 4294967295,
    );
    final request = CreateUniverseEngineRequest(name: 'Campaign', start: start);
    final back =
        (EngineRequest.fromWire(
              request.toWire(),
            ) as CreateUniverseEngineRequest).start
            as FictionalUniverseStart;
    expect(back.initialTick, start.initialTick);
    expect(back.ticksPerMonth, 4294967295);
    final gregorian = UniverseStart.fromWire(
      wire('{"kind":"gregorian","timestamp":"1900-01-01T00:00:00+05:30"}'),
    ) as GregorianUniverseStart;
    expect(gregorian.timestamp, '1900-01-01T00:00:00+05:30');
    final missingMonth = UniverseStart.fromWire(
      wire(
        '{"kind":"fictional","calendar_name":"Story","initial_tick":"0","tick_label":"day"}',
      ),
    ) as FictionalUniverseStart;
    expect(missingMonth.ticksPerMonth, isNull);
    expect(missingMonth.toWire().toText(), contains('"ticks_per_month":null'));
    expect(
      () => EngineRequest.fromWire(
        wire('{"method":"create_universe","name":"Campaign"}'),
      ),
      throwsFormatException,
    );
    for (final raw in ['4294967296', '-1', '1.0', '"1"']) {
      expect(
        () => UniverseStart.fromWire(
          wire(
            '{"kind":"fictional","calendar_name":"Story","initial_tick":"0","tick_label":"day","ticks_per_month":$raw}',
          ),
        ),
        throwsFormatException,
      );
    }
  });
  test('call reply ids and generic results preserve exact values without upgrading an error', () {
    final call = EngineCall(
      id: max,
      request: ToolEngineRequest(
        request: DescribeSummaryRequest(universe: universe),
      ),
    );
    final back = EngineCall.decode(call.toWire().toBytes());
    expect(back.id, max);
    expect(
      (back.request as ToolEngineRequest).request.toolName,
      'universe_describe',
    );
    final reply = EngineReply(
      id: max,
      result: EngineSuccess(
        wire('{"amount":9007199254740993.00,"exponent":1E3}'),
      ),
    );
    final received = EngineReply.decode(reply.toWire().toBytes());
    expect(received.id, max);
    expect(
      (received.result as EngineSuccess).value.toText(),
      '{"amount":9007199254740993.00,"exponent":1E3}',
    );
    final failure = EngineReply(
      id: max,
      result: const EngineFailure(
        ApprovalRequiredError(message: 'Exact approval required'),
      ),
    );
    expect(
      (EngineReply.decode(failure.toWire().toBytes()).result as EngineFailure)
          .error,
      isA<ApprovalRequiredError>(),
    );
    expect(
      EngineReply.fromWire(wire('{"id":0,"result":{"Ok":null}}')).result,
      isA<EngineSuccess>(),
    );
    expect(
      () => EngineResult.fromWire(wire('{"Ok":null,"Err":null}')),
      throwsFormatException,
    );
  });
  test(
    'unsigned ids and versions reject overflow rounding and quoted values',
    () {
      final content = DraftContent(
        baseRevision: revision,
        representedContext: record,
        operations: [],
        rationale: 'Draft',
      );
      for (final raw in ['-1', '1.0', '1e2', '18446744073709551616', '"1"']) {
        expect(
          () => EngineCall.fromWire(
            wire('{"id":$raw,"request":{"method":"status"}}'),
          ),
          throwsFormatException,
        );
        expect(
          () => EngineReply.fromWire(wire('{"id":$raw,"result":{"Ok":null}}')),
          throwsFormatException,
        );
        expect(
          () => SaveDraftEngineRequest.fromWire(
            CanonicalObject([
              MapEntry('method', CanonicalString('save_draft')),
              MapEntry('universe', universe.toWire()),
              MapEntry('continuity_id', CanonicalString(continuity.value)),
              MapEntry('expected_version', wire(raw)),
              MapEntry('content', content.toWire()),
            ]),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => EngineCall(id: -BigInt.one, request: const StatusEngineRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'private messages use bounded strict decoding and closed command variants',
    () {
      final decoders = <Object Function(Uint8List)>[
        EngineRequest.decode,
        EngineCall.decode,
        EngineReply.decode,
        EngineHello.decode,
        EngineWelcome.decode,
      ];
      for (final decode in decoders) {
        expect(() => decode(Uint8List.fromList([0xff])), throwsFormatException);
        expect(
          () => decode(Uint8List(maxFrameBytes + 1)),
          throwsFormatException,
        );
        expect(
          () => decode(Uint8List.fromList(utf8.encode('{"id":1,"id":2}'))),
          throwsFormatException,
        );
      }
      expect(
        () =>
            EngineRequest.fromWire(wire('{"method":"shutdown","force":true}')),
        throwsFormatException,
      );
      expect(
        () => EngineRequest.fromWire(wire('{"method":"unknown"}')),
        throwsFormatException,
      );
      expect(
        () => EngineRequest.fromWire(
          wire(
            '{"method":"export_logical","universe":"Cycle","destination":"/test/backup.ub","record_ids":[],"complete_history":null}',
          ),
        ),
        throwsFormatException,
      );
    },
  );
}
