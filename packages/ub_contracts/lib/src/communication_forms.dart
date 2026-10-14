import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

final class UnfinishedCommunicationForm {
  UnfinishedCommunicationForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.sender = const ExpressionReferenceInput(),
    Iterable<ExpressionReferenceInput> intendedRecipients = const [],
    Iterable<ExpressionReferenceInput> actualRecipients = const [],
    Iterable<ExpressionReferenceInput> content = const [],
    this.channelEnabled = false,
    this.channel = '',
    this.distorted,
    this.sentAt = const TemporalValidityInput(kind: 'instant_unspecified'),
    this.receivedEnabled = false,
    this.receivedAt = const TemporalValidityInput(kind: 'instant_unspecified'),
    this.rationale = '',
    this.original,
    this.correctionTarget,
    this.expectedRecordVersion,
    BigInt? draftVersion,
  }) : intendedRecipients = List.unmodifiable(intendedRecipients),
       actualRecipients = List.unmodifiable(actualRecipients),
       content = List.unmodifiable(content),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, channel, rationale;
  final ExpressionReferenceInput sender;
  final List<ExpressionReferenceInput> intendedRecipients,
      actualRecipients,
      content;
  final bool channelEnabled, receivedEnabled;
  final bool? distorted;
  final TemporalValidityInput sentAt, receivedAt;
  final CommunicationRecord? original;
  final ExpressionReferenceInput? correctionTarget;
  final RecordVersionId? expectedRecordVersion;
  final BigInt? draftVersion;
  UnfinishedCommunicationForm copyWith({
    ExpressionReferenceInput? sender,
    List<ExpressionReferenceInput>? intendedRecipients,
    List<ExpressionReferenceInput>? actualRecipients,
    List<ExpressionReferenceInput>? content,
    bool? channelEnabled,
    String? channel,
    bool? distorted,
    TemporalValidityInput? sentAt,
    bool? receivedEnabled,
    TemporalValidityInput? receivedAt,
    String? rationale,
  }) => UnfinishedCommunicationForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    sender: sender ?? this.sender,
    intendedRecipients: intendedRecipients ?? this.intendedRecipients,
    actualRecipients: actualRecipients ?? this.actualRecipients,
    content: content ?? this.content,
    channelEnabled: channelEnabled ?? this.channelEnabled,
    channel: channel ?? this.channel,
    distorted: distorted ?? this.distorted,
    sentAt: sentAt ?? this.sentAt,
    receivedEnabled: receivedEnabled ?? this.receivedEnabled,
    receivedAt: receivedAt ?? this.receivedAt,
    rationale: rationale ?? this.rationale,
    original: original,
    correctionTarget: correctionTarget,
    expectedRecordVersion: expectedRecordVersion,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('sender', sender.toWire()),
    MapEntry(
      'intended_recipients',
      CanonicalArray(intendedRecipients.map((r) => r.toWire())),
    ),
    MapEntry(
      'actual_recipients',
      CanonicalArray(actualRecipients.map((r) => r.toWire())),
    ),
    MapEntry('content', CanonicalArray(content.map((r) => r.toWire()))),
    MapEntry('channel_enabled', CanonicalBool(channelEnabled)),
    MapEntry('channel', CanonicalString(channel)),
    MapEntry(
      'distorted',
      distorted == null ? const CanonicalNull() : CanonicalBool(distorted!),
    ),
    MapEntry('sent_at', sentAt.toWire()),
    MapEntry('received_enabled', CanonicalBool(receivedEnabled)),
    MapEntry('received_at', receivedAt.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    if (correctionTarget != null)
      MapEntry('correction_target', correctionTarget!.toWire()),
    if (expectedRecordVersion != null)
      MapEntry(
        'expected_record_version',
        CanonicalString(expectedRecordVersion!.value),
      ),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedCommunicationForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'sender',
      'intended_recipients',
      'actual_recipients',
      'content',
      'channel_enabled',
      'channel',
      'distorted',
      'sent_at',
      'received_enabled',
      'received_at',
      'rationale',
      'original',
      'correction_target',
      'expected_record_version',
      'draft_version',
    });
    return UnfinishedCommunicationForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      sender: ExpressionReferenceInput.fromWire(f.require('sender')),
      intendedRecipients: f
          .array('intended_recipients')
          .map(ExpressionReferenceInput.fromWire),
      actualRecipients: f
          .array('actual_recipients')
          .map(ExpressionReferenceInput.fromWire),
      content: f.array('content').map(ExpressionReferenceInput.fromWire),
      channelEnabled: f.boolean('channel_enabled'),
      channel: f.string('channel'),
      distorted: f.optional(
        'distorted',
        (v) => switch (v) {
          CanonicalBool(:final value) => value,
          _ => throw const FormatException('Expected distortion choice'),
        },
      ),
      sentAt: TemporalValidityInput.fromWire(f.require('sent_at')),
      receivedEnabled: f.boolean('received_enabled'),
      receivedAt: TemporalValidityInput.fromWire(f.require('received_at')),
      rationale: f.string('rationale'),
      correctionTarget: f.optional(
        'correction_target',
        ExpressionReferenceInput.fromWire,
      ),
      expectedRecordVersion: f.optional(
        'expected_record_version',
        (v) => RecordVersionId.parse(wireString(v)),
      ),
      original: f.optional('original', CommunicationRecord.fromWire),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
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

final class SavedCommunicationForm {
  SavedCommunicationForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedCommunicationForm form;
}
