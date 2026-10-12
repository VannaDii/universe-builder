import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as facts;
import 'writing_contexts_test.dart' as contexts;
import 'writing_binding_test.dart' as binding;

List<RecordVersion> rows({AssertionRecord? assertion}) => [
  ...contexts.rows(),
  ...facts.fixture().take(2),
  f.row(3, assertion ?? facts.assertion().payload as AssertionRecord),
];
void main() {
  test('fact correction preserves original scope time polarity precision and uses current candidate references', () {
    final original = f.patch<AssertionRecord>(
      facts.assertion().payload as AssertionRecord,
      {
        'precision': Precision.oneOf.toWire(),
        'alternatives': CanonicalArray([const BooleanValue(false).toWire()]),
        'polarity': Polarity.refutation.toWire(),
      },
    );
    final base = rows(assertion: original);
    final result = compileWritingFactEdits(
      frame: facts.frame(),
      base: base,
      corrections: [
        WritingCorrection(
          factHandle: f.ver(3).value,
          value: const FactBooleanValue(false),
          reason: 'Correct authored value',
        ),
      ],
      endings: [],
      withdrawals: [],
    );
    expect(result.clarifications, isEmpty);
    final op = result.operations.last as SupersedeAssertionOperation;
    expect(op.expectedVersion, f.ver(3));
    expect(op.record, f.ref(3));
    expect(op.replacement.scope, original.scope);
    expect(op.replacement.validity, original.validity);
    expect(op.replacement.polarity, original.polarity);
    expect(op.replacement.precision, original.precision);
    expect(op.replacement.alternatives, original.alternatives);
    expect(op.replacement.persistence, original.persistence);
    expect(op.replacement.attributeMode, original.attributeMode);
    expect(op.replacement.basis, const ImportedClaimBasis());
    final proposition =
        (result.operations.first as DefinePropositionOperation).record;
    expect(proposition.subject, f.ref(80));
    expect(proposition.predicate, f.ref(1));
    expect(proposition.context, facts.frame().context);
    expect(proposition.value, const BooleanValue(false));
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base,
      operations: result.operations,
    );
    expect(
      candidate.singleWhere((r) => r.identity.recordId == f.id(3)).payload,
      op.replacement,
    );
    final newId = f.id(82);
    final prior = CreateEntityOperation(
      clientRef: newId.value,
      record: binding.entity(labels: {'en': 'Iris'}),
    );
    final reference = compileWritingFactEdits(
      frame: facts.frame(),
      base: rows(),
      priorOperations: [prior],
      corrections: [
        WritingCorrection(
          factHandle: f.ver(3).value,
          value: const FactObjectValue('Iris'),
          reason: 'Explicit reference',
        ),
      ],
      endings: [],
      withdrawals: [],
    );
    expect(reference.operations, hasLength(2));
    expect(
      (reference.operations.first as DefinePropositionOperation).record.value,
      ReferenceValue(ValueReferenceKind.entity, f.ref(82)),
    );
  });

  test('fact endings use original calendars while withdrawal removes support without asserting an opposite', () {
    final calendar = CalendarId.fromRecordId(f.id(11));
    final original =
        facts
                .assertion(
                  validity: CalendarIntervalValidity(
                    calendar,
                    const ExactBound('9007199254740993'),
                    const ExactBound('9007199254741000'),
                  ),
                )
                .payload
            as AssertionRecord;
    final base = rows(assertion: original);
    final ending = compileWritingFactEdits(
      frame: facts.frame(),
      base: base,
      corrections: [],
      withdrawals: [],
      endings: [
        WritingFactEnding(
          factHandle: f.ver(3).value,
          reason: 'Ended',
          endTick: '9007199254740995',
        ),
      ],
    );
    expect(ending.clarifications, isEmpty);
    final op = ending.operations.single as EndAssertionAtOperation;
    expect(op.at, ExactTime(calendar, '9007199254740995'));
    expect(op.expectedVersion, f.ver(3));
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base,
      operations: ending.operations,
    );
    final changed =
        candidate.singleWhere((r) => r.identity.recordId == f.id(3)).payload
            as AssertionRecord;
    expect(
      changed.validity,
      CalendarIntervalValidity(
        calendar,
        const ExactBound('9007199254740993'),
        const ExactBound('9007199254740995'),
      ),
    );
    expect(changed.proposition, original.proposition);
    expect(changed.polarity, original.polarity);
    final withdrawal = compileWritingFactEdits(
      frame: facts.frame(),
      base: base,
      corrections: [],
      endings: [],
      withdrawals: [
        WritingFactWithdrawal(
          factHandle: f.ver(3).value,
          reason: 'Unreliable recollection',
        ),
      ],
    );
    final withdrawn = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base,
      operations: withdrawal.operations,
    );
    expect(withdrawn.where((r) => r.payload is AssertionRecord), isEmpty);
    expect(
      withdrawn.singleWhere((r) => r.identity.recordId == f.id(2)).payload,
      base.singleWhere((r) => r.identity.recordId == f.id(2)).payload,
    );
    expect(
      withdrawal.additions.single,
      contains('without asserting its opposite'),
    );
  });

  test('fact edits reject stale generated duplicate and unresolved handles without weakening canonical bounds', () {
    final base = rows();
    final duplicate = compileWritingFactEdits(
      frame: facts.frame(),
      base: base,
      corrections: [
        WritingCorrection(
          factHandle: f.ver(3).value,
          value: const FactBooleanValue(false),
          reason: 'Correct',
        ),
      ],
      endings: [
        WritingFactEnding(
          factHandle: f.ver(3).value,
          reason: 'End',
          endTick: '15',
        ),
      ],
      withdrawals: [
        WritingFactWithdrawal(factHandle: f.ver(3).value, reason: 'Withdraw'),
      ],
    );
    expect(duplicate.operations, hasLength(2));
    expect(duplicate.clarifications, hasLength(2));
    final denied = compileWritingFactEdits(
      frame: facts.frame(),
      base: base,
      corrections: [
        WritingCorrection(
          factHandle: f.id(3).value,
          value: const FactBooleanValue(false),
          reason: 'Stale',
        ),
        WritingCorrection(
          factHandle: f.ver(3).value,
          value: const FactObjectValue('Absent'),
          reason: 'Missing',
        ),
      ],
      endings: [],
      withdrawals: [
        WritingFactWithdrawal(factHandle: f.ver(3).value, reason: 'Again'),
      ],
    );
    expect(denied.operations, isEmpty);
    expect(denied.clarifications, hasLength(3));
    final generated = f.patch<AssertionRecord>(
      facts.assertion().payload as AssertionRecord,
      {'establishedBy': EventEffectRef(f.ref(70), 'effect_1').toWire()},
    );
    final effects = compileWritingFactEdits(
      frame: facts.frame(),
      base: rows(assertion: generated),
      corrections: [],
      endings: [],
      withdrawals: [
        WritingFactWithdrawal(
          factHandle: f.ver(3).value,
          reason: 'Direct edit',
        ),
      ],
    );
    expect(effects.operations, isEmpty);
    expect(effects.clarifications.single, contains('authored cause'));
    final unresolved = compileWritingFactEdits(
      frame: facts.frame(),
      base: rows(
        assertion:
            facts.assertion(validity: const UnspecifiedValidity()).payload
                as AssertionRecord,
      ),
      corrections: [],
      endings: [
        WritingFactEnding(
          factHandle: f.ver(3).value,
          reason: 'End',
          endTick: '15',
        ),
      ],
      withdrawals: [],
    );
    expect(unresolved.operations, isEmpty);
    expect(
      unresolved.clarifications.single,
      contains('authored calendar interval'),
    );
    expect(
      () => compileWritingFactEdits(
        frame: facts.frame(),
        base: base,
        corrections: [],
        withdrawals: [],
        endings: [
          WritingFactEnding(
            factHandle: f.ver(3).value,
            reason: 'Outside original duration',
            endTick: '21',
          ),
        ],
      ),
      throwsA(isA<InvalidArgumentError>()),
    );
  });
}
