import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart' show recordWorld;

import 'proposal_authorization.dart';

BigInt _expiry(BigInt value) {
  if (value.isNegative || value.bitLength > 64) {
    throw const FormatException('Context expiry exceeds unsigned 64-bit range');
  }
  return value;
}

/// Closed retained context; a context is pinned state, not current authority.
final class StoredContext {
  StoredContext({
    required this.owner,
    required this.scope,
    required BigInt expires,
    required this.frame,
  }) : expires = _expiry(expires);
  final ProfileId owner;
  final String scope;
  final BigInt expires;
  final Frame frame;
  factory StoredContext.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'owner', 'scope', 'expires', 'frame'});
    return StoredContext(
      owner: ProfileId.parse(f.string('owner')),
      scope: f.string('scope'),
      expires: f.u64('expires'),
      frame: Frame.fromWire(f.require('frame')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('owner', CanonicalString(owner.value)),
    MapEntry('scope', CanonicalString(scope)),
    MapEntry('expires', CanonicalNumber(expires.toString())),
    MapEntry('frame', frame.toWire()),
  ]);
  Frame admit({
    required ProfileId principal,
    required String scopeHash,
    required UniverseId universe,
    required BigInt epochSeconds,
  }) {
    if (owner != principal ||
        scope != scopeHash ||
        frame.universe != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    if (expires < epochSeconds) throw const ContextExpiredError();
    return frame;
  }
}

WorldId? resolveWorldFocus({
  required Selector? world,
  required WorldId? guard,
  required List<RecordVersion> records,
  required Set<WorldId>? scope,
}) {
  if (world == null) return null;
  final key = selectorKey(world.value);
  final visible = visibleRecordIds(records: records, worldScope: scope);
  bool matches(String name) {
    try {
      return selectorKey(name) == key;
    } on FormatException {
      return false;
    }
  }

  final found = [
    for (final row in records)
      if (visible.contains(row.identity.recordId) &&
          row.payload is WorldRecord &&
          [
            (row.payload as WorldRecord).selector,
            ...(row.payload as WorldRecord).aliases,
          ].any(matches))
        row,
  ];
  if (found.length != 1) {
    throw const NotFoundOrNotAccessibleError(message: 'resource');
  }
  final id = recordWorld(found.single.identity.recordId);
  if (guard != null && guard != id) {
    throw const WorldScopeConflictError(message: 'world guard differs');
  }
  return id;
}
