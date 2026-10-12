import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'action_checks_test.dart' as actions;
import 'consequence_execution_test.dart' as consequences;
import 'writing_connected_test.dart' as connected;

List<RecordVersion> base() => connected.eventRows(
  contract: consequences.action(
    const SetEffect(Polarity.support, IntegerValue('3')),
  ),
);
List<RecordVersion> occurred(List<RecordVersion> base, {bool twice = false}) {
  final result = compileConnectedWriting(
    frame: actions.frame,
    base: base,
    input: connected.delta(
      events: [
        WritingEvent(
          action: 'charged_action',
          participants: {'actor': 'Actor'},
          atTick: '11',
        ),
        if (twice)
          WritingEvent(
            action: 'charged_action',
            participants: {'actor': 'Actor'},
            atTick: '12',
          ),
      ],
    ),
  );
  expect(result.clarifications, isEmpty);
  return connected.candidate(base, result.operations, frame: actions.frame);
}

RecordVersion event(List<RecordVersion> rows, {String tick = '11'}) =>
    rows.singleWhere(
      (r) =>
          r.payload is EventRecord &&
          (r.payload as EventRecord).time == ExactTime(actions.cal, tick),
    );
void main() {
  test('event participant and knowledge replacements bind visible identities and scoped world selectors', () {
    final current = occurred(base());
    final original = event(current);
    final full = [
      ...current,
      f.row(
        30,
        f.patch<EntityRecord>(f.entity(), {
          'labels': CanonicalObject([MapEntry('en', CanonicalString('Iris'))]),
        }),
      ),
      f.row(40, WorldRecord(selector: 'Stage', aliases: ['The stage'])),
    ];
    final world = WorldId.parse('wld_${f.suffix(40)}');
    final result = compileWritingEventEdits(
      frame: actions.frame,
      base: full,
      worldScope: {world},
      withdrawals: [],
      corrections: [
        WritingEventCorrection(
          eventHandle: original.identity.recordId.value,
          reason: 'Explicit corrected participants and jurisdiction',
          participants: {'actor': 'Iris'},
          world: 'the STAGE',
          requiresKnowledge: [
            WritingKnowledgeRequirement(
              holder: 'Actor',
              claim: WritingClaim(
                subject: 'Actor',
                property: 'charged',
                value: FactNumberValue(const CanonicalNumber('5')),
              ),
            ),
          ],
        ),
      ],
    );
    expect(result.clarifications, isEmpty);
    final replacement =
        (result.operations.last as ReviseEventOperation).replacement;
    expect(replacement.participants.single.record, f.ref(30));
    expect(replacement.worlds, [world]);
    expect((replacement.preconditions.single as AttitudeExpr).holder, f.ref(1));
    final proposition = result.operations
        .whereType<DefinePropositionOperation>()
        .last
        .record;
    expect(proposition.subject, f.ref(30));
    expect(
      replacement.effects.single.scope.applicability,
      WorldsApplicability([world]),
    );
    final denied = compileWritingEventEdits(
      frame: actions.frame,
      base: full,
      worldScope: {},
      withdrawals: [],
      corrections: [
        WritingEventCorrection(
          eventHandle: original.identity.recordId.value,
          reason: 'Unavailable jurisdiction',
          world: 'Stage',
        ),
      ],
    );
    expect(denied.operations, isEmpty);
    expect(denied.clarifications, hasLength(1));
  });
  test('event corrections retain metadata original calendars and nonknowledge preconditions while deriving fresh effects', () {
    final published = occurred(base());
    final original = event(published);
    final metadata = f.patch<EventRecord>(original.payload as EventRecord, {
      'labels': CanonicalObject([
        MapEntry('en', CanonicalString('Named occurrence')),
      ]),
      'sequence': CanonicalString('Authored sequence'),
      'occurrenceId': CanonicalString('Separate event identity'),
      'preconditions': CanonicalArray([
        const LiteralExpr(true).toWire(),
        AttitudeExpr(
          f.ref(1),
          f.ref(3),
          EpistemicAttitudeKind.believes,
        ).toWire(),
        AttitudeExpr(f.ref(1), f.ref(3), EpistemicAttitudeKind.knows).toWire(),
      ]),
    });
    final current = [
      for (final row in published)
        row.identity.recordId == original.identity.recordId
            ? RecordVersion.build(
                recordVersionId: original.recordVersionId,
                identity: original.identity,
                payload: metadata,
              )
            : row,
    ];
    final result = compileWritingEventEdits(
      frame: actions.frame,
      base: current,
      withdrawals: [],
      corrections: [
        WritingEventCorrection(
          eventHandle: original.identity.recordId.value,
          reason: 'Correct narration time',
          atTick: '9007199254740993',
          requiresKnowledge: [],
        ),
      ],
    );
    expect(result.clarifications, isEmpty);
    final operation = result.operations.last as ReviseEventOperation;
    expect(operation.expectedVersion, original.recordVersionId);
    expect(
      operation.replacement.time,
      ExactTime(actions.cal, '9007199254740993'),
    );
    expect(operation.replacement.sequence, metadata.sequence);
    expect(operation.replacement.occurrenceId, metadata.occurrenceId);
    expect(operation.replacement.labels, metadata.labels);
    expect(
      operation.replacement.participants.map((p) => p.toWire().toText()),
      metadata.participants.map((p) => p.toWire().toText()),
    );
    expect(
      operation.replacement.preconditions.map((p) => p.toWire().toText()),
      metadata.preconditions.take(2).map((p) => p.toWire().toText()),
    );
    expect(
      operation.replacement.effects.single.proposition,
      isNot(metadata.effects.single.proposition),
    );
    final candidate = connected.candidate(
      current,
      result.operations,
      frame: actions.frame,
    );
    final generated = candidate
        .where(
          (r) =>
              r.payload is AssertionRecord &&
              (r.payload as AssertionRecord).establishedBy?.event.record ==
                  original.identity.recordId,
        )
        .single;
    expect(
      (generated.payload as AssertionRecord).validity,
      CalendarIntervalValidity(
        actions.cal,
        const ExactBound('9007199254740993'),
        const UnboundedBound(),
      ),
    );
    expect(
      (original.payload as EventRecord).time,
      ExactTime(actions.cal, '11'),
    );
  });

  test('withdrawal requires a current version and selected context and removes occurrence support without an opposite', () {
    final current = occurred(base());
    final original = event(current);
    final result = compileWritingEventEdits(
      frame: actions.frame,
      base: current,
      withdrawals: [
        WritingEventWithdrawal(
          eventHandle: original.recordVersionId.value,
          reason: 'Incorrectly recorded occurrence',
        ),
        WritingEventWithdrawal(
          eventHandle: original.recordVersionId.value,
          reason: 'Duplicate',
        ),
      ],
      corrections: [
        WritingEventCorrection(
          eventHandle: original.identity.recordId.value,
          reason: 'Also edit',
        ),
      ],
    );
    expect(result.operations, hasLength(1));
    expect(result.clarifications, hasLength(2));
    final candidate = connected.candidate(
      current,
      result.operations,
      frame: actions.frame,
    );
    expect(candidate.where((r) => r.payload is EventRecord), isEmpty);
    expect(
      candidate.where(
        (r) =>
            r.payload is AssertionRecord &&
            (r.payload as AssertionRecord).establishedBy != null,
      ),
      isEmpty,
    );
    expect(
      result.additions.single,
      contains('no non-occurrence or opposite claim'),
    );
    final invalid = compileWritingEventEdits(
      frame: actions.frame,
      base: current,
      corrections: [],
      withdrawals: [
        WritingEventWithdrawal(
          eventHandle: original.identity.recordId.value,
          reason: 'Identity handle',
        ),
        WritingEventWithdrawal(eventHandle: f.ver(900).value, reason: 'Absent'),
      ],
    );
    expect(invalid.operations, isEmpty);
    expect(invalid.clarifications, hasLength(2));
    final foreign = Frame(
      universe: actions.frame.universe,
      continuity: actions.frame.continuity,
      revision: actions.frame.revision,
      context: f.ref(99),
      time: actions.frame.time,
      perspective: actions.frame.perspective,
    );
    final restricted = compileWritingEventEdits(
      frame: foreign,
      base: current,
      corrections: [],
      withdrawals: [
        WritingEventWithdrawal(
          eventHandle: original.recordVersionId.value,
          reason: 'Wrong context',
        ),
      ],
    );
    expect(restricted.operations, isEmpty);
    expect(
      restricted.clarifications.single,
      contains('selected author context'),
    );
  });

  test('unsupported manual effects absent contracts and stale correction handles are retained for explicit advanced correction', () {
    final current = occurred(base());
    final original = event(current);
    final stale = compileWritingEventEdits(
      frame: actions.frame,
      base: current,
      withdrawals: [],
      corrections: [
        WritingEventCorrection(
          eventHandle: original.recordVersionId.value,
          reason: 'Wrong handle',
        ),
        WritingEventCorrection(
          eventHandle: original.identity.recordId.value,
          reason: 'Missing action',
          action: 'Absent',
        ),
        WritingEventCorrection(
          eventHandle: original.identity.recordId.value,
          reason: 'Again',
        ),
      ],
    );
    expect(stale.operations, isEmpty);
    expect(stale.clarifications, hasLength(3));
    final old = original.payload as EventRecord;
    final effect = old.effects.single;
    final manual = f.patch<EventRecord>(old, {
      'effects': CanonicalArray([
        EntityEffect(
          slot: 'manual_extra',
          order: effect.order,
          proposition: effect.proposition,
          polarity: effect.polarity,
          validity: effect.validity,
          scope: effect.scope,
        ).toWire(),
      ]),
    });
    final altered = [
      for (final row in current)
        row.identity.recordId == original.identity.recordId
            ? RecordVersion.build(
                recordVersionId: original.recordVersionId,
                identity: original.identity,
                payload: manual,
              )
            : row,
    ];
    final guarded = compileWritingEventEdits(
      frame: actions.frame,
      base: altered,
      withdrawals: [],
      corrections: [
        WritingEventCorrection(
          eventHandle: original.identity.recordId.value,
          reason: 'Do not discard manual effects',
        ),
      ],
    );
    expect(guarded.operations, isEmpty);
    expect(guarded.clarifications.single, contains('none were dropped'));
    final contracted =
        base().singleWhere((r) => r.identity.recordId == f.id(5)).payload
            as ActionDefinitionRecord;
    final legacyAction = ActionDefinitionRecord(
      namespace: contracted.namespace,
      key: contracted.key,
      labels: contracted.labels,
      requirements: contracted.requirements,
      scope: contracted.scope,
      validity: contracted.validity,
    );
    final legacy = compileWritingEventEdits(
      frame: actions.frame,
      base: [
        for (final row in current)
          row.identity.recordId == f.id(5) ? f.row(5, legacyAction) : row,
      ],
      withdrawals: [],
      corrections: [
        WritingEventCorrection(
          eventHandle: original.identity.recordId.value,
          reason: 'Unknown contract',
        ),
      ],
    );
    expect(legacy.operations, isEmpty);
    expect(legacy.clarifications.single, contains('not contract-derived'));
  });

  test('dependent resource consequences stay frozen until each affected event is explicitly corrected', () {
    final originalBase = connected.eventRows();
    final replenishment = f.patch<ActionDefinitionRecord>(
      consequences.action(consequences.delta('1')),
      {'key': CanonicalString('replenish')},
    );
    final current = occurred([
      ...originalBase,
      f.row(20, replenishment),
    ], twice: true);
    final first = event(current), later = event(current, tick: '12');
    final one = compileWritingEventEdits(
      frame: actions.frame,
      base: current,
      withdrawals: [],
      corrections: [
        WritingEventCorrection(
          eventHandle: first.identity.recordId.value,
          reason: 'Actually replenished',
          action: 'replenish',
        ),
      ],
    );
    expect(one.clarifications, isEmpty);
    final unchangedLater = connected.candidate(
      current,
      one.operations,
      frame: actions.frame,
    );
    expect(
      unchangedLater
          .singleWhere((r) => r.identity.recordId == later.identity.recordId)
          .payload,
      later.payload,
    );
    expect(
      () => validateActionConsequences(
        records: unchangedLater,
        base: current,
        changed: {first.identity.recordId},
        frame: actions.frame,
      ),
      throwsA(
        isA<InvalidArgumentError>().having(
          (e) => e.message,
          'message',
          contains('post-value'),
        ),
      ),
    );
    final repaired = compileWritingEventEdits(
      frame: actions.frame,
      base: current,
      withdrawals: [],
      corrections: [
        WritingEventCorrection(
          eventHandle: first.identity.recordId.value,
          reason: 'Actually replenished',
          action: 'replenish',
        ),
        WritingEventCorrection(
          eventHandle: later.identity.recordId.value,
          reason: 'Explicitly rederive retained later event',
        ),
      ],
    );
    expect(repaired.clarifications, isEmpty);
    final candidate = connected.candidate(
      current,
      repaired.operations,
      frame: actions.frame,
    );
    validateActionConsequences(
      records: candidate,
      base: current,
      changed: {first.identity.recordId, later.identity.recordId},
      frame: actions.frame,
    );
    final effects = repaired.operations
        .whereType<DefinePropositionOperation>()
        .map((p) => p.record.value)
        .toList();
    expect(effects, [const IntegerValue('6'), const IntegerValue('4')]);
  });
}
