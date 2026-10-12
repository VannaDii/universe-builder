import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'writing_binding.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);
final _limit = BigInt.one << 127;
BigInt? _integer(String value) {
  if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(value)) return null;
  final n = BigInt.parse(value);
  return n >= -_limit && n < _limit ? n : null;
}

RecordVersion _original(
  List<RecordVersion> rows,
  String handle,
  RecordKind kind,
  String message,
) => rows.firstWhere(
  (r) => r.recordVersionId.value == handle && r.payload.recordKind == kind,
  orElse: () => throw FormatException(message),
);
RecordRef _ref(Frame frame, RecordId id) =>
    RecordRef(universe: frame.universe, record: id);
TemporalExpression _changedTime(TemporalExpression original, String tick) {
  if (original is! ExactTime) {
    throw const FormatException(
      'This message time is not an exact authored calendar time; use advanced authoring',
    );
  }
  return ExactTime(original.calendar, tick);
}

/// Inputs have already passed current authority, pinned visibility and authored
/// date normalization. This produces operations without publishing any change.
List<DomainOperation> compileWritingMessageCorrection({
  required List<RecordVersion> rows,
  required Frame frame,
  required WritingMessageCorrection patch,
}) {
  final row = _original(
    rows,
    patch.messageEditHandle,
    RecordKind.communication,
    'Retrieve the current author-visible message_edit_handle before editing',
  );
  final old = row.payload as CommunicationRecord;
  if (!_nonWhitespace.hasMatch(patch.reason)) {
    throw const FormatException('Explain the historical message correction');
  }
  if (patch.clearChannel && patch.channel != null ||
      patch.clearReceipt && patch.receivedTick != null) {
    throw const FormatException(
      'Choose a replacement or explicit removal, not both',
    );
  }
  List<RecordRef> participants(List<String> names) => [
    for (final name in names)
      _ref(
        frame,
        resolveWritingObject(rows, name, frame) ??
            (throw FormatException(
              "Which exact communication participant is '$name'?",
            )),
      ),
  ];
  final operations = <DomainOperation>[];
  var content = old.content;
  if (patch.claims != null) {
    if (old.content.any(
      (id) => !rows.any(
        (r) =>
            r.identity.recordId == id.record &&
            r.payload is PropositionRecord &&
            (r.payload as PropositionRecord).context == frame.context,
      ),
    )) {
      throw const FormatException(
        'Select the original message claim context before editing content',
      );
    }
    content = [
      for (final claim in patch.claims!)
        bindWritingProposition(
          operations,
          frame.universe,
          bindWritingClaim(frame.universe, rows, frame, claim),
          rows,
        ),
    ];
  }
  final replacement = CommunicationRecord(
    sender: patch.from == null
        ? old.sender
        : participants([patch.from!]).single,
    intendedRecipients: patch.to == null
        ? old.intendedRecipients
        : participants(patch.to!),
    actualRecipients: patch.receivedBy == null
        ? old.actualRecipients
        : participants(patch.receivedBy!),
    content: content,
    channel: patch.clearChannel ? null : patch.channel ?? old.channel,
    sentAt: patch.sentTick == null
        ? old.sentAt
        : _changedTime(old.sentAt, patch.sentTick!),
    receivedAt: patch.clearReceipt
        ? null
        : patch.receivedTick == null
        ? old.receivedAt
        : _changedTime(old.receivedAt ?? old.sentAt, patch.receivedTick!),
    distorted: patch.distorted ?? old.distorted,
  );
  if (replacement == old) {
    throw const FormatException(
      'Specify a changed historical message field; a later message is a separate declaration',
    );
  }
  operations.add(
    ReviseCommunicationOperation(
      record: _ref(frame, row.identity.recordId),
      expectedVersion: row.recordVersionId,
      replacement: replacement,
      rationale: patch.reason,
    ),
  );
  return List.unmodifiable(operations);
}

List<DomainOperation> compileWritingInterpretationCorrection({
  required List<RecordVersion> rows,
  required Frame frame,
  required WritingInterpretationCorrection patch,
}) {
  final row = _original(
    rows,
    patch.attitudeHandle,
    RecordKind.epistemicAttitude,
    'Retrieve the current author-visible attitude handle before editing interpretation',
  );
  final old = row.payload as EpistemicAttitudeRecord;
  final acquisition = old.acquisition;
  if (acquisition == null) {
    throw const FormatException('No justified receipt acquisition to correct');
  }
  if (old.attitude != EpistemicAttitudeKind.knows ||
      acquisition.basis is! CommunicationKnowledge ||
      acquisition.truthContext != frame.context) {
    throw const FormatException(
      'Select the original context of existing justified communication-receipt knowledge',
    );
  }
  if (!_nonWhitespace.hasMatch(patch.reason) ||
      patch.clearInterpretation == (patch.interpretation != null)) {
    throw const FormatException(
      'Select an explicit interpretation claim or remove interpretation, and explain the historical correction',
    );
  }
  final operations = <DomainOperation>[];
  final interpretation = patch.interpretation == null
      ? null
      : bindWritingProposition(
          operations,
          frame.universe,
          bindWritingClaim(frame.universe, rows, frame, patch.interpretation!),
          rows,
        );
  operations.add(
    ReviseInterpretationOperation(
      record: _ref(frame, row.identity.recordId),
      expectedVersion: row.recordVersionId,
      interpretation: interpretation,
      rationale: patch.reason,
    ),
  );
  return List.unmodifiable(operations);
}

List<DomainOperation> compileWritingAttitudeCorrection({
  required List<RecordVersion> rows,
  required Frame frame,
  required WritingAttitudeCorrection patch,
  required bool privateKnowledge,
}) {
  final row = _original(
    rows,
    patch.attitudeHandle,
    RecordKind.epistemicAttitude,
    'Retrieve the current author-visible attitude handle before editing it',
  );
  final old = row.payload as EpistemicAttitudeRecord;
  final claims = rows
      .where(
        (r) =>
            r.identity.recordId == old.proposition.record &&
            r.payload is PropositionRecord,
      )
      .toList();
  if (claims.isEmpty) {
    throw const FormatException('Retrieve the original attributed claim');
  }
  final claim = claims.first.payload as PropositionRecord;
  if (claim.context != frame.context) {
    throw const FormatException(
      "Select this attitude's original represented context before editing it",
    );
  }
  if (patch.value != null && claim.value == null) {
    throw const FormatException(
      'Ordinary claim correction supports existing property-value claims only',
    );
  }
  if (!_nonWhitespace.hasMatch(patch.reason)) {
    throw const FormatException(
      'Explain the explicit historical attitude correction or ending',
    );
  }
  if (privateKnowledge && old.attitude != EpistemicAttitudeKind.knows) {
    throw const FormatException(
      'The private knowledge edit requires an existing Knows record',
    );
  }
  if (old.attitude == EpistemicAttitudeKind.knows) {
    if (patch.value != null ||
        patch.certainty != null ||
        patch.clearCertainty) {
      throw const FormatException(
        'Knowledge editing preserves claim, certainty, acquisition and basis; only authored duration can change',
      );
    }
    if (!privateKnowledge &&
        old.acquisition?.basis is AuthorEstablishedKnowledge) {
      throw const FormatException(
        'Author-established knowledge editing requires the explicit private edit_knowledge action with this handle, context, exact source and reason',
      );
    }
  }
  final operations = <DomainOperation>[];
  var proposition = old.proposition;
  if (patch.value != null) {
    final fields = Map<String, CanonicalValue>.fromEntries(
      claim.toWire().fields,
    );
    fields['value'] = bindWritingValue(
      frame.universe,
      rows,
      frame,
      patch.value!,
    ).toWire();
    proposition = bindWritingProposition(
      operations,
      frame.universe,
      PropositionRecord.fromWire(CanonicalObject(fields.entries)),
      rows,
    );
  }
  if (patch.clearCertainty && patch.certainty != null) {
    throw const FormatException(
      'Choose a certainty replacement or explicit removal, not both',
    );
  }
  if (patch.endTick != null &&
      (patch.atTick != null || patch.lifetime != null)) {
    throw const FormatException(
      'Choose an ending or historical duration correction, not both',
    );
  }
  var validity = old.validity;
  if (patch.atTick != null || patch.lifetime != null) {
    final (
      CalendarId calendar,
      TemporalBound oldStart,
      TemporalBound? end,
    ) = switch (old.validity) {
      CalendarIntervalValidity(:final calendar, :final start, :final end) => (
        calendar,
        start,
        end,
      ),
      InstantValidity(at: ExactTime(:final calendar, :final value)) => (
        calendar,
        ExactBound(value),
        null,
      ),
      _ => throw const FormatException(
        'This attitude has no supported exact authored duration; use advanced authoring',
      ),
    };
    final start = patch.atTick == null ? oldStart : ExactBound(patch.atTick!);
    if (patch.lifetime != null) {
      if (start is! ExactBound) {
        throw const FormatException(
          'Supply the unresolved attitude start explicitly',
        );
      }
      validity = bindWritingLifetime(
        ExactTime(calendar, start.value),
        patch.lifetime!,
      );
    } else if (end != null) {
      validity = CalendarIntervalValidity(calendar, start, end);
    } else {
      validity = InstantValidity(
        ExactTime(calendar, (start as ExactBound).value),
      );
    }
  }
  if (patch.endTick != null) {
    if (validity is! CalendarIntervalValidity) {
      throw const FormatException(
        'Ending requires an existing authored attitude interval',
      );
    }
    final tick = _integer(patch.endTick!);
    if (tick == null) {
      throw const FormatException('Invalid signed 128-bit coordinate');
    }
    final start = validity.start, end = validity.end;
    if (start is ExactBound &&
            tick <= (_integer(start.value) ?? (_limit - BigInt.one)) ||
        end is ExactBound && tick > (_integer(end.value) ?? -_limit)) {
      throw const FormatException(
        'End after the original start and no later than the original end',
      );
    }
    validity = CalendarIntervalValidity(
      validity.calendar,
      start,
      ExactBound(tick.toString()),
    );
  }
  final replacement = EpistemicAttitudeRecord(
    acquisition: old.acquisition,
    holder: old.holder,
    proposition: proposition,
    attitude: old.attitude,
    certainty: patch.clearCertainty ? null : patch.certainty ?? old.certainty,
    validity: validity,
    basis: old.basis,
  );
  if (replacement == old) {
    throw const FormatException(
      'Specify changed historical attitude fields; later change or loss needs a separate declaration',
    );
  }
  operations.add(
    ReviseAttitudeOperation(
      record: _ref(frame, row.identity.recordId),
      expectedVersion: row.recordVersionId,
      replacement: replacement,
      rationale: patch.reason,
    ),
  );
  return List.unmodifiable(operations);
}
