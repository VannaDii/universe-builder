import 'dart:convert';
import 'dart:typed_data';

import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'revision_input.dart';

/// Ordered historical classification candidates, distinct from a selected type.
final class ConvertedClassification {
  ConvertedClassification(this.relationship, Iterable<RecordId> candidates)
    : candidates = List.unmodifiable(candidates);
  final String relationship;
  final List<RecordId> candidates;
}

final class ConvertedSerializedRecord {
  const ConvertedSerializedRecord(
    this.record,
    this.sourceDigest,
    this.classification,
  );
  final StoredVersion record;
  final String sourceDigest;
  final ConvertedClassification? classification;
}

/// Verify the known original recipe before any normalization. Input SQL and
/// unverified bodies are never used as target schema or repaired by rehashing.
ConvertedSerializedRecord convertSerializedRecord({
  required UniverseId universe,
  required RecordId recordId,
  required RecordVersionId versionId,
  required RecordKind kind,
  required Uint8List bytes,
  required String sourceDigest,
  String? schemaVersion,
}) {
  if (bytes.length > 4194304) {
    throw const FormatException('Serialized conversion body exceeds 4 MiB');
  }
  final original = CanonicalValue.parseJson(utf8.decode(bytes));
  final discriminator = switch (schemaVersion) {
    null => kind.wireName,
    'v1' => '${kind.wireName}:v1:v1',
    _ => throw const FormatException(
      'Unsupported legacy payload digest recipe',
    ),
  };
  if (payloadDigest(discriminator, original) != sourceDigest) {
    throw const FormatException(
      'Original payload digest mismatch; repair a source copy',
    );
  }
  final fields = objectFields(original);
  ConvertedClassification? evidence;
  final mapping = switch (kind) {
    RecordKind.entity => (
      'types',
      'classification',
      'classificationResolution',
      'unclassified',
      'membership',
    ),
    RecordKind.entityType => (
      'parents',
      'parent',
      'parentResolution',
      'root',
      'parent',
    ),
    _ => null,
  };
  if (mapping != null) {
    final candidates = fields.remove(mapping.$1);
    if (candidates != null) {
      if (candidates is! CanonicalArray) {
        throw const FormatException('Invalid classification candidates');
      }
      final ids = <RecordId>[];
      for (final candidate in candidates.items) {
        if (candidate is! CanonicalString) {
          throw const FormatException('Invalid classification candidate');
        }
        ids.add(RecordId.parse(candidate.value));
      }
      fields[mapping.$2] = ids.length == 1
          ? CanonicalString(ids.single.value)
          : const CanonicalNull();
      fields[mapping.$3] = CanonicalString(switch (ids.length) {
        0 => mapping.$4,
        1 => 'resolved',
        _ => 'ambiguous',
      });
      if (kind == RecordKind.entityType) {
        if (!fields.containsKey('name')) {
          throw const FormatException(
            'Legacy entity type lacks an authored name; repair a copy',
          );
        }
        fields.putIfAbsent(
          'applicability',
          () => const UnspecifiedApplicability().toWire(),
        );
      }
      evidence = ConvertedClassification(mapping.$5, ids);
    }
  }
  final normalized = CanonicalObject(fields.entries);
  final payload = RecordPayload.fromWire(normalized).toWire();
  // Domain decoding must not silently discard fields or manufacture defaults.
  if (payload.toText() != normalized.toText()) {
    throw const FormatException(
      'Legacy body has no lossless typed representation',
    );
  }
  final record = StoredVersion.build(
    versionId,
    RecordIdentity(universeId: universe, recordId: recordId, recordKind: kind),
    payload,
  );
  return ConvertedSerializedRecord(record, sourceDigest, evidence);
}

/// Decode the one maintained serialized draft form, retaining all other fields.
/// The full workflow family is validated by the target's typed workflow writer.
CanonicalValue convertSerializedWorkflow(
  String key,
  Uint8List bytes,
  String sourceDigest,
) {
  if (bytes.length > 4194304) {
    throw const FormatException('Serialized workflow body exceeds 4 MiB');
  }
  final original = CanonicalValue.parseJson(utf8.decode(bytes));
  if (canonicalDigest(original) != sourceDigest) {
    throw const FormatException('Original workflow digest mismatch');
  }
  if (!key.startsWith('draft:') || original is! CanonicalObject) {
    return original;
  }
  final fields = objectFields(original);
  final content = fields['content'];
  if (content is! CanonicalObject) return original;
  final contentFields = objectFields(content);
  final operations = contentFields['operations'];
  if (operations is! CanonicalString) return original;
  final array = CanonicalValue.parseJson(operations.value);
  if (array is! CanonicalArray) {
    throw const FormatException(
      'Unrecoverable draft operations; repair a copy',
    );
  }
  contentFields['operations'] = CanonicalArray(
    array.items.map((item) => DomainOperation.fromWire(item).toWire()),
  );
  fields['content'] = CanonicalObject(contentFields.entries);
  return CanonicalObject(fields.entries);
}
