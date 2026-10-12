import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as facts;
import 'writing_contexts_test.dart' as contexts;
import 'writing_binding_test.dart' as binding;
import 'knowledge_checks_test.dart' as knowledge;
import 'communication_checks_test.dart' as channels;
import 'action_checks_test.dart' as actions;
import 'consequence_execution_test.dart' as consequences;

CheckChangesRequest delta({
  List<WritingMessage> messages = const [],
  List<WritingAttitude> attitudes = const [],
  List<WritingEvent> events = const [],
  List<WritingMessageCorrection> messagesEdited = const [],
  List<WritingInterpretationCorrection> interpretations = const [],
  List<WritingAttitudeCorrection> attitudesEdited = const [],
  List<WritingCorrection> corrections = const [],
}) => CheckChangesRequest(
  universe: const Selector('Test'),
  contextId: ContextId.generate(),
  messages: messages,
  attitudes: attitudes,
  events: events,
  messageCorrections: messagesEdited,
  interpretationCorrections: interpretations,
  attitudeCorrections: attitudesEdited,
  corrections: corrections,
);
WritingClaim claim({bool value = true}) => WritingClaim(
  subject: 'Mara',
  property: 'open',
  value: FactBooleanValue(value),
);
List<RecordVersion> rows() => [
  ...contexts.rows(),
  f.row(81, binding.entity(labels: {'en': 'Lena'})),
  ...facts.fixture().take(3),
  f.row(30, knowledge.policy()),
  f.row(31, channels.policy()),
];
WritingMessage message({
  String label = 'Warning',
  List<String> received = const ['Lena'],
  List<String> understood = const ['Lena'],
  bool value = true,
  bool distorted = false,
}) => WritingMessage(
  label: label,
  from: 'Mara',
  to: ['Lena'],
  receivedBy: received,
  understoodBy: understood,
  claim: claim(value: value),
  channel: 'speech',
  sentTick: '10',
  receivedTick: '11',
  distorted: distorted,
);
WritingAttitude attitude({
  WritingAttitudeKind kind = WritingAttitudeKind.knows,
  String? message = 'Warning',
  bool value = true,
}) => WritingAttitude(
  holder: 'Lena',
  claim: claim(value: value),
  attitude: kind,
  message: message,
  atTick: '12',
);
List<RecordVersion> candidate(
  List<RecordVersion> base,
  List<DomainOperation> operations, {
  Frame? frame,
}) => compileWritingCandidate(
  universe: f.u,
  revision: (frame ?? facts.frame()).revision,
  base: base,
  operations: operations,
);
List<RecordVersion> eventRows({ActionDefinitionRecord? contract}) {
  final base = consequences.fixture();
  actions.edit(base, 1, {
    'labels': CanonicalObject([MapEntry('en', CanonicalString('Actor'))]),
  });
  actions.edit(base, 2, {
    'value': const SimpleValueShape(SimpleShapeKind.integer).toWire(),
  });
  actions.edit(base, 3, {'value': const IntegerValue('5').toWire()});
  actions.edit(base, 4, {
    'validity': CalendarIntervalValidity(
      actions.cal,
      const ExactBound('10'),
      const ExactBound('11'),
    ).toWire(),
  });
  actions.edit(
    base,
    5,
    (contract ?? consequences.action(consequences.delta('-2')))
        .toWire()
        .fields
        .fold(<String, CanonicalValue>{}, (map, e) => map..[e.key] = e.value),
  );
  final clock = FictionalUniverseStart(
    calendarName: 'Action time',
    initialTick: '10',
    tickLabel: 'ticks',
  ).build(actions.cal);
  return [
    ...base,
    f.row(9, clock.$2),
    f.row(
      10,
      RepresentedContextRecord(
        universe: f.u,
        kind: const ObjectiveContext(),
        chronology: clock.$1,
        labels: {'en': 'Action context'},
      ),
    ),
  ];
}

void main() {
  test('messages and attributed attitudes stay distinct from objective truth and justified checks remain authoritative', () {
    final base = rows();
    final result = compileConnectedWriting(
      frame: facts.frame(),
      base: base,
      input: delta(
        messages: [message()],
        attitudes: [
          attitude(),
          attitude(kind: WritingAttitudeKind.believes, value: false),
        ],
      ),
    );
    expect(result.clarifications, isEmpty);
    final compiled = candidate(base, result.operations);
    expect(compiled.where((r) => r.payload is AssertionRecord), hasLength(1));
    final communication = compiled.singleWhere(
      (r) => r.payload is CommunicationRecord,
    );
    final known =
        compiled
                .singleWhere(
                  (r) =>
                      r.payload is EpistemicAttitudeRecord &&
                      (r.payload as EpistemicAttitudeRecord).attitude ==
                          EpistemicAttitudeKind.knows,
                )
                .payload
            as EpistemicAttitudeRecord;
    final acquisition = known.acquisition!;
    expect(
      (acquisition.basis as CommunicationKnowledge).communication.record,
      communication.identity.recordId,
    );
    expect(acquisition.truthContext, facts.frame().context);
    expect(
      assessKnowledgeAcquisition(compiled, facts.frame()).single.outcome,
      EvidenceOutcome.supported,
    );
    final distorted = compileConnectedWriting(
      frame: facts.frame(),
      base: base,
      input: delta(
        messages: [message(distorted: true)],
        attitudes: [attitude()],
      ),
    );
    expect(distorted.clarifications, isEmpty);
    expect(
      assessKnowledgeAcquisition(
        candidate(base, distorted.operations),
        facts.frame(),
      ).single.outcome,
      EvidenceOutcome.notEstablished,
    );
  });

  test('knowledge declarations require explicit actual understanding and uniquely authored justified policy', () {
    final base = rows();
    final invalid = compileConnectedWriting(
      frame: facts.frame(),
      base: base,
      input: delta(
        messages: [
          message(understood: []),
          message(),
        ],
        attitudes: [attitude(), attitude(message: null)],
      ),
    );
    expect(invalid.clarifications, hasLength(3));
    expect(invalid.operations.whereType<AddBeliefOperation>(), isEmpty);
    final missing = compileConnectedWriting(
      frame: facts.frame(),
      base: base.where((r) => r.identity.recordId != f.id(30)).toList(),
      input: delta(attitudes: [attitude()]),
    );
    expect(
      missing.clarifications.single,
      contains('justified acquisition policy'),
    );
    final notReceived = compileConnectedWriting(
      frame: facts.frame(),
      base: base,
      input: delta(messages: [message(received: [])]),
    );
    expect(notReceived.clarifications.single, contains('actually received'));
    final sentOnly = compileConnectedWriting(
      frame: facts.frame(),
      base: base,
      input: delta(
        messages: [message(received: [], understood: [])],
      ),
    );
    final record =
        (sentOnly.operations.single as RecordCommunicationOperation).record;
    expect(record.intendedRecipients, [f.ref(81)]);
    expect(record.actualRecipients, isEmpty);
    expect(record.receivedAt, isNull);
    final declared = compileConnectedWriting(
      frame: facts.frame(),
      base: base,
      input: delta(messages: [message()], attitudes: [attitude(value: false)]),
    );
    expect(declared.clarifications.single, contains('actually understand'));
  });

  test('existing communication identity handles can support explicit acquisition but version handles cannot', () {
    final base = rows();
    final original = f.row(
      40,
      CommunicationRecord(
        sender: f.ref(80),
        intendedRecipients: [f.ref(81)],
        actualRecipients: [f.ref(81)],
        content: [f.ref(2)],
        channel: 'speech',
        sentAt: ExactTime(facts.calendar, '10'),
        receivedAt: ExactTime(facts.calendar, '11'),
        distorted: false,
      ),
    );
    final result = compileConnectedWriting(
      frame: facts.frame(),
      base: [...base, original],
      input: delta(attitudes: [attitude(message: f.id(40).value)]),
    );
    expect(result.clarifications, isEmpty);
    expect(
      assessKnowledgeAcquisition(
        candidate([...base, original], result.operations),
        facts.frame(),
      ).single.outcome,
      EvidenceOutcome.supported,
    );
    final stale = compileConnectedWriting(
      frame: facts.frame(),
      base: [...base, original],
      input: delta(attitudes: [attitude(message: f.ver(40).value)]),
    );
    expect(
      stale.clarifications.single,
      contains('actual communication handle'),
    );
  });

  test('correction groups share edit guards and refresh candidates before later declarations', () {
    final base = rows();
    final original = f.row(
      40,
      CommunicationRecord(
        sender: f.ref(80),
        intendedRecipients: [f.ref(81)],
        actualRecipients: [f.ref(81)],
        content: [f.ref(2)],
        channel: 'speech',
        sentAt: ExactTime(facts.calendar, '10'),
        receivedAt: ExactTime(facts.calendar, '11'),
        distorted: false,
      ),
    );
    final recorded = f.row(
      50,
      EpistemicAttitudeRecord(
        holder: f.ref(81),
        proposition: f.ref(2),
        attitude: EpistemicAttitudeKind.knows,
        validity: InstantValidity(ExactTime(facts.calendar, '12')),
        acquisition: KnowledgeAcquisition(
          truthContext: facts.frame().context,
          time: ExactTime(facts.calendar, '12'),
          basis: CommunicationKnowledge(
            communication: f.ref(40),
            interpretation: f.ref(2),
          ),
        ),
        basis: const ImportedClaimBasis(),
      ),
    );
    final result = compileConnectedWriting(
      frame: facts.frame(),
      base: [...base, original, recorded],
      input: delta(
        messagesEdited: [
          WritingMessageCorrection(
            messageEditHandle: f.ver(40).value,
            reason: 'Correct content',
            claims: [claim(value: false)],
          ),
          WritingMessageCorrection(
            messageEditHandle: f.ver(40).value,
            reason: 'Duplicate',
            clearChannel: true,
          ),
        ],
        interpretations: [
          WritingInterpretationCorrection(
            attitudeHandle: f.ver(50).value,
            reason: 'Correct interpretation',
            interpretation: claim(value: false),
          ),
        ],
        attitudesEdited: [
          WritingAttitudeCorrection(
            attitudeHandle: f.ver(50).value,
            reason: 'Conflicting correction',
            endTick: '13',
          ),
        ],
        attitudes: [attitude(message: f.id(40).value, value: false)],
      ),
    );
    expect(result.clarifications, hasLength(2));
    expect(
      result.operations.whereType<ReviseCommunicationOperation>(),
      hasLength(1),
    );
    expect(
      result.operations.whereType<ReviseInterpretationOperation>(),
      hasLength(1),
    );
    expect(result.operations.whereType<AddBeliefOperation>(), hasLength(1));
    expect(result.operations.whereType<ReviseAttitudeOperation>(), isEmpty);
  });

  test('sequential occurred actions use generated balances and explicit knowledge preconditions', () {
    final base = eventRows();
    final result = compileConnectedWriting(
      frame: actions.frame,
      base: base,
      input: delta(
        events: [
          WritingEvent(
            action: 'charged_action',
            participants: {'actor': 'Actor'},
            atTick: '11',
          ),
          WritingEvent(
            action: 'charged_action',
            participants: {'actor': 'Actor'},
            atTick: '12',
          ),
        ],
      ),
    );
    expect(result.clarifications, isEmpty);
    final effects = result.operations
        .whereType<DefinePropositionOperation>()
        .map((op) => op.record.value)
        .toList();
    expect(effects, [const IntegerValue('3'), const IntegerValue('1')]);
    final compiled = candidate(base, result.operations, frame: actions.frame);
    expect(compiled.where((r) => r.payload is EventRecord), hasLength(2));
    expect(
      compiled.where(
        (r) =>
            r.payload is AssertionRecord &&
            (r.payload as AssertionRecord).establishedBy != null,
      ),
      hasLength(2),
    );
    final guarded = compileConnectedWriting(
      frame: actions.frame,
      base: base,
      input: delta(
        events: [
          WritingEvent(
            action: 'charged_action',
            participants: {'actor': 'Actor'},
            atTick: '11',
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
      ),
    );
    expect(guarded.clarifications, isEmpty);
    final event = guarded.operations
        .whereType<RecordEventOperation>()
        .single
        .record;
    final precondition = event.preconditions.single as AttitudeExpr;
    expect(precondition.holder, f.ref(1));
    expect(precondition.attitude, EpistemicAttitudeKind.knows);
    expect(guarded.operations.whereType<AddBeliefOperation>(), isEmpty);
  });

  test('action declarations clarify unresolved contracts participants time and optional consequences', () {
    final base = eventRows();
    final result = compileConnectedWriting(
      frame: actions.frame,
      base: base,
      input: delta(
        events: [
          WritingEvent(action: 'Absent', participants: {}, atTick: '11'),
          WritingEvent(
            action: 'charged_action',
            participants: {'actor': 'Hidden'},
            atTick: '11',
          ),
          WritingEvent(
            action: 'charged_action',
            participants: {'actor': 'Actor'},
          ),
          WritingEvent(
            action: 'charged_action',
            participants: {'actor': 'Actor'},
            atTick: '11',
            world: 'Unknown',
          ),
        ],
      ),
    );
    expect(result.operations, isEmpty);
    expect(result.clarifications, hasLength(4));
    expect(result.clarifications.first, contains('Visible authored choices'));
    final optional = compileConnectedWriting(
      frame: actions.frame,
      base: eventRows(
        contract: consequences.action(
          consequences.delta('-2'),
          presence: EffectPresence.optional,
        ),
      ),
      input: delta(
        events: [
          WritingEvent(
            action: 'charged_action',
            participants: {'actor': 'Actor'},
            atTick: '11',
          ),
        ],
      ),
    );
    expect(optional.operations, isEmpty);
    expect(
      optional.clarifications.single,
      contains('optional action consequences'),
    );
    final empty = compileConnectedWriting(
      frame: actions.frame,
      base: [],
      input: delta(),
      priorOperations: [
        ReviseAttitudeOperation(
          record: f.ref(50),
          expectedVersion: f.ver(50),
          replacement: knowledge.attitude(),
          rationale: 'Not evaluated by an empty group',
        ),
      ],
    );
    expect(empty.operations, isEmpty);
  });
}
