import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'wire.dart';

final class EventEffectInput {
  const EventEffectInput({
    this.slot = '',
    this.propositionRecord = '',
    this.propositionUniverse = '',
    this.polarity = '',
    this.order = '',
    this.scope = const ScopeInput(),
    this.validity = const TemporalValidityInput(kind: 'unspecified'),
    this.original,
  });
  final String slot, propositionRecord, propositionUniverse, polarity, order;
  final ScopeInput scope;
  final TemporalValidityInput validity;
  final EntityEffect? original;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('slot', CanonicalString(slot)),
    MapEntry('proposition_record', CanonicalString(propositionRecord)),
    MapEntry('proposition_universe', CanonicalString(propositionUniverse)),
    MapEntry('polarity', CanonicalString(polarity)),
    MapEntry('order', CanonicalString(order)),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
    if (original != null) MapEntry('original', original!.toWire()),
  ]);
  factory EventEffectInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'slot',
      'proposition_record',
      'proposition_universe',
      'polarity',
      'order',
      'scope',
      'validity',
      'original',
    });
    return EventEffectInput(
      slot: f.string('slot'),
      propositionRecord: f.string('proposition_record'),
      propositionUniverse: f.string('proposition_universe'),
      polarity: f.string('polarity'),
      order: f.string('order'),
      scope: ScopeInput.fromWire(f.require('scope')),
      validity: TemporalValidityInput.fromWire(f.require('validity')),
      original: f.optional('original', EntityEffect.fromWire),
    );
  }
  Iterable<String> get exactTexts => _texts(toWire());
}

Iterable<String> _texts(CanonicalValue value) sync* {
  switch (value) {
    case CanonicalString(:final value):
      yield value;
    case CanonicalArray(:final items):
      for (final item in items) {
        yield* _texts(item);
      }
    case CanonicalObject(:final fields):
      for (final field in fields) {
        yield* _texts(field.value);
      }
    default:
      break;
  }
}
