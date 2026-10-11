part of 'records.dart';

enum PlanStatus {
  active,
  abandoned,
  achieved;

  static PlanStatus fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown plan status'),
  );
}

enum CommitmentStatus {
  unfulfilled,
  fulfilled,
  breached,
  released;

  static CommitmentStatus fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown commitment status'),
  );
}

/// An authored plan never executes steps or reserves resources implicitly.
final class GoalRecord extends RecordPayload {
  GoalRecord({
    required this.actor,
    this.desired,
    required Iterable<Expr> prerequisites,
    required Iterable<RecordRef> steps,
    required this.status,
    required this.validity,
  }) : prerequisites = List.unmodifiable(prerequisites),
       steps = List.unmodifiable(steps);
  final RecordRef actor;
  final RecordRef? desired;
  final List<Expr> prerequisites;
  final List<RecordRef> steps;
  final PlanStatus status;
  final Validity validity;
  factory GoalRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.goal, {
      'actor',
      'desired',
      'prerequisites',
      'steps',
      'status',
      'validity',
    });
    return GoalRecord(
      actor: RecordRef.fromCanonical(f.require('actor')),
      desired: _optionalRef(f, 'desired'),
      prerequisites: f.array('prerequisites').map(Expr.fromWire),
      steps: f.array('steps').map(RecordRef.fromCanonical),
      status: PlanStatus.fromName(f.string('status')),
      validity: Validity.fromWire(f.require('validity')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.goal;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('actor', actor.toCanonical()),
    MapEntry('desired', _nullableRef(desired)),
    MapEntry(
      'prerequisites',
      CanonicalArray(prerequisites.map((e) => e.toWire())),
    ),
    MapEntry('steps', _refs(steps)),
    MapEntry('status', CanonicalString(status.name)),
    MapEntry('validity', validity.toWire()),
  ]);
}

final class CommitmentParty {
  const CommitmentParty(this.record, this.role);
  final RecordRef record;
  final String role;
  factory CommitmentParty.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'record', 'role'});
    return CommitmentParty(
      RecordRef.fromCanonical(f.require('record')),
      f.string('role'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('record', record.toCanonical()),
    MapEntry('role', CanonicalString(role)),
  ]);
}

/// Breach is an authored state; it establishes no automatic consequences.
final class CommitmentRecord extends RecordPayload {
  CommitmentRecord({
    required Iterable<CommitmentParty> parties,
    required this.obligated,
    required Iterable<Expr> conditions,
    this.deadline,
    required this.status,
  }) : parties = List.unmodifiable(parties),
       conditions = List.unmodifiable(conditions);
  final List<CommitmentParty> parties;
  final RecordRef obligated;
  final List<Expr> conditions;
  final TemporalExpression? deadline;
  final CommitmentStatus status;
  factory CommitmentRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.commitment, {
      'parties',
      'obligated',
      'conditions',
      'deadline',
      'status',
    });
    return CommitmentRecord(
      parties: f.array('parties').map(CommitmentParty.fromWire),
      obligated: RecordRef.fromCanonical(f.require('obligated')),
      conditions: f.array('conditions').map(Expr.fromWire),
      deadline: _optionalTime(f, 'deadline'),
      status: CommitmentStatus.fromName(f.string('status')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.commitment;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('parties', CanonicalArray(parties.map((p) => p.toWire()))),
    MapEntry('obligated', obligated.toCanonical()),
    MapEntry('conditions', CanonicalArray(conditions.map((e) => e.toWire()))),
    MapEntry('deadline', _nullableTime(deadline)),
    MapEntry('status', CanonicalString(status.name)),
  ]);
}
