import 'canonical.dart';
import 'fields.dart';
import 'ids.dart';
import 'references.dart';
import 'time_space.dart';

/// Fictional viewpoint is distinct from application permission.
sealed class Perspective {
  const Perspective();
  CanonicalValue toWire();
  CanonicalValue toCanonical();
  static Perspective fromWire(CanonicalValue value) {
    if (value is CanonicalString) {
      return switch (value.value) {
        'author' => const AuthorPerspective(),
        'reader' => const ReaderPerspective(),
        _ => throw const FormatException('Unknown perspective'),
      };
    }
    final f = Fields(value)..allow({'character', 'narrator'});
    if (f.values.length != 1) {
      throw const FormatException('Expected one perspective variant');
    }
    if (f.values.containsKey('character')) {
      return CharacterPerspective(RecordId.parse(f.string('character')));
    }
    return NarratorPerspective(RecordId.parse(f.string('narrator')));
  }

  @override
  bool operator ==(Object other) =>
      other is Perspective && toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toCanonical().toText().hashCode;
}

final class AuthorPerspective extends Perspective {
  const AuthorPerspective();
  @override
  CanonicalString toWire() => CanonicalString('author');
  @override
  CanonicalString toCanonical() => toWire();
}

final class ReaderPerspective extends Perspective {
  const ReaderPerspective();
  @override
  CanonicalString toWire() => CanonicalString('reader');
  @override
  CanonicalString toCanonical() => toWire();
}

final class CharacterPerspective extends Perspective {
  const CharacterPerspective(this.record);
  final RecordId record;
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('character', CanonicalString(record.value))]);
  @override
  CanonicalObject toCanonical() =>
      tagged('character', [MapEntry('record', CanonicalString(record.value))]);
}

final class NarratorPerspective extends Perspective {
  const NarratorPerspective(this.record);
  final RecordId record;
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('narrator', CanonicalString(record.value))]);
  @override
  CanonicalObject toCanonical() =>
      tagged('narrator', [MapEntry('record', CanonicalString(record.value))]);
}

enum EventTimeSide {
  before,
  after;

  static EventTimeSide fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown event time side'),
  );
}

/// Timeless is an explicit query, never an inferred current authored clock.
sealed class FrameTime {
  const FrameTime();
  CanonicalObject toWire();
  CanonicalValue toCanonical();
  static FrameTime fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'timeless':
        f.allow({'kind'});
        return const TimelessFrameTime();
      case 'at':
        f.allow({'kind', 'time'});
        return AtFrameTime(TemporalExpression.fromWire(f.require('time')));
      case 'at_event':
        f.allow({'kind', 'event', 'side'});
        return AtEventFrameTime(
          RecordRef.fromCanonical(f.require('event')),
          EventTimeSide.fromName(f.string('side')),
        );
      default:
        throw const FormatException('Unknown frame time');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FrameTime && toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toCanonical().toText().hashCode;
}

final class TimelessFrameTime extends FrameTime {
  const TimelessFrameTime();
  @override
  CanonicalObject toWire() => tagged('timeless', []);
  @override
  CanonicalString toCanonical() => CanonicalString('timeless');
}

final class AtFrameTime extends FrameTime {
  const AtFrameTime(this.time);
  final TemporalExpression time;
  @override
  CanonicalObject toWire() =>
      tagged('at', [MapEntry('time', time.encode(canonical: false))]);
  @override
  CanonicalObject toCanonical() =>
      tagged('at', [MapEntry('time', time.encode(canonical: true))]);
}

final class AtEventFrameTime extends FrameTime {
  const AtEventFrameTime(this.event, this.side);
  final RecordRef event;
  final EventTimeSide side;
  @override
  CanonicalObject toWire() => tagged('at_event', [
    MapEntry('event', event.toCanonical()),
    MapEntry('side', CanonicalString(side.name)),
  ]);
  @override
  CanonicalObject toCanonical() => toWire();
}

/// A resolved query frame. Ownership and expiry belong to service context
/// handles; per-request world focus never becomes hidden frame state.
final class Frame {
  const Frame({
    required this.universe,
    required this.continuity,
    required this.revision,
    required this.context,
    required this.time,
    required this.perspective,
    this.readerScene,
    this.personalSequence,
  });
  final UniverseId universe;
  final ContinuityId continuity;
  final RevisionId revision;
  final RecordRef context;
  final FrameTime time;
  final Perspective perspective;
  final RecordId? readerScene;
  final String? personalSequence;
  factory Frame.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({
        'universe',
        'continuity',
        'revision',
        'context',
        'time',
        'perspective',
        'readerScene',
        'personalSequence',
      });
    final scene = f.optionalString('readerScene');
    return Frame(
      universe: UniverseId.parse(f.string('universe')),
      continuity: ContinuityId.parse(f.string('continuity')),
      revision: RevisionId.parse(f.string('revision')),
      context: RecordRef.fromCanonical(f.require('context')),
      time: FrameTime.fromWire(f.require('time')),
      perspective: Perspective.fromWire(f.require('perspective')),
      readerScene: scene == null ? null : RecordId.parse(scene),
      personalSequence: f.optionalString('personalSequence'),
    );
  }
  CanonicalObject toWire() => _encode(canonical: false);
  CanonicalObject toCanonical() => _encode(canonical: true);
  CanonicalObject _encode({required bool canonical}) => CanonicalObject([
    MapEntry('universe', CanonicalString(universe.value)),
    MapEntry('continuity', CanonicalString(continuity.value)),
    MapEntry('revision', CanonicalString(revision.value)),
    MapEntry('context', context.toCanonical()),
    MapEntry('time', canonical ? time.toCanonical() : time.toWire()),
    MapEntry(
      'perspective',
      canonical ? perspective.toCanonical() : perspective.toWire(),
    ),
    if (readerScene != null)
      MapEntry('readerScene', CanonicalString(readerScene!.value)),
    if (personalSequence != null)
      MapEntry('personalSequence', CanonicalString(personalSequence!)),
  ]);
  @override
  bool operator ==(Object other) =>
      other is Frame && toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toCanonical().toText().hashCode;
}
