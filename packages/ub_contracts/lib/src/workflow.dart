import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';

enum Submission {
  draft('draft'),
  submitted('submitted');

  const Submission(this.wireName);
  final String wireName;
  static Submission fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown Submission'),
  );
}

enum Coverage {
  complete('complete'),
  partial('partial'),
  unsupported('unsupported'),
  restricted('restricted'),
  failed('failed');

  const Coverage(this.wireName);
  final String wireName;
  static Coverage fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown Coverage'),
  );
}

enum OperationKind {
  propose('propose'),
  validate('validate'),
  commit('commit'),
  cancel('cancel');

  const OperationKind(this.wireName);
  final String wireName;
  static OperationKind fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown OperationKind'),
  );
}

enum OperationState {
  queued('queued'),
  running('running'),
  awaitingAuthority('awaiting_authority'),
  committing('committing'),
  succeeded('succeeded'),
  failed('failed'),
  cancelled('cancelled'),
  interrupted('interrupted');

  const OperationState(this.wireName);
  final String wireName;
  static OperationState fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown OperationState'),
  );
}

final class ProposalRef {
  ProposalRef({
    required this.proposalId,
    required BigInt version,
    required this.digest,
  }) : version = checkedU64(version);
  final ProposalId proposalId;
  final BigInt version;
  final String digest;
  @override
  bool operator ==(Object other) =>
      other is ProposalRef &&
      proposalId == other.proposalId &&
      version == other.version &&
      digest == other.digest;
  @override
  int get hashCode => Object.hash(proposalId, version, digest);
  factory ProposalRef.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'proposal_id', 'version', 'digest'});
    return ProposalRef(
      proposalId: ProposalId.parse(wireString(f.require('proposal_id'))),
      version: f.u64('version'),
      digest: f.string('digest'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('proposal_id', CanonicalString(proposalId.value)),
    MapEntry('version', CanonicalNumber(version.toString())),
    MapEntry('digest', CanonicalString(digest)),
  ]);
}

final class Proposal {
  Proposal({
    required this.baseFrame,
    this.worldScope,
    required this.proposalId,
    required BigInt version,
    required this.digest,
    required this.submission,
    required Iterable<DomainOperation> operations,
    Iterable<CompiledChange> compiledChanges = const [],
    required this.rationale,
    required this.canonical,
    required this.operationId,
    required this.withdrawn,
  }) : version = checkedU64(version),
       operations = List.unmodifiable(operations),
       compiledChanges = List.unmodifiable(compiledChanges);
  final Frame baseFrame;
  final WorldId? worldScope;
  final ProposalId proposalId;
  final BigInt version;
  final String digest;
  final Submission submission;
  final List<DomainOperation> operations;
  final List<CompiledChange> compiledChanges;
  final String rationale;
  final bool canonical;
  final OperationId operationId;
  final bool withdrawn;
  factory Proposal.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_frame',
      'world_scope',
      'proposal_id',
      'version',
      'digest',
      'submission',
      'operations',
      'compiled_changes',
      'rationale',
      'canonical',
      'operation_id',
      'withdrawn',
    });
    return Proposal(
      baseFrame: Frame.fromWire(f.require('base_frame')),
      worldScope: f.optional(
        'world_scope',
        (v) => WorldId.parse(wireString(v)),
      ),
      proposalId: ProposalId.parse(wireString(f.require('proposal_id'))),
      version: f.u64('version'),
      digest: f.string('digest'),
      submission: Submission.fromName(f.string('submission')),
      operations: f.array('operations').map((v) => DomainOperation.fromWire(v)),
      compiledChanges: f
          .array('compiled_changes', defaultEmpty: true)
          .map((v) => CompiledChange.fromWire(v)),
      rationale: f.string('rationale'),
      canonical: f.boolean('canonical'),
      operationId: OperationId.parse(wireString(f.require('operation_id'))),
      withdrawn: f.boolean('withdrawn'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_frame', baseFrame.toWire()),
    MapEntry(
      'world_scope',
      worldScope == null
          ? const CanonicalNull()
          : CanonicalString(worldScope!.value),
    ),
    MapEntry('proposal_id', CanonicalString(proposalId.value)),
    MapEntry('version', CanonicalNumber(version.toString())),
    MapEntry('digest', CanonicalString(digest)),
    MapEntry('submission', CanonicalString(submission.wireName)),
    MapEntry('operations', CanonicalArray(operations.map((v) => v.toWire()))),
    if (compiledChanges.isNotEmpty)
      MapEntry(
        'compiled_changes',
        CanonicalArray(compiledChanges.map((v) => v.toWire())),
      ),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry('canonical', CanonicalBool(canonical)),
    MapEntry('operation_id', CanonicalString(operationId.value)),
    MapEntry('withdrawn', CanonicalBool(withdrawn)),
  ]);
}

final class CompiledChange {
  CompiledChange({required this.recordId, this.expected, this.next});
  final RecordId recordId;
  final RecordVersionId? expected;
  final RecordVersion? next;
  factory CompiledChange.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'record_id', 'expected', 'next'});
    return CompiledChange(
      recordId: RecordId.parse(wireString(f.require('record_id'))),
      expected: f.optional(
        'expected',
        (v) => RecordVersionId.parse(wireString(v)),
      ),
      next: f.optional('next', (v) => RecordVersion.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('record_id', CanonicalString(recordId.value)),
    MapEntry(
      'expected',
      expected == null
          ? const CanonicalNull()
          : CanonicalString(expected!.value),
    ),
    MapEntry('next', next == null ? const CanonicalNull() : next!.toWire()),
  ]);
}

final class Impact {
  Impact({
    required Iterable<RecordId> records,
    required this.coverage,
    required Iterable<WorldId> worldIds,
  }) : records = List.unmodifiable(records),
       worldIds = List.unmodifiable(worldIds);
  final List<RecordId> records;
  final Coverage coverage;
  final List<WorldId> worldIds;
  factory Impact.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'records', 'coverage', 'world_ids'});
    return Impact(
      records: f.array('records').map((v) => RecordId.parse(wireString(v))),
      coverage: Coverage.fromName(f.string('coverage')),
      worldIds: f.array('world_ids').map((v) => WorldId.parse(wireString(v))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry(
      'records',
      CanonicalArray(records.map((v) => CanonicalString(v.value))),
    ),
    MapEntry('coverage', CanonicalString(coverage.wireName)),
    MapEntry(
      'world_ids',
      CanonicalArray(worldIds.map((v) => CanonicalString(v.value))),
    ),
  ]);
}

final class CommitReceipt {
  CommitReceipt({
    required this.operationId,
    required this.proposalId,
    required this.revision,
  });
  final OperationId operationId;
  final ProposalId proposalId;
  final RevisionId revision;
  factory CommitReceipt.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'operation_id', 'proposal_id', 'revision'});
    return CommitReceipt(
      operationId: OperationId.parse(wireString(f.require('operation_id'))),
      proposalId: ProposalId.parse(wireString(f.require('proposal_id'))),
      revision: RevisionId.parse(wireString(f.require('revision'))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('operation_id', CanonicalString(operationId.value)),
    MapEntry('proposal_id', CanonicalString(proposalId.value)),
    MapEntry('revision', CanonicalString(revision.value)),
  ]);
}
