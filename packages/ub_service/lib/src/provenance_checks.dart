import 'package:ub_contracts/ub_contracts.dart' show InvalidArgumentError;
import 'package:ub_domain/ub_domain.dart';

/// Does not trust a writer's verification flag or verify retained source bytes.
void validateProvenanceLinks(
  RecordPayload payload,
  Map<RecordId, RecordPayload> records,
) {
  final basis = switch (payload) {
    AssertionRecord(:final basis) ||
    EpistemicAttitudeRecord(:final basis) ||
    ObservationRecord(:final basis) => basis,
    _ => null,
  };
  final citation = switch (basis) {
    SourceAnchorBasis(:final anchor) => anchor,
    _ => payload is PassageRecord ? payload.anchor : null,
  };
  if (citation != null && records[citation.record] is! AnchorRecord) {
    throw InvalidArgumentError(
      field: 'provenance.anchor',
      message: 'source evidence and passage citations must reference an anchor record',
    );
  }
}
