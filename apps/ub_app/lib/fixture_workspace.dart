import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

abstract interface class FixtureTransport {
  Future<Response> call(Request request);
  Future<void> close();
}

/// Exact reviewed input survives an uncertain reply for an explicit same-key retry.
final class FixtureProposalDraft {
  FixtureProposalDraft({
    required this.universe,
    required this.context,
    required this.label,
    required this.valueState,
  }) : key = OperationId.generate().value;
  final Selector universe;
  final ContextId context;
  final String label, valueState, key;
  CreateProposalRequest get request => CreateProposalRequest(
    universe: universe,
    contextId: context,
    operations: [
      CreateEntityOperation(
        clientRef: 'new_entity',
        record: EntityRecord(
          names: [],
          classificationResolution: ClassificationResolution.unclassified,
          worldAssociations: [],
          labels: {'en': label},
          metadata: {'draft_value_state': TextValue(valueState)},
        ),
      ),
    ],
    submission: Submission.draft,
    rationale: 'Native feasibility proposal; no asserted fact or canon change',
    idempotencyKey: key,
  );
}

final class FixtureWorkspace {
  FixtureWorkspace(this.transport);
  final FixtureTransport transport;
  static String worldLabel(WorldId id) =>
      {
        'wld_${'1'.padLeft(24, '0')}': 'Aster',
        'wld_${'2'.padLeft(24, '0')}': 'Nacre',
        'wld_${'3'.padLeft(24, '0')}': 'Aster',
      }[id.value] ??
      id.value;
  static const universes = ['The Ashen Cycle', 'The Glass Archive'];
  String universe = universes.first;
  String? world;
  ContextId? context;
  List<SearchHit> hits = const [];
  bool busy = false;

  void selectScope(String universe, String? world) {
    if (busy) throw StateError('Wait for the current fixture request.');
    if (!universes.contains(universe) ||
        world != null &&
            world != 'Aster' &&
            !(universe == universes.first && world == 'Nacre')) {
      throw const FormatException('Choose a fixture universe and world.');
    }
    this.universe = universe;
    this.world = world;
    context = null;
    hits = const [];
  }

  Future<void> open() async {
    if (busy) throw StateError('Wait for the current fixture request.');
    busy = true;
    context = null;
    hits = const [];
    try {
      final opened = await transport.call(
        OpenContextRequest(
          universe: Selector(universe),
          continuityId: ContinuityId.parse('cont_${'1'.padLeft(24, '0')}'),
          revision: const HeadRevisionSelector(),
          representedContext: ContextIdSelector(
            RecordId.parse('rec_${'5a'.padLeft(24, '0')}'),
          ),
          temporalQuery: const TimelessFrameTime(),
          temporalSystems: [],
          perspective: const AuthorPerspective(),
        ),
      ) as OpenContextResponse;
      final rows = await transport.call(
        SearchRequest(
          universe: Selector(universe),
          contextId: opened.body.result.contextId,
          world: world == null ? null : Selector(world!),
          query: '',
          typedFilters: Filters(recordKinds: []),
          limit: 25,
        ),
      ) as SearchResponse;
      context = opened.body.result.contextId;
      hits = rows.body.result.hits;
    } finally {
      busy = false;
    }
  }

  FixtureProposalDraft review(String label, String valueState) {
    if (busy || context == null) {
      throw StateError('Open the selected universe first.');
    }
    if (label.trim().isEmpty ||
        !{'unspecified', 'explicit_absence', 'known'}.contains(valueState)) {
      throw const FormatException(
        'Enter an entity label and choose its value state.',
      );
    }
    // World focus is a reading filter. This fixture draft remains unassigned.
    return FixtureProposalDraft(
      universe: Selector(universe),
      context: context!,
      label: label,
      valueState: valueState,
    );
  }

  Future<Proposal> save(FixtureProposalDraft draft) async {
    if (busy || draft.universe.value != universe || draft.context != context) {
      throw StateError('Review this proposal in its original universe.');
    }
    busy = true;
    try {
      final reply = await transport.call(draft.request) as ProposeResponse;
      return (reply.body.result as SemanticProposalOutcome).proposal;
    } finally {
      busy = false;
    }
  }
}
