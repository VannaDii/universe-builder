import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

final class UnfinishedPropositionForm {
  UnfinishedPropositionForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.subject = const ExpressionReferenceInput(),
    this.predicate = const ExpressionReferenceInput(),
    this.context = const ExpressionReferenceInput(),
    Iterable<PropositionRoleInput> roles = const [],
    this.quantification = '',
    this.hasValue = false,
    this.value = const QualifierInput(kind: 'text'),
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : roles = List.unmodifiable(roles),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, quantification, rationale;
  final ExpressionReferenceInput subject, predicate, context;
  final List<PropositionRoleInput> roles;
  final bool hasValue;
  final QualifierInput value;
  final PropositionRecord? original;
  final BigInt? draftVersion;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('subject', subject.toWire()),
    MapEntry('predicate', predicate.toWire()),
    MapEntry('context', context.toWire()),
    MapEntry('roles', CanonicalArray(roles.map((v) => v.toWire()))),
    MapEntry('quantification', CanonicalString(quantification)),
    MapEntry('has_value', CanonicalBool(hasValue)),
    MapEntry('value', value.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedPropositionForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'subject',
      'predicate',
      'context',
      'roles',
      'quantification',
      'has_value',
      'value',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedPropositionForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      subject: ExpressionReferenceInput.fromWire(f.require('subject')),
      predicate: ExpressionReferenceInput.fromWire(f.require('predicate')),
      context: ExpressionReferenceInput.fromWire(f.require('context')),
      roles: f.array('roles').map(PropositionRoleInput.fromWire),
      quantification: f.string('quantification'),
      hasValue: f.boolean('has_value'),
      value: QualifierInput.fromWire(f.require('value')),
      rationale: f.string('rationale'),
      original: f.optional('original', PropositionRecord.fromWire),
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

final class SavedPropositionForm {
  SavedPropositionForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedPropositionForm form;
}
