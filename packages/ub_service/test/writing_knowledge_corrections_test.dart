import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as facts;
import 'writing_contexts_test.dart' as contexts;
import 'writing_binding_test.dart' as binding;

final frame = facts.frame();
final otherCalendar = CalendarId.fromRecordId(f.id(11));
CommunicationRecord message({
  TemporalExpression? sent,
  TemporalExpression? received,
  List<RecordRef>? content,
}) => CommunicationRecord(
  sender: f.ref(80),
  intendedRecipients: [f.ref(81)],
  actualRecipients: [f.ref(81)],
  content: content ?? [f.ref(2)],
  channel: 'letter',
  sentAt: sent ?? ExactTime(otherCalendar, '10'),
  receivedAt: received,
  distorted: false,
);
EpistemicAttitudeRecord attitude({
  EpistemicAttitudeKind stance = EpistemicAttitudeKind.believes,
  KnowledgeAcquisition? acquisition,
  Validity? validity,
}) => EpistemicAttitudeRecord(
  acquisition: acquisition,
  holder: f.ref(81),
  proposition: f.ref(2),
  attitude: stance,
  certainty: 'tentative',
  validity:
      validity ??
      CalendarIntervalValidity(
        otherCalendar,
        const ExactBound('10'),
        const ExactBound('100'),
      ),
  basis: const ImportedClaimBasis(),
);
List<RecordVersion> rows({
  CommunicationRecord? communication,
  EpistemicAttitudeRecord? record,
}) => [
  ...contexts.rows(),
  f.row(81, binding.entity(labels: {'en': 'Lena'})),
  ...facts.fixture().take(2),
  f.row(40, communication ?? message()),
  f.row(50, record ?? attitude()),
];
WritingClaim claim(bool value) => WritingClaim(
  subject: 'Mara',
  property: 'open',
  value: FactBooleanValue(value),
);
RecordPayload compiled(
  List<RecordVersion> base,
  List<DomainOperation> operations,
  int id,
) => compileWritingCandidate(
  universe: f.u,
  revision: f.revision,
  base: base,
  operations: operations,
).singleWhere((r) => r.identity.recordId == f.id(id)).payload;
Matcher fails(String text) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  test('historical message corrections retain calendars omitted fields and exact current version', () {
    final base = rows();
    final operations = compileWritingMessageCorrection(
      rows: base,
      frame: frame,
      patch: WritingMessageCorrection(
        messageEditHandle: f.ver(40).value,
        reason: 'Receipt corrected',
        receivedTick: '9007199254740993',
        receivedBy: [],
        distorted: true,
      ),
    );
    final op = operations.single as ReviseCommunicationOperation;
    expect(op.expectedVersion, f.ver(40));
    expect(op.replacement.sender, f.ref(80));
    expect(op.replacement.intendedRecipients, [f.ref(81)]);
    expect(op.replacement.actualRecipients, isEmpty);
    expect(op.replacement.content, [f.ref(2)]);
    expect(op.replacement.channel, 'letter');
    expect(
      op.replacement.receivedAt,
      ExactTime(otherCalendar, '9007199254740993'),
    );
    expect(compiled(base, operations, 40), op.replacement);
    final original = message(received: ExactTime(facts.calendar, '20'));
    final differentClock = compileWritingMessageCorrection(
      rows: rows(communication: original),
      frame: frame,
      patch: WritingMessageCorrection(
        messageEditHandle: f.ver(40).value,
        reason: 'Receipt revised',
        sentTick: '12',
        receivedTick: '22',
      ),
    );
    final replacement =
        (differentClock.single as ReviseCommunicationOperation).replacement;
    expect(replacement.sentAt, ExactTime(otherCalendar, '12'));
    expect(replacement.receivedAt, ExactTime(facts.calendar, '22'));
    final cleared = compileWritingMessageCorrection(
      rows: rows(communication: original),
      frame: frame,
      patch: WritingMessageCorrection(
        messageEditHandle: f.ver(40).value,
        reason: 'Explicit removal',
        clearReceipt: true,
        clearChannel: true,
        to: [],
        claims: [],
      ),
    );
    final clearedRecord =
        (cleared.single as ReviseCommunicationOperation).replacement;
    expect(clearedRecord.receivedAt, isNull);
    expect(clearedRecord.channel, isNull);
    expect(clearedRecord.content, isEmpty);
    expect(clearedRecord.intendedRecipients, isEmpty);
    expect(clearedRecord.actualRecipients, [f.ref(81)]);
  });

  test('message content corrections bind visible claims in the original context only', () {
    final base = rows();
    final ops = compileWritingMessageCorrection(
      rows: base,
      frame: frame,
      patch: WritingMessageCorrection(
        messageEditHandle: f.ver(40).value,
        reason: 'Correct remembered text',
        claims: [claim(false)],
      ),
    );
    expect(ops.first, isA<DefinePropositionOperation>());
    final corrected = compiled(base, ops, 40) as CommunicationRecord;
    expect(corrected.content, [
      (ops.last as ReviseCommunicationOperation).replacement.content.single,
    ]);
    expect(
      (ops.first as DefinePropositionOperation).record.context,
      frame.context,
    );
    final foreign = f.patch<PropositionRecord>(
      base.singleWhere((r) => r.identity.recordId == f.id(2)).payload
          as PropositionRecord,
      {'context': f.ref(98).toCanonical()},
    );
    expect(
      () => compileWritingMessageCorrection(
        rows: [
          for (final row in base)
            row.identity.recordId == f.id(2) ? f.row(2, foreign) : row,
        ],
        frame: frame,
        patch: WritingMessageCorrection(
          messageEditHandle: f.ver(40).value,
          reason: 'Incorrect context',
          claims: [],
        ),
      ),
      fails('original message claim context'),
    );
    for (final patch in [
      WritingMessageCorrection(
        messageEditHandle: f.id(40).value,
        reason: 'Stale',
      ),
      WritingMessageCorrection(
        messageEditHandle: f.ver(40).value,
        reason: 'No change',
      ),
      WritingMessageCorrection(
        messageEditHandle: f.ver(40).value,
        reason: 'Both',
        clearChannel: true,
        channel: 'new',
      ),
      WritingMessageCorrection(
        messageEditHandle: f.ver(40).value,
        reason: 'Both',
        clearReceipt: true,
        receivedTick: '20',
      ),
      WritingMessageCorrection(
        messageEditHandle: f.ver(40).value,
        reason: 'Hidden',
        from: 'Absent',
      ),
    ]) {
      expect(
        () => compileWritingMessageCorrection(
          rows: base,
          frame: frame,
          patch: patch,
        ),
        throwsFormatException,
      );
    }
  });

  test('belief corrections preserve stance identity provenance and exact claim structure', () {
    final base = rows();
    final ops = compileWritingAttitudeCorrection(
      rows: base,
      frame: frame,
      privateKnowledge: false,
      patch: WritingAttitudeCorrection(
        attitudeHandle: f.ver(50).value,
        reason: 'Correct belief',
        value: const FactBooleanValue(false),
        clearCertainty: true,
        atTick: '9007199254740993',
        lifetime: FactUntilLifetime(endTick: '9007199254740995'),
      ),
    );
    final op = ops.last as ReviseAttitudeOperation;
    expect(op.expectedVersion, f.ver(50));
    expect(op.replacement.holder, f.ref(81));
    expect(op.replacement.attitude, EpistemicAttitudeKind.believes);
    expect(op.replacement.basis, attitude().basis);
    expect(op.replacement.certainty, isNull);
    expect(
      op.replacement.validity,
      CalendarIntervalValidity(
        otherCalendar,
        const ExactBound('9007199254740993'),
        const ExactBound('9007199254740995'),
      ),
    );
    final newClaim = (ops.first as DefinePropositionOperation).record;
    expect(newClaim.subject, f.ref(80));
    expect(newClaim.predicate, f.ref(1));
    expect(newClaim.context, frame.context);
    expect(newClaim.quantification, Quantification.particular);
    expect(newClaim.value, const BooleanValue(false));
    expect(compiled(base, ops, 50), op.replacement);
    for (final patch in [
      WritingAttitudeCorrection(
        attitudeHandle: f.ver(50).value,
        reason: 'No change',
      ),
      WritingAttitudeCorrection(
        attitudeHandle: f.ver(50).value,
        reason: 'Both',
        certainty: 'certain',
        clearCertainty: true,
      ),
      WritingAttitudeCorrection(
        attitudeHandle: f.ver(50).value,
        reason: 'Both',
        endTick: '20',
        atTick: '15',
      ),
      WritingAttitudeCorrection(
        attitudeHandle: f.ver(50).value,
        reason: 'Before',
        endTick: '10',
      ),
      WritingAttitudeCorrection(
        attitudeHandle: f.ver(50).value,
        reason: 'After',
        endTick: '101',
      ),
      WritingAttitudeCorrection(
        attitudeHandle: f.ver(50).value,
        reason: 'Overflow',
        endTick: (BigInt.one << 127).toString(),
      ),
    ]) {
      expect(
        () => compileWritingAttitudeCorrection(
          rows: base,
          frame: frame,
          patch: patch,
          privateKnowledge: false,
        ),
        throwsFormatException,
      );
    }
  });

  test('knowledge duration corrections preserve acquisition and respect the private author-established path', () {
    final acquisition = KnowledgeAcquisition(
      truthContext: frame.context,
      time: ExactTime(otherCalendar, '10'),
      basis: const AuthorEstablishedKnowledge(),
    );
    final base = rows(
      record: attitude(
        stance: EpistemicAttitudeKind.knows,
        acquisition: acquisition,
      ),
    );
    final patch = WritingAttitudeCorrection(
      attitudeHandle: f.ver(50).value,
      reason: 'Knowledge ended',
      endTick: '+00020',
    );
    expect(
      () => compileWritingAttitudeCorrection(
        rows: base,
        frame: frame,
        patch: patch,
        privateKnowledge: false,
      ),
      fails('private edit_knowledge'),
    );
    final ops = compileWritingAttitudeCorrection(
      rows: base,
      frame: frame,
      patch: patch,
      privateKnowledge: true,
    );
    final op = ops.single as ReviseAttitudeOperation;
    expect(op.replacement.proposition, f.ref(2));
    expect(op.replacement.certainty, 'tentative');
    expect(op.replacement.acquisition, same(acquisition));
    expect(
      op.replacement.validity,
      CalendarIntervalValidity(
        otherCalendar,
        const ExactBound('10'),
        const ExactBound('20'),
      ),
    );
    expect(compiled(base, ops, 50), op.replacement);
    expect(
      () => compileWritingAttitudeCorrection(
        rows: base,
        frame: frame,
        privateKnowledge: true,
        patch: WritingAttitudeCorrection(
          attitudeHandle: f.ver(50).value,
          reason: 'Substitute',
          value: const FactBooleanValue(false),
        ),
      ),
      fails('preserves claim'),
    );
    expect(
      () => compileWritingAttitudeCorrection(
        rows: rows(),
        frame: frame,
        privateKnowledge: true,
        patch: patch,
      ),
      fails('existing Knows'),
    );
    final receipt = KnowledgeAcquisition(
      truthContext: frame.context,
      time: ExactTime(otherCalendar, '10'),
      basis: CommunicationKnowledge(communication: f.ref(40)),
    );
    expect(
      compileWritingAttitudeCorrection(
        rows: rows(
          record: attitude(
            stance: EpistemicAttitudeKind.knows,
            acquisition: receipt,
          ),
        ),
        frame: frame,
        patch: patch,
        privateKnowledge: false,
      ),
      hasLength(1),
    );
  });

  test('interpretation correction requires existing justified receipt knowledge and explicit selection', () {
    final acquisition = KnowledgeAcquisition(
      truthContext: frame.context,
      time: ExactTime(otherCalendar, '10'),
      basis: CommunicationKnowledge(communication: f.ref(40)),
    );
    final base = rows(
      record: attitude(
        stance: EpistemicAttitudeKind.knows,
        acquisition: acquisition,
      ),
    );
    final ops = compileWritingInterpretationCorrection(
      rows: base,
      frame: frame,
      patch: WritingInterpretationCorrection(
        attitudeHandle: f.ver(50).value,
        reason: 'Correct interpretation',
        interpretation: claim(false),
      ),
    );
    final op = ops.last as ReviseInterpretationOperation;
    expect(op.expectedVersion, f.ver(50));
    final candidate = compiled(base, ops, 50) as EpistemicAttitudeRecord;
    expect(candidate.proposition, op.interpretation);
    expect(candidate.holder, f.ref(81));
    expect(candidate.attitude, EpistemicAttitudeKind.knows);
    expect(candidate.certainty, 'tentative');
    final receipt = candidate.acquisition!.basis as CommunicationKnowledge;
    expect(receipt.communication, f.ref(40));
    expect(receipt.interpretation, op.interpretation);
    expect(candidate.acquisition!.time, acquisition.time);
    final clearing = compileWritingInterpretationCorrection(
      rows: base,
      frame: frame,
      patch: WritingInterpretationCorrection(
        attitudeHandle: f.ver(50).value,
        reason: 'Remove interpretation',
        clearInterpretation: true,
      ),
    );
    expect(
      (clearing.single as ReviseInterpretationOperation).interpretation,
      isNull,
    );
    for (final patch in [
      WritingInterpretationCorrection(
        attitudeHandle: f.id(50).value,
        reason: 'Stale',
        clearInterpretation: true,
      ),
      WritingInterpretationCorrection(
        attitudeHandle: f.ver(50).value,
        reason: 'Neither',
      ),
      WritingInterpretationCorrection(
        attitudeHandle: f.ver(50).value,
        reason: 'Both',
        interpretation: claim(true),
        clearInterpretation: true,
      ),
    ]) {
      expect(
        () => compileWritingInterpretationCorrection(
          rows: base,
          frame: frame,
          patch: patch,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => compileWritingInterpretationCorrection(
        rows: rows(),
        frame: frame,
        patch: WritingInterpretationCorrection(
          attitudeHandle: f.ver(50).value,
          reason: 'No receipt',
          clearInterpretation: true,
        ),
      ),
      fails('No justified receipt'),
    );
  });
}
