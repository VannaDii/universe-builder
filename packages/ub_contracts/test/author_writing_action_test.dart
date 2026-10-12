import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalValue wire(String raw) => CanonicalValue.parseWireJson(raw);
final candidate = ProposalId.parse('prp_000000000000000000000001');
final ref = ProposalRef(
  proposalId: candidate,
  version: BigInt.parse('18446744073709551615'),
  digest: 'exact retained digest',
);
final context = ContextId.parse('ctx_000000000000000000000001');
void main() {
  test('inspect reopens exact review while prepare and reject retain candidate identity only', () {
    final inspect = AuthorWritingAction.fromWire(
      InspectWritingAction(candidate: ref).toWire(),
    ) as InspectWritingAction;
    expect(inspect.candidate, ref);
    final prepare = AuthorWritingAction.fromWire(
      PrepareWritingAction(
        candidate: candidate,
        label: 'Remembered account',
        text: 'Source é',
      ).toWire(),
    ) as PrepareWritingAction;
    expect(prepare.candidate, candidate);
    expect(prepare.text, 'Source é');
    expect(prepare.toWire().toText(), isNot(contains('validation_run')));
    expect(
      AuthorWritingAction.fromWire(
        RejectWritingAction(candidate: candidate).toWire(),
      ),
      isA<RejectWritingAction>(),
    );
    expect(
      () => AuthorWritingAction.fromWire(
        wire('{"action":"inspect","candidate":"${candidate.value}"}'),
      ),
      throwsFormatException,
    );
    expect(
      () => AuthorWritingAction.fromWire(
        CanonicalObject([
          MapEntry('action', CanonicalString('prepare')),
          MapEntry('candidate', ref.toWire()),
          MapEntry('label', CanonicalString('Account')),
          MapEntry('text', CanonicalString('Source')),
        ]),
      ),
      throwsFormatException,
    );
  });
  test('publish requires exact version digest validation run and retry key without inline approval', () {
    final publish = PublishWritingAction(
      candidate: ref,
      validationRun: ValidationRunId.parse('val_000000000000000000000001'),
      idempotencyKey: 'retry-one',
    );
    final back =
        AuthorWritingAction.fromWire(publish.toWire()) as PublishWritingAction;
    expect(back.candidate, ref);
    expect(back.validationRun, publish.validationRun);
    expect(back.idempotencyKey, 'retry-one');
    for (final key in ['candidate', 'validation_run', 'idempotency_key']) {
      expect(
        () => AuthorWritingAction.fromWire(
          CanonicalObject(publish.toWire().fields.where((e) => e.key != key)),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => AuthorWritingAction.fromWire(
        CanonicalObject([
          ...publish.toWire().fields,
          const MapEntry('approved', CanonicalBool(true)),
        ]),
      ),
      throwsFormatException,
    );
  });
  test('finding acceptance preserves opaque fingerprint scope and rationale with exact candidate', () {
    const fingerprint = FindingFingerprint('opaque supplied fingerprint');
    final action = AcceptWritingAction(
      candidate: ref,
      fingerprint: fingerprint,
      scope: 'Earth/Account',
      rationale: 'Explicit authored choice',
    );
    final back =
        AuthorWritingAction.fromWire(action.toWire()) as AcceptWritingAction;
    expect(back.candidate, ref);
    expect(back.fingerprint, fingerprint);
    expect(back.scope, 'Earth/Account');
    expect(back.rationale, 'Explicit authored choice');
    expect(back.toWire().toText(), isNot(contains('truth')));
    expect(
      () => AuthorWritingAction.fromWire(
        CanonicalObject(action.toWire().fields.where((e) => e.key != 'scope')),
      ),
      throwsFormatException,
    );
  });
  test('knowledge correction retains explicit clear flags separately from new declarations', () {
    final correction = WritingAttitudeCorrection(
      attitudeHandle: 'opaque attitude',
      reason: 'Correct testimony',
      value: const FactBooleanValue(false),
      clearCertainty: true,
    );
    final edit = EditKnowledgeWritingAction(
      contextId: context,
      correction: correction,
      label: 'Account',
      text: 'Authored correction',
    );
    final back = AuthorWritingAction.fromWire(
      edit.toWire(),
    ) as EditKnowledgeWritingAction;
    expect(back.contextId, context);
    expect(back.correction.clearCertainty, isTrue);
    expect(back.correction.certainty, isNull);
    expect(back.correction.atTick, isNull);
    expect(back.correction.value!.toWire().toText(), 'false');
    final declaration = AuthorKnowledgeDeclaration(
      holder: 'Mara',
      claim: WritingClaim(
        subject: 'Door',
        property: 'open',
        value: const FactBooleanValue(true),
      ),
      lifetime: const FactUntilChangedLifetime(),
    );
    final establish = EstablishKnowledgeWritingAction(
      contextId: context,
      declaration: declaration,
      rationale: 'Explicit author declaration',
      label: 'Account',
      text: 'Authored source',
    );
    final established = AuthorWritingAction.fromWire(
      establish.toWire(),
    ) as EstablishKnowledgeWritingAction;
    expect(established.declaration.atTick, '');
    expect(established.declaration.world, isNull);
    expect(established.declaration.holder, 'Mara');
    expect(established.rationale, 'Explicit author declaration');
  });
  test('private contract preparation stays distinct and public requests cannot carry author actions', () {
    final action = PrepareContractsWritingAction(
      candidate: candidate,
      label: 'Rules',
      text: 'Authored contracts',
    );
    expect(
      AuthorWritingAction.fromWire(action.toWire()),
      isA<PrepareContractsWritingAction>(),
    );
    expect(
      () => Request.fromTool('universe_propose', action.toWire()),
      throwsA(isA<InvalidArgumentError>()),
    );
    expect(
      () => Request.fromTool('prepare_contracts', action.toWire()),
      throwsA(isA<InvalidArgumentError>()),
    );
    expect(
      () => AuthorWritingAction.fromWire(
        wire('{"action":"approve","candidate":"${candidate.value}"}'),
      ),
      throwsFormatException,
    );
    expect(
      () => AuthorWritingAction.fromWire(
        CanonicalObject([
          ...RejectWritingAction(candidate: candidate).toWire().fields,
          MapEntry('text', CanonicalString('unused source')),
        ]),
      ),
      throwsFormatException,
    );
  });
}
