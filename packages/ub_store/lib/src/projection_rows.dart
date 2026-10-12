import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'references.dart';
import 'revision_input.dart';

/// Disposable fixed-schema rows shared by both backends. Canonical history and
/// typed bodies, never these projections, remain factual authority.
Iterable<(String, List<Object?>)> recordProjectionRows(
  int generation,
  StoredVersion version,
) sync* {
  final refs = ReferenceScan.collect(
    version.payload,
    version.identity.universeId,
  );
  final id = version.versionId.value;
  for (final reference in refs.records) {
    yield (
      'reference_index',
      <Object?>[
        generation,
        id,
        reference.record.value,
        reference.version?.value,
        reference.path,
      ],
    );
    if ({
      RecordKind.work,
      RecordKind.workVersion,
      RecordKind.saga,
      RecordKind.sceneRef,
      RecordKind.passageRef,
    }.contains(version.identity.recordKind)) {
      yield (
        'narrative_projection',
        <Object?>[generation, id, reference.record.value, reference.path],
      );
    }
  }
  for (final world in refs.worlds) {
    yield ('world_projection', <Object?>[generation, id, world.value]);
  }
  for (final (path, value) in refs.scalars) {
    yield ('typed_projection', <Object?>[generation, id, path, value]);
  }
  final fields = objectFields(version.payload);
  final String text;
  switch (version.identity.recordKind) {
    case RecordKind.entity:
      final names = (fields['names'] as CanonicalArray).items;
      text = [
        for (final value in objectFields(fields['labels']!).values)
          (value as CanonicalString).value,
        for (final name in names)
          (objectFields(name)['text'] as CanonicalString).value,
      ].join(' ');
    case RecordKind.world:
      text = [
        (fields['selector'] as CanonicalString).value,
        for (final alias
            in (fields['aliases'] as CanonicalArray?)?.items ??
                const <CanonicalValue>[])
          (alias as CanonicalString).value,
      ].join(' ');
    case RecordKind.work:
    case RecordKind.saga:
      text = (fields['title'] as CanonicalString).value;
    case RecordKind.appearance:
    case RecordKind.source:
      text = (fields['label'] as CanonicalString).value;
    case RecordKind.imageAsset:
      text = (fields['original_name'] as CanonicalString).value;
    default:
      text = '';
  }
  yield ('search_index', <Object?>[generation, id, text]);
}
