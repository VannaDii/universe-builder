import 'package:ub_domain/ub_domain.dart';

import 'read_response.dart';
import 'request.dart';
import 'wire.dart';

/// A response page at the service's supplied scope. This is not an authority
/// grant, and delivery completeness does not establish evidence completeness.
final class Envelope<T> {
  Envelope({
    required this.contractVersion,
    required BigInt requestId,
    required this.universeId,
    required this.universe,
    required this.aliasMatched,
    this.frame,
    this.worldFocus,
    required this.authorizationScope,
    required this.delivery,
    required this.result,
  }) : requestId = checkedU64(requestId);

  final String contractVersion;
  final BigInt requestId;
  final UniverseId universeId;
  final Selector universe;
  final bool aliasMatched;
  final Frame? frame;
  final WorldId? worldFocus;
  final String authorizationScope;
  final Delivery delivery;
  final T result;

  factory Envelope.fromWire(
    CanonicalValue value,
    T Function(CanonicalValue) parseResult,
  ) {
    final f = WireFields(value, {
      'contract_version',
      'request_id',
      'universe_id',
      'universe',
      'alias_matched',
      'frame',
      'world_focus',
      'authorization_scope',
      'delivery',
      'result',
    });
    return Envelope(
      contractVersion: f.string('contract_version'),
      requestId: f.u64('request_id'),
      universeId: UniverseId.parse(f.string('universe_id')),
      universe: Selector.fromWire(f.require('universe')),
      aliasMatched: f.boolean('alias_matched'),
      frame: f.optional('frame', Frame.fromWire),
      worldFocus: f.optional(
        'world_focus',
        (v) => WorldId.parse(wireString(v)),
      ),
      authorizationScope: f.string('authorization_scope'),
      delivery: Delivery.fromWire(f.require('delivery')),
      result: parseResult(f.require('result')),
    );
  }

  CanonicalObject toWire(CanonicalValue Function(T) encodeResult) =>
      CanonicalObject([
        MapEntry('contract_version', CanonicalString(contractVersion)),
        MapEntry('request_id', CanonicalNumber(requestId.toString())),
        MapEntry('universe_id', CanonicalString(universeId.value)),
        MapEntry('universe', universe.toWire()),
        MapEntry('alias_matched', CanonicalBool(aliasMatched)),
        MapEntry('frame', frame?.toWire() ?? const CanonicalNull()),
        MapEntry(
          'world_focus',
          worldFocus == null
              ? const CanonicalNull()
              : CanonicalString(worldFocus!.value),
        ),
        MapEntry('authorization_scope', CanonicalString(authorizationScope)),
        MapEntry('delivery', delivery.toWire()),
        MapEntry('result', encodeResult(result)),
      ]);
}
