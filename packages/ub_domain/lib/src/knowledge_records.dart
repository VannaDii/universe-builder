part of 'records.dart';

/// Authored knowledge is distinct from belief, suspicion, rejection and memory.
enum EpistemicAttitudeKind {
  believes,
  suspects,
  rejects,
  remembers,
  knows;

  static EpistemicAttitudeKind fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown epistemic attitude'),
  );
}

enum KnowledgeMode {
  authorEstablished('author_established'),
  justified('justified');

  const KnowledgeMode(this.wireName);
  final String wireName;
  static KnowledgeMode fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown knowledge mode'),
  );
}

final class KnowledgePolicy {
  const KnowledgePolicy({required this.context, required this.mode});
  final RecordRef context;
  final KnowledgeMode mode;
  factory KnowledgePolicy.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'context', 'mode'});
    return KnowledgePolicy(
      context: RecordRef.fromCanonical(f.require('context')),
      mode: KnowledgeMode.fromName(f.string('mode')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('context', context.toCanonical()),
    MapEntry('mode', CanonicalString(mode.wireName)),
  ]);
}

sealed class KnowledgeBasis {
  const KnowledgeBasis();
  CanonicalObject toWire();
  static KnowledgeBasis fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'author_established':
        f.allow({'kind'});
        return const AuthorEstablishedKnowledge();
      case 'communication_receipt':
        f.allow({'kind', 'communication', 'interpretation'});
        return CommunicationKnowledge(
          communication: RecordRef.fromCanonical(f.require('communication')),
          interpretation: _optionalRef(f, 'interpretation'),
        );
      default:
        throw const FormatException('Unknown knowledge basis');
    }
  }
}

final class AuthorEstablishedKnowledge extends KnowledgeBasis {
  const AuthorEstablishedKnowledge();
  @override
  CanonicalObject toWire() => tagged('author_established', []);
}

final class CommunicationKnowledge extends KnowledgeBasis {
  const CommunicationKnowledge({
    required this.communication,
    this.interpretation,
  });
  final RecordRef communication;
  final RecordRef? interpretation;
  @override
  CanonicalObject toWire() => tagged('communication_receipt', [
    MapEntry('communication', communication.toCanonical()),
    MapEntry('interpretation', _nullableRef(interpretation)),
  ]);
}

/// Omitted world means universe-wide evidence, never an implicit world choice.
final class KnowledgeAcquisition {
  const KnowledgeAcquisition({
    required this.truthContext,
    required this.time,
    this.world,
    required this.basis,
  });
  final RecordRef truthContext;
  final TemporalExpression time;
  final RecordRef? world;
  final KnowledgeBasis basis;
  factory KnowledgeAcquisition.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'truthContext', 'time', 'world', 'basis'});
    return KnowledgeAcquisition(
      truthContext: RecordRef.fromCanonical(f.require('truthContext')),
      time: TemporalExpression.fromWire(f.require('time')),
      world: _optionalRef(f, 'world'),
      basis: KnowledgeBasis.fromWire(f.require('basis')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('truthContext', truthContext.toCanonical()),
    MapEntry('time', time.encode(canonical: false)),
    if (world != null) MapEntry('world', world!.toCanonical()),
    MapEntry('basis', basis.toWire()),
  ]);
}

final class EpistemicAttitudeRecord extends RecordPayload {
  const EpistemicAttitudeRecord({
    this.acquisition,
    required this.holder,
    required this.proposition,
    required this.attitude,
    this.certainty,
    required this.validity,
    required this.basis,
  });
  final KnowledgeAcquisition? acquisition;
  final RecordRef holder, proposition;
  final EpistemicAttitudeKind attitude;
  final String? certainty;
  final Validity validity;
  final EvidenceBasis basis;
  factory EpistemicAttitudeRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.epistemicAttitude, {
      'acquisition',
      'holder',
      'proposition',
      'attitude',
      'certainty',
      'validity',
      'basis',
    });
    final acquisition = f.values['acquisition'];
    return EpistemicAttitudeRecord(
      acquisition: acquisition == null || acquisition is CanonicalNull
          ? null
          : KnowledgeAcquisition.fromWire(acquisition),
      holder: RecordRef.fromCanonical(f.require('holder')),
      proposition: RecordRef.fromCanonical(f.require('proposition')),
      attitude: EpistemicAttitudeKind.fromName(f.string('attitude')),
      certainty: f.optionalString('certainty'),
      validity: Validity.fromWire(f.require('validity')),
      basis: EvidenceBasis.fromWire(f.require('basis')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.epistemicAttitude;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    if (acquisition != null) MapEntry('acquisition', acquisition!.toWire()),
    MapEntry('holder', holder.toCanonical()),
    MapEntry('proposition', proposition.toCanonical()),
    MapEntry('attitude', CanonicalString(attitude.name)),
    MapEntry('certainty', _nullableString(certainty)),
    MapEntry('validity', validity.toWire()),
    MapEntry('basis', basis.toWire()),
  ]);
}

/// Presence alone establishes neither sensory access nor understanding.
final class ObservationRecord extends RecordPayload {
  const ObservationRecord({
    required this.observer,
    required this.observed,
    required this.sensoryAccess,
    required this.time,
    this.interpretation,
    required this.basis,
  });
  final RecordRef observer, observed;
  final bool sensoryAccess;
  final TemporalExpression time;
  final RecordRef? interpretation;
  final EvidenceBasis basis;
  factory ObservationRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.observation, {
      'observer',
      'observed',
      'sensoryAccess',
      'time',
      'interpretation',
      'basis',
    });
    return ObservationRecord(
      observer: RecordRef.fromCanonical(f.require('observer')),
      observed: RecordRef.fromCanonical(f.require('observed')),
      sensoryAccess: f.boolean('sensoryAccess'),
      time: TemporalExpression.fromWire(f.require('time')),
      interpretation: _optionalRef(f, 'interpretation'),
      basis: EvidenceBasis.fromWire(f.require('basis')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.observation;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('observer', observer.toCanonical()),
    MapEntry('observed', observed.toCanonical()),
    MapEntry('sensoryAccess', CanonicalBool(sensoryAccess)),
    MapEntry('time', time.encode(canonical: false)),
    MapEntry('interpretation', _nullableRef(interpretation)),
    MapEntry('basis', basis.toWire()),
  ]);
}

/// Intended recipients and actual receipt remain independent authored lists.
final class CommunicationRecord extends RecordPayload {
  CommunicationRecord({
    required this.sender,
    required Iterable<RecordRef> intendedRecipients,
    required Iterable<RecordRef> actualRecipients,
    required Iterable<RecordRef> content,
    this.channel,
    required this.sentAt,
    this.receivedAt,
    required this.distorted,
  }) : intendedRecipients = List.unmodifiable(intendedRecipients),
       actualRecipients = List.unmodifiable(actualRecipients),
       content = List.unmodifiable(content);
  final RecordRef sender;
  final List<RecordRef> intendedRecipients, actualRecipients, content;
  final String? channel;
  final TemporalExpression sentAt;
  final TemporalExpression? receivedAt;
  final bool distorted;
  factory CommunicationRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.communication, {
      'sender',
      'intendedRecipients',
      'actualRecipients',
      'content',
      'channel',
      'sentAt',
      'receivedAt',
      'distorted',
    });
    return CommunicationRecord(
      sender: RecordRef.fromCanonical(f.require('sender')),
      intendedRecipients: f
          .array('intendedRecipients')
          .map(RecordRef.fromCanonical),
      actualRecipients: f
          .array('actualRecipients')
          .map(RecordRef.fromCanonical),
      content: f.array('content').map(RecordRef.fromCanonical),
      channel: f.optionalString('channel'),
      sentAt: TemporalExpression.fromWire(f.require('sentAt')),
      receivedAt: _optionalTime(f, 'receivedAt'),
      distorted: f.boolean('distorted'),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.communication;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('sender', sender.toCanonical()),
    MapEntry('intendedRecipients', _refs(intendedRecipients)),
    MapEntry('actualRecipients', _refs(actualRecipients)),
    MapEntry('content', _refs(content)),
    MapEntry('channel', _nullableString(channel)),
    MapEntry('sentAt', sentAt.encode(canonical: false)),
    MapEntry('receivedAt', _nullableTime(receivedAt)),
    MapEntry('distorted', CanonicalBool(distorted)),
  ]);
}

/// Remembered content may be false, incomplete or detached from alleged events.
final class MemoryRecord extends RecordPayload {
  const MemoryRecord({
    required this.holder,
    required this.content,
    this.alleged,
    required this.accessibility,
    required this.altered,
    required this.validity,
  });
  final RecordRef holder, content;
  final RecordRef? alleged;
  final String accessibility;
  final bool altered;
  final Validity validity;
  factory MemoryRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.memory, {
      'holder',
      'content',
      'alleged',
      'accessibility',
      'altered',
      'validity',
    });
    return MemoryRecord(
      holder: RecordRef.fromCanonical(f.require('holder')),
      content: RecordRef.fromCanonical(f.require('content')),
      alleged: _optionalRef(f, 'alleged'),
      accessibility: f.string('accessibility'),
      altered: f.boolean('altered'),
      validity: Validity.fromWire(f.require('validity')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.memory;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('holder', holder.toCanonical()),
    MapEntry('content', content.toCanonical()),
    MapEntry('alleged', _nullableRef(alleged)),
    MapEntry('accessibility', CanonicalString(accessibility)),
    MapEntry('altered', CanonicalBool(altered)),
    MapEntry('validity', validity.toWire()),
  ]);
}

/// Fictional secrecy and application permissions are separate concepts.
final class SecretRecord extends RecordPayload {
  SecretRecord({
    required Iterable<RecordRef> scope,
    required Iterable<RecordRef> fictionalKnowers,
    required this.readerDisclosed,
    this.concealment,
    required this.validity,
  }) : scope = List.unmodifiable(scope),
       fictionalKnowers = List.unmodifiable(fictionalKnowers);
  final List<RecordRef> scope, fictionalKnowers;
  final bool readerDisclosed;
  final String? concealment;
  final Validity validity;
  factory SecretRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.secret, {
      'scope',
      'fictionalKnowers',
      'readerDisclosed',
      'concealment',
      'validity',
    });
    return SecretRecord(
      scope: f.array('scope').map(RecordRef.fromCanonical),
      fictionalKnowers: f
          .array('fictionalKnowers')
          .map(RecordRef.fromCanonical),
      readerDisclosed: f.boolean('readerDisclosed'),
      concealment: f.optionalString('concealment'),
      validity: Validity.fromWire(f.require('validity')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.secret;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('scope', _refs(scope)),
    MapEntry('fictionalKnowers', _refs(fictionalKnowers)),
    MapEntry('readerDisclosed', CanonicalBool(readerDisclosed)),
    MapEntry('concealment', _nullableString(concealment)),
    MapEntry('validity', validity.toWire()),
  ]);
}

sealed class CompletenessKind {
  const CompletenessKind();
  CanonicalValue toWire();
  CanonicalValue toCanonical();
  static CompletenessKind fromWire(CanonicalValue value) {
    if (value is CanonicalString && value.value == 'objective_reality') {
      return const ObjectiveCompleteness();
    }
    final outer = Fields(value)..allow({'observer_known'});
    final f = Fields(outer.require('observer_known'))..allow({'observer'});
    return ObserverCompleteness(RecordId.parse(f.string('observer')));
  }
}

final class ObjectiveCompleteness extends CompletenessKind {
  const ObjectiveCompleteness();
  @override
  CanonicalString toWire() => CanonicalString('objective_reality');
  @override
  CanonicalString toCanonical() => CanonicalString('objective');
}

final class ObserverCompleteness extends CompletenessKind {
  const ObserverCompleteness(this.observer);
  final RecordId observer;
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry(
      'observer_known',
      CanonicalObject([MapEntry('observer', CanonicalString(observer.value))]),
    ),
  ]);
  @override
  CanonicalObject toCanonical() => tagged('observer_known', [
    MapEntry('observer', CanonicalString(observer.value)),
  ]);
}

/// A complete empty set is explicit scoped evidence, unlike an empty search.
final class CompletenessRecord extends RecordPayload {
  CompletenessRecord({
    required this.subject,
    required this.predicate,
    required Iterable<RecordRef> members,
    required this.completeness,
    required this.validity,
    required this.scope,
  }) : members = List.unmodifiable(members);
  final RecordRef subject;
  final String predicate;
  final List<RecordRef> members;
  final CompletenessKind completeness;
  final Validity validity;
  final Scope scope;
  factory CompletenessRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.completeness, {
      'subject',
      'predicate',
      'members',
      'completeness',
      'validity',
      'scope',
    });
    return CompletenessRecord(
      subject: RecordRef.fromCanonical(f.require('subject')),
      predicate: f.string('predicate'),
      members: f.array('members').map(RecordRef.fromCanonical),
      completeness: CompletenessKind.fromWire(f.require('completeness')),
      validity: Validity.fromWire(f.require('validity')),
      scope: Scope.fromWire(f.require('scope')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.completeness;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('subject', subject.toCanonical()),
    MapEntry('predicate', CanonicalString(predicate)),
    MapEntry('members', _refs(members)),
    MapEntry('completeness', completeness.toWire()),
    MapEntry('validity', validity.toWire()),
    MapEntry('scope', scope.toWire()),
  ]);
}
