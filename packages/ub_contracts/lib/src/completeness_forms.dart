import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

final class UnfinishedCompletenessForm {
  UnfinishedCompletenessForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.subject = const ExpressionReferenceInput(),
    this.predicate = '',
    Iterable<ExpressionReferenceInput> members = const [],
    this.kind = '',
    this.observer = '',
    this.scope = const ScopeInput(),
    this.validity = const TemporalValidityInput(kind: 'unspecified'),
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : members = List.unmodifiable(members),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, predicate, kind, observer, rationale;
  final ExpressionReferenceInput subject;
  final List<ExpressionReferenceInput> members;
  final ScopeInput scope;
  final TemporalValidityInput validity;
  final CompletenessRecord? original;
  final BigInt? draftVersion;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('subject', subject.toWire()),
    MapEntry('predicate', CanonicalString(predicate)),
    MapEntry('members', CanonicalArray(members.map((v) => v.toWire()))),
    MapEntry('kind', CanonicalString(kind)),
    MapEntry('observer', CanonicalString(observer)),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedCompletenessForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'subject',
      'predicate',
      'members',
      'kind',
      'observer',
      'scope',
      'validity',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedCompletenessForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      subject: ExpressionReferenceInput.fromWire(f.require('subject')),
      predicate: f.string('predicate'),
      members: f.array('members').map(ExpressionReferenceInput.fromWire),
      kind: f.string('kind'),
      observer: f.string('observer'),
      scope: ScopeInput.fromWire(f.require('scope')),
      validity: TemporalValidityInput.fromWire(f.require('validity')),
      rationale: f.string('rationale'),
      original: f.optional('original', CompletenessRecord.fromWire),
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

final class SavedCompletenessForm {
  SavedCompletenessForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedCompletenessForm form;
}
