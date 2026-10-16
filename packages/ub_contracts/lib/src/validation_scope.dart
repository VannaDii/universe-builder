import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';
import 'workflow.dart';
import 'validation.dart';

/// Hash the complete unpaged execution core with its existing wire serializer.
/// The source-assessment wrapper is deliberately outside this digest.
Sha256Hex executionResultDigest(Validation execution) =>
    Sha256Hex(canonicalDigest(execution.toWire()));

final class Sha256Hex {
  Sha256Hex(this.value) {
    if (value.length != 64 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw const FormatException(
        'Expected 64 lower-case hexadecimal characters',
      );
    }
  }
  final String value;
  @override
  bool operator ==(Object other) => other is Sha256Hex && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

final class AssessmentId {
  AssessmentId(this.value) {
    if (value.length != 28 || !RegExp(r'^asm_[0-9a-f]{24}$').hasMatch(value)) {
      throw const FormatException(
        'Expected asm_ plus 24 lower-case hexadecimal characters',
      );
    }
  }
  final String value;
  @override
  bool operator ==(Object other) =>
      other is AssessmentId && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

enum SourceRepresentation {
  exactUtf8V1('exact-utf8-v1');

  const SourceRepresentation(this.wireName);
  final String wireName;
  static SourceRepresentation fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown SourceRepresentation'),
  );
}

enum DeclaredConclusion {
  consistentWithDeclaredInventory('consistent_with_declared_inventory'),
  inconsistent('inconsistent'),
  unresolved('unresolved');

  const DeclaredConclusion(this.wireName);
  final String wireName;
  static DeclaredConclusion fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown DeclaredConclusion'),
  );
}

enum ByteVerification {
  verified('verified');

  const ByteVerification(this.wireName);
  final String wireName;
  static ByteVerification fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown ByteVerification'),
  );
}

enum StaleReason {
  candidateChanged('candidate_changed'),
  sourceChanged('source_changed'),
  editionChanged('edition_changed'),
  dependencyChanged('dependency_changed'),
  selectionChanged('selection_changed'),
  evaluatorChanged('evaluator_changed');

  const StaleReason(this.wireName);
  final String wireName;
  static StaleReason fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown StaleReason'),
  );
}

enum UnavailableReason {
  missingRetainedMaterial('missing_retained_material'),
  unsupportedRepresentation('unsupported_representation'),
  failedOrCancelledCheck('failed_or_cancelled_check');

  const UnavailableReason(this.wireName);
  final String wireName;
  static UnavailableReason fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown UnavailableReason'),
  );
}

enum RestrictedCoverage {
  restricted('restricted');

  const RestrictedCoverage(this.wireName);
  final String wireName;
  static RestrictedCoverage fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown RestrictedCoverage'),
  );
}

enum CheckScope {
  candidate,
  dependencies,
  universe;

  static CheckScope fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown check scope'),
  );
  String get wireName => name;
}

final class AssessmentVersionRef {
  const AssessmentVersionRef({
    required this.universe,
    required this.record,
    required this.version,
  });
  final UniverseId universe;
  final RecordId record;
  final RecordVersionId version;
  factory AssessmentVersionRef.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'universe', 'record', 'version'});
    return AssessmentVersionRef(
      universe: UniverseId.parse(wireString(f.require('universe'))),
      record: RecordId.parse(wireString(f.require('record'))),
      version: RecordVersionId.parse(wireString(f.require('version'))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('universe', CanonicalString(universe.value)),
    MapEntry('record', CanonicalString(record.value)),
    MapEntry('version', CanonicalString(version.value)),
  ]);
}

final class ByteRange {
  ByteRange({required BigInt start, required BigInt end})
    : start = checkedU64(start),
      end = checkedU64(end);
  final BigInt start;
  final BigInt end;
  factory ByteRange.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'start', 'end'});
    return ByteRange(start: f.u64('start'), end: f.u64('end'));
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('start', CanonicalNumber(start.toString())),
    MapEntry('end', CanonicalNumber(end.toString())),
  ]);
}

final class SourceBinding {
  SourceBinding({
    required this.key,
    required this.sourceVersion,
    required this.blobDigest,
    required BigInt byteSize,
    required this.representation,
    required Iterable<ByteRange> ranges,
    required this.workEdition,
    required this.passageId,
  }) : byteSize = checkedU64(byteSize),
       ranges = List.unmodifiable(ranges);
  final String key;
  final AssessmentVersionRef sourceVersion;
  final Sha256Hex blobDigest;
  final BigInt byteSize;
  final SourceRepresentation representation;
  final List<ByteRange> ranges;
  final AssessmentVersionRef? workEdition;
  final String? passageId;
  factory SourceBinding.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'key',
      'source_version',
      'blob_digest',
      'byte_size',
      'representation',
      'ranges',
      'work_edition',
      'passage_id',
    });
    f.require('passage_id');
    f.require('work_edition');
    return SourceBinding(
      key: wireString(f.require('key')),
      sourceVersion: AssessmentVersionRef.fromWire(f.require('source_version')),
      blobDigest: Sha256Hex(wireString(f.require('blob_digest'))),
      byteSize: f.u64('byte_size'),
      representation: SourceRepresentation.fromName(
        wireString(f.require('representation')),
      ),
      ranges: f.array('ranges').map((v) => ByteRange.fromWire(v)),
      workEdition: f.optional(
        'work_edition',
        (v) => AssessmentVersionRef.fromWire(v),
      ),
      passageId: f.optional('passage_id', (v) => wireString(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('key', CanonicalString(key)),
    MapEntry('source_version', sourceVersion.toWire()),
    MapEntry('blob_digest', CanonicalString(blobDigest.value)),
    MapEntry('byte_size', CanonicalNumber(byteSize.toString())),
    MapEntry('representation', CanonicalString(representation.wireName)),
    MapEntry('ranges', CanonicalArray(ranges.map((v) => v.toWire()))),
    MapEntry(
      'work_edition',
      workEdition == null ? const CanonicalNull() : workEdition!.toWire(),
    ),
    MapEntry(
      'passage_id',
      passageId == null ? const CanonicalNull() : CanonicalString(passageId!),
    ),
  ]);
}

final class AssessmentRef {
  const AssessmentRef({required this.assessmentId, required this.digest});
  final AssessmentId assessmentId;
  final Sha256Hex digest;
  factory AssessmentRef.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'assessment_id', 'digest'});
    return AssessmentRef(
      assessmentId: AssessmentId(wireString(f.require('assessment_id'))),
      digest: Sha256Hex(wireString(f.require('digest'))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('assessment_id', CanonicalString(assessmentId.value)),
    MapEntry('digest', CanonicalString(digest.value)),
  ]);
}

final class OperationStatusV3 {
  const OperationStatusV3({
    this.validation,
    this.failure,
    required this.operationId,
    required this.kind,
    required this.state,
    this.proposal,
    this.receipt,
    required this.cancellationRequested,
  });
  final ValidationV3? validation;
  final String? failure;
  final OperationId operationId;
  final OperationKind kind;
  final OperationState state;
  final Proposal? proposal;
  final CommitReceipt? receipt;
  final bool cancellationRequested;
  factory OperationStatusV3.fromStored(
    OperationStatus stored,
    ValidationV3? validation,
  ) => OperationStatusV3(
    validation: validation,
    failure: stored.failure,
    operationId: stored.operationId,
    kind: stored.kind,
    state: stored.state,
    proposal: stored.proposal,
    receipt: stored.receipt,
    cancellationRequested: stored.cancellationRequested,
  );
  factory OperationStatusV3.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'validation',
      'failure',
      'operation_id',
      'kind',
      'state',
      'proposal',
      'receipt',
      'cancellation_requested',
    });
    return OperationStatusV3(
      validation: f.optional('validation', (v) => ValidationV3.fromWire(v)),
      failure: f.optional('failure', (v) => wireString(v)),
      operationId: OperationId.parse(wireString(f.require('operation_id'))),
      kind: OperationKind.fromName(wireString(f.require('kind'))),
      state: OperationState.fromName(wireString(f.require('state'))),
      proposal: f.optional('proposal', (v) => Proposal.fromWire(v)),
      receipt: f.optional('receipt', (v) => CommitReceipt.fromWire(v)),
      cancellationRequested: f.boolean('cancellation_requested'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry(
      'validation',
      validation == null ? const CanonicalNull() : validation!.toWire(),
    ),
    MapEntry(
      'failure',
      failure == null ? const CanonicalNull() : CanonicalString(failure!),
    ),
    MapEntry('operation_id', CanonicalString(operationId.value)),
    MapEntry('kind', CanonicalString(kind.wireName)),
    MapEntry('state', CanonicalString(state.wireName)),
    MapEntry(
      'proposal',
      proposal == null ? const CanonicalNull() : proposal!.toWire(),
    ),
    MapEntry(
      'receipt',
      receipt == null ? const CanonicalNull() : receipt!.toWire(),
    ),
    MapEntry('cancellation_requested', CanonicalBool(cancellationRequested)),
  ]);
}

sealed class SubmittedInput {
  const SubmittedInput();
  CanonicalObject toWire();
  static SubmittedInput fromWire(CanonicalValue value) {
    if (value is! CanonicalObject) {
      throw const FormatException('Expected variant object');
    }
    final kind = wireString(
      value.fields
          .firstWhere(
            (e) => e.key == 'kind',
            orElse: () => throw const FormatException('Missing kind'),
          )
          .value,
    );
    return switch (kind) {
      'query' => QueryInput.fromWire(value),
      'record_candidate' => RecordCandidateInput.fromWire(value),
      'source_assessed_candidate' => SourceAssessedCandidateInput.fromWire(
        value,
      ),
      _ => throw const FormatException('Unknown variant'),
    };
  }
}

final class QueryInput extends SubmittedInput {
  const QueryInput({required this.frame, required this.checkScope});
  final Frame frame;
  final CheckScope checkScope;
  factory QueryInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'frame', 'check_scope', 'kind'});
    if (f.string('kind') != 'query') {
      throw const FormatException('Wrong variant');
    }
    return QueryInput(
      frame: Frame.fromWire(f.require('frame')),
      checkScope: CheckScope.fromName(wireString(f.require('check_scope'))),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('query')),
    MapEntry('frame', frame.toWire()),
    MapEntry('check_scope', CanonicalString(checkScope.wireName)),
  ]);
}

final class RecordCandidateInput extends SubmittedInput {
  const RecordCandidateInput({
    required this.proposal,
    required this.includesSources,
  });
  final ProposalRef proposal;
  final bool includesSources;
  factory RecordCandidateInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'proposal', 'includes_sources', 'kind'});
    if (f.string('kind') != 'record_candidate') {
      throw const FormatException('Wrong variant');
    }
    return RecordCandidateInput(
      proposal: ProposalRef.fromWire(f.require('proposal')),
      includesSources: f.boolean('includes_sources'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('record_candidate')),
    MapEntry('proposal', proposal.toWire()),
    MapEntry('includes_sources', CanonicalBool(includesSources)),
  ]);
}

final class SourceAssessedCandidateInput extends SubmittedInput {
  SourceAssessedCandidateInput({
    required this.proposal,
    required Iterable<SourceBinding> sources,
    required this.inventoryDigest,
  }) : sources = List.unmodifiable(sources);
  final ProposalRef proposal;
  final List<SourceBinding> sources;
  final Sha256Hex inventoryDigest;
  factory SourceAssessedCandidateInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'proposal',
      'sources',
      'inventory_digest',
      'kind',
    });
    if (f.string('kind') != 'source_assessed_candidate') {
      throw const FormatException('Wrong variant');
    }
    return SourceAssessedCandidateInput(
      proposal: ProposalRef.fromWire(f.require('proposal')),
      sources: f.array('sources').map((v) => SourceBinding.fromWire(v)),
      inventoryDigest: Sha256Hex(wireString(f.require('inventory_digest'))),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('source_assessed_candidate')),
    MapEntry('proposal', proposal.toWire()),
    MapEntry('sources', CanonicalArray(sources.map((v) => v.toWire()))),
    MapEntry('inventory_digest', CanonicalString(inventoryDigest.value)),
  ]);
}

sealed class AssessmentState {
  const AssessmentState();
  CanonicalObject toWire();
  static AssessmentState fromWire(CanonicalValue value) {
    if (value is! CanonicalObject) {
      throw const FormatException('Expected variant object');
    }
    final kind = wireString(
      value.fields
          .firstWhere(
            (e) => e.key == 'kind',
            orElse: () => throw const FormatException('Missing kind'),
          )
          .value,
    );
    return switch (kind) {
      'absent' => AbsentAssessment.fromWire(value),
      'unavailable' => UnavailableAssessment.fromWire(value),
      'stale' => StaleAssessment.fromWire(value),
      'bound' => BoundAssessment.fromWire(value),
      _ => throw const FormatException('Unknown variant'),
    };
  }
}

final class AbsentAssessment extends AssessmentState {
  const AbsentAssessment();
  factory AbsentAssessment.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind'});
    if (f.string('kind') != 'absent') {
      throw const FormatException('Wrong variant');
    }
    return AbsentAssessment();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('kind', CanonicalString('absent'))]);
}

final class UnavailableAssessment extends AssessmentState {
  const UnavailableAssessment({required this.reason});
  final UnavailableReason reason;
  factory UnavailableAssessment.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'reason', 'kind'});
    if (f.string('kind') != 'unavailable') {
      throw const FormatException('Wrong variant');
    }
    return UnavailableAssessment(
      reason: UnavailableReason.fromName(wireString(f.require('reason'))),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('unavailable')),
    MapEntry('reason', CanonicalString(reason.wireName)),
  ]);
}

final class StaleAssessment extends AssessmentState {
  StaleAssessment({
    required this.assessmentReference,
    required Iterable<StaleReason> reasons,
  }) : reasons = List.unmodifiable(reasons);
  final AssessmentRef assessmentReference;
  final List<StaleReason> reasons;
  factory StaleAssessment.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'assessment_reference', 'reasons', 'kind'});
    if (f.string('kind') != 'stale') {
      throw const FormatException('Wrong variant');
    }
    return StaleAssessment(
      assessmentReference: AssessmentRef.fromWire(
        f.require('assessment_reference'),
      ),
      reasons: f
          .array('reasons')
          .map((v) => StaleReason.fromName(wireString(v))),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('stale')),
    MapEntry('assessment_reference', assessmentReference.toWire()),
    MapEntry(
      'reasons',
      CanonicalArray(reasons.map((v) => CanonicalString(v.wireName))),
    ),
  ]);
}

final class BoundAssessment extends AssessmentState {
  BoundAssessment({
    required this.assessmentReference,
    required BigInt selectionGeneration,
    required this.byteVerification,
    required this.declaredConclusion,
    required BigInt inventoryCount,
    required BigInt mappingCount,
    required BigInt unresolvedCount,
    required this.inventoryDigest,
  }) : selectionGeneration = checkedU64(selectionGeneration),
       inventoryCount = checkedU64(inventoryCount),
       mappingCount = checkedU64(mappingCount),
       unresolvedCount = checkedU64(unresolvedCount);
  final AssessmentRef assessmentReference;
  final BigInt selectionGeneration;
  final ByteVerification byteVerification;
  final DeclaredConclusion declaredConclusion;
  final BigInt inventoryCount;
  final BigInt mappingCount;
  final BigInt unresolvedCount;
  final Sha256Hex inventoryDigest;
  factory BoundAssessment.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'assessment_reference',
      'selection_generation',
      'byte_verification',
      'declared_conclusion',
      'inventory_count',
      'mapping_count',
      'unresolved_count',
      'inventory_digest',
      'kind',
    });
    if (f.string('kind') != 'bound') {
      throw const FormatException('Wrong variant');
    }
    return BoundAssessment(
      assessmentReference: AssessmentRef.fromWire(
        f.require('assessment_reference'),
      ),
      selectionGeneration: f.u64('selection_generation'),
      byteVerification: ByteVerification.fromName(
        wireString(f.require('byte_verification')),
      ),
      declaredConclusion: DeclaredConclusion.fromName(
        wireString(f.require('declared_conclusion')),
      ),
      inventoryCount: f.u64('inventory_count'),
      mappingCount: f.u64('mapping_count'),
      unresolvedCount: f.u64('unresolved_count'),
      inventoryDigest: Sha256Hex(wireString(f.require('inventory_digest'))),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('bound')),
    MapEntry('assessment_reference', assessmentReference.toWire()),
    MapEntry(
      'selection_generation',
      CanonicalNumber(selectionGeneration.toString()),
    ),
    MapEntry('byte_verification', CanonicalString(byteVerification.wireName)),
    MapEntry(
      'declared_conclusion',
      CanonicalString(declaredConclusion.wireName),
    ),
    MapEntry('inventory_count', CanonicalNumber(inventoryCount.toString())),
    MapEntry('mapping_count', CanonicalNumber(mappingCount.toString())),
    MapEntry('unresolved_count', CanonicalNumber(unresolvedCount.toString())),
    MapEntry('inventory_digest', CanonicalString(inventoryDigest.value)),
  ]);
}

sealed class RestrictedInput {
  const RestrictedInput();
  CanonicalObject toWire();
  static RestrictedInput fromWire(CanonicalValue value) {
    if (value is! CanonicalObject) {
      throw const FormatException('Expected variant object');
    }
    final kind = wireString(
      value.fields
          .firstWhere(
            (e) => e.key == 'kind',
            orElse: () => throw const FormatException('Missing kind'),
          )
          .value,
    );
    return switch (kind) {
      'restricted' => RestrictedInputValue.fromWire(value),
      _ => throw const FormatException('Unknown variant'),
    };
  }
}

final class RestrictedInputValue extends RestrictedInput {
  const RestrictedInputValue();
  factory RestrictedInputValue.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind'});
    if (f.string('kind') != 'restricted') {
      throw const FormatException('Wrong variant');
    }
    return RestrictedInputValue();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('kind', CanonicalString('restricted'))]);
}

sealed class RestrictedAssessment {
  const RestrictedAssessment();
  CanonicalObject toWire();
  static RestrictedAssessment fromWire(CanonicalValue value) {
    if (value is! CanonicalObject) {
      throw const FormatException('Expected variant object');
    }
    final kind = wireString(
      value.fields
          .firstWhere(
            (e) => e.key == 'kind',
            orElse: () => throw const FormatException('Missing kind'),
          )
          .value,
    );
    return switch (kind) {
      'restricted' => RestrictedAssessmentValue.fromWire(value),
      _ => throw const FormatException('Unknown variant'),
    };
  }
}

final class RestrictedAssessmentValue extends RestrictedAssessment {
  const RestrictedAssessmentValue();
  factory RestrictedAssessmentValue.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind'});
    if (f.string('kind') != 'restricted') {
      throw const FormatException('Wrong variant');
    }
    return RestrictedAssessmentValue();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('kind', CanonicalString('restricted'))]);
}

sealed class ValidationV3 {
  const ValidationV3();
  factory ValidationV3.restricted() => const RestrictedValidation(
    executionCoverage: RestrictedCoverage.restricted,
    submittedInput: RestrictedInputValue(),
    assessment: RestrictedAssessmentValue(),
  );
  Validation? get execution;
  CanonicalObject toWire();
  static ValidationV3 fromWire(CanonicalValue value) {
    if (value is! CanonicalObject) {
      throw const FormatException('Expected variant object');
    }
    final kind = wireString(
      value.fields
          .firstWhere(
            (e) => e.key == 'kind',
            orElse: () => throw const FormatException('Missing kind'),
          )
          .value,
    );
    return switch (kind) {
      'evaluated' => EvaluatedValidation.fromWire(value),
      'restricted' => RestrictedValidation.fromWire(value),
      _ => throw const FormatException('Unknown variant'),
    };
  }
}

final class EvaluatedValidation extends ValidationV3 {
  const EvaluatedValidation({
    required this.execution,
    required this.submittedInput,
    required this.assessment,
    required this.finalBindingDigest,
  });
  @override
  final Validation execution;
  final SubmittedInput submittedInput;
  final AssessmentState assessment;
  final Sha256Hex? finalBindingDigest;
  factory EvaluatedValidation.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'execution',
      'submitted_input',
      'assessment',
      'final_binding_digest',
      'kind',
    });
    if (f.string('kind') != 'evaluated') {
      throw const FormatException('Wrong variant');
    }
    f.require('final_binding_digest');
    return EvaluatedValidation(
      execution: Validation.fromWire(f.require('execution')),
      submittedInput: SubmittedInput.fromWire(f.require('submitted_input')),
      assessment: AssessmentState.fromWire(f.require('assessment')),
      finalBindingDigest: f.optional(
        'final_binding_digest',
        (v) => Sha256Hex(wireString(v)),
      ),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('evaluated')),
    MapEntry('execution', execution.toWire()),
    MapEntry('submitted_input', submittedInput.toWire()),
    MapEntry('assessment', assessment.toWire()),
    MapEntry(
      'final_binding_digest',
      finalBindingDigest == null
          ? const CanonicalNull()
          : CanonicalString(finalBindingDigest!.value),
    ),
  ]);
}

final class RestrictedValidation extends ValidationV3 {
  const RestrictedValidation({
    required this.executionCoverage,
    required this.submittedInput,
    required this.assessment,
  });
  final RestrictedCoverage executionCoverage;
  final RestrictedInput submittedInput;
  final RestrictedAssessment assessment;
  @override
  Validation? get execution => null;
  factory RestrictedValidation.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'execution_coverage',
      'submitted_input',
      'assessment',
      'kind',
    });
    if (f.string('kind') != 'restricted') {
      throw const FormatException('Wrong variant');
    }
    return RestrictedValidation(
      executionCoverage: RestrictedCoverage.fromName(
        wireString(f.require('execution_coverage')),
      ),
      submittedInput: RestrictedInput.fromWire(f.require('submitted_input')),
      assessment: RestrictedAssessment.fromWire(f.require('assessment')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('restricted')),
    MapEntry('execution_coverage', CanonicalString(executionCoverage.wireName)),
    MapEntry('submitted_input', submittedInput.toWire()),
    MapEntry('assessment', assessment.toWire()),
  ]);
}
