import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';

final class UnfinishedSourceForm {
  UnfinishedSourceForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.label = '',
    this.text = '',
    this.rationale = '',
    Iterable<DomainOperation> staged = const [],
  }) : staged = List.unmodifiable(staged);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, label, text, rationale;
  final List<DomainOperation> staged;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('label', CanonicalString(label)),
    MapEntry('text', CanonicalString(text)),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry('staged', CanonicalArray(staged.map((o) => o.toWire()))),
  ]);
  factory UnfinishedSourceForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'label',
      'text',
      'rationale',
      'staged',
    });
    return UnfinishedSourceForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      label: f.string('label'),
      text: f.string('text'),
      rationale: f.string('rationale'),
      staged: f.array('staged').map(DomainOperation.fromWire),
    );
  }
  Iterable<String> get exactTexts => [
    clientRef,
    label,
    text,
    rationale,
    ...staged.map((o) => o.toWire().toText()),
  ];
}

final class SavedSourceForm {
  SavedSourceForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedSourceForm form;
}
