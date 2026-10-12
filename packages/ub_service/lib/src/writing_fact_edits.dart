import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'writing_binding.dart';
import 'writing_candidate.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);

/// Original handles and metadata are pinned to [base]; replacement values bind
/// against the canonical candidate, including preceding operations. No writes.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> clarifications,
})
compileWritingFactEdits({
  required Frame frame,
  required List<RecordVersion> base,
  required List<WritingCorrection> corrections,
  required List<WritingFactEnding> endings,
  required List<WritingFactWithdrawal> withdrawals,
  List<DomainOperation> priorOperations = const [],
}) {
  final operations = List<DomainOperation>.of(priorOperations),
      additions = <String>[],
      clarifications = <String>[],
      edited = <RecordId>{};
  if (corrections.isEmpty && endings.isEmpty && withdrawals.isEmpty) {
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
  void once(RecordId id) {
    if (!edited.add(id)) {
      throw const FormatException(
        'Submit only one correction, ending or withdrawal for each authored fact in a delta.',
      );
    }
  }

  for (final correction in corrections) {
    DomainOperation? operation;
    try {
      if (!_nonWhitespace.hasMatch(correction.reason)) {
        throw const FormatException(
          "A factual correction requires the author's stated reason",
        );
      }
      final (row, old) = bindWritingAuthoredFact(base, correction.factHandle);
      once(row.identity.recordId);
      final claims = base
          .where(
            (r) =>
                r.identity.recordId == old.proposition.record &&
                r.payload is PropositionRecord,
          )
          .toList();
      if (claims.isEmpty) {
        throw const FormatException(
          'Retrieve the original correction proposition',
        );
      }
      final fields = Map<String, CanonicalValue>.fromEntries(
        claims.first.payload.toWire().fields,
      );
      fields['value'] = bindWritingValue(
        frame.universe,
        rows,
        frame,
        correction.value,
      ).toWire();
      final proposition = bindWritingProposition(
        operations,
        frame.universe,
        PropositionRecord.fromWire(CanonicalObject(fields.entries)),
        rows,
      );
      final replacement = Map<String, CanonicalValue>.fromEntries(
        old.toWire().fields,
      );
      replacement['proposition'] = proposition.toCanonical();
      replacement['basis'] = const ImportedClaimBasis().toWire();
      operation = SupersedeAssertionOperation(
        record: RecordRef(
          universe: frame.universe,
          record: row.identity.recordId,
        ),
        expectedVersion: row.recordVersionId,
        replacement: AssertionRecord.fromWire(
          CanonicalObject(replacement.entries),
        ),
        rationale: correction.reason,
      );
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
    if (operation != null) {
      operations.add(operation);
      additions.add(
        'Correction to authored fact ${correction.factHandle} (original scope/time preserved)',
      );
      rows = candidate();
    }
  }
  for (final (handle, reason, tick) in [
    for (final ending in endings)
      (ending.factHandle, ending.reason, ending.endTick),
    for (final withdrawal in withdrawals)
      (withdrawal.factHandle, withdrawal.reason, null),
  ]) {
    DomainOperation? operation;
    try {
      if (!_nonWhitespace.hasMatch(reason)) {
        throw const FormatException(
          "Explain the author's fact ending or withdrawal.",
        );
      }
      final (row, assertion) = bindWritingAuthoredFact(base, handle);
      once(row.identity.recordId);
      final reference = RecordRef(
        universe: frame.universe,
        record: row.identity.recordId,
      );
      if (tick != null) {
        final validity = assertion.validity;
        if (validity is! CalendarIntervalValidity) {
          throw const FormatException(
            'Ending requires an authored calendar interval; use withdrawal or explicit historical correction for other validity.',
          );
        }
        operation = EndAssertionAtOperation(
          record: reference,
          expectedVersion: row.recordVersionId,
          at: ExactTime(validity.calendar, tick),
          basis: const ImportedClaimBasis(),
        );
      } else {
        operation = RetractAssertionOperation(
          record: reference,
          expectedVersion: row.recordVersionId,
          rationale: reason,
        );
      }
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
    if (operation != null) {
      operations.add(operation);
      additions.add(
        tick != null
            ? 'Authored fact ends at $tick: $reason'
            : 'Authored fact support withdrawn, without asserting its opposite: $reason',
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
