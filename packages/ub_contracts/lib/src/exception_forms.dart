import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

final class UnfinishedExceptionForm {
  UnfinishedExceptionForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.rule = const ExpressionReferenceInput(),
    this.ruleVersionEnabled = false,
    this.ruleVersion = '',
    this.decision = const ExpressionReferenceInput(),
    this.scope = const ScopeInput(),
    this.validity = const TemporalValidityInput(kind: 'unspecified'),
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, ruleVersion, rationale;
  final ExpressionReferenceInput rule, decision;
  final bool ruleVersionEnabled;
  final ScopeInput scope;
  final TemporalValidityInput validity;
  final ExceptionRecord? original;
  final BigInt? draftVersion;
  UnfinishedExceptionForm copyWith({
    ExpressionReferenceInput? rule,
    bool? ruleVersionEnabled,
    String? ruleVersion,
    ExpressionReferenceInput? decision,
    ScopeInput? scope,
    TemporalValidityInput? validity,
    String? rationale,
  }) => UnfinishedExceptionForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    rule: rule ?? this.rule,
    ruleVersionEnabled: ruleVersionEnabled ?? this.ruleVersionEnabled,
    ruleVersion: ruleVersion ?? this.ruleVersion,
    decision: decision ?? this.decision,
    scope: scope ?? this.scope,
    validity: validity ?? this.validity,
    rationale: rationale ?? this.rationale,
    original: original,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('rule', rule.toWire()),
    MapEntry('rule_version_enabled', CanonicalBool(ruleVersionEnabled)),
    MapEntry('rule_version', CanonicalString(ruleVersion)),
    MapEntry('decision', decision.toWire()),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedExceptionForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'rule',
      'rule_version_enabled',
      'rule_version',
      'decision',
      'scope',
      'validity',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedExceptionForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      rule: ExpressionReferenceInput.fromWire(f.require('rule')),
      ruleVersionEnabled: f.boolean('rule_version_enabled'),
      ruleVersion: f.string('rule_version'),
      decision: ExpressionReferenceInput.fromWire(f.require('decision')),
      scope: ScopeInput.fromWire(f.require('scope')),
      validity: TemporalValidityInput.fromWire(f.require('validity')),
      rationale: f.string('rationale'),
      original: f.optional('original', ExceptionRecord.fromWire),
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

final class SavedExceptionForm {
  SavedExceptionForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedExceptionForm form;
}
