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
    this.anchorSource,
    BigInt? draftVersion,
  }) : staged = List.unmodifiable(staged),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, label, text, rationale;
  final List<DomainOperation> staged;
  final VersionRef? anchorSource;
  final BigInt? draftVersion;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('label', CanonicalString(label)),
    MapEntry('text', CanonicalString(text)),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry('staged', CanonicalArray(staged.map((o) => o.toWire()))),
    if (anchorSource != null)
      MapEntry('anchor_source', anchorSource!.toCanonical()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
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
      'anchor_source',
      'draft_version',
    });
    return UnfinishedSourceForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      label: f.string('label'),
      text: f.string('text'),
      rationale: f.string('rationale'),
      staged: f.array('staged').map(DomainOperation.fromWire),
      anchorSource: f.optional('anchor_source', VersionRef.fromCanonical),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
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
