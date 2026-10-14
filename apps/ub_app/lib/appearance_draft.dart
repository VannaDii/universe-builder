import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

RecordRef _ref(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: UniverseId.parse(input.universe),
);
ExpressionReferenceInput _input(RecordRef ref) => ExpressionReferenceInput(
  record: ref.record.value,
  universe: ref.universe?.value ?? '',
);

DomainOperation appearanceOperation(UnfinishedAppearanceForm form) {
  final target = switch (form.targetKind) {
    'universe' => const UniverseAppearance(),
    'entry' => EntryAppearance(_ref(form.target)),
    _ => throw const FormatException('Choose what this appearance describes.'),
  };
  TemporalBound bound(String text, bool unbounded) {
    if (unbounded) return const UnboundedBound();
    if (text.trim().isEmpty) {
      throw const FormatException(
        'Enter the bound or choose explicitly unbounded.',
      );
    }
    return ExactBound(text);
  }

  final validity = switch (form.validityKind) {
    'unspecified' => const UnspecifiedValidity(),
    'retain' =>
      form.original?.validity ??
          (throw const FormatException(
            'Original appearance time scope unavailable.',
          )),
    'calendar_interval' => CalendarIntervalValidity(
      CalendarId.parse(form.calendar),
      bound(form.start, form.startUnbounded),
      bound(form.end, form.endUnbounded),
    ),
    _ => throw const FormatException('Choose the appearance time scope.'),
  };
  final record = AppearanceRecord(
    target: target,
    label: form.label,
    physicalDescription: form.physicalDescription,
    atmosphere: form.atmosphere,
    images: form.images.map((image) {
      if (image.stagedOperation != null &&
          image.stagedOperation!.clientRef != image.asset.record) {
        throw const FormatException(
          'Retained image differs from the selected image.',
        );
      }
      return AppearanceImage(
        asset: _ref(image.asset),
        caption: image.caption,
        purpose: ImagePurpose.fromName(image.purpose),
      );
    }),
    links: form.links.map(
      (link) => AppearanceLink(
        entry: _ref(link.entry),
        relationship: AppearanceRelationship.fromName(link.relationship),
        note: link.note,
      ),
    ),
    validity: validity,
  );
  if (form.revisionTarget == null) {
    return CreateAppearanceOperation(clientRef: form.clientRef, record: record);
  }
  if (form.expectedRecordVersion == null) {
    throw const FormatException('Original appearance version unavailable.');
  }
  return ReviseAppearanceOperation(
    record: _ref(form.revisionTarget!),
    expectedVersion: form.expectedRecordVersion!,
    replacement: record,
  );
}

UnfinishedAppearanceForm _fromRecord({
  required AppearanceRecord record,
  required RevisionId base,
  required RecordId context,
  required String clientRef,
  RecordRef? target,
  RecordVersionId? expected,
  BigInt? draftVersion,
  List<DomainOperation> operations = const [],
}) => UnfinishedAppearanceForm(
  baseRevision: base,
  representedContext: context,
  clientRef: clientRef,
  targetKind: record.target is UniverseAppearance ? 'universe' : 'entry',
  target: record.target is EntryAppearance
      ? _input((record.target as EntryAppearance).entry)
      : const ExpressionReferenceInput(),
  label: record.label,
  physicalDescription: record.physicalDescription,
  atmosphere: record.atmosphere,
  images: record.images.map((image) {
    final staged = operations
        .whereType<AddImageAssetOperation>()
        .where((op) => op.clientRef == image.asset.record.value)
        .firstOrNull;
    return AppearanceImageInput(
      asset: _input(image.asset),
      caption: image.caption,
      purpose: image.purpose.name,
      stagedOperation: staged,
    );
  }),
  links: record.links.map(
    (link) => AppearanceLinkInput(
      entry: _input(link.entry),
      relationship: link.relationship.wireName,
      note: link.note,
    ),
  ),
  validityKind: 'retain',
  calendar: record.validity is CalendarIntervalValidity
      ? (record.validity as CalendarIntervalValidity).calendar.value
      : '',
  start: switch (record.validity) {
    CalendarIntervalValidity(start: ExactBound(:final value)) => value,
    _ => '',
  },
  end: switch (record.validity) {
    CalendarIntervalValidity(end: ExactBound(:final value)) => value,
    _ => '',
  },
  startUnbounded:
      record.validity is CalendarIntervalValidity &&
      (record.validity as CalendarIntervalValidity).start is UnboundedBound,
  endUnbounded:
      record.validity is CalendarIntervalValidity &&
      (record.validity as CalendarIntervalValidity).end is UnboundedBound,
  original: record,
  revisionTarget: target == null ? null : _input(target),
  expectedRecordVersion: expected,
  draftVersion: draftVersion,
);

UnfinishedAppearanceForm appearanceFormFromDraft(SavedDraft draft, int index) =>
    switch (draft.content.operations[index]) {
      CreateAppearanceOperation(:final clientRef, :final record) => _fromRecord(
        record: record,
        base: draft.content.baseRevision,
        context: draft.content.representedContext,
        clientRef: clientRef,
        draftVersion: draft.version,
        operations: draft.content.operations,
      ),
      ReviseAppearanceOperation(
        :final record,
        :final expectedVersion,
        :final replacement,
      ) =>
        _fromRecord(
          record: replacement,
          base: draft.content.baseRevision,
          context: draft.content.representedContext,
          clientRef: record.record.value,
          target: record,
          expected: expectedVersion,
          draftVersion: draft.version,
          operations: draft.content.operations,
        ),
      _ => throw const FormatException('Choose an appearance from Changes.'),
    };

UnfinishedAppearanceForm appearanceFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  if (record.payload is! AppearanceRecord) {
    throw const FormatException('Choose a published appearance.');
  }
  return _fromRecord(
    record: record.payload as AppearanceRecord,
    base: baseRevision,
    context: representedContext,
    clientRef: record.identity.recordId.value,
    target: RecordRef(
      universe: record.identity.universeId,
      record: record.identity.recordId,
    ),
    expected: record.recordVersionId,
  );
}

SaveDraftEngineRequest appearanceDraftRequest({
  required SavedDraft draft,
  required UnfinishedAppearanceForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this appearance.',
    );
  }
  final operation = appearanceOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    if (form.draftVersion != draft.version ||
        index < 0 ||
        index >= operations.length ||
        appearanceFormFromDraft(draft, index).clientRef != form.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current appearance.',
      );
    }
    operations[index] = operation;
  }
  for (final image in form.images) {
    final staged = image.stagedOperation;
    if (staged == null) continue;
    final matches = operations
        .where(
          (op) =>
              Map.fromEntries(op.toWire().fields)['client_ref']?.toText() ==
              CanonicalString(staged.clientRef).toText(),
        )
        .toList();
    if (matches.isNotEmpty) {
      if (matches.length != 1 ||
          matches.single.toWire().toText() != staged.toWire().toText()) {
        throw const FormatException(
          'This image differs from Changes. Review it there.',
        );
      }
    } else {
      operations.add(staged);
    }
  }
  if (index == null) {
    final duplicates = operations
        .where(
          (existing) => switch ((operation, existing)) {
            (
              CreateAppearanceOperation(clientRef: final a),
              CreateAppearanceOperation(clientRef: final b),
            ) =>
              a == b,
            (
              ReviseAppearanceOperation(record: final a),
              ReviseAppearanceOperation(record: final b),
            ) =>
              a == b,
            _ => false,
          },
        )
        .toList();
    if (duplicates.isNotEmpty) {
      if (duplicates.length != 1 ||
          duplicates.single.toWire().toText() != operation.toWire().toText()) {
        throw const FormatException(
          'This appearance is already in Changes. Edit it there.',
        );
      }
    } else {
      operations.add(operation);
    }
  }
  final unchanged =
      CanonicalArray(operations.map((op) => op.toWire())).toText() ==
      CanonicalArray(draft.content.operations.map((op) => op.toWire()))
          .toText();
  return SaveDraftEngineRequest(
    universe: universe,
    continuityId: continuity,
    expectedVersion: draft.version,
    content: unchanged
        ? draft.content
        : DraftContent(
            baseRevision: draft.content.baseRevision,
            representedContext: draft.content.representedContext,
            operations: operations,
            rationale: index == null
                ? [
                    if (draft.content.rationale.isNotEmpty)
                      draft.content.rationale,
                    if (form.rationale.isNotEmpty) form.rationale,
                  ].join('\n\n')
                : draft.content.rationale,
          ),
  );
}
