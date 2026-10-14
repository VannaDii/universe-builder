import 'package:ub_domain/ub_domain.dart';

import 'expression_forms.dart';
import 'work_forms.dart';
import 'wire.dart';

final class UnfinishedSceneForm {
  UnfinishedSceneForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.sceneId = '',
    this.edition = const ExpressionReferenceInput(),
    this.editionVersion = '',
    this.viewpointEnabled = false,
    this.viewpoint = const ExpressionReferenceInput(),
    this.narrationEnabled = false,
    this.narration = const ExpressionReferenceInput(),
    this.positionEnabled = false,
    this.position = '',
    Iterable<ExpressionReferenceInput> disclosed = const [],
    Iterable<ExpressionReferenceInput> depicted = const [],
    Iterable<WorkAssociationInput> associations = const [],
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : disclosed = List.unmodifiable(disclosed),
       depicted = List.unmodifiable(depicted),
       associations = List.unmodifiable(associations),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, sceneId, editionVersion, position, rationale;
  final ExpressionReferenceInput edition, viewpoint, narration;
  final bool viewpointEnabled, narrationEnabled, positionEnabled;
  final List<ExpressionReferenceInput> disclosed, depicted;
  final List<WorkAssociationInput> associations;
  final SceneRecord? original;
  final BigInt? draftVersion;
  UnfinishedSceneForm copyWith({
    String? sceneId,
    ExpressionReferenceInput? edition,
    String? editionVersion,
    bool? viewpointEnabled,
    ExpressionReferenceInput? viewpoint,
    bool? narrationEnabled,
    ExpressionReferenceInput? narration,
    bool? positionEnabled,
    String? position,
    List<ExpressionReferenceInput>? disclosed,
    List<ExpressionReferenceInput>? depicted,
    List<WorkAssociationInput>? associations,
    String? rationale,
  }) => UnfinishedSceneForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    sceneId: sceneId ?? this.sceneId,
    edition: edition ?? this.edition,
    editionVersion: editionVersion ?? this.editionVersion,
    viewpointEnabled: viewpointEnabled ?? this.viewpointEnabled,
    viewpoint: viewpoint ?? this.viewpoint,
    narrationEnabled: narrationEnabled ?? this.narrationEnabled,
    narration: narration ?? this.narration,
    positionEnabled: positionEnabled ?? this.positionEnabled,
    position: position ?? this.position,
    disclosed: disclosed ?? this.disclosed,
    depicted: depicted ?? this.depicted,
    associations: associations ?? this.associations,
    rationale: rationale ?? this.rationale,
    original: original,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('scene_id', CanonicalString(sceneId)),
    MapEntry('edition', edition.toWire()),
    MapEntry('edition_version', CanonicalString(editionVersion)),
    MapEntry('viewpoint_enabled', CanonicalBool(viewpointEnabled)),
    MapEntry('viewpoint', viewpoint.toWire()),
    MapEntry('narration_enabled', CanonicalBool(narrationEnabled)),
    MapEntry('narration', narration.toWire()),
    MapEntry('position_enabled', CanonicalBool(positionEnabled)),
    MapEntry('position', CanonicalString(position)),
    MapEntry('disclosed', CanonicalArray(disclosed.map((r) => r.toWire()))),
    MapEntry('depicted', CanonicalArray(depicted.map((r) => r.toWire()))),
    MapEntry(
      'associations',
      CanonicalArray(associations.map((a) => a.toWire())),
    ),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedSceneForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'scene_id',
      'edition',
      'edition_version',
      'viewpoint_enabled',
      'viewpoint',
      'narration_enabled',
      'narration',
      'position_enabled',
      'position',
      'disclosed',
      'depicted',
      'associations',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedSceneForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      sceneId: f.string('scene_id'),
      edition: ExpressionReferenceInput.fromWire(f.require('edition')),
      editionVersion: f.string('edition_version'),
      viewpointEnabled: f.boolean('viewpoint_enabled'),
      viewpoint: ExpressionReferenceInput.fromWire(f.require('viewpoint')),
      narrationEnabled: f.boolean('narration_enabled'),
      narration: ExpressionReferenceInput.fromWire(f.require('narration')),
      positionEnabled: f.boolean('position_enabled'),
      position: f.string('position'),
      disclosed: f.array('disclosed').map(ExpressionReferenceInput.fromWire),
      depicted: f.array('depicted').map(ExpressionReferenceInput.fromWire),
      associations: f.array('associations').map(WorkAssociationInput.fromWire),
      rationale: f.string('rationale'),
      original: f.optional('original', SceneRecord.fromWire),
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

final class SavedSceneForm {
  SavedSceneForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedSceneForm form;
}
