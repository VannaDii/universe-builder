import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

final class CommitmentPartyInput {
  const CommitmentPartyInput({
    this.record = '',
    this.universe = '',
    this.role = '',
  });
  final String record, universe, role;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('record', CanonicalString(record)),
    MapEntry('universe', CanonicalString(universe)),
    MapEntry('role', CanonicalString(role)),
  ]);
  factory CommitmentPartyInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'record', 'universe', 'role'});
    return CommitmentPartyInput(
      record: f.string('record'),
      universe: f.string('universe'),
      role: f.string('role'),
    );
  }
}

final class UnfinishedCommitmentForm {
  UnfinishedCommitmentForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    Iterable<CommitmentPartyInput> parties = const [],
    this.obligated = const ExpressionReferenceInput(),
    Iterable<ExpressionInput> conditions = const [],
    this.deadlineEnabled = false,
    this.deadline = const TemporalValidityInput(kind: 'instant_unspecified'),
    this.status = '',
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : parties = List.unmodifiable(parties),
       conditions = List.unmodifiable(conditions),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, status, rationale;
  final List<CommitmentPartyInput> parties;
  final ExpressionReferenceInput obligated;
  final List<ExpressionInput> conditions;
  final bool deadlineEnabled;
  final TemporalValidityInput deadline;
  final CommitmentRecord? original;
  final BigInt? draftVersion;
  UnfinishedCommitmentForm copyWith({
    List<CommitmentPartyInput>? parties,
    ExpressionReferenceInput? obligated,
    List<ExpressionInput>? conditions,
    bool? deadlineEnabled,
    TemporalValidityInput? deadline,
    String? status,
    String? rationale,
  }) => UnfinishedCommitmentForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    parties: parties ?? this.parties,
    obligated: obligated ?? this.obligated,
    conditions: conditions ?? this.conditions,
    deadlineEnabled: deadlineEnabled ?? this.deadlineEnabled,
    deadline: deadline ?? this.deadline,
    status: status ?? this.status,
    rationale: rationale ?? this.rationale,
    original: original,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('parties', CanonicalArray(parties.map((p) => p.toWire()))),
    MapEntry('obligated', obligated.toWire()),
    MapEntry('conditions', CanonicalArray(conditions.map((p) => p.toWire()))),
    MapEntry('deadline_enabled', CanonicalBool(deadlineEnabled)),
    MapEntry('deadline', deadline.toWire()),
    MapEntry('status', CanonicalString(status)),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedCommitmentForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'parties',
      'obligated',
      'conditions',
      'deadline_enabled',
      'deadline',
      'status',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedCommitmentForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      parties: f.array('parties').map(CommitmentPartyInput.fromWire),
      obligated: ExpressionReferenceInput.fromWire(f.require('obligated')),
      conditions: f.array('conditions').map(ExpressionInput.fromWire),
      deadlineEnabled: f.boolean('deadline_enabled'),
      deadline: TemporalValidityInput.fromWire(f.require('deadline')),
      status: f.string('status'),
      rationale: f.string('rationale'),
      original: f.optional('original', CommitmentRecord.fromWire),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts => _texts(toWire());
}

Iterable<String> _texts(CanonicalValue value) sync* {
  switch (value) {
    case CanonicalString(:final value):
      yield value;
    case CanonicalArray(:final items):
      for (final item in items) {
        yield* _texts(item);
      }
    case CanonicalObject(:final fields):
      for (final field in fields) {
        yield* _texts(field.value);
      }
    default:
      break;
  }
}

final class SavedCommitmentForm {
  SavedCommitmentForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedCommitmentForm form;
}
