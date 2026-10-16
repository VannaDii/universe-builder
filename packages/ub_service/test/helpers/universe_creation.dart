import 'package:ub_service/src/universe_evidence_policy.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/ub_store.dart';
import 'package:ub_domain/ub_domain.dart';

List<DomainOperation> unsourcedCreationFact(
  UniverseId universe,
  RecordId context,
) {
  RecordId id(int n) =>
      RecordId.parse('rec_${n.toRadixString(16).padLeft(24, '0')}');
  RecordRef ref(int n) => RecordRef(universe: universe, record: id(n));
  final represented = RecordRef(universe: universe, record: context);
  return [
    CreateEntityOperation(
      clientRef: id(30).value,
      record: EntityRecord(
        names: [],
        classificationResolution: ClassificationResolution.unclassified,
        worldAssociations: [],
        labels: {},
        metadata: {},
      ),
    ),
    DefinePropertyOperation(
      clientRef: id(31).value,
      record: PropertyRecord(
        namespace: 'authored',
        key: 'documented',
        labels: {},
        value: const SimpleValueShape(SimpleShapeKind.boolean),
        multiplicity: Multiplicity.single,
        persistence: PersistenceSemantics.explicitInterval,
        exclusive: false,
        symmetric: false,
        transitive: false,
      ),
    ),
    AssertPropositionOperation(
      clientRef: id(32).value,
      proposition: PropositionRecord(
        predicate: ref(31),
        subject: ref(30),
        value: const BooleanValue(true),
        quantification: Quantification.particular,
        context: represented,
      ),
      assertion: AssertionRecord(
        attributeMode: AttributeMode.instance,
        proposition: ref(32),
        polarity: Polarity.support,
        scope: Scope(
          context: represented,
          applicability: const UniverseApplicability(),
        ),
        validity: const UnspecifiedValidity(),
        persistence: PersistenceSemantics.explicitInterval,
        precision: Precision.exact,
        basis: const AuthorDecisionBasis('Initial authored fact'),
      ),
    ),
  ];
}

/// Complete the v0 root records in low-level authority fixtures.
void addFixtureRoot(OwnedSqliteDatabase package) {
  final universe = package.universeId;
  final journal = SqliteJournal(package.database, universe);
  for (final head in journal.heads().entries) {
    SqliteKernel(package.database, universe).commit(
      CommitInput(
        universe: universe,
        continuity: head.key,
        expectedHead: head.value,
        principal: PrincipalId.generate(),
        decision: 'Root policy',
        reason: 'Current v0 fixture',
        idempotencyKey: 'fixture-root:${head.key.value}',
        changes: [
          for (final row in initialUniversePolicyRecords(universe, false))
            Assignment(
              recordId: row.identity.recordId,
              next: StoredVersion.build(
                row.recordVersionId,
                row.identity,
                row.payload.toWire(),
              ),
            ),
        ],
      ),
    );
  }
}
