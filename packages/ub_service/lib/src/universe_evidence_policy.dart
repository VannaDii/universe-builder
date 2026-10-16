import 'package:ub_domain/ub_domain.dart';

/// Every new universe has a selected, defined root policy. Real World creation
/// clones the built-in evidence requirement; scratch creation starts empty.
/// No imported source qualifies until the author selects its category membership.
List<RecordVersion> initialUniversePolicyRecords(
  UniverseId universe,
  bool realWorld, {
  RecordId? definitionId,
  String? definitionKey,
  String evidenceNamespace = 'real_world',
}) {
  RecordVersion record(RecordPayload payload, {RecordId? id}) => RecordVersion.build(
    recordVersionId: RecordVersionId.generate(),
    identity: RecordIdentity(
      universeId: universe,
      recordId: id ?? RecordId.generate(),
      recordKind: payload.recordKind,
    ),
    payload: payload,
  );
  final evidence = <RecordVersion>[];
  if (realWorld) {
    final category = record(
      DomainPackRecord(
        key: '$evidenceNamespace.sources',
        version: '1',
        dependencies: {},
        capabilities: [],
        records: [],
      ),
    );
    final policy = record(
      RuleRecord(
        namespace: evidenceNamespace,
        key: 'default',
        labels: {'en': 'Real World evidence'},
        kind: RuleKind.authorialRestriction,
        commitPolicy: CommitPolicy.alwaysBlock,
        applicability: const UniverseApplicability(),
        targetPredicates: [],
        expression: const LiteralExpr(true),
        capabilities: [],
        executable: true,
        validity: const UnspecifiedValidity(),
        requiredEvidence: RequiredEvidence(
          sourceCategories: [
            VersionRef(
              universe: universe,
              record: category.identity.recordId,
              version: category.recordVersionId,
            ),
          ],
        ),
      ),
    );
    evidence.addAll([category, policy]);
  }
  final definition = record(
    DomainPackRecord(
      key:
          definitionKey ??
          '$universePolicyDefinitionPrefix${realWorld ? 'real_world' : 'custom'}',
      version: '1',
      dependencies: {},
      capabilities: [],
      records: [
        for (final row in evidence)
          if (row.payload is RuleRecord) row.identity.recordId,
      ],
    ),
    id: definitionId,
  );
  final pack = definition.payload as DomainPackRecord;
  final selection = record(
    DomainPackRecord(
      key: universePolicySelectionKey,
      version: '1',
      dependencies: {pack.key: pack.version},
      capabilities: [],
      records: [definition.identity.recordId],
    ),
  );
  final result = [...evidence, definition, selection];
  UniversePolicySelection.fromRecords(universe, result);
  return List.unmodifiable(result);
}
