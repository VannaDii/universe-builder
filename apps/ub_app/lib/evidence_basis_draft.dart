import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

EvidenceBasisInput evidenceBasisInput(EvidenceBasis basis) => switch (basis) {
  AuthorDecisionBasis(:final note) => EvidenceBasisInput(
    kind: 'author_decision',
    note: note,
  ),
  SourceAnchorBasis(:final anchor, :final verified) => EvidenceBasisInput(
    kind: 'source_anchor',
    anchorRecord: anchor.record.value,
    anchorUniverse: anchor.universe?.value ?? '',
    verified: verified,
  ),
  ImportedClaimBasis() => const EvidenceBasisInput(kind: 'imported_claim'),
  _ => const EvidenceBasisInput(),
};

EvidenceBasis buildEvidenceBasis(
  EvidenceBasisInput input,
  EvidenceBasis original,
) => switch (input.kind) {
  'retain' => original,
  'author_decision' => AuthorDecisionBasis(input.note),
  'source_anchor' => SourceAnchorBasis(
    RecordRef(
      record: RecordId.parse(input.anchorRecord),
      universe: input.anchorUniverse.isEmpty
          ? null
          : UniverseId.parse(input.anchorUniverse),
    ),
    input.verified,
  ),
  'imported_claim' => const ImportedClaimBasis(),
  _ => throw const FormatException('Choose an authored source basis.'),
};
