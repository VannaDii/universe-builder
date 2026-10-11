import 'canonical.dart';
import 'fields.dart';
import 'ids.dart';
import 'references.dart';
import 'time_space.dart';

enum Polarity {
  support('support'),
  refutation('refutation');

  const Polarity(this.wireName);
  final String wireName;
  CanonicalString toWire() => CanonicalString(wireName);
  static Polarity fromWire(CanonicalValue value) => switch (_string(value)) {
    'support' => support,
    'refutation' => refutation,
    _ => throw const FormatException('Unknown polarity'),
  };
}

enum Precision {
  exact('exact'),
  approximate('approximate'),
  range('range'),
  oneOf('one_of'),
  unresolved('unresolved');

  const Precision(this.wireName);
  final String wireName;
  CanonicalString toWire() => CanonicalString(wireName);
  static Precision fromWire(CanonicalValue value) => switch (_string(value)) {
    'exact' => exact,
    'approximate' => approximate,
    'range' => range,
    'one_of' => oneOf,
    'unresolved' => unresolved,
    _ => throw const FormatException('Unknown precision'),
  };
}

enum PersistenceSemantics {
  explicitInterval('explicit_interval'),
  persistentUntilChanged('persistent_until_changed'),
  instantaneousObservation('instantaneous_observation'),
  conditionDependent('condition_dependent'),
  unspecified('unspecified');

  const PersistenceSemantics(this.wireName);
  final String wireName;
  CanonicalString toWire() => CanonicalString(wireName);
  static PersistenceSemantics fromWire(CanonicalValue value) =>
      switch (_string(value)) {
        'explicit_interval' => explicitInterval,
        'persistent_until_changed' => persistentUntilChanged,
        'instantaneous_observation' => instantaneousObservation,
        'condition_dependent' => conditionDependent,
        'unspecified' => unspecified,
        _ => throw const FormatException('Unknown persistence'),
      };
}

/// Applicability is authored separately from universe ownership. Worlds retain
/// their list order and duplicates; an empty world list is legal, not universal.
sealed class Applicability {
  const Applicability();
  CanonicalObject encode({required bool canonical});
  CanonicalObject toWire() => encode(canonical: false);
  CanonicalObject toCanonical() => encode(canonical: true);
  @override
  bool operator ==(Object other) =>
      other is Applicability &&
      runtimeType == other.runtimeType &&
      toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toCanonical().toText().hashCode;
  static Applicability fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'universe_wide':
        f.allow({'kind'});
        return const UniverseApplicability();
      case 'worlds':
        f.allow({'kind', 'world_ids'});
        return WorldsApplicability(
          f.array('world_ids').map((w) => WorldId.parse(_string(w))),
        );
      case 'conditional':
        f.allow({'kind'});
        return const ConditionalApplicability();
      case 'unspecified':
        f.allow({'kind'});
        return const UnspecifiedApplicability();
      default:
        throw const FormatException('Unknown applicability');
    }
  }
}

final class UniverseApplicability extends Applicability {
  const UniverseApplicability();
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('universe_wide', []);
}

final class WorldsApplicability extends Applicability {
  WorldsApplicability(Iterable<WorldId> worlds)
    : worldIds = List.unmodifiable(worlds);
  final List<WorldId> worldIds;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('worlds', [
    MapEntry(
      canonical ? 'worldIds' : 'world_ids',
      CanonicalArray(worldIds.map((w) => CanonicalString(w.value))),
    ),
  ]);
}

final class ConditionalApplicability extends Applicability {
  const ConditionalApplicability();
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('conditional', []);
}

final class UnspecifiedApplicability extends Applicability {
  const UnspecifiedApplicability();
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('unspecified', []);
}

final class Scope {
  const Scope({required this.applicability, required this.context, this.realm});
  final Applicability applicability;
  final RecordRef context;
  final RecordRef? realm;
  factory Scope.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'applicability', 'context', 'realm'});
    return Scope(
      applicability: Applicability.fromWire(f.require('applicability')),
      context: RecordRef.fromCanonical(f.require('context')),
      realm: f.values['realm'] == null || f.values['realm'] is CanonicalNull
          ? null
          : RecordRef.fromCanonical(f.require('realm')),
    );
  }
  CanonicalObject toWire() => _encode(false);
  CanonicalObject toCanonical() => _encode(true);
  CanonicalObject _encode(bool canonical) => CanonicalObject([
    MapEntry(
      'applicability',
      canonical ? applicability.toCanonical() : applicability.toWire(),
    ),
    MapEntry('context', context.toCanonical()),
    if (realm != null) MapEntry('realm', realm!.toCanonical()),
  ]);
  @override
  bool operator ==(Object other) =>
      other is Scope &&
      applicability == other.applicability &&
      context == other.context &&
      realm == other.realm;
  @override
  int get hashCode => Object.hash(applicability, context, realm);
}

/// Fictional-time validity is distinct from publication revision and editorial
/// order. Unknown boundaries never become infinity implicitly.
sealed class Validity {
  const Validity();
  CanonicalObject toWire();
  // Rust canonicalizes this family through serde, including nested value wire
  // shapes, rather than through the manual temporal comparison encoding.
  CanonicalObject toCanonical() => toWire();
  bool get isTemporal =>
      this is InstantValidity ||
      this is IntervalValidity ||
      this is CalendarIntervalValidity ||
      this is PersistentValidity;
  (TemporalBound, TemporalBound)? asInterval() => switch (this) {
    IntervalValidity(:final start, :final end) => (start, end),
    CalendarIntervalValidity(:final start, :final end) => (start, end),
    PersistentValidity(:final from) => (from, const UnboundedBound()),
    InstantValidity(:final at) => switch (at) {
      ExactTime(:final value) => (ExactBound(value), ExactBound(value)),
      IntervalTime(
        start: ExactBound(value: final a),
        end: ExactBound(value: final b),
      )
          when a == b =>
        (ExactBound(a), ExactBound(b)),
      _ => null,
    },
    _ => null,
  };
  @override
  bool operator ==(Object other) =>
      other is Validity &&
      runtimeType == other.runtimeType &&
      toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toCanonical().toText().hashCode;
  static Validity fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'unspecified':
        f.allow({'kind'});
        return const UnspecifiedValidity();
      case 'unknown':
        f.allow({'kind'});
        return const UnknownValidity();
      case 'condition_dependent':
        f.allow({'kind'});
        return const ConditionalValidity();
      case 'instant':
        f.allow({'kind', 'at'});
        return InstantValidity(TemporalExpression.fromWire(f.require('at')));
      case 'interval':
        f.allow({'kind', 'start', 'end'});
        return IntervalValidity(
          TemporalBound.fromWire(f.require('start')),
          TemporalBound.fromWire(f.require('end')),
        );
      case 'calendar_interval':
        f.allow({'kind', 'calendar', 'start', 'end'});
        return CalendarIntervalValidity(
          CalendarId.parse(f.string('calendar')),
          TemporalBound.fromWire(f.require('start')),
          TemporalBound.fromWire(f.require('end')),
        );
      case 'persistent_until_changed':
        f.allow({'kind', 'from'});
        return PersistentValidity(TemporalBound.fromWire(f.require('from')));
      default:
        throw const FormatException('Unknown validity');
    }
  }
}

final class UnspecifiedValidity extends Validity {
  const UnspecifiedValidity();
  @override
  CanonicalObject toWire() => tagged('unspecified', []);
}

final class UnknownValidity extends Validity {
  const UnknownValidity();
  @override
  CanonicalObject toWire() => tagged('unknown', []);
}

final class ConditionalValidity extends Validity {
  const ConditionalValidity();
  @override
  CanonicalObject toWire() => tagged('condition_dependent', []);
}

final class InstantValidity extends Validity {
  const InstantValidity(this.at);
  final TemporalExpression at;
  @override
  CanonicalObject toWire() =>
      tagged('instant', [MapEntry('at', at.encode(canonical: false))]);
}

final class IntervalValidity extends Validity {
  const IntervalValidity(this.start, this.end);
  final TemporalBound start, end;
  @override
  CanonicalObject toWire() => tagged('interval', _bounds(start, end));
}

final class CalendarIntervalValidity extends Validity {
  const CalendarIntervalValidity(this.calendar, this.start, this.end);
  final CalendarId calendar;
  final TemporalBound start, end;
  @override
  CanonicalObject toWire() => tagged('calendar_interval', [
    MapEntry('calendar', CanonicalString(calendar.value)),
    ..._bounds(start, end),
  ]);
}

final class PersistentValidity extends Validity {
  const PersistentValidity(this.from);
  final TemporalBound from;
  @override
  CanonicalObject toWire() => tagged('persistent_until_changed', [
    MapEntry('from', from.encode(canonical: false)),
  ]);
}

Iterable<MapEntry<String, CanonicalValue>> _bounds(
  TemporalBound start,
  TemporalBound end,
) => [
  MapEntry('start', start.encode(canonical: false)),
  MapEntry('end', end.encode(canonical: false)),
];

/// Evidence provenance. A verified anchor establishes a content match, not the
/// truth of the source or its entailment of a proposed objective assertion.
sealed class EvidenceBasis {
  const EvidenceBasis();
  CanonicalObject encode({required bool canonical});
  CanonicalObject toWire() => encode(canonical: false);
  CanonicalObject toCanonical() => encode(canonical: true);
  @override
  bool operator ==(Object other) =>
      other is EvidenceBasis &&
      runtimeType == other.runtimeType &&
      toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toCanonical().toText().hashCode;
  static EvidenceBasis fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'author_decision':
        f.allow({'kind', 'note'});
        return AuthorDecisionBasis(f.string('note'));
      case 'source_anchor':
        f.allow({'kind', 'anchor', 'verified'});
        return SourceAnchorBasis(
          RecordRef.fromCanonical(f.require('anchor')),
          f.boolean('verified'),
        );
      case 'event_effect':
        f.allow({'kind', 'event', 'slot'});
        return EventEffectBasis(
          RecordRef.fromCanonical(f.require('event')),
          f.string('slot'),
        );
      case 'instance_initialization':
        f.allow({'kind', 'start', 'definition', 'source_revision'});
        return InstanceInitializationBasis(
          VersionRef.fromCanonical(f.require('start')),
          VersionRef.fromCanonical(f.require('definition')),
          RevisionId.parse(f.string('source_revision')),
        );
      case 'imported_claim':
        f.allow({'kind'});
        return const ImportedClaimBasis();
      case 'derivation':
        f.allow({'kind', 'chain', 'evaluator'});
        return DerivationBasis(
          f.array('chain').map(VersionRef.fromCanonical),
          f.optionalString('evaluator'),
        );
      default:
        throw const FormatException('Unknown evidence basis');
    }
  }
}

final class AuthorDecisionBasis extends EvidenceBasis {
  const AuthorDecisionBasis(this.note);
  final String note;
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('author_decision', [MapEntry('note', CanonicalString(note))]);
}

final class SourceAnchorBasis extends EvidenceBasis {
  const SourceAnchorBasis(this.anchor, this.verified);
  final RecordRef anchor;
  final bool verified;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('source_anchor', [
    MapEntry('anchor', anchor.toCanonical()),
    MapEntry('verified', CanonicalBool(verified)),
  ]);
}

final class EventEffectBasis extends EvidenceBasis {
  const EventEffectBasis(this.event, this.slot);
  final RecordRef event;
  final String slot;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('event_effect', [
    MapEntry('event', event.toCanonical()),
    MapEntry('slot', CanonicalString(slot)),
  ]);
}

final class InstanceInitializationBasis extends EvidenceBasis {
  const InstanceInitializationBasis(
    this.start,
    this.definition,
    this.sourceRevision,
  );
  final VersionRef start, definition;
  final RevisionId sourceRevision;
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('instance_initialization', [
        MapEntry('start', start.toCanonical()),
        MapEntry('definition', definition.toCanonical()),
        MapEntry('source_revision', CanonicalString(sourceRevision.value)),
      ]);
}

final class ImportedClaimBasis extends EvidenceBasis {
  const ImportedClaimBasis();
  @override
  CanonicalObject encode({required bool canonical}) =>
      tagged('imported_claim', []);
}

final class DerivationBasis extends EvidenceBasis {
  DerivationBasis(Iterable<VersionRef> chain, this.evaluator)
    : chain = List.unmodifiable(chain);
  final List<VersionRef> chain;
  final String? evaluator;
  @override
  CanonicalObject encode({required bool canonical}) => tagged('derivation', [
    MapEntry('chain', CanonicalArray(chain.map((v) => v.toCanonical()))),
    if (!canonical || evaluator != null)
      MapEntry(
        'evaluator',
        evaluator == null ? const CanonicalNull() : CanonicalString(evaluator!),
      ),
  ]);
}

String _string(CanonicalValue value) {
  if (value is! CanonicalString) {
    throw const FormatException('Expected enum string');
  }
  return value.value;
}
