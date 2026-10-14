import 'package:ub_domain/ub_domain.dart';

import 'expression_forms.dart';
import 'wire.dart';

final class UnfinishedPassageForm {
  UnfinishedPassageForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.passageId = '',
    this.edition = const ExpressionReferenceInput(),
    this.editionVersion = '',
    this.anchorEnabled = false,
    this.anchor = const ExpressionReferenceInput(),
    this.rationale = '',
    BigInt? draftVersion,
  }) : draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, passageId, editionVersion, rationale;
  final ExpressionReferenceInput edition, anchor;
  final bool anchorEnabled;
  final BigInt? draftVersion;
  UnfinishedPassageForm copyWith({
    String? passageId,
    ExpressionReferenceInput? edition,
    String? editionVersion,
    bool? anchorEnabled,
    ExpressionReferenceInput? anchor,
    String? rationale,
  }) => UnfinishedPassageForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    passageId: passageId ?? this.passageId,
    edition: edition ?? this.edition,
    editionVersion: editionVersion ?? this.editionVersion,
    anchorEnabled: anchorEnabled ?? this.anchorEnabled,
    anchor: anchor ?? this.anchor,
    rationale: rationale ?? this.rationale,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('passage_id', CanonicalString(passageId)),
    MapEntry('edition', edition.toWire()),
    MapEntry('edition_version', CanonicalString(editionVersion)),
    MapEntry('anchor_enabled', CanonicalBool(anchorEnabled)),
    MapEntry('anchor', anchor.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedPassageForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'passage_id',
      'edition',
      'edition_version',
      'anchor_enabled',
      'anchor',
      'rationale',
      'draft_version',
    });
    return UnfinishedPassageForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      passageId: f.string('passage_id'),
      edition: ExpressionReferenceInput.fromWire(f.require('edition')),
      editionVersion: f.string('edition_version'),
      anchorEnabled: f.boolean('anchor_enabled'),
      anchor: ExpressionReferenceInput.fromWire(f.require('anchor')),
      rationale: f.string('rationale'),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts => [
    clientRef,
    passageId,
    edition.record,
    edition.universe,
    editionVersion,
    anchor.record,
    anchor.universe,
    rationale,
  ];
}

final class SavedPassageForm {
  SavedPassageForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedPassageForm form;
}
