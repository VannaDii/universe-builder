import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart' show recordWorld;

import 'consequence_execution.dart';
import 'writing_binding.dart';
import 'writing_candidate.dart';
import 'writing_fact_edits.dart';
import 'writing_knowledge_corrections.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);

/// The caller supplies admitted pinned rows and date-normalized input. Canonical
/// candidate compilation stays authoritative; failed compilation propagates.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> clarifications,
})
compileConnectedWriting({
  required Frame frame,
  required List<RecordVersion> base,
  required CheckChangesRequest input,
  List<DomainOperation> priorOperations = const [],
}) {
  final operations = List<DomainOperation>.of(priorOperations),
      additions = <String>[],
      clarifications = <String>[];
  if (input.events.isEmpty &&
      input.messages.isEmpty &&
      input.attitudes.isEmpty &&
      input.attitudeCorrections.isEmpty &&
      input.messageCorrections.isEmpty &&
      input.interpretationCorrections.isEmpty &&
      input.corrections.isEmpty &&
      input.factEndings.isEmpty &&
      input.factWithdrawals.isEmpty) {
    return (
      operations: const <DomainOperation>[],
      additions: const <String>[],
      clarifications: const <String>[],
    );
  }
  List<RecordVersion> candidate() => compileWritingCandidate(
    universe: frame.universe,
    revision: frame.revision,
    base: base,
    operations: operations,
  );
  var rows = candidate();
  final edited = <String>{};
  for (final patch in input.messageCorrections) {
    if (!edited.add(patch.messageEditHandle)) {
      clarifications.add('Edit each message once per delta');
      continue;
    }
    try {
      operations.addAll(
        compileWritingMessageCorrection(rows: rows, frame: frame, patch: patch),
      );
      additions.add('Historical communication correction: ${patch.reason}');
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
  }
  rows = candidate();
  for (final patch in input.interpretationCorrections) {
    if (!edited.add(patch.attitudeHandle)) {
      clarifications.add('Edit each recorded attitude once per delta');
      continue;
    }
    try {
      operations.addAll(
        compileWritingInterpretationCorrection(
          rows: rows,
          frame: frame,
          patch: patch,
        ),
      );
      additions.add('Historical interpretation correction: ${patch.reason}');
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
  }
  for (final patch in input.attitudeCorrections) {
    if (!edited.add(patch.attitudeHandle)) {
      clarifications.add('Edit each recorded attitude once in a delta');
      continue;
    }
    try {
      operations.addAll(
        compileWritingAttitudeCorrection(
          rows: rows,
          frame: frame,
          patch: patch,
          privateKnowledge: false,
        ),
      );
      additions.add('Historical attitude edit: ${patch.reason}');
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
  }
  rows = candidate();
  final messages = <String, (RecordId, RecordRef, List<String>)>{};
  for (final message in input.messages) {
    (RecordId, CommunicationRecord, RecordRef)? built;
    try {
      if (messages.containsKey(message.label) ||
          !_nonWhitespace.hasMatch(message.label)) {
        throw const FormatException(
          'Communication labels must identify separate depicted messages uniquely',
        );
      }
      RecordRef resolve(String name) => RecordRef(
        universe: frame.universe,
        record:
            resolveWritingObject(rows, name, frame) ??
            (throw FormatException(
              "Which exact communication participant is '$name'?",
            )),
      );
      final sender = resolve(message.from),
          intended = message.to.map(resolve).toList(),
          actual = message.receivedBy.map(resolve).toList();
      if (message.understoodBy.any(
        (name) => !message.receivedBy.contains(name),
      )) {
        throw const FormatException(
          'Who actually received the communication they understood?',
        );
      }
      final prop = bindWritingProposition(
        operations,
        frame.universe,
        bindWritingClaim(frame.universe, rows, frame, message.claim),
        rows,
      );
      final sent = bindWritingTime(frame, rows, message.sentTick);
      final received = actual.isEmpty
          ? null
          : bindWritingTime(frame, rows, message.receivedTick);
      built = (
        RecordId.generate(),
        CommunicationRecord(
          sender: sender,
          intendedRecipients: intended,
          actualRecipients: actual,
          content: [prop],
          channel: message.channel,
          sentAt: sent,
          receivedAt: received,
          distorted: message.distorted,
        ),
        prop,
      );
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
    if (built != null) {
      final (id, record, prop) = built;
      operations.add(
        RecordCommunicationOperation(clientRef: id.value, record: record),
      );
      messages[message.label] = (id, prop, message.understoodBy);
      additions.add(
        "Communication '${message.label}' from ${message.from} (content is not objective truth)",
      );
      rows = candidate();
    }
  }
  for (final attitude in input.attitudes) {
    EpistemicAttitudeRecord? built;
    try {
      final holder = RecordRef(
        universe: frame.universe,
        record:
            resolveWritingObject(rows, attitude.holder, frame) ??
            (throw FormatException(
              "Which exact attitude holder is '${attitude.holder}' ?",
            )),
      );
      final prop = bindWritingProposition(
        operations,
        frame.universe,
        bindWritingClaim(frame.universe, rows, frame, attitude.claim),
        rows,
      );
      final at = bindWritingTime(frame, rows, attitude.atTick);
      final kind = EpistemicAttitudeKind.fromName(attitude.attitude.name);
      KnowledgeAcquisition? acquisition;
      if (kind == EpistemicAttitudeKind.knows) {
        final policies = [
          for (final row in rows)
            if (row.payload case RuleRecord(
              knowledgePolicy: final KnowledgePolicy policy,
            ))
              if (policy.context == frame.context) policy,
        ];
        if (policies.length != 1 ||
            policies.single.mode != KnowledgeMode.justified) {
          throw const FormatException(
            'Knowledge requires the authored justified acquisition policy; author-established knowledge needs a separate explicit author decision',
          );
        }
        final label =
            attitude.message ??
            (throw FormatException(
              "Which actual interpreted communication establishes ${attitude.holder}'s knowledge?",
            ));
        final RecordId message;
        final selected = messages[label];
        if (selected != null) {
          if (!selected.$3.contains(attitude.holder) || selected.$2 != prop) {
            throw FormatException(
              'What claim did ${attitude.holder} actually understand from this communication?',
            );
          }
          message = selected.$1;
        } else {
          final found = rows
              .where((r) => r.identity.recordId.value == label)
              .toList();
          if (found.isEmpty) {
            throw const FormatException(
              'Retrieve the actual communication handle before claiming knowledge',
            );
          }
          final payload = found.first.payload;
          if (payload is! CommunicationRecord) {
            throw const FormatException(
              'Knowledge receipt handle is not a communication',
            );
          }
          if (!payload.content.contains(prop)) {
            throw const FormatException(
              'The claimed interpretation differs from the communication content',
            );
          }
          message = found.first.identity.recordId;
        }
        acquisition = KnowledgeAcquisition(
          truthContext: frame.context,
          time: at,
          basis: CommunicationKnowledge(
            communication: RecordRef(universe: frame.universe, record: message),
            interpretation: prop,
          ),
        );
      }
      built = EpistemicAttitudeRecord(
        holder: holder,
        proposition: prop,
        attitude: kind,
        acquisition: acquisition,
        validity: bindWritingLifetime(at, attitude.lifetime),
        basis: const ImportedClaimBasis(),
      );
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
    if (built != null) {
      operations.add(
        AddBeliefOperation(clientRef: RecordId.generate().value, record: built),
      );
      final kind = attitude.attitude.name;
      additions.add(
        '${attitude.holder}: ${kind[0].toUpperCase()}${kind.substring(1)} (distinct from objective truth)',
      );
      rows = candidate();
    }
  }
  final facts = compileWritingFactEdits(
    frame: frame,
    base: base,
    priorOperations: operations,
    corrections: input.corrections,
    endings: input.factEndings,
    withdrawals: input.factWithdrawals,
  );
  operations.addAll(facts.operations);
  additions.addAll(facts.additions);
  clarifications.addAll(facts.clarifications);
  rows = candidate();
  for (final event in input.events) {
    (RecordId, EventRecord, List<AuthoredConsequence>)? built;
    try {
      final matches = rows
          .where(
            (r) =>
                r.payload is ActionDefinitionRecord &&
                ((r.payload as ActionDefinitionRecord).key == event.action ||
                    (r.payload as ActionDefinitionRecord).labels.values
                        .contains(event.action)),
          )
          .toList();
      if (matches.length != 1) {
        final choices = CanonicalArray([
          for (final row in rows)
            if (row.payload case final ActionDefinitionRecord action)
              if (action.scope.context == frame.context)
                (() {
                  final roles = {
                    for (final r in action.requirements) r.role,
                    for (final s
                        in action.consequenceContract?.slots ?? <EffectSlot>[])
                      s.target.role,
                  };
                  final ordered = CanonicalObject([
                    for (final role in roles)
                      MapEntry(role, const CanonicalNull()),
                  ]);
                  return CanonicalObject([
                    MapEntry('name', CanonicalString(action.key)),
                    MapEntry(
                      'roles',
                      CanonicalArray(
                        ordered.fields.map((e) => CanonicalString(e.key)),
                      ),
                    ),
                  ]);
                })(),
        ]);
        throw FormatException(
          "Which existing authored action contract is '${event.action}' ? Visible authored choices: ${choices.toText()}",
        );
      }
      final selected = matches.single,
          action = selected.payload as ActionDefinitionRecord;
      if (action.scope.context != frame.context || action.scope.realm != null) {
        throw const FormatException(
          'Action contract does not apply to this represented context',
        );
      }
      final roles = CanonicalObject(
        event.participants.entries.map(
          (e) => MapEntry(e.key, CanonicalString(e.value)),
        ),
      );
      final participants = [
        for (final role in roles.fields)
          EventParticipant(
            RecordRef(
              universe: frame.universe,
              record:
                  resolveWritingObject(
                    rows,
                    (role.value as CanonicalString).value,
                    frame,
                  ) ??
                  (throw FormatException(
                    "Which exact object fills action role '${role.key}' as '${(role.value as CanonicalString).value}'?",
                  )),
            ),
            role.key,
          ),
      ];
      final List<WorldId> worlds;
      if (event.world != null) {
        final found = [
          for (final row in rows)
            if (row.payload case WorldRecord(:final selector))
              if (selector == event.world) recordWorld(row.identity.recordId),
        ];
        if (found.length != 1) {
          throw FormatException(
            "Which accessible authored world is '${event.world}'?",
          );
        }
        worlds = found;
      } else {
        worlds = switch (action.scope.applicability) {
          UniverseApplicability() => [],
          WorldsApplicability(:final worldIds) when worldIds.length == 1 =>
            worldIds,
          _ => throw const FormatException(
            'Which authored world does this action occur in?',
          ),
        };
      }
      final id = RecordId.generate();
      final time = bindWritingTime(frame, rows, event.atTick);
      final preconditions = <Expr>[];
      for (final requirement in event.requiresKnowledge) {
        final holder = RecordRef(
          universe: frame.universe,
          record:
              resolveWritingObject(rows, requirement.holder, frame) ??
              (throw FormatException(
                "Which exact knowledge holder is '${requirement.holder}' ?",
              )),
        );
        final prop = bindWritingProposition(
          operations,
          frame.universe,
          bindWritingClaim(frame.universe, rows, frame, requirement.claim),
          rows,
        );
        preconditions.add(
          AttitudeExpr(holder, prop, EpistemicAttitudeKind.knows),
        );
      }
      final record = EventRecord(
        occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
        action: RecordRef(
          universe: frame.universe,
          record: selected.identity.recordId,
        ),
        worlds: worlds,
        time: time,
        participants: participants,
        preconditions: preconditions,
        labels: {},
      );
      final effects = authorActionEffects(
        records: rows,
        eventId: id,
        event: record,
        action: action,
        frame: frame,
      );
      built = (id, record, effects);
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    } on InvalidArgumentError catch (error) {
      clarifications.add(error.message);
    }
    if (built != null) {
      final (id, record, effects) = built;
      for (final effect in effects) {
        operations.add(
          DefinePropositionOperation(
            clientRef: effect.$1.value,
            record: effect.$2,
          ),
        );
      }
      operations.add(
        RecordEventOperation(
          clientRef: id.value,
          record: EventRecord(
            occurrence: record.occurrence,
            action: record.action,
            worlds: record.worlds,
            time: record.time,
            participants: record.participants,
            preconditions: record.preconditions,
            effects: effects.map((e) => e.$3),
            labels: record.labels,
            basis: record.basis,
          ),
        ),
      );
      additions.add(
        'Occurred action: ${event.action} (authored contract consequences)',
      );
      rows = candidate();
    }
  }
  return (
    operations: List.unmodifiable(operations.skip(priorOperations.length)),
    additions: List.unmodifiable(additions),
    clarifications: List.unmodifiable(clarifications),
  );
}
