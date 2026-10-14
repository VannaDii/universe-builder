import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'qualifier_draft.dart';

ExpressionReferenceInput _referenceInput(RecordRef reference) =>
    ExpressionReferenceInput(
      record: reference.record.value,
      universe: reference.universe?.value ?? '',
    );
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);

OperandInput operandInput(Operand operand) => switch (operand) {
  VariableOperand(:final name) => OperandInput(
    kind: 'variable',
    name: name,
    original: operand,
  ),
  RecordOperand(:final reference) => OperandInput(
    kind: 'record',
    reference: _referenceInput(reference),
    original: operand,
  ),
  ValueOperand(:final value) => OperandInput(
    kind: 'value',
    value: qualifierInput('value', value),
    original: operand,
  ),
  FrameTimeOperand() => OperandInput(kind: 'frame_time', original: operand),
  EventParticipantOperand(:final role) => OperandInput(
    kind: 'event_participant',
    name: role,
    original: operand,
  ),
  EventRefOperand() => OperandInput(kind: 'event_ref', original: operand),
};
Operand buildOperand(OperandInput input) => switch (input.kind) {
  'variable' => VariableOperand(input.name),
  'record' => RecordOperand(_reference(input.reference)),
  'value' => ValueOperand(
    buildQualifierValue(
      input.value ?? (throw const FormatException('Enter an operand value.')),
      input.original is ValueOperand
          ? (input.original as ValueOperand).value
          : null,
    ),
  ),
  'frame_time' => const FrameTimeOperand(),
  'event_participant' => EventParticipantOperand(input.name),
  'event_ref' => const EventRefOperand(),
  _ => throw const FormatException('Choose an operand kind.'),
};

const _operandKeys = {
  'subject',
  'context',
  'left',
  'right',
  'element',
  'collection',
  'over',
  'participant',
  'value',
};
ExpressionInput expressionInput(Expr expression) {
  final fields = Map.fromEntries(expression.toWire().fields);
  final kind = wireString(fields.remove('kind')!);
  final strings = <String, String>{},
      flags = <String, bool?>{},
      operands = <String, OperandInput>{},
      references = <String, ExpressionReferenceInput>{},
      children = <String, ExpressionInput>{};
  final items = <ExpressionInput>[], roles = <ExpressionRoleInput>[];
  QualifierInput? value;
  for (final entry in fields.entries) {
    final key = entry.key, field = entry.value;
    if (key == 'expr' || key == 'body') {
      children[key] = expressionInput(Expr.fromWire(field));
    } else if (key == 'exprs') {
      items.addAll(
        (field as CanonicalArray).items.map(
          (v) => expressionInput(Expr.fromWire(v)),
        ),
      );
    } else if (key == 'roles') {
      for (final role in (field as CanonicalArray).items) {
        final pair = (role as CanonicalArray).items;
        roles.add(
          ExpressionRoleInput(
            role: wireString(pair[0]),
            operand: operandInput(Operand.fromWire(pair[1])),
          ),
        );
      }
    } else if (key == 'holder' || key == 'proposition') {
      references[key] = _referenceInput(RecordRef.fromCanonical(field));
    } else if (key == 'count') {
      value = qualifierInput('count', DomainValue.fromWire(field));
    } else if (_operandKeys.contains(key) && field is CanonicalObject) {
      operands[key] = operandInput(Operand.fromWire(field));
    } else if (field is CanonicalString) {
      strings[key] = field.value;
    } else if (field is CanonicalBool) {
      flags[key] = field.value;
    } else if (field is CanonicalNull) {
      if (!_operandKeys.contains(key)) flags[key] = null;
    } else {
      throw const FormatException('Unsupported expression input field.');
    }
  }
  return ExpressionInput(
    kind: kind,
    strings: strings,
    flags: flags,
    operands: operands,
    references: references,
    children: children,
    items: items,
    roles: roles,
    value: value,
    original: expression,
  );
}

Expr buildExpression(ExpressionInput input) => Expr.fromWire(
  CanonicalObject([
    MapEntry('kind', CanonicalString(input.kind)),
    for (final entry in input.strings.entries)
      MapEntry(entry.key, CanonicalString(entry.value)),
    for (final entry in input.flags.entries)
      MapEntry(
        entry.key,
        entry.value == null
            ? const CanonicalNull()
            : CanonicalBool(entry.value!),
      ),
    for (final entry in input.operands.entries)
      MapEntry(entry.key, buildOperand(entry.value).toWire()),
    for (final entry in input.references.entries)
      MapEntry(entry.key, _reference(entry.value).toCanonical()),
    for (final entry in input.children.entries)
      MapEntry(entry.key, buildExpression(entry.value).toWire()),
    if (input.kind == 'all' || input.kind == 'any')
      MapEntry(
        'exprs',
        CanonicalArray(input.items.map((e) => buildExpression(e).toWire())),
      ),
    if ({'claim', 'negated_claim', 'existence'}.contains(input.kind))
      MapEntry(
        'roles',
        CanonicalArray(
          input.roles.map(
            (r) => CanonicalArray([
              CanonicalString(r.role),
              buildOperand(r.operand).toWire(),
            ]),
          ),
        ),
      ),
    if (input.value != null)
      MapEntry(
        'count',
        buildQualifierValue(
          input.value!,
          input.original is CardinalityExpr
              ? (input.original as CardinalityExpr).count
              : null,
        ).toWire(),
      ),
  ]),
);
