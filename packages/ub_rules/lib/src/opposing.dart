import 'dart:convert';

import 'package:ub_domain/ub_domain.dart';

import 'comparison.dart';
import 'time.dart';

/// Diagnostics over one structurally checked, event-expanded active revision.
enum OpposingGap {
  equality,
  context,
  realm,
  worlds,
  time,
  precision,
  persistence,
  provenance,
  budget,
}

sealed class OpposingIntersection {
  const OpposingIntersection();
}

final class UnqualifiedIntersection extends OpposingIntersection {
  const UnqualifiedIntersection();
}

final class ExactIntersection extends OpposingIntersection {
  const ExactIntersection(this.validity);
  final Validity validity;
}

final class UncertainIntersection extends OpposingIntersection {
  const UncertainIntersection(this.left, this.right, this.guaranteed);
  final Validity left, right;
  final Validity? guaranteed;
}

final class UnresolvedIntersection extends OpposingIntersection {
  const UnresolvedIntersection();
}

final class OpposingChain {
  OpposingChain({
    required this.assertion,
    required this.proposition,
    required Iterable<RecordVersion> dependencies,
    required this.complete,
  }) : dependencies = List.unmodifiable(dependencies);
  final RecordVersion assertion, proposition;
  final List<RecordVersion> dependencies;
  final bool complete;
}

final class OpposingPair {
  OpposingPair({
    required Iterable<int> comparisonKey,
    required this.support,
    required this.refutation,
    required this.context,
    required this.applicability,
    required this.realm,
    required this.intersection,
    required Iterable<OpposingGap> gaps,
  }) : comparisonKey = List.unmodifiable(comparisonKey),
       gaps = Set.unmodifiable(gaps);
  final List<int> comparisonKey;
  final OpposingChain support, refutation;
  final RecordRef context;
  final Applicability? applicability;
  final RecordRef? realm;
  final OpposingIntersection intersection;
  final Set<OpposingGap> gaps;
  bool get definite =>
      gaps.every((g) => g == OpposingGap.provenance) &&
      intersection is! UnresolvedIntersection;
}

final class OpposingScan {
  OpposingScan({
    required Iterable<OpposingPair> pairs,
    required this.complete,
    required this.comparisons,
    required Iterable<OpposingGap> gaps,
  }) : pairs = List.unmodifiable(pairs),
       gaps = Set.unmodifiable(gaps);
  final List<OpposingPair> pairs;
  final bool complete;
  final int comparisons;
  final Set<OpposingGap> gaps;
}

final class OpposingError implements Exception {
  const OpposingError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// No focus-world narrowing or transitive grouping of numeric equality.
OpposingScan detectOpposing({
  required UniverseId universe,
  required List<RecordVersion> records,
  required bool indexed,
  required int budget,
}) {
  if (budget < 0) {
    throw ArgumentError('Negative opposing-evidence budget');
  }
  if (budget > 10000) budget = 10000;
  if (records.length > 10000) {
    throw const OpposingError('active membership budget exhausted');
  }
  final membership = <RecordId, RecordVersion>{};
  for (final r in records) {
    if (r.identity.universeId != universe) {
      throw const OpposingError('mixed universe membership');
    }
    final old = membership[r.identity.recordId];
    if (old != null && old.toWire().toText() != r.toWire().toText()) {
      throw const OpposingError('ambiguous active membership');
    }
    membership[r.identity.recordId] = r;
  }
  RecordVersion resolve(RecordRef ref) {
    try {
      ref.resolveNamespace(universe);
    } on FormatException {
      throw const OpposingError('cross-universe reference');
    }
    final found = membership[ref.record];
    if (found == null) throw const OpposingError('missing active reference');
    return found;
  }

  final keys = <RecordVersionId, String>{};
  final buckets =
      <
        String,
        List<(RecordVersion, AssertionRecord, RecordVersion, PropositionRecord)>
      >{};
  final orderedIds = membership.keys.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  for (final id in orderedIds) {
    final r = membership[id]!, a = r.payload;
    if (a is! AssertionRecord) continue;
    final prop = resolve(a.proposition), p = prop.payload;
    if (p is! PropositionRecord) {
      throw const OpposingError('assertion target is not a proposition');
    }
    final def = resolve(p.predicate);
    resolve(p.subject);
    if (resolve(p.context).payload is! RepresentedContextRecord) {
      throw const OpposingError('invalid represented context');
    }
    resolve(a.scope.context);
    if (a.scope.realm != null) resolve(a.scope.realm!);
    final roles = <(String, RecordRef)>[];
    for (final role in p.roles) {
      resolve(role.participant);
      roles.add((role.role, role.participant.resolveNamespace(universe)));
    }
    _sortRoles(roles);
    final valid = switch (def.payload) {
      PropertyRecord() => roles.isEmpty,
      RelationRecord(:final roles) => p.roles.every(
        (r) => roles.any((d) => d.name == r.role),
      ),
      _ => false,
    };
    if (!valid) {
      throw const OpposingError('invalid predicate or role declaration');
    }
    // serde tuple/ref field ordering is retained for the private comparison key.
    final key = jsonEncode([
      _refWire(p.subject.resolveNamespace(universe)),
      def.recordVersionId.value,
      p.quantification.name,
      _refWire(p.context.resolveNamespace(universe)),
      roles.map((r) => [r.$1, _refWire(r.$2)]).toList(),
    ]);
    keys[prop.recordVersionId] = key;
    buckets.putIfAbsent(indexed ? key : '', () => []).add((r, a, prop, p));
  }
  final pairs = <OpposingPair>[], scanGaps = <OpposingGap>{};
  final chains = <RecordVersionId, OpposingChain>{};
  var complete = true, comparisons = 0;
  OpposingScan result() {
    pairs.sort(_pairOrder);
    return OpposingScan(
      pairs: pairs,
      complete: complete,
      comparisons: comparisons,
      gaps: scanGaps.toList()..sort((a, b) => a.index.compareTo(b.index)),
    );
  }

  final bucketKeys = buckets.keys.toList()..sort(_stringOrder);
  for (final key in bucketKeys) {
    final items = buckets[key]!;
    for (final (s, sa, sp, ps) in items.where(
      (r) => r.$2.polarity == Polarity.support,
    )) {
      for (final (r, ra, rp, pr) in items.where(
        (r) => r.$2.polarity == Polarity.refutation,
      )) {
        if (comparisons == budget) {
          complete = false;
          scanGaps.add(OpposingGap.budget);
          return result();
        }
        comparisons++;
        if (!_sameMeaning(ps, pr, universe)) continue;
        final gaps = <OpposingGap>{};
        final applicability = _worlds(
          sa.scope.applicability,
          ra.scope.applicability,
        );
        if (applicability is WorldsApplicability &&
            applicability.worldIds.isEmpty) {
          continue;
        }
        if (sa.scope.realm != null &&
            ra.scope.realm != null &&
            sa.scope.realm!.resolveNamespace(universe) !=
                ra.scope.realm!.resolveNamespace(universe)) {
          continue;
        }
        if (temporalOverlaps(sa.validity, ra.validity) == false) continue;
        final a = ps.value, b = pr.value;
        final equal = a == null && b == null
            ? true
            : a == null || b == null
            ? false
            : a.toCanonical().toText() == b.toCanonical().toText()
            ? true
            : compareValues(a, Comparator.eq, b);
        if (equal == false) continue;
        if (equal == null) gaps.add(OpposingGap.equality);
        if (applicability == null) gaps.add(OpposingGap.worlds);
        if ((sa.scope.realm == null) != (ra.scope.realm == null)) {
          gaps.add(OpposingGap.realm);
        }
        for (final (a, p) in [(sa, ps), (ra, pr)]) {
          if (a.scope.context.resolveNamespace(universe) !=
              p.context.resolveNamespace(universe)) {
            gaps.add(OpposingGap.context);
          }
          if (a.precision != Precision.exact || a.alternatives.isNotEmpty) {
            gaps.add(OpposingGap.precision);
          }
          if (a.persistence == PersistenceSemantics.persistentUntilChanged ||
              a.persistence == PersistenceSemantics.conditionDependent) {
            gaps.add(OpposingGap.persistence);
          }
        }
        final intersection = _intersection(sa.validity, ra.validity);
        if (intersection is UnresolvedIntersection) gaps.add(OpposingGap.time);
        final support = chains.putIfAbsent(
          s.recordVersionId,
          () => _chain(s, sp, universe, membership),
        );
        final refutation = chains.putIfAbsent(
          r.recordVersionId,
          () => _chain(r, rp, universe, membership),
        );
        if (!support.complete || !refutation.complete) {
          gaps.add(OpposingGap.provenance);
        }
        complete =
            complete && gaps.isEmpty && intersection is! UncertainIntersection;
        pairs.add(
          OpposingPair(
            comparisonKey: utf8.encode(keys[sp.recordVersionId]!),
            support: support,
            refutation: refutation,
            context: ps.context.resolveNamespace(universe),
            applicability: applicability,
            realm: sa.scope.realm?.resolveNamespace(universe),
            intersection: intersection,
            gaps: gaps.toList()..sort((a, b) => a.index.compareTo(b.index)),
          ),
        );
      }
    }
  }
  return result();
}

Map<String, String> _refWire(RecordRef ref) => {
  if (ref.universe != null) 'universe': ref.universe!.value,
  'record': ref.record.value,
};
int _bytesOrder(List<int> a, List<int> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    final result = a[i].compareTo(b[i]);
    if (result != 0) return result;
  }
  return a.length.compareTo(b.length);
}

int _stringOrder(String a, String b) =>
    _bytesOrder(utf8.encode(a), utf8.encode(b));
void _sortRoles(List<(String, RecordRef)> roles) => roles.sort((a, b) {
  final name = _stringOrder(a.$1, b.$1);
  return name != 0
      ? name
      : _stringOrder(a.$2.universe!.value, b.$2.universe!.value) != 0
      ? _stringOrder(a.$2.universe!.value, b.$2.universe!.value)
      : a.$2.record.value.compareTo(b.$2.record.value);
});
bool _sameMeaning(
  PropositionRecord a,
  PropositionRecord b,
  UniverseId universe,
) {
  List<(String, RecordRef)> roles(PropositionRecord p) => p.roles
      .map((r) => (r.role, r.participant.resolveNamespace(universe)))
      .toList();
  final ar = roles(a), br = roles(b);
  _sortRoles(ar);
  _sortRoles(br);
  return a.subject.resolveNamespace(universe) ==
          b.subject.resolveNamespace(universe) &&
      a.predicate.resolveNamespace(universe) ==
          b.predicate.resolveNamespace(universe) &&
      a.context.resolveNamespace(universe) ==
          b.context.resolveNamespace(universe) &&
      a.quantification == b.quantification &&
      ar.length == br.length &&
      Iterable<int>.generate(ar.length).every((i) => ar[i] == br[i]);
}

Applicability? _worlds(Applicability a, Applicability b) {
  if (a is WorldsApplicability && a.worldIds.isEmpty ||
      b is WorldsApplicability && b.worldIds.isEmpty) {
    return WorldsApplicability([]);
  }
  List<WorldId> ordered(Iterable<WorldId> ids) =>
      ids.toSet().toList()..sort((a, b) => a.value.compareTo(b.value));
  if (a is UniverseApplicability && b is UniverseApplicability) {
    return const UniverseApplicability();
  }
  if (a is UniverseApplicability && b is WorldsApplicability) {
    return WorldsApplicability(ordered(b.worldIds));
  }
  if (b is UniverseApplicability && a is WorldsApplicability) {
    return WorldsApplicability(ordered(a.worldIds));
  }
  if (a is WorldsApplicability && b is WorldsApplicability) {
    return WorldsApplicability(ordered(a.worldIds.where(b.worldIds.contains)));
  }
  return null;
}

final _min = -(BigInt.one << 127), _max = (BigInt.one << 127) - BigInt.one;
BigInt? _number(String s) {
  if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(s)) return null;
  final n = BigInt.tryParse(s);
  return n == null || n < _min || n > _max ? null : n;
}

Validity? _exactIntersection(Validity a, Validity b, bool guaranteed) {
  (CalendarId, BigInt, BigInt, bool)? bounds(Validity v) {
    BigInt? endpoint(TemporalBound b, bool start) => switch (b) {
      ExactBound(:final value) => _number(value),
      UnboundedBound() => start ? _min : _max,
      UncertainBound(:final lower, :final upper) when guaranteed => _number(
        start ? upper : lower,
      ),
      _ => null,
    };
    if (v is CalendarIntervalValidity) {
      final lo = endpoint(v.start, true), hi = endpoint(v.end, false);
      return lo == null || hi == null ? null : (v.calendar, lo, hi, false);
    }
    if (v is InstantValidity && v.at is ExactTime) {
      final at = v.at as ExactTime, n = _number((v.at as ExactTime).value);
      return n == null ? null : (at.calendar, n, n, true);
    }
    return null;
  }

  final left = bounds(a), right = bounds(b);
  if (left == null || right == null || left.$1 != right.$1) return null;
  final (calendar, lo, hi, point) = left;
  final (_, x, y, otherPoint) = right;
  if (point || otherPoint) {
    final n = point ? lo : x;
    if (point && otherPoint && lo == x ||
        point && !otherPoint && x <= n && n < y ||
        !point && otherPoint && lo <= n && n < hi) {
      return InstantValidity(ExactTime(calendar, '$n'));
    }
    return null;
  }
  final start = lo > x ? lo : x, end = hi < y ? hi : y;
  if (start >= end) return null;
  TemporalBound bound(BigInt n) =>
      n == _min || n == _max ? const UnboundedBound() : ExactBound('$n');
  return CalendarIntervalValidity(calendar, bound(start), bound(end));
}

OpposingIntersection _intersection(Validity a, Validity b) {
  if (a is UnspecifiedValidity && b is UnspecifiedValidity) {
    return const UnqualifiedIntersection();
  }
  if (temporalOverlaps(a, b) != true) return const UnresolvedIntersection();
  final exact = _exactIntersection(a, b, false);
  return exact != null
      ? ExactIntersection(exact)
      : UncertainIntersection(a, b, _exactIntersection(a, b, true));
}

OpposingChain _chain(
  RecordVersion a,
  RecordVersion p,
  UniverseId universe,
  Map<RecordId, RecordVersion> membership,
) {
  final found = <RecordVersionId, RecordVersion>{}, pending = [a, p];
  var complete = true;
  void refs(CanonicalValue v, List<(RecordRef, RecordVersionId?)> out) {
    if (v is CanonicalObject) {
      final fields = {for (final f in v.fields) f.key: f.value};
      if (fields.containsKey('record')) {
        try {
          final ref = RecordRef.fromCanonical(
            CanonicalObject(fields.entries.where((f) => f.key != 'version')),
          );
          RecordVersionId? version;
          final ver = fields['version'];
          if (ver is CanonicalString) {
            try {
              version = RecordVersionId.parse(ver.value);
            } on FormatException {
              /* Matches absent invalid version link. */
            }
          }
          out.add((ref, version));
          return;
        } on FormatException {
          /* Continue traversal of non-reference objects. */
        }
      }
      for (final f in v.fields) {
        refs(f.value, out);
      }
    } else if (v is CanonicalArray) {
      for (final item in v.items) {
        refs(item, out);
      }
    }
  }

  while (pending.isNotEmpty) {
    final r = pending.removeLast();
    if (found.containsKey(r.recordVersionId)) continue;
    if (r.payload case AssertionRecord(basis: ImportedClaimBasis())) {
      complete = false;
    }
    final links = <(RecordRef, RecordVersionId?)>[];
    refs(r.payload.toWire(), links);
    for (final (link, version) in links) {
      RecordVersion? next;
      try {
        link.resolveNamespace(universe);
        next = membership[link.record];
      } on FormatException {
        /* Incomplete cross-universe provenance. */
      }
      if (next != null &&
          (version == null || version == next.recordVersionId)) {
        pending.add(next);
      } else {
        complete = false;
      }
    }
    found[r.recordVersionId] = r;
  }
  found.remove(a.recordVersionId);
  found.remove(p.recordVersionId);
  final ids = found.keys.toList()..sort((a, b) => a.value.compareTo(b.value));
  return OpposingChain(
    assertion: a,
    proposition: p,
    dependencies: ids.map((id) => found[id]!),
    complete: complete,
  );
}

// Only definite overlapping temporal forms reach an uncertain/exact sort cell.
// Preserve serde field order here; canonical payload bytes use their own recipe.
String _validityWire(Validity v) {
  String temporal(CanonicalObject value) {
    final fields = {for (final f in value.fields) f.key: f.value};
    final order = [
      'kind',
      'calendar',
      'start',
      'end',
      'value',
      'lower',
      'upper',
    ];
    return '{${order.where(fields.containsKey).map((k) => '${jsonEncode(k)}:${fields[k] is CanonicalObject ? temporal(fields[k]! as CanonicalObject) : fields[k]!.toText()}').join(',')}}';
  }

  final fields = {for (final f in v.toWire().fields) f.key: f.value};
  return '{${['kind', 'calendar', 'start', 'end', 'at'].where(fields.containsKey).map((k) => '${jsonEncode(k)}:${fields[k] is CanonicalObject ? temporal(fields[k]! as CanonicalObject) : fields[k]!.toText()}').join(',')}}';
}

String _intersectionWire(OpposingIntersection i) => switch (i) {
  UnqualifiedIntersection() => '"Unqualified"',
  UnresolvedIntersection() => '"Unresolved"',
  ExactIntersection(:final validity) => '{"Exact":${_validityWire(validity)}}',
  UncertainIntersection(:final left, :final right, :final guaranteed) =>
    '{"Uncertain":{"left":${_validityWire(left)},"right":${_validityWire(right)},"guaranteed":${guaranteed == null ? 'null' : _validityWire(guaranteed)}}}',
};
int _pairOrder(OpposingPair a, OpposingPair b) {
  int optional(Applicability? a, Applicability? b) => a == null
      ? (b == null ? 0 : -1)
      : b == null
      ? 1
      : _bytesOrder(a.toCanonical().toBytes(), b.toCanonical().toBytes());
  final comparisons = [
    _bytesOrder(a.comparisonKey, b.comparisonKey),
    _bytesOrder(
      a.support.proposition.payload.toCanonical().toBytes(),
      b.support.proposition.payload.toCanonical().toBytes(),
    ),
    optional(a.applicability, b.applicability),
    _stringOrder(
      jsonEncode(a.realm == null ? null : _refWire(a.realm!)),
      jsonEncode(b.realm == null ? null : _refWire(b.realm!)),
    ),
    _stringOrder(
      _intersectionWire(a.intersection),
      _intersectionWire(b.intersection),
    ),
    a.support.assertion.recordVersionId.value.compareTo(
      b.support.assertion.recordVersionId.value,
    ),
    a.refutation.assertion.recordVersionId.value.compareTo(
      b.refutation.assertion.recordVersionId.value,
    ),
  ];
  return comparisons.firstWhere((n) => n != 0, orElse: () => 0);
}
