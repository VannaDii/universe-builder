import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'writing_contract_projection.dart';
import 'writing_disclosures.dart';
import 'writing_policies.dart';
import 'writing_relations.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);

RecordPayload _replace(
  RecordPayload old,
  RecordPayload replacement,
  Set<String> allowed,
) {
  final fields = Map.fromEntries(old.toWire().fields)
    ..removeWhere((key, _) => allowed.contains(key));
  for (final field in replacement.toWire().fields) {
    if (allowed.contains(field.key)) fields[field.key] = field.value;
  }
  return RecordPayload.fromWire(CanonicalObject(fields.entries));
}

bool _permittedDefinition(RecordPayload old, RecordPayload replacement) {
  switch ((old, replacement)) {
    case (PropertyRecord(), PropertyRecord()):
      return _replace(old, replacement, {'multiplicity', 'persistence'}) ==
          replacement;
    case (EntityTypeRecord(), EntityTypeRecord()):
      return _replace(old, replacement, {
            'parent',
            'parentResolution',
            'applicability',
          }) ==
          replacement;
    case (
      final ActionDefinitionRecord old,
      final ActionDefinitionRecord replacement,
    ):
      return _replace(old, replacement, {
                'requirements',
                'consequenceContract',
                'scope',
                'validity',
              }) ==
              replacement &&
          old.scope.context == replacement.scope.context &&
          old.scope.realm == replacement.scope.realm;
    case (final RelationRecord old, final RelationRecord replacement):
      if (old.roles.length != replacement.roles.length) return false;
      for (var i = 0; i < old.roles.length; i++) {
        if (old.roles[i].name != replacement.roles[i].name) return false;
      }
      return _replace(old, replacement, {'roles'}) == replacement;
    case (final RuleRecord old, final RuleRecord replacement)
        when supportedWritingRelationLimit(old) &&
            supportedWritingRelationLimit(replacement):
      final before = old.relationCardinality!,
          after = replacement.relationCardinality!;
      final permitted = RuleRecord.fromWire(
        CanonicalObject([
          ...old.toWire().fields.where((f) => f.key != 'relationCardinality'),
          MapEntry(
            'relationCardinality',
            RelationCardinality(
              relation: before.relation,
              grouping: after.grouping,
              countedRole: after.countedRole,
              maximum: after.maximum,
              scope: Scope(
                context: before.scope.context,
                realm: before.scope.realm,
                applicability: after.scope.applicability,
              ),
              validity: after.validity,
            ).toWire(),
          ),
        ]),
      );
      return permitted == replacement;
    case (final RuleRecord old, final RuleRecord replacement):
      return permittedWritingPolicyCorrection(old, replacement);
    default:
      return false;
  }
}

/// Exact source preparation is a private author route, not a general operation
/// bypass. The caller admits the author and current draft before using this gate.
void validateWritingSourcePreparation({
  required List<DomainOperation> operations,
  required List<RecordVersion> originals,
  required bool contracts,
  required bool authorOrigin,
  required List<RecordVersion> Function(ContinuityId, RevisionId) canonAt,
  String? knowledgeRationale,
}) {
  RecordPayload? original(RecordRef ref, RecordVersionId version) => originals
      .where(
        (r) =>
            r.identity.recordId == ref.record && r.recordVersionId == version,
      )
      .firstOrNull
      ?.payload;
  bool disclosures(SceneRecord scene) {
    try {
      checkWritingSceneDisclosures(
        edition: scene.workVersion,
        disclosures: scene.disclosedRecords,
        rows: originals,
        canonAt: canonAt,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  bool allowed(DomainOperation operation) {
    switch (operation) {
      case RecordNarrativeReferenceOperation(:final record, :final payload):
        if (record == RecordKind.representedContext &&
            payload is RepresentedContextRecord) {
          return contracts &&
              (payload.kind is AuthoredContext ||
                  payload.kind is NarratorContext) &&
              payload.parent != null &&
              payload.chronology != null &&
              (payload.kind is! NarratorContext ||
                  originals.any(
                    (r) =>
                        r.identity.recordId ==
                            (payload.kind as NarratorContext).narrator.record &&
                        r.payload is EntityRecord,
                  ));
        }
        return contracts &&
            ((record == RecordKind.workVersion &&
                    payload is WorkVersionRecord) ||
                (record == RecordKind.sceneRef &&
                    payload is SceneRecord &&
                    disclosures(payload)));
      case ReviseSceneOperation(
        :final record,
        :final expectedVersion,
        :final replacement,
        :final rationale,
      ):
        final old = original(record, expectedVersion);
        return contracts &&
            _nonWhitespace.hasMatch(rationale) &&
            disclosures(replacement) &&
            old is SceneRecord &&
            old.sceneId == replacement.sceneId &&
            old.workVersion == replacement.workVersion &&
            CanonicalArray(old.worldAssociations.map((a) => a.toWire()))
                    .toText() ==
                CanonicalArray(
                  replacement.worldAssociations.map((a) => a.toWire()),
                ).toText();
      case AddBeliefOperation(:final record)
          when record.acquisition?.basis is AuthorEstablishedKnowledge:
        return knowledgeRationale != null &&
            authorOrigin &&
            record.basis == AuthorDecisionBasis(knowledgeRationale);
      case ReviseCommunicationOperation() || ReviseInterpretationOperation():
        return true;
      case ReviseAttitudeOperation(
        :final record,
        :final expectedVersion,
        :final replacement,
      ):
        final old = original(record, expectedVersion);
        if (old is! EpistemicAttitudeRecord ||
            old.holder != replacement.holder ||
            old.attitude != replacement.attitude ||
            old.acquisition?.toWire().toText() !=
                replacement.acquisition?.toWire().toText() ||
            old.basis != replacement.basis) {
          return false;
        }
        if (old.attitude == EpistemicAttitudeKind.knows) {
          if (old.proposition != replacement.proposition ||
              old.certainty != replacement.certainty) {
            return false;
          }
          if (old.acquisition?.basis is AuthorEstablishedKnowledge) {
            return knowledgeRationale != null && authorOrigin;
          }
        }
        return true;
      case ReviseItemPowerOperation(
        :final record,
        :final expectedVersion,
        :final replacement,
        :final rationale,
      ):
        final old = original(record, expectedVersion);
        return contracts &&
            _nonWhitespace.hasMatch(rationale) &&
            old is ItemPowerRecord &&
            old.item == replacement.item &&
            old.holderPredicate == replacement.holderPredicate &&
            old.powerPredicate == replacement.powerPredicate &&
            old.scope.context == replacement.scope.context;
      case ReviseDefinitionOperation(
        :final record,
        :final expectedVersion,
        :final replacement,
      ):
        final old = original(record, expectedVersion);
        return contracts &&
            old != null &&
            _permittedDefinition(old, replacement);
      case AddNameOperation(:final record, :final expectedVersion):
        return original(record, expectedVersion) is EntityRecord;
      case EndAssertionAtOperation(:final record, :final expectedVersion) ||
          RetractAssertionOperation(:final record, :final expectedVersion):
        final old = original(record, expectedVersion);
        if (old is! AssertionRecord || old.establishedBy != null) return false;
        final proposition = originals
            .where((r) => r.identity.recordId == old.proposition.record)
            .firstOrNull
            ?.payload;
        if (proposition is! PropositionRecord) return false;
        final predicate = originals
            .where((r) => r.identity.recordId == proposition.predicate.record)
            .firstOrNull
            ?.payload;
        return predicate is PropertyRecord ||
            operation is EndAssertionAtOperation &&
                old.attributeMode == AttributeMode.instance &&
                predicate is RelationRecord;
      case WithdrawEventOperation(
        :final record,
        :final expectedVersion,
        :final rationale,
      ):
        final old = original(record, expectedVersion);
        return _nonWhitespace.hasMatch(rationale) &&
            old is EventRecord &&
            old.occurrence is SimpleOccurrence &&
            (old.occurrence as SimpleOccurrence).kind ==
                OccurrenceKind.occurred;
      case SetCompletenessOperation(:final record):
        return contracts && record.completeness is ObjectiveCompleteness;
      case DefineActionOperation() ||
          DefineRelationOperation() ||
          DefineItemPowerOperation():
        return contracts;
      case DefineUnitOperation(:final record):
        return contracts && record.base == null && record.scaleToBase == null;
      case DefineRuleOperation(:final record):
        return contracts &&
            (supportedWritingPolicy(record) ||
                supportedWritingKnowledgePolicy(record) ||
                supportedWritingBoundary(record) ||
                supportedWritingRelationLimit(record));
      case IntroduceInstanceOperation() ||
          CreateWorldOperation() ||
          CreateWorkOperation() ||
          IntroduceDefinitionOperation() ||
          AddNamedAttributeOperation() ||
          RefineClassificationOperation() ||
          DefinePropertyOperation() ||
          RecordRelationOperation() ||
          AssertPropositionOperation() ||
          DefinePropositionOperation() ||
          InitializeInstanceOperation() ||
          ReviseEventOperation() ||
          RecordEventOperation() ||
          RecordCommunicationOperation() ||
          AddBeliefOperation() ||
          SupersedeAssertionOperation():
        return true;
      default:
        return false;
    }
  }

  if (operations.any((op) => !allowed(op))) {
    throw const PolicyDeniedError(
      message: 'Source preparation accepts agent factual deltas only; protected contracts require explicit author contract review; creative acceptance requires a separate explicit author decision.',
    );
  }
}

/// Produce the existing exact UTF-8 staging records. Import time is supplied by
/// the admitted native caller; neither staging nor a digest approves the source.
({
  List<DomainOperation> operations,
  List<MapEntry<String, CanonicalValue>> entries,
  RecordId sourceVersion,
  String digest,
  BigInt byteSize,
})
stageWritingSource({
  required UniverseId universe,
  required ProfileId author,
  required String label,
  required String text,
  required String importTime,
}) {
  final retained = CanonicalString(text);
  CanonicalString(label);
  final bytes = utf8.encode(text);
  if (bytes.length > 512000 ||
      !_nonWhitespace.hasMatch(label) ||
      utf8.encode(label).length > 256) {
    throw const InvalidArgumentError(
      field: 'source',
      message: 'source label and text exceed limits',
    );
  }
  final digest = sha256.convert(bytes).toString(),
      size = BigInt.from(bytes.length);
  final source = RecordId.generate(), version = RecordId.generate();
  final payload = SourceRecord(
    label: label,
    origin: const OriginMetadata(),
    versions: [version],
  );
  final versionPayload = SourceVersionRecord(
    source: RecordRef(universe: universe, record: source),
    contentDigest: digest,
    mediaType: 'text/plain; charset=utf-8',
    byteSize: size,
    importActor: PrincipalId.parse(author.value.replaceFirst('prf_', 'prn_')),
    importTime: importTime,
    decoding: DecodingDescriptor(
      encoding: 'UTF-8',
      representation: 'exact-utf8-v1',
      byteLength: size,
    ),
    origin: const OriginMetadata(),
  );
  return (
    operations: List.unmodifiable([
      RecordNarrativeReferenceOperation(
        clientRef: source.value,
        record: RecordKind.source,
        payload: payload,
      ),
      RecordNarrativeReferenceOperation(
        clientRef: version.value,
        record: RecordKind.sourceVersion,
        payload: versionPayload,
      ),
    ]),
    entries: List.unmodifiable([
      MapEntry('source:$digest', retained),
      MapEntry('source-version:${version.value}', versionPayload.toWire()),
    ]),
    sourceVersion: version,
    digest: digest,
    byteSize: size,
  );
}

/// Attach the exact author passage to the reviewed assertions. Metadata and
/// acquisition remain unchanged; explicit author knowledge keeps its decision.
({List<DomainOperation> operations, Map<RecordId, RecordVersionId> versions})
attachWritingSource({
  required UniverseId universe,
  required RecordRef context,
  required List<DomainOperation> operations,
  required List<DomainOperation> sourceOperations,
  required RecordId sourceVersion,
  required String text,
  required String digest,
  required BigInt byteSize,
  String? knowledgeRationale,
}) {
  final version = RecordVersionId.generate(), anchor = RecordId.generate();
  final basis = SourceAnchorBasis(
    RecordRef(universe: universe, record: anchor),
    true,
  );
  DomainOperation attach(DomainOperation op) {
    final field = switch (op) {
      AssertPropositionOperation() || RecordRelationOperation() => 'assertion',
      SupersedeAssertionOperation() => 'replacement',
      AddNamedAttributeOperation() => 'evidence',
      AddBeliefOperation() when knowledgeRationale == null => 'record',
      _ => null,
    };
    final wire = Map.fromEntries(op.toWire().fields);
    if (field != null) {
      wire[field] = CanonicalObject(
        {
          ...Map.fromEntries((wire[field]! as CanonicalObject).fields),
          'basis': basis.toWire(),
        }.entries,
      );
    } else if (op is EndAssertionAtOperation) {
      wire['basis'] = basis.toWire();
    } else {
      return op;
    }
    return DomainOperation.fromWire(CanonicalObject(wire.entries));
  }

  return (
    operations: List.unmodifiable([
      ...sourceOperations,
      AddSourceAnchorOperation(
        clientRef: anchor.value,
        record: AnchorRecord(
          sourceVersion: VersionRef(
            universe: universe,
            record: sourceVersion,
            version: version,
          ),
          locator: ByteRangeLocator(BigInt.zero, byteSize),
          excerptDigest: digest,
          excerpt: text,
          context: context,
        ),
      ),
      ...operations.map(attach),
    ]),
    versions: Map.unmodifiable({sourceVersion: version}),
  );
}
