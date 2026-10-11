import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';

/// Transient storage boundary. This is not the application payload model or a
/// grant to publish; the service's typed records encode into this closed form.
final class StoredVersion {
  const StoredVersion({
    required this.versionId,
    required this.identity,
    required this.payload,
    required this.digest,
  });
  final RecordVersionId versionId;
  final RecordIdentity identity;
  final CanonicalValue payload;
  final String digest;

  factory StoredVersion.build(
    RecordVersionId id,
    RecordIdentity identity,
    CanonicalValue payload,
  ) {
    final result = StoredVersion(
      versionId: id,
      identity: identity,
      payload: payload,
      digest: payloadDigest(identity.recordKind.wireName, payload),
    );
    result.verify();
    return result;
  }

  void verify() {
    final kind = objectFields(payload)['record_kind'];
    if (kind is! CanonicalString ||
        kind.value != identity.recordKind.wireName ||
        !BodyCatalog.instance.fits('Payload', payload) ||
        payload.toText() !=
            CanonicalValue.parseJson(payload.toText()).toText() ||
        digest != payloadDigest(identity.recordKind.wireName, payload)) {
      throw const FormatException('Record kind, body or digest mismatch');
    }
  }

  CanonicalObject toCanonical() => CanonicalObject([
    MapEntry('record_version_id', CanonicalString(versionId.value)),
    MapEntry('identity', identity.toCanonical()),
    MapEntry('payload', payload),
    MapEntry('payload_digest', CanonicalString(digest)),
  ]);
}

final class Assignment {
  const Assignment({required this.recordId, this.expected, this.next});
  final RecordId recordId;
  final RecordVersionId? expected;
  final StoredVersion? next;
  CanonicalObject toCanonical() => CanonicalObject([
    MapEntry('record_id', CanonicalString(recordId.value)),
    MapEntry(
      'expected',
      expected == null
          ? const CanonicalNull()
          : CanonicalString(expected!.value),
    ),
    MapEntry('next', next?.toCanonical() ?? const CanonicalNull()),
  ]);
}

/// Exact Rust CommitInput serialization, including explicit nullable assignment
/// fields and authored change order. No approval or authority is inferred here.
final class CommitInput {
  CommitInput({
    required this.universe,
    required this.continuity,
    required this.expectedHead,
    required this.principal,
    required this.decision,
    required this.reason,
    required this.idempotencyKey,
    required Iterable<Assignment> changes,
  }) : changes = List.unmodifiable(changes);
  final UniverseId universe;
  final ContinuityId continuity;
  final RevisionId expectedHead;
  final PrincipalId principal;
  final String decision;
  final String reason;
  final String idempotencyKey;
  final List<Assignment> changes;
  CanonicalObject toCanonical() => CanonicalObject([
    MapEntry('universe', CanonicalString(universe.value)),
    MapEntry('continuity', CanonicalString(continuity.value)),
    MapEntry('expected_head', CanonicalString(expectedHead.value)),
    MapEntry('principal', CanonicalString(principal.value)),
    MapEntry('decision', CanonicalString(decision)),
    MapEntry('reason', CanonicalString(reason)),
    MapEntry('idempotency_key', CanonicalString(idempotencyKey)),
    MapEntry('changes', CanonicalArray(changes.map((a) => a.toCanonical()))),
  ]);
}
