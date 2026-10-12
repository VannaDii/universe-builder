import 'package:ub_contracts/ub_contracts.dart' as protocol;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' as rules;

protocol.OpposingChain _chain(rules.OpposingChain chain) =>
    protocol.OpposingChain(
      assertionId: chain.assertion.identity.recordId,
      propositionId: chain.proposition.identity.recordId,
      assertion: chain.assertion.recordVersionId,
      proposition: chain.proposition.recordVersionId,
      dependencies: chain.dependencies.map(
        (r) => VersionRef(
          universe: r.identity.universeId,
          record: r.identity.recordId,
          version: r.recordVersionId,
        ),
      ),
      complete: chain.complete,
    );

protocol.OpposingIntersection _intersection(
  rules.OpposingIntersection value,
) => switch (value) {
  rules.UnqualifiedIntersection() => const protocol.UnqualifiedIntersection(),
  rules.UnresolvedIntersection() => const protocol.UnresolvedIntersection(),
  rules.ExactIntersection(:final validity) => protocol.ExactIntersection(
    validity,
  ),
  rules.UncertainIntersection(:final left, :final right, :final guaranteed) =>
    protocol.UncertainIntersection(
      left: left,
      right: right,
      guaranteed: guaranteed,
    ),
};

// Rust's internal Intersection uses externally tagged, capitalized variants in
// fingerprint tuples; the public diagnostic uses its separate wire contract.
CanonicalValue _fingerprintIntersection(
  rules.OpposingIntersection value,
) => switch (value) {
  rules.UnqualifiedIntersection() => CanonicalString('Unqualified'),
  rules.UnresolvedIntersection() => CanonicalString('Unresolved'),
  rules.ExactIntersection(:final validity) => CanonicalObject([
    MapEntry('Exact', validity.toWire()),
  ]),
  rules.UncertainIntersection(:final left, :final right, :final guaranteed) =>
    CanonicalObject([
      MapEntry(
        'Uncertain',
        CanonicalObject([
          MapEntry('left', left.toWire()),
          MapEntry('right', right.toWire()),
          MapEntry('guaranteed', guaranteed?.toWire() ?? const CanonicalNull()),
        ]),
      ),
    ]),
};

/// Diagnostics bind the complete candidate and policy versions; they do not
/// select a truth winner or decide publication admission.
List<protocol.OpposingEvidence> buildOpposingDiagnostics({
  required List<RecordVersion> records,
  required Frame frame,
  required String digest,
  required String evaluator,
  required List<String> unsupported,
}) {
  final rules.OpposingScan scan;
  try {
    scan = rules.detectOpposing(
      universe: frame.universe,
      records: records,
      indexed: true,
      budget: 10000,
    );
  } on rules.OpposingError catch (e) {
    unsupported.add('opposing_evidence.v1:${e.message}');
    return [];
  }
  final scanGaps = scan.gaps.toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  if (!scan.complete) {
    final debug = scanGaps
        .map((g) => '${g.name[0].toUpperCase()}${g.name.substring(1)}')
        .join(', ');
    unsupported.add('opposing_evidence.v1:{$debug}');
  }
  final policies =
      records
          .where((r) => r.payload is RuleRecord)
          .map((r) => r.recordVersionId)
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));
  final exceptions =
      records
          .where((r) => r.payload is ExceptionRecord)
          .map((r) => r.recordVersionId)
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));
  return scan.pairs.map((pair) {
    final support = _chain(pair.support), refutation = _chain(pair.refutation);
    final fingerprint = canonicalDigest(
      CanonicalArray([
        frame.toWire(),
        CanonicalString(digest),
        CanonicalString(evaluator),
        CanonicalArray(
          pair.comparisonKey.map((n) => CanonicalNumber(n.toString())),
        ),
        pair.context.toCanonical(),
        pair.applicability?.toWire() ?? const CanonicalNull(),
        pair.realm?.toCanonical() ?? const CanonicalNull(),
        _fingerprintIntersection(pair.intersection),
        support.toWire(),
        refutation.toWire(),
        CanonicalArray(policies.map((v) => CanonicalString(v.value))),
        CanonicalArray(exceptions.map((v) => CanonicalString(v.value))),
      ]),
    );
    final gaps = pair.gaps.toList()..sort((a, b) => a.index.compareTo(b.index));
    return protocol.OpposingEvidence(
      diagnosticVersion: 'opposing_evidence.v1',
      fingerprint: FindingFingerprint(fingerprint),
      kind: pair.definite
          ? protocol.OpposingKind.definite
          : protocol.OpposingKind.unresolved,
      proposition: pair.support.proposition.payload as PropositionRecord,
      support: support,
      refutation: refutation,
      context: pair.context,
      applicability: pair.applicability,
      realm: pair.realm,
      intersection: _intersection(pair.intersection),
      coverage: gaps.isEmpty
          ? protocol.Coverage.complete
          : protocol.Coverage.partial,
      unresolvedReasons: gaps.map(
        (g) => protocol.OpposingReason.values[g.index],
      ),
      policyVersions: policies,
      exceptionVersions: exceptions,
    );
  }).toList();
}
