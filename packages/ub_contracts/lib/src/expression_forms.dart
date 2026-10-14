import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'wire.dart';

final class ExpressionReferenceInput {
  const ExpressionReferenceInput({this.record = '', this.universe = ''});
  final String record, universe;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('record', CanonicalString(record)),
    MapEntry('universe', CanonicalString(universe)),
  ]);
  factory ExpressionReferenceInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'record', 'universe'});
    return ExpressionReferenceInput(
      record: f.string('record'),
      universe: f.string('universe'),
    );
  }
}

final class OperandInput {
  const OperandInput({
    this.kind = '',
    this.name = '',
    this.reference = const ExpressionReferenceInput(),
    this.value,
    this.original,
  });
  final String kind, name;
  final ExpressionReferenceInput reference;
  final QualifierInput? value;
  final Operand? original;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString(kind)),
    MapEntry('name', CanonicalString(name)),
    MapEntry('reference', reference.toWire()),
    if (value != null) MapEntry('value', value!.toWire()),
    if (original != null) MapEntry('original', original!.toWire()),
  ]);
  factory OperandInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'kind',
      'name',
      'reference',
      'value',
      'original',
    });
    return OperandInput(
      kind: f.string('kind'),
      name: f.string('name'),
      reference: ExpressionReferenceInput.fromWire(f.require('reference')),
      value: f.optional('value', QualifierInput.fromWire),
      original: f.optional('original', Operand.fromWire),
    );
  }
}

final class ExpressionRoleInput {
  const ExpressionRoleInput({
    this.role = '',
    this.operand = const OperandInput(),
  });
  final String role;
  final OperandInput operand;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('role', CanonicalString(role)),
    MapEntry('operand', operand.toWire()),
  ]);
  factory ExpressionRoleInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'role', 'operand'});
    return ExpressionRoleInput(
      role: f.string('role'),
      operand: OperandInput.fromWire(f.require('operand')),
    );
  }
}

/// Recoverable inputs for the existing expression grammar; evaluation stays in the service.
final class ExpressionInput {
  ExpressionInput({
    this.kind = '',
    Map<String, String> strings = const {},
    Map<String, bool?> flags = const {},
    Map<String, OperandInput> operands = const {},
    Map<String, ExpressionReferenceInput> references = const {},
    Map<String, ExpressionInput> children = const {},
    Iterable<ExpressionInput> items = const [],
    Iterable<ExpressionRoleInput> roles = const [],
    this.value,
    this.original,
  }) : strings = Map.unmodifiable(strings),
       flags = Map.unmodifiable(flags),
       operands = Map.unmodifiable(operands),
       references = Map.unmodifiable(references),
       children = Map.unmodifiable(children),
       items = List.unmodifiable(items),
       roles = List.unmodifiable(roles);
  final String kind;
  final Map<String, String> strings;
  final Map<String, bool?> flags;
  final Map<String, OperandInput> operands;
  final Map<String, ExpressionReferenceInput> references;
  final Map<String, ExpressionInput> children;
  final List<ExpressionInput> items;
  final List<ExpressionRoleInput> roles;
  final QualifierInput? value;
  final Expr? original;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString(kind)),
    MapEntry(
      'strings',
      CanonicalObject(
        strings.entries.map((e) => MapEntry(e.key, CanonicalString(e.value))),
      ),
    ),
    MapEntry(
      'flags',
      CanonicalObject(
        flags.entries.map(
          (e) => MapEntry(
            e.key,
            e.value == null ? const CanonicalNull() : CanonicalBool(e.value!),
          ),
        ),
      ),
    ),
    MapEntry(
      'operands',
      CanonicalObject(
        operands.entries.map((e) => MapEntry(e.key, e.value.toWire())),
      ),
    ),
    MapEntry(
      'references',
      CanonicalObject(
        references.entries.map((e) => MapEntry(e.key, e.value.toWire())),
      ),
    ),
    MapEntry(
      'children',
      CanonicalObject(
        children.entries.map((e) => MapEntry(e.key, e.value.toWire())),
      ),
    ),
    MapEntry('items', CanonicalArray(items.map((e) => e.toWire()))),
    MapEntry('roles', CanonicalArray(roles.map((e) => e.toWire()))),
    if (value != null) MapEntry('value', value!.toWire()),
    if (original != null) MapEntry('original', original!.toWire()),
  ]);
  factory ExpressionInput.fromWire(CanonicalValue value, {int depth = 0}) {
    if (depth > 128) {
      throw const FormatException('Expression decoding nesting limit');
    }
    final f = WireFields(value, {
      'kind',
      'strings',
      'flags',
      'operands',
      'references',
      'children',
      'items',
      'roles',
      'value',
      'original',
    });
    Map<String, T> map<T>(String key, T Function(CanonicalValue) parse) {
      final value = f.require(key);
      if (value is! CanonicalObject) {
        throw const FormatException('Expected expression inputs');
      }
      return {for (final field in value.fields) field.key: parse(field.value)};
    }

    return ExpressionInput(
      kind: f.string('kind'),
      strings: map('strings', wireString),
      flags: map('flags', (v) {
        if (v is CanonicalNull) return null;
        if (v is CanonicalBool) return v.value;
        throw const FormatException('Expected boolean expression input');
      }),
      operands: map('operands', OperandInput.fromWire),
      references: map('references', ExpressionReferenceInput.fromWire),
      children: map(
        'children',
        (v) => ExpressionInput.fromWire(v, depth: depth + 1),
      ),
      items: f
          .array('items')
          .map((v) => ExpressionInput.fromWire(v, depth: depth + 1)),
      roles: f.array('roles').map(ExpressionRoleInput.fromWire),
      value: f.optional('value', QualifierInput.fromWire),
      original: f.optional('original', Expr.fromWire),
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
