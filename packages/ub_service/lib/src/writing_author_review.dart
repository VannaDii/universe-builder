import 'dart:convert';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'proposal_state.dart';
import 'writing_projection.dart';
import 'writing_contract_projection.dart';

String _debug(Enum value) =>
    '${value.name[0].toUpperCase()}${value.name.substring(1)}';
CanonicalValue _text(String? value) =>
    value == null ? const CanonicalNull() : CanonicalString(value);

/// Presentation uses the retained assignments, never a second compilation.
/// The caller admits the author and exact current proposal before projecting.
List<String> summarizeWritingAuthorReview({
  required StoredProposal stored,
  required List<RecordVersion> originals,
}) {
  final records = {for (final row in originals) row.identity.recordId: row};
  final before = Map<RecordId, RecordVersion>.of(records);
  for (final change in stored.changes) {
    records.remove(change.recordId);
    if (change.next != null) {
      records[change.recordId] = RecordVersion.fromWire(
        change.next!.toCanonical(),
      );
    }
  }
  String? label(RecordId id) {
    final payload = records[id]?.payload;
    if (payload == null) return null;
    return switch (payload) {
      RelationRecord(:final key) || RuleRecord(:final key) => key,
      RealmRecord(:final labels) =>
        labels.isEmpty
            ? null
            : wireString(
                CanonicalObject(
                  labels.entries.map(
                    (e) => MapEntry(e.key, CanonicalString(e.value)),
                  ),
                ).fields.first.value,
              ),
      _ => writingFactLabel(payload),
    };
  }

  String name(RecordRef ref, [String fallback = 'unresolved']) =>
      label(ref.record) ?? fallback;
  String time(Validity value) => plainWritingTime(value.toWire(), label);
  CanonicalValue value(DomainValue v) =>
      plainWritingValue(v, label) ?? const CanonicalNull();
  CanonicalArray participants(PropositionRecord p) => CanonicalArray(
    p.roles.map(
      (r) => CanonicalObject([
        MapEntry('role', CanonicalString(r.role)),
        MapEntry('object', _text(label(r.participant.record))),
      ]),
    ),
  );
  CanonicalValue claim(RecordRef ref) {
    final p = records[ref.record]?.payload;
    if (p is! PropositionRecord) {
      return CanonicalObject([
        MapEntry('unknown_claim', CanonicalString(ref.record.value)),
      ]);
    }
    return CanonicalObject([
      MapEntry('subject', _text(label(p.subject.record))),
      MapEntry('property', _text(label(p.predicate.record))),
      MapEntry(
        'value',
        (p.value == null ? null : plainWritingValue(p.value!, label)) ??
            CanonicalObject([MapEntry('participants', participants(p))]),
      ),
    ]);
  }

  String attitudeClaim(Map<RecordId, RecordVersion> rows, RecordRef ref) {
    final p = rows[ref.record]?.payload;
    if (p is! PropositionRecord) return 'unresolved claim';
    return '${name(p.subject)}.${name(p.predicate)} = ${p.value == null ? 'null' : value(p.value!).toText()}';
  }

  final summary = <String>[];
  final edits = <RecordId>{};
  final operations = stored.proposal.operations;
  for (final op in operations) {
    switch (op) {
      case ReviseCommunicationOperation(
        :final record,
        :final replacement,
        :final rationale,
      ):
        summary.add(
          'Historical message correction: ${name(record, 'message')}; sender ${name(replacement.sender)}; intended recipients ${replacement.intendedRecipients.map((r) => label(r.record)).whereType<String>().join(', ')}; actual recipients ${replacement.actualRecipients.map((r) => label(r.record)).whereType<String>().join(', ')}; sent ${plainWritingTime(replacement.sentAt.encode(canonical: false), label)}; received ${replacement.receivedAt == null ? 'no established receipt' : plainWritingTime(replacement.receivedAt!.encode(canonical: false), label)}; channel ${replacement.channel ?? 'unspecified'}; distortion ${replacement.distorted}; content ${replacement.content.map((r) => claim(r).toText()).join('; ')}; reason: $rationale. Dependent knowledge/actions are rechecked; a later message is a separate declaration.',
        );
      case ReviseInterpretationOperation(
        :final interpretation,
        :final rationale,
      ):
        summary.add(
          'Historical justified interpretation correction: ${interpretation == null ? 'interpretation removed; knowledge may become unsupported' : claim(interpretation).toText()}; holder, message, acquisition time and basis retained; reason: $rationale',
        );
      default:
        break;
    }
  }
  for (final op in operations.whereType<ReviseAttitudeOperation>()) {
    final old = before[op.record.record]?.payload;
    if (old is EpistemicAttitudeRecord) {
      summary.add(
        'Historical attitude correction: ${name(old.holder, 'unresolved holder')} ${_debug(old.attitude)}; original claim ${attitudeClaim(before, old.proposition)}, time ${time(old.validity)}; proposed claim ${attitudeClaim(records, op.replacement.proposition)}, time ${time(op.replacement.validity)}; acquisition and basis retained; reason: ${op.rationale}',
      );
    }
  }
  for (final op in operations.whereType<ReviseItemPowerOperation>()) {
    final old = before[op.record.record]?.payload;
    if (old is ItemPowerRecord) {
      summary.add(
        'Correct item grant: ${name(old.item)} — ${name(old.powerPredicate)}; original value ${value(old.value).toText()}, time ${time(old.validity)}; proposed value ${value(op.replacement.value).toText()}, time ${time(op.replacement.validity)}, scope ${plainWritingScope(op.replacement.scope, label).toText()}; reason: ${op.rationale}',
      );
    }
  }
  for (final op in operations.whereType<WithdrawEventOperation>()) {
    final old = before[op.record.record]?.payload;
    if (old is EventRecord) {
      summary.add(
        'Withdraw occurred event: ${old.action == null ? 'authored occurrence' : name(old.action!, 'authored occurrence')}; time ${plainWritingTime(old.time.encode(canonical: false), label)}; generated effects removed; no non-occurrence asserted; reason: ${op.rationale}',
      );
    }
  }
  for (final op in operations) {
    final target = switch (op) {
      SupersedeAssertionOperation(:final record) ||
      EndAssertionAtOperation(:final record) ||
      RetractAssertionOperation(:final record) => record,
      _ => null,
    };
    if (target == null) continue;
    final old = before[target.record]?.payload;
    if (old is! AssertionRecord) continue;
    edits.add(target.record);
    final original = claim(old.proposition).toText();
    summary.add(switch (op) {
      SupersedeAssertionOperation(:final replacement, :final rationale) =>
        'Correct earlier fact: $original; replacement ${claim(replacement.proposition).toText()}; reason: $rationale',
      EndAssertionAtOperation(:final at) =>
        'End fact duration: $original; end ${plainWritingTime(at.encode(canonical: false), label)}; earlier support remains',
      RetractAssertionOperation(:final rationale) =>
        'Withdraw fact support: $original; no opposite claim asserted; reason: $rationale',
      _ => throw StateError('Not a factual edit'),
    });
  }
  summary.addAll(
    const LineSplitter()
        .convert(stored.proposal.rationale)
        .where((line) => line.startsWith('Proposed fact ending reason:')),
  );
  for (final change in stored.changes) {
    final row = records[change.recordId];
    if (change.next == null || row == null) continue;
    switch (row.payload) {
      case EntityRecord(:final classification, :final names):
        final aliases = names
            .map(
              (n) => CanonicalObject([
                MapEntry('text', CanonicalString(n.text)),
                MapEntry('language', _text(n.language)),
                MapEntry('community', _text(n.community)),
                MapEntry('role', _text(n.role)),
                MapEntry('time', CanonicalString(time(n.validity))),
              ]).toText(),
            )
            .join(', ');
        summary.add(
          'Proposed identity: ${label(row.identity.recordId) ?? row.identity.recordId.value}; classification ${classification == null ? 'unclassified' : label(classification) ?? 'unresolved'}; authored names $aliases',
        );
      case EntityTypeRecord(:final name, :final parent, :final applicability):
        summary.add(
          'Proposed reusable definition: $name; parent ${parent == null ? 'root' : label(parent) ?? 'unresolved'}; applicability ${applicability.toWire().toText()}',
        );
      case AssertionRecord a when !edits.contains(row.identity.recordId):
        final p = records[a.proposition.record]?.payload;
        if (p is PropositionRecord) {
          final v =
              (p.value == null ? null : plainWritingValue(p.value!, label)) ??
              CanonicalObject([MapEntry('participants', participants(p))]);
          summary.add(
            'Proposed fact: ${name(p.subject, p.subject.record.value)} — ${name(p.predicate, p.predicate.record.value)} = ${v.toText()}; mode ${_debug(a.attributeMode)}; polarity ${_debug(a.polarity)}; validity ${time(a.validity)}; scope ${a.scope.applicability.toWire().toText()}',
          );
        }
      case AnchorRecord a:
        summary.add(
          'Exact author source: ${utf8.encode(a.excerpt).length} UTF-8 bytes; digest ${a.excerptDigest}',
        );
      case EventRecord e:
        final wire = Map.fromEntries(e.toWire().fields);
        summary.add(
          'Proposed occurred action: ${e.action == null ? '' : name(e.action!, '')}; time ${wire['time']!.toText()}; participants ${wire['participants']!.toText()}; preconditions ${wire['preconditions']!.toText()}; effects ${wire['effects']!.toText()}. Exact source shares this reviewed editorial commit; no direct event anchor link.',
        );
      case CommunicationRecord c:
        final wire = Map.fromEntries(c.toWire().fields);
        summary.add(
          'Proposed communication: sender ${name(c.sender, '')}; actual recipients ${c.actualRecipients.map((r) => label(r.record)).whereType<String>().join(', ')}; claims ${CanonicalArray(c.content.map(claim)).toText()}; receipt ${(wire['receivedAt'] ?? const CanonicalNull()).toText()}; distorted ${c.distorted}. Content alone is not objective truth; exact source shares this reviewed editorial commit without a direct message anchor link.',
        );
      case EpistemicAttitudeRecord a:
        if (a.basis case AuthorDecisionBasis(:final note)) {
          summary.add(
            'Explicit author knowledge decision: $note; attributed knowledge only, no objective fact asserted',
          );
        }
        summary.add(
          'Proposed attitude: ${name(a.holder, '')} ${_debug(a.attitude)}; claim ${claim(a.proposition).toText()}; acquisition ${a.acquisition?.toWire().toText() ?? 'null'}; validity ${a.validity.toWire().toText()}',
        );
      case UnitRecord d:
        summary.add(
          'Author unit declaration: ${d.key}; dimension ${d.dimension}; symbol ${d.symbol}; no conversion declared',
        );
      case PropertyRecord d:
        summary.add(
          'Proposed property: ${d.key}; values ${_debug(d.multiplicity)}; persistence ${_debug(d.persistence)}',
        );
      case RelationRecord d:
        final roles = d.roles
            .map(
              (r) =>
                  '${r.name} (${_debug(r.multiplicity)}, ordered ${r.ordered}, participant types ${r.participantTypes.isEmpty ? 'unrestricted' : r.participantTypes.map((id) => label(id) ?? 'unresolved').join(', ')})',
            )
            .join(', ');
        summary.add('Author relationship declaration: ${d.key}; roles $roles');
      case RuleRecord d when d.relationCardinality != null:
        final c = d.relationCardinality!;
        summary.add(
          'Author relationship limit: ${d.key}; relationship ${name(c.relation)}; counted role ${c.countedRole}; maximum ${c.maximum}; grouping ${c.grouping.toWire().toText()}; scope ${plainWritingScope(c.scope, label).toText()}; time ${time(c.validity)}',
        );
      case CompletenessRecord c:
        summary.add(
          'Author exhaustive set: ${name(c.subject)}; property ${c.predicate}; members ${c.members.map((m) => name(m)).join(', ')}',
        );
      case ItemPowerRecord p:
        summary.add(
          'Author possession-dependent ability: ${name(p.item)}; holder property ${name(p.holderPredicate)}; ability ${name(p.powerPredicate)}; value ${value(p.value).toText()}; scope ${plainWritingScope(p.scope, label).toText()}; time ${time(p.validity)}. Ownership relations do not establish possession.',
        );
      case ActionDefinitionRecord d:
        summary.add(
          'Author action declaration: ${plainWritingAction(d, label).toText()}',
        );
      case RuleRecord d when d.knowledgeBoundary != null:
        final b = d.knowledgeBoundary!;
        summary.add(
          'Author knowledge boundary: ${d.key}; holder ${name(b.holder)}; cannot know claim ${claim(b.proposition).toText()}; scope ${plainWritingScope(Scope(applicability: d.applicability, context: b.context), label).toText()}; time ${time(d.validity)}; no objective truth or automatic absence outside this period',
        );
      case RuleRecord d when d.knowledgePolicy != null:
        final policy = d.knowledgePolicy!;
        summary.add(
          'Author knowledge policy: ${d.key}; selected context ${name(policy.context, 'selected context')}; mode ${_debug(policy.mode)}; no automatic understanding or objective truth',
        );
      case RuleRecord d when d.channelChronology != null:
        final c = d.channelChronology!;
        summary.add(
          'Author channel policy: ${d.key}; channel ${c.channel}; forward-only ${c.forwardOnly}; minimum delay ${c.minimumDelay == null ? 'None' : 'Some(${CanonicalString(c.minimumDelay!).toText()})'}; maximum delay ${c.maximumDelay == null ? 'None' : 'Some(${CanonicalString(c.maximumDelay!).toText()})'} authored ticks',
        );
      case RuleRecord d:
        final targets = d.targetPredicates
            .map((key) {
              for (final r in records.values) {
                if (r.payload case PropertyRecord p
                    when '${p.namespace}:${p.key}' == key) {
                  return p.key;
                }
              }
              return 'unresolved property';
            })
            .join(', ');
        final scope = plainWritingScope(
          Scope(
            applicability: d.applicability,
            context: stored.proposal.baseFrame.context,
          ),
          label,
        );
        summary.add(
          'Author constraint declaration: ${d.key}; properties $targets; policy ${_debug(d.commitPolicy)}; scope ${scope.toText()}; time ${time(d.validity)}',
        );
      case IssueDecisionRecord d:
        summary.add(
          'Author creative acceptance: ${d.scope}; reason ${d.rationale}',
        );
      default:
        break;
    }
  }
  return List.unmodifiable(summary);
}
