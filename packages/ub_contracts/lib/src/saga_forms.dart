import 'package:ub_domain/ub_domain.dart';

import 'expression_forms.dart';
import 'property_forms.dart';
import 'wire.dart';

final class SagaMembershipInput {
  const SagaMembershipInput({
    this.work = const ExpressionReferenceInput(),
    this.role = '',
    this.orderEnabled = false,
    this.order = '',
  });
  final ExpressionReferenceInput work;
  final String role, order;
  final bool orderEnabled;
  SagaMembershipInput copyWith({
    ExpressionReferenceInput? work,
    String? role,
    bool? orderEnabled,
    String? order,
  }) => SagaMembershipInput(
    work: work ?? this.work,
    role: role ?? this.role,
    orderEnabled: orderEnabled ?? this.orderEnabled,
    order: order ?? this.order,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('work', work.toWire()),
    MapEntry('role', CanonicalString(role)),
    MapEntry('order_enabled', CanonicalBool(orderEnabled)),
    MapEntry('order', CanonicalString(order)),
  ]);
  factory SagaMembershipInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'work', 'role', 'order_enabled', 'order'});
    return SagaMembershipInput(
      work: ExpressionReferenceInput.fromWire(f.require('work')),
      role: f.string('role'),
      orderEnabled: f.boolean('order_enabled'),
      order: f.string('order'),
    );
  }
}

final class UnfinishedSagaForm {
  UnfinishedSagaForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.title = '',
    Iterable<PropertyLabelInput> labels = const [],
    Iterable<SagaMembershipInput> memberships = const [],
    this.rationale = '',
    BigInt? draftVersion,
  }) : labels = List.unmodifiable(labels),
       memberships = List.unmodifiable(memberships),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, title, rationale;
  final List<PropertyLabelInput> labels;
  final List<SagaMembershipInput> memberships;
  final BigInt? draftVersion;
  UnfinishedSagaForm copyWith({
    String? title,
    List<PropertyLabelInput>? labels,
    List<SagaMembershipInput>? memberships,
    String? rationale,
  }) => UnfinishedSagaForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    title: title ?? this.title,
    labels: labels ?? this.labels,
    memberships: memberships ?? this.memberships,
    rationale: rationale ?? this.rationale,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('title', CanonicalString(title)),
    MapEntry('labels', CanonicalArray(labels.map((e) => e.toWire()))),
    MapEntry('memberships', CanonicalArray(memberships.map((e) => e.toWire()))),
    MapEntry('rationale', CanonicalString(rationale)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedSagaForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'title',
      'labels',
      'memberships',
      'rationale',
      'draft_version',
    });
    return UnfinishedSagaForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      title: f.string('title'),
      labels: f.array('labels').map(PropertyLabelInput.fromWire),
      memberships: f.array('memberships').map(SagaMembershipInput.fromWire),
      rationale: f.string('rationale'),
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

final class SavedSagaForm {
  SavedSagaForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedSagaForm form;
}
