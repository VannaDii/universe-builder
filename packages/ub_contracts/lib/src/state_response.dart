import 'package:ub_domain/ub_domain.dart';

import 'workflow.dart';
import 'wire.dart';

// Evidence projections do not choose a candidate or infer absent facts.

final class DerivedFact {
  DerivedFact({
    required this.subject,
    required this.predicate,
    required this.value,
    required Iterable<RecordVersionId> evidence,
    required this.rule,
  }) : evidence = List.unmodifiable(evidence);
  final RecordRef subject;
  final RecordRef predicate;
  final DomainValue value;
  final List<RecordVersionId> evidence;
  final RecordId rule;
  factory DerivedFact.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'subject',
      'predicate',
      'value',
      'evidence',
      'rule',
    });
    return DerivedFact(
      subject: RecordRef.fromCanonical(f.require('subject')),
      predicate: RecordRef.fromCanonical(f.require('predicate')),
      value: DomainValue.fromWire(f.require('value')),
      evidence: f
          .array('evidence')
          .map((v) => RecordVersionId.parse(wireString(v))),
      rule: RecordId.parse(wireString(f.require('rule'))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('subject', subject.toCanonical()),
    MapEntry('predicate', predicate.toCanonical()),
    MapEntry('value', value.toWire()),
    MapEntry(
      'evidence',
      CanonicalArray(evidence.map((v) => CanonicalString(v.value))),
    ),
    MapEntry('rule', CanonicalString(rule.value)),
  ]);
}

final class ObjectEvidence {
  ObjectEvidence({
    required this.record,
    this.applicability,
    required Iterable<String> unknowns,
  }) : unknowns = List.unmodifiable(unknowns);
  final RecordVersion record;
  final bool? applicability;
  final List<String> unknowns;
  factory ObjectEvidence.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'record', 'applicability', 'unknowns'});
    return ObjectEvidence(
      record: RecordVersion.fromWire(f.require('record')),
      applicability: f.optional('applicability', (v) => _stateBool(v)),
      unknowns: f.array('unknowns').map((v) => wireString(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('record', record.toWire()),
    MapEntry(
      'applicability',
      applicability == null
          ? const CanonicalNull()
          : CanonicalBool(applicability!),
    ),
    MapEntry(
      'unknowns',
      CanonicalArray(unknowns.map((v) => CanonicalString(v))),
    ),
  ]);
}

final class ObjectConflict {
  ObjectConflict({
    this.applicability,
    required this.predicate,
    required Iterable<RecordVersionId> assertions,
    required this.initialValues,
  }) : assertions = List.unmodifiable(assertions);
  final bool? applicability;
  final RecordId predicate;
  final List<RecordVersionId> assertions;
  final bool initialValues;
  factory ObjectConflict.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'applicability',
      'predicate',
      'assertions',
      'initial_values',
    });
    return ObjectConflict(
      applicability: f.optional('applicability', (v) => _stateBool(v)),
      predicate: RecordId.parse(wireString(f.require('predicate'))),
      assertions: f
          .array('assertions')
          .map((v) => RecordVersionId.parse(wireString(v))),
      initialValues: _stateBool(f.require('initial_values')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry(
      'applicability',
      applicability == null
          ? const CanonicalNull()
          : CanonicalBool(applicability!),
    ),
    MapEntry('predicate', CanonicalString(predicate.value)),
    MapEntry(
      'assertions',
      CanonicalArray(assertions.map((v) => CanonicalString(v.value))),
    ),
    MapEntry('initial_values', CanonicalBool(initialValues)),
  ]);
}

final class ContextualNameEvidence {
  ContextualNameEvidence({required this.name, this.applicability});
  final ContextualName name;
  final bool? applicability;
  factory ContextualNameEvidence.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'name', 'applicability'});
    return ContextualNameEvidence(
      name: ContextualName.fromWire(f.require('name')),
      applicability: f.optional('applicability', (v) => _stateBool(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', name.toWire()),
    MapEntry(
      'applicability',
      applicability == null
          ? const CanonicalNull()
          : CanonicalBool(applicability!),
    ),
  ]);
}

final class EffectiveObject {
  EffectiveObject({
    required this.identity,
    Iterable<ContextualNameEvidence> contextualNames = const [],
    required Iterable<RecordVersion> ancestry,
    required this.ancestryComplete,
    required Iterable<ObjectEvidence> sharedAttributes,
    required Iterable<ObjectEvidence> instanceFacts,
    required Iterable<ObjectEvidence> initialValueCandidates,
    required Iterable<InitializationReceipt> initializationReceipts,
    required this.initializationHistoryCoverage,
    required Iterable<ObjectEvidence> behavioralRequirements,
    required Iterable<ObjectEvidence> rules,
    required Iterable<RecordVersion> dependencies,
    required Iterable<ObjectConflict> conflicts,
    required Iterable<String> unknowns,
    required this.coverage,
  }) : contextualNames = List.unmodifiable(contextualNames),
       ancestry = List.unmodifiable(ancestry),
       sharedAttributes = List.unmodifiable(sharedAttributes),
       instanceFacts = List.unmodifiable(instanceFacts),
       initialValueCandidates = List.unmodifiable(initialValueCandidates),
       initializationReceipts = List.unmodifiable(initializationReceipts),
       behavioralRequirements = List.unmodifiable(behavioralRequirements),
       rules = List.unmodifiable(rules),
       dependencies = List.unmodifiable(dependencies),
       conflicts = List.unmodifiable(conflicts),
       unknowns = List.unmodifiable(unknowns);
  final RecordVersion identity;
  final List<ContextualNameEvidence> contextualNames;
  final List<RecordVersion> ancestry;
  final bool ancestryComplete;
  final List<ObjectEvidence> sharedAttributes;
  final List<ObjectEvidence> instanceFacts;
  final List<ObjectEvidence> initialValueCandidates;
  final List<InitializationReceipt> initializationReceipts;
  final Coverage initializationHistoryCoverage;
  final List<ObjectEvidence> behavioralRequirements;
  final List<ObjectEvidence> rules;
  final List<RecordVersion> dependencies;
  final List<ObjectConflict> conflicts;
  final List<String> unknowns;
  final Coverage coverage;
  factory EffectiveObject.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'identity',
      'contextual_names',
      'ancestry',
      'ancestry_complete',
      'shared_attributes',
      'instance_facts',
      'initial_value_candidates',
      'initialization_receipts',
      'initialization_history_coverage',
      'behavioral_requirements',
      'rules',
      'dependencies',
      'conflicts',
      'unknowns',
      'coverage',
    });
    return EffectiveObject(
      identity: RecordVersion.fromWire(f.require('identity')),
      contextualNames: f
          .array('contextual_names', defaultEmpty: true)
          .map((v) => ContextualNameEvidence.fromWire(v)),
      ancestry: f.array('ancestry').map((v) => RecordVersion.fromWire(v)),
      ancestryComplete: _stateBool(f.require('ancestry_complete')),
      sharedAttributes: f
          .array('shared_attributes')
          .map((v) => ObjectEvidence.fromWire(v)),
      instanceFacts: f
          .array('instance_facts')
          .map((v) => ObjectEvidence.fromWire(v)),
      initialValueCandidates: f
          .array('initial_value_candidates')
          .map((v) => ObjectEvidence.fromWire(v)),
      initializationReceipts: f
          .array('initialization_receipts')
          .map((v) => InitializationReceipt.fromWire(v)),
      initializationHistoryCoverage: Coverage.fromName(
        wireString(f.require('initialization_history_coverage')),
      ),
      behavioralRequirements: f
          .array('behavioral_requirements')
          .map((v) => ObjectEvidence.fromWire(v)),
      rules: f.array('rules').map((v) => ObjectEvidence.fromWire(v)),
      dependencies: f
          .array('dependencies')
          .map((v) => RecordVersion.fromWire(v)),
      conflicts: f.array('conflicts').map((v) => ObjectConflict.fromWire(v)),
      unknowns: f.array('unknowns').map((v) => wireString(v)),
      coverage: Coverage.fromName(wireString(f.require('coverage'))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('identity', identity.toWire()),
    MapEntry(
      'contextual_names',
      CanonicalArray(contextualNames.map((v) => v.toWire())),
    ),
    MapEntry('ancestry', CanonicalArray(ancestry.map((v) => v.toWire()))),
    MapEntry('ancestry_complete', CanonicalBool(ancestryComplete)),
    MapEntry(
      'shared_attributes',
      CanonicalArray(sharedAttributes.map((v) => v.toWire())),
    ),
    MapEntry(
      'instance_facts',
      CanonicalArray(instanceFacts.map((v) => v.toWire())),
    ),
    MapEntry(
      'initial_value_candidates',
      CanonicalArray(initialValueCandidates.map((v) => v.toWire())),
    ),
    MapEntry(
      'initialization_receipts',
      CanonicalArray(initializationReceipts.map((v) => v.toWire())),
    ),
    MapEntry(
      'initialization_history_coverage',
      CanonicalString(initializationHistoryCoverage.wireName),
    ),
    MapEntry(
      'behavioral_requirements',
      CanonicalArray(behavioralRequirements.map((v) => v.toWire())),
    ),
    MapEntry('rules', CanonicalArray(rules.map((v) => v.toWire()))),
    MapEntry(
      'dependencies',
      CanonicalArray(dependencies.map((v) => v.toWire())),
    ),
    MapEntry('conflicts', CanonicalArray(conflicts.map((v) => v.toWire()))),
    MapEntry(
      'unknowns',
      CanonicalArray(unknowns.map((v) => CanonicalString(v))),
    ),
    MapEntry('coverage', CanonicalString(coverage.wireName)),
  ]);
}

final class State {
  State({
    required Iterable<EffectiveObject> objects,
    required Iterable<DerivedFact> derived,
    required Iterable<RecordVersion> epistemic,
    this.chronology,
    required Iterable<RecordId> unresolvedAssertionIds,
    required Iterable<RecordVersion> assertions,
    required Iterable<RecordVersion> propositions,
    required Iterable<RecordVersion> completeness,
    required this.coverage,
    required Iterable<String> unsupportedCapabilities,
  }) : objects = List.unmodifiable(objects),
       derived = List.unmodifiable(derived),
       epistemic = List.unmodifiable(epistemic),
       unresolvedAssertionIds = List.unmodifiable(unresolvedAssertionIds),
       assertions = List.unmodifiable(assertions),
       propositions = List.unmodifiable(propositions),
       completeness = List.unmodifiable(completeness),
       unsupportedCapabilities = List.unmodifiable(unsupportedCapabilities);
  final List<EffectiveObject> objects;
  final List<DerivedFact> derived;
  final List<RecordVersion> epistemic;
  final Chronology? chronology;
  final List<RecordId> unresolvedAssertionIds;
  final List<RecordVersion> assertions;
  final List<RecordVersion> propositions;
  final List<RecordVersion> completeness;
  final Coverage coverage;
  final List<String> unsupportedCapabilities;
  factory State.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'objects',
      'derived',
      'epistemic',
      'chronology',
      'unresolved_assertion_ids',
      'assertions',
      'propositions',
      'completeness',
      'coverage',
      'unsupported_capabilities',
    });
    return State(
      objects: f.array('objects').map((v) => EffectiveObject.fromWire(v)),
      derived: f.array('derived').map((v) => DerivedFact.fromWire(v)),
      epistemic: f.array('epistemic').map((v) => RecordVersion.fromWire(v)),
      chronology: f.optional('chronology', (v) => Chronology.fromWire(v)),
      unresolvedAssertionIds: f
          .array('unresolved_assertion_ids')
          .map((v) => RecordId.parse(wireString(v))),
      assertions: f.array('assertions').map((v) => RecordVersion.fromWire(v)),
      propositions: f
          .array('propositions')
          .map((v) => RecordVersion.fromWire(v)),
      completeness: f
          .array('completeness')
          .map((v) => RecordVersion.fromWire(v)),
      coverage: Coverage.fromName(wireString(f.require('coverage'))),
      unsupportedCapabilities: f
          .array('unsupported_capabilities')
          .map((v) => wireString(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('objects', CanonicalArray(objects.map((v) => v.toWire()))),
    MapEntry('derived', CanonicalArray(derived.map((v) => v.toWire()))),
    MapEntry('epistemic', CanonicalArray(epistemic.map((v) => v.toWire()))),
    MapEntry(
      'chronology',
      chronology == null ? const CanonicalNull() : chronology!.toWire(),
    ),
    MapEntry(
      'unresolved_assertion_ids',
      CanonicalArray(
        unresolvedAssertionIds.map((v) => CanonicalString(v.value)),
      ),
    ),
    MapEntry('assertions', CanonicalArray(assertions.map((v) => v.toWire()))),
    MapEntry(
      'propositions',
      CanonicalArray(propositions.map((v) => v.toWire())),
    ),
    MapEntry(
      'completeness',
      CanonicalArray(completeness.map((v) => v.toWire())),
    ),
    MapEntry('coverage', CanonicalString(coverage.wireName)),
    MapEntry(
      'unsupported_capabilities',
      CanonicalArray(unsupportedCapabilities.map((v) => CanonicalString(v))),
    ),
  ]);
}

bool _stateBool(CanonicalValue value) => switch (value) {
  CanonicalBool(:final value) => value,
  _ => throw const FormatException('Expected state boolean'),
};
