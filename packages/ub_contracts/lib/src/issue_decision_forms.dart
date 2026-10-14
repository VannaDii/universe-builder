import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';

final class UnfinishedIssueDecisionForm {
  UnfinishedIssueDecisionForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    required this.principal,
    this.mode = '',
    Iterable<String> fingerprints = const [],
    this.scope = '',
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : fingerprints = List.unmodifiable(fingerprints),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final PrincipalId principal;
  final String clientRef, mode, scope, rationale;
  final List<String> fingerprints;
  final IssueDecisionRecord? original;
  final BigInt? draftVersion;
  UnfinishedIssueDecisionForm copyWith({
    String? mode,
    List<String>? fingerprints,
    String? scope,
    String? rationale,
  }) => UnfinishedIssueDecisionForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    principal: principal,
    mode: mode ?? this.mode,
    fingerprints: fingerprints ?? this.fingerprints,
    scope: scope ?? this.scope,
    rationale: rationale ?? this.rationale,
    original: original,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('principal', CanonicalString(principal.value)),
    MapEntry('mode', CanonicalString(mode)),
    MapEntry(
      'fingerprints',
      CanonicalArray(fingerprints.map(CanonicalString.new)),
    ),
    MapEntry('scope', CanonicalString(scope)),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedIssueDecisionForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'principal',
      'mode',
      'fingerprints',
      'scope',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedIssueDecisionForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      principal: PrincipalId.parse(f.string('principal')),
      mode: f.string('mode'),
      fingerprints: f.array('fingerprints').map(wireString),
      scope: f.string('scope'),
      rationale: f.string('rationale'),
      original: f.optional('original', IssueDecisionRecord.fromWire),
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

final class SavedIssueDecisionForm {
  SavedIssueDecisionForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedIssueDecisionForm form;
}
