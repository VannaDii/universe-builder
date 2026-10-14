import 'package:ub_domain/ub_domain.dart';

import 'expression_forms.dart';
import 'wire.dart';

final class RuleKnowledgeInput {
  const RuleKnowledgeInput({
    this.policyEnabled = false,
    this.boundaryEnabled = false,
    this.mode = '',
    this.policyContext = const ExpressionReferenceInput(),
    this.holder = const ExpressionReferenceInput(),
    this.proposition = const ExpressionReferenceInput(),
    this.boundaryContext = const ExpressionReferenceInput(),
  });
  final bool policyEnabled, boundaryEnabled;
  final String mode;
  final ExpressionReferenceInput policyContext,
      holder,
      proposition,
      boundaryContext;
  RuleKnowledgeInput copyWith({
    bool? policyEnabled,
    bool? boundaryEnabled,
    String? mode,
    ExpressionReferenceInput? policyContext,
    ExpressionReferenceInput? holder,
    ExpressionReferenceInput? proposition,
    ExpressionReferenceInput? boundaryContext,
  }) => RuleKnowledgeInput(
    policyEnabled: policyEnabled ?? this.policyEnabled,
    boundaryEnabled: boundaryEnabled ?? this.boundaryEnabled,
    mode: mode ?? this.mode,
    policyContext: policyContext ?? this.policyContext,
    holder: holder ?? this.holder,
    proposition: proposition ?? this.proposition,
    boundaryContext: boundaryContext ?? this.boundaryContext,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('policy_enabled', CanonicalBool(policyEnabled)),
    MapEntry('boundary_enabled', CanonicalBool(boundaryEnabled)),
    MapEntry('mode', CanonicalString(mode)),
    MapEntry('policy_context', policyContext.toWire()),
    MapEntry('holder', holder.toWire()),
    MapEntry('proposition', proposition.toWire()),
    MapEntry('boundary_context', boundaryContext.toWire()),
  ]);
  factory RuleKnowledgeInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'policy_enabled',
      'boundary_enabled',
      'mode',
      'policy_context',
      'holder',
      'proposition',
      'boundary_context',
    });
    return RuleKnowledgeInput(
      policyEnabled: f.boolean('policy_enabled'),
      boundaryEnabled: f.boolean('boundary_enabled'),
      mode: f.string('mode'),
      policyContext: ExpressionReferenceInput.fromWire(
        f.require('policy_context'),
      ),
      holder: ExpressionReferenceInput.fromWire(f.require('holder')),
      proposition: ExpressionReferenceInput.fromWire(f.require('proposition')),
      boundaryContext: ExpressionReferenceInput.fromWire(
        f.require('boundary_context'),
      ),
    );
  }
}
