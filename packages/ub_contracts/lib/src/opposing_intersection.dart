import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';

/// A declared diagnostic intersection, not a newly inferred validity.
sealed class OpposingIntersection {
  const OpposingIntersection();
  CanonicalObject toWire();
  static OpposingIntersection fromWire(CanonicalValue value) {
    if (value is! CanonicalObject) {
      throw const FormatException('Expected opposing intersection');
    }
    final kind = WireFields(value, {
      'kind',
      'validity',
      'left',
      'right',
      'guaranteed',
    }).string('kind');
    switch (kind) {
      case 'unqualified':
        WireFields(value, {'kind'});
        return const UnqualifiedIntersection();
      case 'unresolved':
        WireFields(value, {'kind'});
        return const UnresolvedIntersection();
      case 'exact':
        final f = WireFields(value, {'kind', 'validity'});
        return ExactIntersection(Validity.fromWire(f.require('validity')));
      case 'uncertain':
        final f = WireFields(value, {'kind', 'left', 'right', 'guaranteed'});
        return UncertainIntersection(
          left: Validity.fromWire(f.require('left')),
          right: Validity.fromWire(f.require('right')),
          guaranteed: f.optional('guaranteed', Validity.fromWire),
        );
      default:
        throw const FormatException('Unknown opposing intersection');
    }
  }
}

final class UnqualifiedIntersection extends OpposingIntersection {
  const UnqualifiedIntersection();
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('kind', CanonicalString('unqualified'))]);
}

final class UnresolvedIntersection extends OpposingIntersection {
  const UnresolvedIntersection();
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('kind', CanonicalString('unresolved'))]);
}

final class ExactIntersection extends OpposingIntersection {
  const ExactIntersection(this.validity);
  final Validity validity;
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('exact')),
    MapEntry('validity', validity.toWire()),
  ]);
}

final class UncertainIntersection extends OpposingIntersection {
  const UncertainIntersection({
    required this.left,
    required this.right,
    this.guaranteed,
  });
  final Validity left, right;
  final Validity? guaranteed;
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('uncertain')),
    MapEntry('left', left.toWire()),
    MapEntry('right', right.toWire()),
    MapEntry(
      'guaranteed',
      guaranteed == null ? const CanonicalNull() : guaranteed!.toWire(),
    ),
  ]);
}
