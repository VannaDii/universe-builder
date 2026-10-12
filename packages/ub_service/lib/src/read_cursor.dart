import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

String readCursorBinding({
  required CanonicalObject args,
  required Frame frame,
  required ProfileId principal,
  required String scopeHash,
}) => canonicalDigest(
  CanonicalArray([
    CanonicalObject(args.fields.where((entry) => entry.key != 'cursor')),
    frame.toWire(),
    CanonicalString(principal.value),
    CanonicalString(scopeHash),
  ]),
);

/// Opaque persisted offset bound to exact arguments, frame and current access.
final class StoredReadCursor {
  StoredReadCursor({required this.binding, required this.offset});
  final String binding;
  final BigInt offset;
  factory StoredReadCursor.fromWire(CanonicalValue value) {
    final fields = WireFields(value, {'binding', 'offset'});
    return StoredReadCursor(
      binding: fields.string('binding'),
      offset: fields.u64('offset'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('binding', CanonicalString(binding)),
    MapEntry('offset', CanonicalNumber(offset.toString())),
  ]);
}
