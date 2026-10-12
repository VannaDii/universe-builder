import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' show expandEvents, EventEvaluationError;

import 'context_binding.dart';
import 'consequence_execution.dart';
import 'writing_binding.dart';
import 'writing_candidate.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);
bool _occurred(EventRecord event) =>
    event.occurrence is SimpleOccurrence &&
    (event.occurrence as SimpleOccurrence).kind == OccurrenceKind.occurred;
bool _generatedBy(RecordVersion row, RecordId event) =>
    row.payload is AssertionRecord &&
    (row.payload as AssertionRecord).establishedBy?.event.record == event;
ActionDefinitionRecord? _action(
  List<RecordVersion> rows,
  RecordRef? reference,
) {
  if (reference == null) return null;
  for (final row in rows) {
    if (row.identity.recordId == reference.record &&
        row.payload is ActionDefinitionRecord) {
      return row.payload as ActionDefinitionRecord;
    }
  }
  return null;
}

String _error(ProtocolError error) =>
    WireFields(error.toWire(), {
      'code',
      'field',
      'message',
      'expected',
      'actual',
    }).optional('message', (value) => wireString(value)) ??
    error.code;

/// Edits use admitted pinned handles. Only replacement consequences are derived;
/// unrelated dependent events are never repaired automatically.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> clarifications,
})
compileWritingEventEdits({
  required Frame frame,
  required List<RecordVersion> base,
  required List<WritingEventCorrection> corrections,
  required List<WritingEventWithdrawal> withdrawals,
  List<DomainOperation> priorOperations = const [],
  Set<WorldId>? worldScope,
}) {
  final operations = List<DomainOperation>.of(priorOperations),
      additions = <String>[],
      clarifications = <String>[],
      corrected = <RecordId>{};
  for (final withdrawal in withdrawals) {
    try {
      if (!_nonWhitespace.hasMatch(withdrawal.reason)) {
        throw const FormatException(
          "Explain the author's occurrence withdrawal.",
        );
      }
      final found = base
          .where((r) => r.recordVersionId.value == withdrawal.eventHandle)
          .toList();
      if (found.isEmpty) {
        throw const FormatException(
          'Retrieve the current occurred-event edit handle before withdrawing it; stale, absent or restricted handles cannot be edited.',
        );
      }
      final original = found.first;
      final event = original.payload;
      if (event is! EventRecord) {
        throw const FormatException('Retrieve an occurred-event edit handle.');
      }
      if (!_occurred(event) ||
          !(_action(base, event.action)?.scope.context == frame.context ||
              event.action == null &&
                  event.effects.isNotEmpty &&
                  event.effects.every(
                    (effect) => effect.scope.context == frame.context,
                  ))) {
        throw const FormatException(
          'Retrieve an occurred event in this selected author context.',
        );
      }
      if (!corrected.add(original.identity.recordId)) {
        throw const FormatException(
          'Submit one correction or withdrawal per event in this delta.',
        );
      }
      operations.add(
        WithdrawEventOperation(
          record: RecordRef(
            universe: frame.universe,
            record: original.identity.recordId,
          ),
          expectedVersion: original.recordVersionId,
          rationale: withdrawal.reason,
        ),
      );
      additions.add(
        'Withdraw occurrence support; no non-occurrence or opposite claim asserted; reason: ${withdrawal.reason}',
      );
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
  }
  for (final correction in corrections) {
    try {
      if (!_nonWhitespace.hasMatch(correction.reason)) {
        throw const FormatException("Explain the author's event correction.");
      }
      final found = base
          .where((r) => r.identity.recordId.value == correction.eventHandle)
          .toList();
      if (found.isEmpty) {
        throw const FormatException(
          'Retrieve the pinned occurred event before correcting it.',
        );
      }
      final original = found.first, id = original.identity.recordId;
      if (!corrected.add(id)) {
        throw const FormatException(
          'Submit one incremental correction per event in this delta.',
        );
      }
      final old = original.payload;
      if (old is! EventRecord) {
        throw const FormatException(
          'Correction handle does not select an occurred event.',
        );
      }
      if (!_occurred(old)) {
        throw const FormatException(
          'This ordinary correction path supports occurred events only.',
        );
      }
      final derivationBase = base
          .where((r) => r.identity.recordId != id && !_generatedBy(r, id))
          .toList();
      var rows = compileWritingCandidate(
        universe: frame.universe,
        revision: frame.revision,
        base: derivationBase,
        operations: operations,
      ).toList();
      final originalAction = _action(rows, old.action);
      if (originalAction == null) {
        throw const FormatException(
          'The original event lacks a readable declared action; use explicit advanced correction.',
        );
      }
      final contract = originalAction.consequenceContract;
      if (contract == null) {
        throw const FormatException(
          "The original event's consequences are not contract-derived; use explicit advanced correction.",
        );
      }
      if (old.effects.any(
        (effect) => !contract.slots.any((slot) => slot.slot == effect.slot),
      )) {
        throw const FormatException(
          'Manually authored effects outside the declared contract require explicit advanced correction; none were dropped.',
        );
      }
      final fields = Map<String, CanonicalValue>.fromEntries(
        old.toWire().fields,
      );
      if (correction.action != null) {
        final matches = rows
            .where(
              (r) =>
                  r.payload is ActionDefinitionRecord &&
                  ((r.payload as ActionDefinitionRecord).key ==
                          correction.action ||
                      (r.payload as ActionDefinitionRecord).labels.values
                          .contains(correction.action)),
            )
            .toList();
        if (matches.length != 1) {
          throw FormatException(
            "Which exact authored action is '${correction.action}'? Research its contract before correcting the event.",
          );
        }
        fields['action'] = RecordRef(
          universe: frame.universe,
          record: matches.single.identity.recordId,
        ).toCanonical();
      }
      if (correction.participants != null) {
        final ordered = CanonicalObject(
          correction.participants!.entries.map(
            (e) => MapEntry(e.key, CanonicalString(e.value)),
          ),
        );
        fields['participants'] = CanonicalArray([
          for (final role in ordered.fields)
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
                      "Which exact object fills corrected role '${role.key}' as '${(role.value as CanonicalString).value}'?",
                    )),
              ),
              role.key,
            ).toWire(),
        ]);
      }
      if (correction.atTick != null) {
        final time = old.time;
        if (time is! ExactTime) {
          throw const FormatException(
            "The event's calendar is unresolved; ordinary coordinate correction cannot choose a calendar.",
          );
        }
        fields['time'] = ExactTime(
          time.calendar,
          correction.atTick!,
        ).encode(canonical: false);
      }
      if (correction.world != null) {
        final world = resolveWorldFocus(
          world: Selector(correction.world!),
          guard: null,
          records: rows,
          scope: worldScope,
        )!;
        fields['worlds'] = CanonicalArray([CanonicalString(world.value)]);
      }
      final changes = <DomainOperation>[];
      if (correction.requiresKnowledge != null) {
        final preconditions = old.preconditions
            .where(
              (p) =>
                  p is! AttitudeExpr ||
                  p.attitude != EpistemicAttitudeKind.knows,
            )
            .toList();
        for (final dependency in correction.requiresKnowledge!) {
          final holder =
              resolveWritingObject(rows, dependency.holder, frame) ??
              (throw FormatException(
                "Which exact holder is '${dependency.holder}' ?",
              ));
          final proposition = bindWritingProposition(
            changes,
            frame.universe,
            bindWritingClaim(frame.universe, rows, frame, dependency.claim),
            rows,
          );
          preconditions.add(
            AttitudeExpr(
              RecordRef(universe: frame.universe, record: holder),
              proposition,
              EpistemicAttitudeKind.knows,
            ),
          );
        }
        fields['preconditions'] = CanonicalArray(
          preconditions.map((p) => p.toWire()),
        );
      }
      var replacement = EventRecord.fromWire(CanonicalObject(fields.entries));
      final action = _action(rows, replacement.action);
      if (action == null) {
        throw const FormatException(
          "Retrieve the event's applicable authored action contract.",
        );
      }
      rows.removeWhere((r) => r.identity.recordId == id || _generatedBy(r, id));
      final expanded = expandEvents(rows);
      rows.removeWhere(
        (r) =>
            r.payload is AssertionRecord &&
            (r.payload as AssertionRecord).establishedBy != null,
      );
      for (final entry in expanded.entries) {
        rows.add(
          RecordVersion.build(
            recordVersionId: RecordVersionId.generate(),
            identity: RecordIdentity(
              universeId: frame.universe,
              recordId: entry.key,
              recordKind: RecordKind.assertion,
            ),
            payload: entry.value,
          ),
        );
      }
      fields['effects'] = CanonicalArray([]);
      replacement = EventRecord.fromWire(CanonicalObject(fields.entries));
      final effects = authorActionEffects(
        records: rows,
        eventId: id,
        event: replacement,
        action: action,
        frame: frame,
      );
      for (final effect in effects) {
        changes.add(
          DefinePropositionOperation(
            clientRef: effect.$1.value,
            record: effect.$2,
          ),
        );
      }
      fields['effects'] = CanonicalArray(
        effects.map((effect) => effect.$3.toWire()),
      );
      replacement = EventRecord.fromWire(CanonicalObject(fields.entries));
      changes.add(
        ReviseEventOperation(
          record: RecordRef(universe: frame.universe, record: id),
          expectedVersion: original.recordVersionId,
          replacement: replacement,
        ),
      );
      compileWritingCandidate(
        universe: frame.universe,
        revision: frame.revision,
        base: base,
        operations: [...operations, ...changes],
      );
      operations.addAll(changes);
      additions.add(
        'Occurred event correction: ${correction.eventHandle}; reason ${correction.reason}. Consequences rechecked; dependent events are not automatically repaired.',
      );
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    } on ProtocolError catch (error) {
      clarifications.add(_error(error));
    } on EventEvaluationError catch (error) {
      clarifications.add(error.message);
    }
  }
  return (
    operations: List.unmodifiable(operations.skip(priorOperations.length)),
    additions: List.unmodifiable(additions),
    clarifications: List.unmodifiable(clarifications),
  );
}
