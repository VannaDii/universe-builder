import 'dart:convert';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/fixture.dart';

String id(String prefix, int n) =>
    '${prefix}_${n.toRadixString(16).padLeft(24, '0')}';
const universe = 'The Ashen Cycle';
final operation = <String, Object?>{
  'kind': 'create_entity',
  'client_ref': 'new_entity',
  'record': {
    'names': <Object?>[],
    'classification': null,
    'classificationResolution': 'unclassified',
    'worldAssociations': <Object?>[],
    'labels': {'en': 'The Lantern House'},
    'metadata': <String, Object?>{},
  },
};

void main() {
  late DisposableFixture fixture;
  var next = 0;
  Response call(String tool, Map<String, Object?> args) => fixture.handle(
    BigInt.from(++next),
    Request.fromTool(
      'universe_$tool',
      CanonicalValue.parseWireJson(jsonEncode({'universe': universe, ...args})),
    ),
  );
  Map<String, Object?> openArgs({String? scene}) => {
    'continuity_id': id('cont', 1),
    'revision': {'kind': 'head'},
    'represented_context': id('rec', 90),
    'temporal_query': {'kind': 'timeless'},
    'temporal_systems': <Object?>[],
    'perspective': 'author',
    'reader_scene': ?scene,
  };
  String open({String owner = universe}) => (call('open_context', {
    ...openArgs(),
    'universe': owner,
  }) as OpenContextResponse).body.result.contextId.value;
  SearchResponse search(
    String context, {
    String owner = universe,
    String? world,
    String query = '',
    int limit = 25,
  }) => call('search', {
    'universe': owner,
    'context_id': context,
    'query': query,
    'typed_filters': {'record_kinds': <Object?>[]},
    'limit': limit,
    'world': ?world,
  }) as SearchResponse;
  Map<String, Object?> createArgs(String context, {String key = 'fixture-1'}) =>
      {
        'context_id': context,
        'action': 'create',
        'operations': [operation],
        'submission': 'draft',
        'rationale': 'Fixture proposal',
        'idempotency_key': key,
      };
  Proposal proposal(Response response) =>
      ((response as ProposeResponse).body.result as SemanticProposalOutcome)
          .proposal;
  Map<String, Object?> reference(Proposal p) => {
    'proposal_id': p.proposalId.value,
    'version': p.version.toInt(),
    'digest': p.digest,
  };
  setUp(() {
    fixture = DisposableFixture();
    next = 0;
  });

  test(
    'literal named universes, frames and per-request world focus stay isolated',
    () {
      final context = open();
      final selected = search(context, world: 'Aster');
      expect(selected.body.worldFocus!.value, id('wld', 1));
      expect(
        selected.body.result.hits.map((h) => h.scopeCategory),
        contains(ScopeCategory.unassigned),
      );
      final all = search(context);
      expect(all.body.worldFocus, isNull);
      expect(
        all.body.result.hits.length,
        greaterThan(selected.body.result.hits.length),
      );
      expect(
        () => search(context, owner: 'The Glass Archive'),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      final other = search(
        open(owner: 'The Glass Archive'),
        owner: 'The Glass Archive',
        world: 'Aster',
      );
      expect(other.body.universeId.value, id('unv', 2));
      expect(other.body.worldFocus!.value, id('wld', 3));
      expect(
        () => call('describe', {
          'universe': 'the ashen cycle',
          'mode': 'summary',
        }),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      expect(
        () =>
            call('describe', {'universe_id': id('unv', 2), 'mode': 'summary'}),
        throwsA(isA<UniverseScopeMismatchError>()),
      );
      expect(
        () => search(context, limit: 1),
        throwsA(isA<EvaluationLimitReachedError>()),
      );
      expect(
        search(context, query: 'MARA').body.result.hits.single.label,
        'Mara — seal custodian',
      );
    },
  );

  test('records retain fixture IDs, canonical payloads and explicit scope restrictions', () {
    final context = open();
    final get = call('get', {
      'context_id': context,
      'record_ids': [id('rec', 149), id('rec', 10)],
      'field_groups': ['payload'],
    }) as GetResponse;
    expect(get.body.result.records.first.recordVersionId.value, id('ver', 149));
    expect(
      (get.body.result.records.first.payload as WorldRecord).selector,
      'Aster',
    );
    expect(
      () => call('get', {
        'context_id': context,
        'world': 'Aster',
        'record_ids': [id('rec', 150)],
        'field_groups': ['payload'],
      }),
      throwsA(isA<WorldScopeConflictError>()),
    );
    expect(
      () => call('get', {
        'context_id': context,
        'record_ids': [id('rec', 20)],
        'field_groups': ['payload'],
      }),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(
      () => call('get', {
        'context_id': context,
        'record_ids': [id('rec', 10)],
        'field_groups': ['history'],
      }),
      throwsA(isA<UnsupportedSemanticsError>()),
    );
  });

  test('proposal retry and operation recovery return frozen content without mutating canon', () {
    final context = open();
    final args = createArgs(context);
    final first = proposal(call('propose', args));
    expect(first.canonical, isFalse);
    expect(first.proposalId.value, id('prp', 1003));
    expect(first.operationId.value, id('op', 1002));
    expect(
      proposal(call('propose', args)).toWire().toText(),
      first.toWire().toText(),
    );
    // A second handle resolving to the same frame is the same semantic request.
    expect(
      proposal(call('propose', {...args, 'context_id': open()})).digest,
      first.digest,
    );
    final recovered = call('get_operation', {
      'lookup': 'key',
      'operation_kind': 'propose',
      'idempotency_key': 'fixture-1',
    }) as GetOperationResponse;
    expect(
      recovered.body.result.proposal!.toWire().toText(),
      first.toWire().toText(),
    );
    final cancel = call('cancel_operation', {
      'operation_id': first.operationId.value,
      'idempotency_key': 'cancel-1',
    }) as CancelOperationResponse;
    expect(cancel.body.result.state, OperationState.succeeded);
    expect(cancel.body.result.cancellationRequested, isTrue);
    final status = call('get_operation', {
      'lookup': 'id',
      'operation_id': first.operationId.value,
    }) as GetOperationResponse;
    expect(status.body.result.cancellationRequested, isFalse);
    expect(
      () => call('propose', {...args, 'rationale': 'different'}),
      throwsA(isA<IdempotencyKeyReusedError>()),
    );
    expect(search(context, query: 'Lantern').body.result.hits, isEmpty);
    expect(
      () => call('get_operation', {
        'universe': 'The Glass Archive',
        'lookup': 'id',
        'operation_id': first.operationId.value,
      }),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final fresh = DisposableFixture();
    expect(
      () => fresh.handle(
        BigInt.one,
        Request.fromTool(
          'universe_get_operation',
          CanonicalValue.parseWireJson(
            jsonEncode({
              'universe': universe,
              'lookup': 'key',
              'operation_kind': 'propose',
              'idempotency_key': 'fixture-1',
            }),
          ),
        ),
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  test('revision, submission and withdrawal retain history and reject stale bindings', () {
    final context = open();
    final first = proposal(call('propose', createArgs(context)));
    final revised = proposal(
      call('propose', {
        ...createArgs(context, key: 'revise'),
        'action': 'revise',
        'proposal_reference': reference(first),
        'rationale': 'Revised 記憶\r\n',
      }),
    );
    expect(revised.version, BigInt.two);
    expect(revised.proposalId, first.proposalId);
    expect(revised.digest, isNot(first.digest));
    final old = call('get_proposal', {
      'proposal_id': first.proposalId.value,
      'version': 1,
    }) as GetProposalResponse;
    expect(
      (old.body.result as FrozenProposalView).proposal.toWire().toText(),
      first.toWire().toText(),
    );
    Map<String, Object?> action(String name, Proposal p) => {
      'context_id': context,
      'action': name,
      'proposal_reference': reference(p),
      'idempotency_key': '$name-${p.version}',
    };
    expect(
      () => call('propose', action('submit', first)),
      throwsA(isA<InvalidArgumentError>()),
    );
    final submitted = proposal(call('propose', action('submit', revised)));
    expect(submitted.submission, Submission.submitted);
    final withdrawn = proposal(call('propose', action('withdraw', submitted)));
    expect(withdrawn.withdrawn, isTrue);
    expect(
      () => call('propose', action('submit', withdrawn)),
      throwsA(isA<InvalidArgumentError>()),
    );
  });

  test('world proposals reject unassigned, shared and foreign effects', () {
    final context = open();
    final args = {...createArgs(context), 'world': 'Aster'};
    expect(
      () => call('propose', args),
      throwsA(isA<WorldScopeConflictError>()),
    );
    Map<String, Object?> entity(List<int> worlds) => {
      ...operation,
      'record': {
        ...operation['record']! as Map<String, Object?>,
        'worldAssociations': [
          for (final n in worlds)
            {
              'world': id('wld', n),
              'role': 'setting',
              'validity': {'kind': 'unspecified'},
              'qualifiers': <String, Object?>{},
            },
        ],
      },
    };
    expect(
      () => call('propose', {
        ...args,
        'operations': [
          entity([1, 2]),
        ],
      }),
      throwsA(isA<WorldScopeConflictError>()),
    );
    expect(
      () => call('propose', {
        ...args,
        'operations': [
          entity([3]),
        ],
      }),
      throwsA(isA<WorldNotFoundOrNotAccessibleError>()),
    );
    final scoped = proposal(
      call('propose', {
        ...args,
        'operations': [
          entity([1]),
        ],
      }),
    );
    expect(scoped.worldScope!.value, id('wld', 1));
    final foreign = {
      'kind': 'tombstone_record',
      'record': {'universe': id('unv', 2), 'record': id('rec', 20)},
      'expected_version': id('ver', 20),
      'rationale': 'withdraw foreign record',
    };
    expect(
      () => call('propose', {
        ...createArgs(context, key: 'foreign'),
        'operations': [foreign],
      }),
      throwsA(isA<UniverseScopeMismatchError>()),
    );
  });

  test(
    'bounded contexts and unsupported persistent operations fail explicitly',
    () {
      final context = open();
      expect(
        () => call('get_state', {
          'context_id': context,
          'entity_ids': [id('rec', 10)],
          'predicate_filters': <Object?>[],
        }),
        throwsA(isA<UnsupportedSemanticsError>()),
      );
      expect(
        () => call('commit', {
          'proposal_reference': {
            'proposal_id': id('prp', 1),
            'version': 1,
            'digest': 'fixture-digest',
          },
          'expected_base_revision': id('rev', 1),
          'validation_run': id('val', 1),
          'idempotency_key': 'commit',
        }),
        throwsA(isA<PolicyDeniedError>()),
      );
      for (var n = 1; n < 128; n++) {
        open();
      }
      expect(() => open(), throwsA(isA<EvaluationLimitReachedError>()));
      expect(
        (call('describe', {
          'mode': 'summary',
        }) as DescribeResponse).body.result.fixture,
        isTrue,
      );
    },
  );
}
