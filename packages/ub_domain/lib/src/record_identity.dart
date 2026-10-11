import 'canonical.dart';
import 'ids.dart';

enum RecordKind {
  entity('entity'),
  appearance('appearance'),
  imageAsset('image_asset'),
  world('world'),
  realm('realm'),
  work('work'),
  workVersion('work_version'),
  sceneRef('scene_ref'),
  passageRef('passage_ref'),
  saga('saga'),
  entityType('entity_type'),
  property('property'),
  relation('relation'),
  unit('unit'),
  calendar('calendar'),
  valueDefinition('value_definition'),
  domainPack('domain_pack'),
  proposition('proposition'),
  assertion('assertion'),
  representedContext('represented_context'),
  completeness('completeness'),
  boundary('boundary'),
  rule('rule'),
  exception('exception'),
  event('event'),
  itemPower('item_power'),
  actionDefinition('action_definition'),
  epistemicAttitude('epistemic_attitude'),
  observation('observation'),
  communication('communication'),
  memory('memory'),
  secret('secret'),
  goal('goal'),
  commitment('commitment'),
  source('source'),
  sourceVersion('source_version'),
  anchor('anchor'),
  issueDecision('issue_decision');

  const RecordKind(this.wireName);
  final String wireName;
  static RecordKind parse(String value) => values.firstWhere(
    (kind) => kind.wireName == value,
    orElse: () => throw FormatException('Unknown record kind: $value'),
  );
}

final class RecordIdentity {
  const RecordIdentity({
    required this.universeId,
    required this.recordId,
    required this.recordKind,
  });
  final UniverseId universeId;
  final RecordId recordId;
  final RecordKind recordKind;
  CanonicalObject toCanonical() => CanonicalObject([
    MapEntry('universe_id', CanonicalString(universeId.value)),
    MapEntry('record_id', CanonicalString(recordId.value)),
    MapEntry('record_kind', CanonicalString(recordKind.wireName)),
  ]);
}
