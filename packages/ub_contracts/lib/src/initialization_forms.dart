import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

/// Private unfinished input for an explicit instance initialization.
final class UnfinishedInitializationForm {
  UnfinishedInitializationForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.instance = const ExpressionReferenceInput(),
    this.start = const ExpressionReferenceInput(),
    this.definition,
    this.scope = const ScopeInput(),
    this.endKind = '',
    this.endCoordinate = '',
    this.rationale = '',
    BigInt? draftVersion,
  }) : draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, endKind, endCoordinate, rationale;
  final ExpressionReferenceInput instance, start;
  final VersionRef? definition;
  final ScopeInput scope;
  final BigInt? draftVersion;

  UnfinishedInitializationForm copyWith({
    ExpressionReferenceInput? instance,
    ExpressionReferenceInput? start,
    VersionRef? definition,
    bool clearDefinition = false,
    ScopeInput? scope,
    String? endKind,
    String? endCoordinate,
    String? rationale,
  }) => UnfinishedInitializationForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    instance: instance ?? this.instance,
    start: start ?? this.start,
    definition: clearDefinition ? null : definition ?? this.definition,
    scope: scope ?? this.scope,
    endKind: endKind ?? this.endKind,
    endCoordinate: endCoordinate ?? this.endCoordinate,
    rationale: rationale ?? this.rationale,
    draftVersion: draftVersion,
  );

  Iterable<String> get exactTexts => [
    clientRef,
    instance.record,
    instance.universe,
    start.record,
    start.universe,
    ...scope.exactTexts,
    endKind,
    endCoordinate,
    rationale,
  ];

  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('instance', instance.toWire()),
    MapEntry('start', start.toWire()),
    if (definition != null) MapEntry('definition', definition!.toCanonical()),
    MapEntry('scope', scope.toWire()),
    MapEntry('end_kind', CanonicalString(endKind)),
    MapEntry('end_coordinate', CanonicalString(endCoordinate)),
    MapEntry('rationale', CanonicalString(rationale)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);

  factory UnfinishedInitializationForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'instance',
      'start',
      'definition',
      'scope',
      'end_kind',
      'end_coordinate',
      'rationale',
      'draft_version',
    });
    return UnfinishedInitializationForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      instance: ExpressionReferenceInput.fromWire(f.require('instance')),
      start: ExpressionReferenceInput.fromWire(f.require('start')),
      definition: f.optional('definition', VersionRef.fromCanonical),
      scope: ScopeInput.fromWire(f.require('scope')),
      endKind: f.string('end_kind'),
      endCoordinate: f.string('end_coordinate'),
      rationale: f.string('rationale'),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
}

final class SavedInitializationForm {
  SavedInitializationForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedInitializationForm form;
}
