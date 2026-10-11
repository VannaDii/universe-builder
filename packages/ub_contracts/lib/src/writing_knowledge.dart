part of 'request.dart';

enum WritingAttitudeKind {
  believes,
  suspects,
  rejects,
  remembers,
  knows;

  static WritingAttitudeKind fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown writing attitude'),
  );
}

final class WritingKnowledgeRequirement {
  WritingKnowledgeRequirement({required this.holder, required this.claim});
  final String holder;
  final WritingClaim claim;
  factory WritingKnowledgeRequirement.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'holder', 'claim'});
    return WritingKnowledgeRequirement(
      holder: wireString(f.require('holder')),
      claim: WritingClaim.fromWire(f.require('claim')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('holder', CanonicalString(holder)),
    MapEntry('claim', claim.toWire()),
  ]);
}

final class WritingEvent {
  WritingEvent({
    required this.action,
    required Map<String, String> participants,
    this.atTick,
    this.atDate,
    this.world,
    Iterable<WritingKnowledgeRequirement> requiresKnowledge = const [],
  }) : participants = Map.unmodifiable(participants),
       requiresKnowledge = List.unmodifiable(requiresKnowledge);
  final String action;
  final Map<String, String> participants;
  final String? atTick;
  final String? atDate;
  final String? world;
  final List<WritingKnowledgeRequirement> requiresKnowledge;
  factory WritingEvent.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'action',
      'participants',
      'at_tick',
      'at_date',
      'world',
      'requires_knowledge',
    });
    return WritingEvent(
      action: wireString(f.require('action')),
      participants: _writingStringMap(f.require('participants')),
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      world: f.optional('world', (v) => wireString(v)),
      requiresKnowledge: f
          .array('requires_knowledge', defaultEmpty: true)
          .map((v) => WritingKnowledgeRequirement.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('action', CanonicalString(action)),
    MapEntry(
      'participants',
      CanonicalObject(
        participants.entries.map(
          (e) => MapEntry(e.key, CanonicalString(e.value)),
        ),
      ),
    ),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry(
      'world',
      world == null ? const CanonicalNull() : CanonicalString(world!),
    ),
    MapEntry(
      'requires_knowledge',
      CanonicalArray(requiresKnowledge.map((v) => v.toWire())),
    ),
  ]);
}

final class WritingMessage {
  WritingMessage({
    required this.label,
    required this.from,
    required Iterable<String> to,
    required Iterable<String> receivedBy,
    required this.claim,
    Iterable<String> understoodBy = const [],
    this.channel,
    this.sentTick,
    this.sentDate,
    this.receivedTick,
    this.receivedDate,
    this.distorted = false,
  }) : to = List.unmodifiable(to),
       receivedBy = List.unmodifiable(receivedBy),
       understoodBy = List.unmodifiable(understoodBy);
  final String label;
  final String from;
  final List<String> to;
  final List<String> receivedBy;
  final WritingClaim claim;
  final List<String> understoodBy;
  final String? channel;
  final String? sentTick;
  final String? sentDate;
  final String? receivedTick;
  final String? receivedDate;
  final bool distorted;
  factory WritingMessage.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'label',
      'from',
      'to',
      'received_by',
      'claim',
      'understood_by',
      'channel',
      'sent_tick',
      'sent_date',
      'received_tick',
      'received_date',
      'distorted',
    });
    return WritingMessage(
      label: wireString(f.require('label')),
      from: wireString(f.require('from')),
      to: f.array('to', defaultEmpty: false).map((v) => wireString(v)),
      receivedBy: f
          .array('received_by', defaultEmpty: false)
          .map((v) => wireString(v)),
      claim: WritingClaim.fromWire(f.require('claim')),
      understoodBy: f
          .array('understood_by', defaultEmpty: true)
          .map((v) => wireString(v)),
      channel: f.optional('channel', (v) => wireString(v)),
      sentTick: f.optional('sent_tick', (v) => wireString(v)),
      sentDate: f.optional('sent_date', (v) => wireString(v)),
      receivedTick: f.optional('received_tick', (v) => wireString(v)),
      receivedDate: f.optional('received_date', (v) => wireString(v)),
      distorted: f.values.containsKey('distorted')
          ? _writingBool(f.require('distorted'))
          : false,
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('label', CanonicalString(label)),
    MapEntry('from', CanonicalString(from)),
    MapEntry('to', CanonicalArray(to.map((v) => CanonicalString(v)))),
    MapEntry(
      'received_by',
      CanonicalArray(receivedBy.map((v) => CanonicalString(v))),
    ),
    MapEntry('claim', claim.toWire()),
    MapEntry(
      'understood_by',
      CanonicalArray(understoodBy.map((v) => CanonicalString(v))),
    ),
    MapEntry(
      'channel',
      channel == null ? const CanonicalNull() : CanonicalString(channel!),
    ),
    MapEntry(
      'sent_tick',
      sentTick == null ? const CanonicalNull() : CanonicalString(sentTick!),
    ),
    if (sentDate != null) MapEntry('sent_date', CanonicalString(sentDate!)),
    MapEntry(
      'received_tick',
      receivedTick == null
          ? const CanonicalNull()
          : CanonicalString(receivedTick!),
    ),
    if (receivedDate != null)
      MapEntry('received_date', CanonicalString(receivedDate!)),
    MapEntry('distorted', CanonicalBool(distorted)),
  ]);
}

final class WritingAttitude {
  WritingAttitude({
    required this.holder,
    required this.claim,
    required this.attitude,
    this.message,
    this.atTick,
    this.atDate,
    this.lifetime = const FactUnspecifiedLifetime(),
  });
  final String holder;
  final WritingClaim claim;
  final WritingAttitudeKind attitude;
  final String? message;
  final String? atTick;
  final String? atDate;
  final FactLifetime lifetime;
  factory WritingAttitude.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'holder',
      'claim',
      'attitude',
      'message',
      'at_tick',
      'at_date',
      'lifetime',
    });
    return WritingAttitude(
      holder: wireString(f.require('holder')),
      claim: WritingClaim.fromWire(f.require('claim')),
      attitude: WritingAttitudeKind.fromName(wireString(f.require('attitude'))),
      message: f.optional('message', (v) => wireString(v)),
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: f.values.containsKey('lifetime')
          ? FactLifetime.fromWire(f.require('lifetime'))
          : const FactUnspecifiedLifetime(),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('holder', CanonicalString(holder)),
    MapEntry('claim', claim.toWire()),
    MapEntry('attitude', CanonicalString(attitude.name)),
    MapEntry(
      'message',
      message == null ? const CanonicalNull() : CanonicalString(message!),
    ),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry('lifetime', lifetime.toWire()),
  ]);
}

final class WritingKnowledgeBoundary {
  WritingKnowledgeBoundary({
    required this.name,
    required this.holder,
    required this.claim,
    required this.scope,
    this.atTick,
    this.atDate,
    required this.lifetime,
  });
  final String name;
  final String holder;
  final WritingClaim claim;
  final String scope;
  final String? atTick;
  final String? atDate;
  final FactLifetime lifetime;
  factory WritingKnowledgeBoundary.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'holder',
      'claim',
      'scope',
      'at_tick',
      'at_date',
      'lifetime',
    });
    return WritingKnowledgeBoundary(
      name: wireString(f.require('name')),
      holder: wireString(f.require('holder')),
      claim: WritingClaim.fromWire(f.require('claim')),
      scope: wireString(f.require('scope')),
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: FactLifetime.fromWire(f.require('lifetime')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('holder', CanonicalString(holder)),
    MapEntry('claim', claim.toWire()),
    MapEntry('scope', CanonicalString(scope)),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    MapEntry(
      'at_date',
      atDate == null ? const CanonicalNull() : CanonicalString(atDate!),
    ),
    MapEntry('lifetime', lifetime.toWire()),
  ]);
}

final class WritingMessageCorrection {
  WritingMessageCorrection({
    required this.messageEditHandle,
    required this.reason,
    this.from,
    Iterable<String>? to,
    Iterable<String>? receivedBy,
    Iterable<WritingClaim>? claims,
    this.channel,
    this.clearChannel = false,
    this.sentTick,
    this.sentDate,
    this.receivedTick,
    this.receivedDate,
    this.clearReceipt = false,
    this.distorted,
  }) : to = to == null ? null : List.unmodifiable(to),
       receivedBy = receivedBy == null ? null : List.unmodifiable(receivedBy),
       claims = claims == null ? null : List.unmodifiable(claims);
  final String messageEditHandle;
  final String reason;
  final String? from;
  final List<String>? to;
  final List<String>? receivedBy;
  final List<WritingClaim>? claims;
  final String? channel;
  final bool clearChannel;
  final String? sentTick;
  final String? sentDate;
  final String? receivedTick;
  final String? receivedDate;
  final bool clearReceipt;
  final bool? distorted;
  factory WritingMessageCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'message_edit_handle',
      'reason',
      'from',
      'to',
      'received_by',
      'claims',
      'channel',
      'clear_channel',
      'sent_tick',
      'sent_date',
      'received_tick',
      'received_date',
      'clear_receipt',
      'distorted',
    });
    return WritingMessageCorrection(
      messageEditHandle: wireString(f.require('message_edit_handle')),
      reason: wireString(f.require('reason')),
      from: f.optional('from', (v) => wireString(v)),
      to: f.optional('to', (v) => _writingArray(v).map((v) => wireString(v))),
      receivedBy: f.optional(
        'received_by',
        (v) => _writingArray(v).map((v) => wireString(v)),
      ),
      claims: f.optional(
        'claims',
        (v) => _writingArray(v).map((v) => WritingClaim.fromWire(v)),
      ),
      channel: f.optional('channel', (v) => wireString(v)),
      clearChannel: f.values.containsKey('clear_channel')
          ? _writingBool(f.require('clear_channel'))
          : false,
      sentTick: f.optional('sent_tick', (v) => wireString(v)),
      sentDate: f.optional('sent_date', (v) => wireString(v)),
      receivedTick: f.optional('received_tick', (v) => wireString(v)),
      receivedDate: f.optional('received_date', (v) => wireString(v)),
      clearReceipt: f.values.containsKey('clear_receipt')
          ? _writingBool(f.require('clear_receipt'))
          : false,
      distorted: f.optional('distorted', (v) => _writingBool(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('message_edit_handle', CanonicalString(messageEditHandle)),
    MapEntry('reason', CanonicalString(reason)),
    MapEntry(
      'from',
      from == null ? const CanonicalNull() : CanonicalString(from!),
    ),
    MapEntry(
      'to',
      to == null
          ? const CanonicalNull()
          : CanonicalArray(to!.map((v) => CanonicalString(v))),
    ),
    MapEntry(
      'received_by',
      receivedBy == null
          ? const CanonicalNull()
          : CanonicalArray(receivedBy!.map((v) => CanonicalString(v))),
    ),
    MapEntry(
      'claims',
      claims == null
          ? const CanonicalNull()
          : CanonicalArray(claims!.map((v) => v.toWire())),
    ),
    MapEntry(
      'channel',
      channel == null ? const CanonicalNull() : CanonicalString(channel!),
    ),
    MapEntry('clear_channel', CanonicalBool(clearChannel)),
    MapEntry(
      'sent_tick',
      sentTick == null ? const CanonicalNull() : CanonicalString(sentTick!),
    ),
    if (sentDate != null) MapEntry('sent_date', CanonicalString(sentDate!)),
    MapEntry(
      'received_tick',
      receivedTick == null
          ? const CanonicalNull()
          : CanonicalString(receivedTick!),
    ),
    if (receivedDate != null)
      MapEntry('received_date', CanonicalString(receivedDate!)),
    MapEntry('clear_receipt', CanonicalBool(clearReceipt)),
    MapEntry(
      'distorted',
      distorted == null ? const CanonicalNull() : CanonicalBool(distorted!),
    ),
  ]);
}

final class WritingInterpretationCorrection {
  WritingInterpretationCorrection({
    required this.attitudeHandle,
    required this.reason,
    this.interpretation,
    this.clearInterpretation = false,
  });
  final String attitudeHandle;
  final String reason;
  final WritingClaim? interpretation;
  final bool clearInterpretation;
  factory WritingInterpretationCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'attitude_handle',
      'reason',
      'interpretation',
      'clear_interpretation',
    });
    return WritingInterpretationCorrection(
      attitudeHandle: wireString(f.require('attitude_handle')),
      reason: wireString(f.require('reason')),
      interpretation: f.optional(
        'interpretation',
        (v) => WritingClaim.fromWire(v),
      ),
      clearInterpretation: f.values.containsKey('clear_interpretation')
          ? _writingBool(f.require('clear_interpretation'))
          : false,
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('attitude_handle', CanonicalString(attitudeHandle)),
    MapEntry('reason', CanonicalString(reason)),
    MapEntry(
      'interpretation',
      interpretation == null ? const CanonicalNull() : interpretation!.toWire(),
    ),
    MapEntry('clear_interpretation', CanonicalBool(clearInterpretation)),
  ]);
}

final class WritingAttitudeCorrection {
  WritingAttitudeCorrection({
    required this.attitudeHandle,
    required this.reason,
    this.value,
    this.certainty,
    this.clearCertainty = false,
    this.atTick,
    this.atDate,
    this.lifetime,
    this.endTick,
    this.endDate,
  });
  final String attitudeHandle;
  final String reason;
  final FactValue? value;
  final String? certainty;
  final bool clearCertainty;
  final String? atTick;
  final String? atDate;
  final FactLifetime? lifetime;
  final String? endTick;
  final String? endDate;
  factory WritingAttitudeCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'attitude_handle',
      'reason',
      'value',
      'certainty',
      'clear_certainty',
      'at_tick',
      'at_date',
      'lifetime',
      'end_tick',
      'end_date',
    });
    return WritingAttitudeCorrection(
      attitudeHandle: wireString(f.require('attitude_handle')),
      reason: wireString(f.require('reason')),
      value: f.optional('value', (v) => FactValue.fromWire(v)),
      certainty: f.optional('certainty', (v) => wireString(v)),
      clearCertainty: f.values.containsKey('clear_certainty')
          ? _writingBool(f.require('clear_certainty'))
          : false,
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: f.optional('lifetime', (v) => FactLifetime.fromWire(v)),
      endTick: f.optional('end_tick', (v) => wireString(v)),
      endDate: f.optional('end_date', (v) => wireString(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('attitude_handle', CanonicalString(attitudeHandle)),
    MapEntry('reason', CanonicalString(reason)),
    MapEntry('value', value == null ? const CanonicalNull() : value!.toWire()),
    MapEntry(
      'certainty',
      certainty == null ? const CanonicalNull() : CanonicalString(certainty!),
    ),
    MapEntry('clear_certainty', CanonicalBool(clearCertainty)),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry(
      'lifetime',
      lifetime == null ? const CanonicalNull() : lifetime!.toWire(),
    ),
    MapEntry(
      'end_tick',
      endTick == null ? const CanonicalNull() : CanonicalString(endTick!),
    ),
    if (endDate != null) MapEntry('end_date', CanonicalString(endDate!)),
  ]);
}

final class WritingPolicyCorrection {
  WritingPolicyCorrection({
    required this.policyHandle,
    required this.reason,
    this.mode,
    this.forwardOnly,
    this.minimumDelay,
    this.maximumDelay,
    this.clearMinimumDelay = false,
    this.clearMaximumDelay = false,
    this.scope,
    this.atTick,
    this.atDate,
    this.lifetime,
  });
  final String policyHandle;
  final String reason;
  final KnowledgeMode? mode;
  final bool? forwardOnly;
  final String? minimumDelay;
  final String? maximumDelay;
  final bool clearMinimumDelay;
  final bool clearMaximumDelay;
  final String? scope;
  final String? atTick;
  final String? atDate;
  final FactLifetime? lifetime;
  factory WritingPolicyCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'policy_handle',
      'reason',
      'mode',
      'forward_only',
      'minimum_delay',
      'maximum_delay',
      'clear_minimum_delay',
      'clear_maximum_delay',
      'scope',
      'at_tick',
      'at_date',
      'lifetime',
    });
    return WritingPolicyCorrection(
      policyHandle: wireString(f.require('policy_handle')),
      reason: wireString(f.require('reason')),
      mode: f.optional('mode', (v) => KnowledgeMode.fromName(wireString(v))),
      forwardOnly: f.optional('forward_only', (v) => _writingBool(v)),
      minimumDelay: f.optional('minimum_delay', (v) => wireString(v)),
      maximumDelay: f.optional('maximum_delay', (v) => wireString(v)),
      clearMinimumDelay: f.values.containsKey('clear_minimum_delay')
          ? _writingBool(f.require('clear_minimum_delay'))
          : false,
      clearMaximumDelay: f.values.containsKey('clear_maximum_delay')
          ? _writingBool(f.require('clear_maximum_delay'))
          : false,
      scope: f.optional('scope', (v) => wireString(v)),
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: f.optional('lifetime', (v) => FactLifetime.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('policy_handle', CanonicalString(policyHandle)),
    MapEntry('reason', CanonicalString(reason)),
    MapEntry(
      'mode',
      mode == null ? const CanonicalNull() : CanonicalString(mode!.wireName),
    ),
    MapEntry(
      'forward_only',
      forwardOnly == null ? const CanonicalNull() : CanonicalBool(forwardOnly!),
    ),
    MapEntry(
      'minimum_delay',
      minimumDelay == null
          ? const CanonicalNull()
          : CanonicalString(minimumDelay!),
    ),
    MapEntry(
      'maximum_delay',
      maximumDelay == null
          ? const CanonicalNull()
          : CanonicalString(maximumDelay!),
    ),
    MapEntry('clear_minimum_delay', CanonicalBool(clearMinimumDelay)),
    MapEntry('clear_maximum_delay', CanonicalBool(clearMaximumDelay)),
    MapEntry(
      'scope',
      scope == null ? const CanonicalNull() : CanonicalString(scope!),
    ),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry(
      'lifetime',
      lifetime == null ? const CanonicalNull() : lifetime!.toWire(),
    ),
  ]);
}

final class WritingEventCorrection {
  WritingEventCorrection({
    required this.eventHandle,
    required this.reason,
    this.action,
    Map<String, String>? participants,
    this.atTick,
    this.atDate,
    this.world,
    Iterable<WritingKnowledgeRequirement>? requiresKnowledge,
  }) : participants = participants == null
           ? null
           : Map.unmodifiable(participants),
       requiresKnowledge = requiresKnowledge == null
           ? null
           : List.unmodifiable(requiresKnowledge);
  final String eventHandle;
  final String reason;
  final String? action;
  final Map<String, String>? participants;
  final String? atTick;
  final String? atDate;
  final String? world;
  final List<WritingKnowledgeRequirement>? requiresKnowledge;
  factory WritingEventCorrection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'event_handle',
      'reason',
      'action',
      'participants',
      'at_tick',
      'at_date',
      'world',
      'requires_knowledge',
    });
    return WritingEventCorrection(
      eventHandle: wireString(f.require('event_handle')),
      reason: wireString(f.require('reason')),
      action: f.optional('action', (v) => wireString(v)),
      participants: f.optional('participants', (v) => _writingStringMap(v)),
      atTick: f.optional('at_tick', (v) => wireString(v)),
      atDate: f.optional('at_date', (v) => wireString(v)),
      world: f.optional('world', (v) => wireString(v)),
      requiresKnowledge: f.optional(
        'requires_knowledge',
        (v) =>
            _writingArray(v)
                .map((v) => WritingKnowledgeRequirement.fromWire(v)),
      ),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('event_handle', CanonicalString(eventHandle)),
    MapEntry('reason', CanonicalString(reason)),
    MapEntry(
      'action',
      action == null ? const CanonicalNull() : CanonicalString(action!),
    ),
    MapEntry(
      'participants',
      participants == null
          ? const CanonicalNull()
          : CanonicalObject(
              participants!.entries.map(
                (e) => MapEntry(e.key, CanonicalString(e.value)),
              ),
            ),
    ),
    MapEntry(
      'at_tick',
      atTick == null ? const CanonicalNull() : CanonicalString(atTick!),
    ),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry(
      'world',
      world == null ? const CanonicalNull() : CanonicalString(world!),
    ),
    MapEntry(
      'requires_knowledge',
      requiresKnowledge == null
          ? const CanonicalNull()
          : CanonicalArray(requiresKnowledge!.map((v) => v.toWire())),
    ),
  ]);
}

final class WritingEventWithdrawal {
  WritingEventWithdrawal({required this.eventHandle, required this.reason});
  final String eventHandle;
  final String reason;
  factory WritingEventWithdrawal.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'event_handle', 'reason'});
    return WritingEventWithdrawal(
      eventHandle: wireString(f.require('event_handle')),
      reason: wireString(f.require('reason')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('event_handle', CanonicalString(eventHandle)),
    MapEntry('reason', CanonicalString(reason)),
  ]);
}

final class AuthorKnowledgeDeclaration {
  AuthorKnowledgeDeclaration({
    required this.holder,
    required this.claim,
    this.atTick = '',
    this.atDate,
    required this.lifetime,
    this.world,
  });
  final String holder;
  final WritingClaim claim;
  final String atTick;
  final String? atDate;
  final FactLifetime lifetime;
  final String? world;
  factory AuthorKnowledgeDeclaration.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'holder',
      'claim',
      'at_tick',
      'at_date',
      'lifetime',
      'world',
    });
    return AuthorKnowledgeDeclaration(
      holder: wireString(f.require('holder')),
      claim: WritingClaim.fromWire(f.require('claim')),
      atTick: f.values.containsKey('at_tick')
          ? wireString(f.require('at_tick'))
          : '',
      atDate: f.optional('at_date', (v) => wireString(v)),
      lifetime: FactLifetime.fromWire(f.require('lifetime')),
      world: f.optional('world', (v) => wireString(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('holder', CanonicalString(holder)),
    MapEntry('claim', claim.toWire()),
    MapEntry('at_tick', CanonicalString(atTick)),
    if (atDate != null) MapEntry('at_date', CanonicalString(atDate!)),
    MapEntry('lifetime', lifetime.toWire()),
    MapEntry(
      'world',
      world == null ? const CanonicalNull() : CanonicalString(world!),
    ),
  ]);
}

sealed class WritingKnowledgePolicy {
  const WritingKnowledgePolicy();
  CanonicalObject toWire();
  static WritingKnowledgePolicy fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'kind',
      'name',
      'mode',
      'channel',
      'forward_only',
      'minimum_delay',
      'maximum_delay',
    });
    return switch (f.string('kind')) {
      'knowledge' => WritingKnowledgeModePolicy.fromWire(value),
      'channel' => WritingChannelPolicy.fromWire(value),
      _ => throw const FormatException('Unknown writing knowledge policy'),
    };
  }
}

final class WritingKnowledgeModePolicy extends WritingKnowledgePolicy {
  const WritingKnowledgeModePolicy({required this.name, required this.mode});
  final String name;
  final KnowledgeMode mode;
  factory WritingKnowledgeModePolicy.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'name', 'mode'});
    if (f.string('kind') != 'knowledge') {
      throw const FormatException('Wrong knowledge policy');
    }
    return WritingKnowledgeModePolicy(
      name: f.string('name'),
      mode: KnowledgeMode.fromName(f.string('mode')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('knowledge')),
    MapEntry('name', CanonicalString(name)),
    MapEntry('mode', CanonicalString(mode.wireName)),
  ]);
}

final class WritingChannelPolicy extends WritingKnowledgePolicy {
  const WritingChannelPolicy({
    required this.name,
    required this.channel,
    required this.forwardOnly,
    this.minimumDelay,
    this.maximumDelay,
  });
  final String name;
  final String channel;
  final bool forwardOnly;
  final String? minimumDelay;
  final String? maximumDelay;
  factory WritingChannelPolicy.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'kind',
      'name',
      'channel',
      'forward_only',
      'minimum_delay',
      'maximum_delay',
    });
    if (f.string('kind') != 'channel') {
      throw const FormatException('Wrong knowledge policy');
    }
    return WritingChannelPolicy(
      name: f.string('name'),
      channel: f.string('channel'),
      forwardOnly: f.boolean('forward_only'),
      minimumDelay: f.optional('minimum_delay', wireString),
      maximumDelay: f.optional('maximum_delay', wireString),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('channel')),
    MapEntry('name', CanonicalString(name)),
    MapEntry('channel', CanonicalString(channel)),
    MapEntry('forward_only', CanonicalBool(forwardOnly)),
    MapEntry(
      'minimum_delay',
      minimumDelay == null
          ? const CanonicalNull()
          : CanonicalString(minimumDelay!),
    ),
    MapEntry(
      'maximum_delay',
      maximumDelay == null
          ? const CanonicalNull()
          : CanonicalString(maximumDelay!),
    ),
  ]);
}

List<CanonicalValue> _writingArray(CanonicalValue value) => switch (value) {
  CanonicalArray(:final items) => items,
  _ => throw const FormatException('Expected writing array'),
};
Map<String, String> _writingStringMap(CanonicalValue value) {
  if (value is! CanonicalObject) {
    throw const FormatException('Expected role/name map');
  }
  return {for (final e in value.fields) e.key: wireString(e.value)};
}
