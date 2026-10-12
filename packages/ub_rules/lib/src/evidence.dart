import 'package:ub_domain/ub_domain.dart';

/// One independent side of factual evidence, retaining its exact derivations.
final class EvidenceBit {
  EvidenceBit({
    required this.present,
    required Iterable<RecordVersionId> sources,
  }) : sources = List.unmodifiable(sources);
  EvidenceBit.absent() : this(present: false, sources: const []);
  EvidenceBit.withSource(RecordVersionId source)
    : this(present: true, sources: [source]);
  EvidenceBit.withSources(Iterable<RecordVersionId> sources)
    : this(present: true, sources: sources);

  final bool present;
  final List<RecordVersionId> sources;

  EvidenceBit or(EvidenceBit other) => !present && !other.present
      ? EvidenceBit.absent()
      : EvidenceBit.withSources(_union(sources, other.sources));

  // Both derivations are required; conjunction is not a source intersection.
  EvidenceBit and(EvidenceBit other) => !present || !other.present
      ? EvidenceBit.absent()
      : EvidenceBit.withSources(_union(sources, other.sources));

  EvidenceBit negate() => EvidenceBit(present: !present, sources: sources);
  bool get isDefinite => present;
  bool get isAbsent => !present && sources.isEmpty;
  bool get isIndeterminate => present && sources.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is EvidenceBit &&
      present == other.present &&
      sources.length == other.sources.length &&
      Iterable<int>.generate(sources.length)
          .every((i) => sources[i] == other.sources[i]);
  @override
  int get hashCode => Object.hash(present, Object.hashAll(sources));
}

/// Support and refutation remain independent; missing support is not refutation.
final class Evidence {
  const Evidence({required this.support, required this.refutation});
  Evidence.notEstablished()
    : this(support: EvidenceBit.absent(), refutation: EvidenceBit.absent());
  Evidence.supported(Iterable<RecordVersionId> sources)
    : this(
        support: EvidenceBit.withSources(sources),
        refutation: EvidenceBit.absent(),
      );
  Evidence.refuted(Iterable<RecordVersionId> sources)
    : this(
        support: EvidenceBit.absent(),
        refutation: EvidenceBit.withSources(sources),
      );
  Evidence.conflicting(
    Iterable<RecordVersionId> support,
    Iterable<RecordVersionId> refutation,
  ) : this(
        support: EvidenceBit.withSources(support),
        refutation: EvidenceBit.withSources(refutation),
      );

  final EvidenceBit support, refutation;
  EvidenceOutcome get outcome =>
      switch ((support.present, refutation.present)) {
        (true, false) => EvidenceOutcome.supported,
        (false, true) => EvidenceOutcome.refuted,
        (true, true) => EvidenceOutcome.conflicting,
        (false, false) => EvidenceOutcome.notEstablished,
      };
  Evidence negate() => Evidence(support: refutation, refutation: support);
  Evidence all(Evidence other) => Evidence(
    support: support.and(other.support),
    refutation: refutation.or(other.refutation),
  );
  Evidence any(Evidence other) => Evidence(
    support: support.or(other.support),
    refutation: refutation.and(other.refutation),
  );
  List<RecordVersionId> get allSources =>
      _union(support.sources, refutation.sources);
  bool get isDefinite => support.isDefinite || refutation.isDefinite;
  bool get isTrulyAbsent => support.isAbsent && refutation.isAbsent;

  @override
  bool operator ==(Object other) =>
      other is Evidence &&
      support == other.support &&
      refutation == other.refutation;
  @override
  int get hashCode => Object.hash(support, refutation);
}

enum EvidenceOutcome {
  supported('supported'),
  refuted('refuted'),
  conflicting('conflicting'),
  notEstablished('not_established');

  const EvidenceOutcome(this.label);
  final String label;
  @override
  String toString() => label;
}

List<RecordVersionId> _union(
  Iterable<RecordVersionId> a,
  Iterable<RecordVersionId> b,
) {
  final result = {...a, ...b}.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  return List.unmodifiable(result);
}
