import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

String _id(String prefix, int n) =>
    '${prefix}_${n.toRadixString(16).padLeft(24, '0')}';
CanonicalObject _object(Map<String, CanonicalValue> fields) =>
    CanonicalObject(fields.entries);
Map<String, CanonicalValue> _fields(CanonicalObject value) =>
    Map.fromEntries(value.fields);
String? _text(CanonicalValue? value) =>
    value is CanonicalString ? value.value : null;
const _null = CanonicalNull();

final class _Universe {
  _Universe(this.id, this.name, this.worlds, this.records);
  final UniverseId id;
  final String name;
  final List<WorldSummary> worlds;
  final List<RecordVersion> records;
}

final class _Receipt {
  _Receipt(this.fingerprint, this.proposal);
  final String fingerprint;
  final Proposal proposal;
}

/// Bounded process-local state. This mode never opens an installation, grants
/// production authority, evaluates stored canon, or publishes proposed changes.
final class DisposableFixture {
  DisposableFixture() {
    for (final n in [1, 2]) {
      final owner = UniverseId.parse(_id('unv', n));
      final worlds = [
        WorldSummary(
          id: WorldId.parse(_id('wld', n == 1 ? 1 : 3)),
          name: const Selector('Aster'),
        ),
        if (n == 1)
          WorldSummary(
            id: WorldId.parse(_id('wld', 2)),
            name: const Selector('Nacre'),
          ),
      ];
      final associations = worlds
          .map(
            (w) => WorldAssociation(
              world: w.id,
              role: 'setting',
              validity: const UnspecifiedValidity(),
              qualifiers: {},
            ),
          )
          .toList();
      RecordVersion row(int number, RecordPayload payload) =>
          RecordVersion.build(
            recordVersionId: RecordVersionId.parse(_id('ver', number)),
            identity: RecordIdentity(
              universeId: owner,
              recordId: RecordId.parse(_id('rec', number)),
              recordKind: payload.recordKind,
            ),
            payload: payload,
          );
      EntityRecord entity(String label, List<WorldAssociation> associations) =>
          EntityRecord(
            names: [],
            classificationResolution: ClassificationResolution.unclassified,
            worldAssociations: associations,
            labels: {'en': label},
            metadata: {},
          );
      _universes.add(
        _Universe(
          owner,
          n == 1 ? 'The Ashen Cycle' : 'The Glass Archive',
          worlds,
          [
            for (final w in worlds)
              row(
                100 + w.id.value.codeUnitAt(w.id.value.length - 1),
                WorldRecord(
                  selector: w.name.value,
                  aliases: [],
                  labels: {},
                  metadata: {},
                ),
              ),
            row(
              n * 10,
              entity(
                n == 1 ? 'Mara — seal custodian' : 'Iven — archivist',
                associations,
              ),
            ),
            row(
              n * 10 + 1,
              WorkRecord(
                kind: WorkKind.novel,
                title: n == 1 ? 'Across Aster and Nacre' : 'The Glass Archive',
                labels: {},
                sourceRefs: [],
                versions: [],
                worldAssociations: associations,
              ),
            ),
            row(n * 10 + 2, entity('Unassigned traveler', [])),
          ],
        ),
      );
    }
  }
  final _universes = <_Universe>[];
  final _contexts = <String, Frame>{};
  final _proposals = <(String, BigInt), (UniverseId, Proposal)>{};
  final _receipts = <(UniverseId, String), _Receipt>{};
  int _next = 1000;
  String _allocate(String prefix) => _id(prefix, ++_next);

  Response handle(BigInt requestId, Request request) {
    if (requestId.isNegative || requestId.bitLength > 64) {
      throw const FormatException(
        'Unsigned 64-bit fixture request ID required',
      );
    }
    request.validate();
    final u = _universes
        .where((u) => u.name == request.universe.value)
        .firstOrNull;
    if (u == null) {
      throw const NotFoundOrNotAccessibleError(message: 'universe');
    }
    final a = _fields(request.toArgs());
    if (_text(a['universe_id']) case final String id when id != u.id.value) {
      throw const UniverseScopeMismatchError(
        message: 'universe guard does not match',
      );
    }
    Frame? frame;
    if (_text(a['context_id']) case final String id) {
      frame = _contexts[id];
      if (frame == null || frame.universe != u.id) {
        throw const NotFoundOrNotAccessibleError(message: 'context');
      }
    }
    WorldId? world;
    if (_text(a['world']) case final String name) {
      final selected = u.worlds.where((w) => w.name.value == name).firstOrNull;
      if (selected == null) {
        throw const NotFoundOrNotAccessibleError(message: 'world');
      }
      world = selected.id;
      if (_text(a['world_id']) case final String id when id != world.value) {
        throw const WorldScopeConflictError(
          message: 'world guard does not match',
        );
      }
    }
    for (final key in [
      'record_ids',
      'entity_ids',
      'focus_ids',
      'changed_records',
    ]) {
      if (a[key] case CanonicalArray(:final items)) {
        for (final target in items) {
          if (!u.records.any(
            (r) => r.identity.recordId.value == _text(target),
          )) {
            throw const NotFoundOrNotAccessibleError(message: 'record');
          }
        }
      }
    }
    if (a.containsKey('cursor')) _unsupported('fixture pagination');
    Response wrap(CanonicalValue result) => Response.fromTool(
      request.toolName,
      Envelope<CanonicalValue>(
        contractVersion: protocolVersion,
        requestId: requestId,
        universeId: u.id,
        universe: Selector(u.name),
        aliasMatched: false,
        frame: frame,
        worldFocus: world,
        authorizationScope: 'disposable-fixture/read-propose-only',
        delivery: Delivery(complete: true),
        result: result,
      ).toWire((v) => v),
    );
    switch (request.toolName) {
      case 'universe_describe':
        return wrap(
          _object({
            'fixture': const CanonicalBool(true),
            'worlds': CanonicalArray(u.worlds.map((w) => w.toWire())),
            'capabilities': CanonicalArray(
              _capabilities.map((c) => c.toWire()),
            ),
            'definition_ids': CanonicalArray([]),
            'continuities': CanonicalArray([]),
          }),
        );
      case 'universe_open_context':
        if (_contexts.length >= 128) _limit();
        final represented = _text(a['represented_context']);
        if (represented == null) {
          _unsupported('fixture supports an objective context ID only');
        }
        if (_text(a['continuity_id']) != _id('cont', 1) ||
            represented != _id('rec', 90) ||
            a['temporal_query']!.toText() != '{"kind":"timeless"}' ||
            _text(a['perspective']) != 'author' ||
            (a['temporal_systems'] as CanonicalArray).items.isNotEmpty) {
          _unsupported(
            'fixture supports main, objective, timeless author frame only',
          );
        }
        final revision = _fields(a['revision'] as CanonicalObject);
        if (_text(revision['kind']) == 'exact' &&
            _text(revision['revision_id']) != _id('rev', 1)) {
          throw const NotFoundOrNotAccessibleError(message: 'revision');
        }
        final contextId = _allocate('ctx');
        final readerScene = a['reader_scene'];
        if (readerScene != null &&
            readerScene is! CanonicalNull &&
            readerScene is! CanonicalString) {
          _unsupported('named scenes require persistent storage');
        }
        frame = Frame(
          universe: u.id,
          continuity: ContinuityId.parse(_id('cont', 1)),
          revision: RevisionId.parse(_id('rev', 1)),
          context: RecordRef(
            universe: u.id,
            record: RecordId.parse(represented),
          ),
          time: const TimelessFrameTime(),
          perspective: const AuthorPerspective(),
          readerScene: readerScene is CanonicalString
              ? RecordId.parse(readerScene.value)
              : null,
        );
        _contexts[contextId] = frame;
        return wrap(
          _object({
            'context_id': CanonicalString(contextId),
            'frame': frame.toWire(),
          }),
        );
      case 'universe_search':
        final search = request as SearchRequest;
        final hits = <SearchHit>[];
        for (final r in u.records) {
          final label = _label(r), worlds = _worlds(r, u);
          if (!label.toLowerCase().contains(search.query.toLowerCase()) ||
              search.typedFilters.recordKinds.isNotEmpty &&
                  !search.typedFilters.recordKinds.contains(
                    r.identity.recordKind,
                  )) {
            continue;
          }
          if (world != null && worlds.isNotEmpty && !worlds.contains(world)) {
            continue;
          }
          hits.add(
            SearchHit(
              recordId: r.identity.recordId,
              kind: r.identity.recordKind,
              label: label,
              worldIds: worlds,
              scopeCategory: worlds.isEmpty
                  ? ScopeCategory.unassigned
                  : world == null
                  ? ScopeCategory.shared
                  : ScopeCategory.selectedWorld,
            ),
          );
        }
        if (hits.length > search.limit) _limit();
        return wrap(
          _object({'hits': CanonicalArray(hits.map((h) => h.toWire()))}),
        );
      case 'universe_get':
        final get = request as GetRequest;
        if (get.fieldGroups.isEmpty ||
            get.fieldGroups.any((g) => g != FieldGroup.payload)) {
          _unsupported('fixture get supports the payload field group only');
        }
        final records = <RecordVersion>[];
        for (final id in get.recordIds) {
          final r = u.records.firstWhere((r) => r.identity.recordId == id);
          final worlds = _worlds(r, u);
          if (world != null && worlds.isNotEmpty && !worlds.contains(world)) {
            throw const WorldScopeConflictError(
              message: 'record outside selected world',
            );
          }
          records.add(r);
        }
        return wrap(
          _object({
            'records': CanonicalArray(records.map((r) => r.toWire())),
            'summaries': CanonicalArray([]),
            'evidence': CanonicalArray([]),
            'history': CanonicalArray([]),
            'history_coverage': _null,
          }),
        );
      case 'universe_propose':
        final action = _text(a['action']);
        if (action == 'attach_assessment' || action == 'select_assessment') {
          _unsupported('assessment actions require a persistent installation');
        }
        final key = (u.id, _text(a['idempotency_key'])!);
        final semantic = Map.of(a)
          ..remove('universe')
          ..remove('universe_id')
          ..remove('context_id')
          ..remove('world')
          ..remove('world_id');
        semantic['frame'] = frame?.toWire() ?? _null;
        semantic['resolved_world'] = world == null
            ? _null
            : CanonicalString(world.value);
        final fingerprint = _digest(_object(semantic));
        final retained = _receipts[key];
        if (retained != null) {
          if (retained.fingerprint != fingerprint) {
            throw const IdempotencyKeyReusedError(
              message: 'different proposal content',
            );
          }
          return wrap(retained.proposal.toWire());
        }
        if (_receipts.length >= 256) _limit();
        final operationId = OperationId.parse(_allocate('op'));
        final Map<String, CanonicalValue> p;
        if (action == 'create') {
          p = {
            'base_frame': frame!.toWire(),
            'world_scope': world == null ? _null : CanonicalString(world.value),
            'proposal_id': CanonicalString(_allocate('prp')),
            'version': const CanonicalNumber('1'),
            'digest': CanonicalString(''),
            'submission': a['submission']!,
            'operations': a['operations']!,
            'rationale': a['rationale']!,
            'canonical': const CanonicalBool(false),
            'operation_id': CanonicalString(operationId.value),
            'withdrawn': const CanonicalBool(false),
          };
        } else {
          final old = _bound(
            u.id,
            ProposalRef.fromWire(a['proposal_reference']!),
          );
          p = _fields(old.toWire());
          p['version'] = CanonicalNumber((old.version + BigInt.one).toString());
          if (action == 'revise') {
            p.addAll({
              'base_frame': frame!.toWire(),
              'world_scope': world == null
                  ? _null
                  : CanonicalString(world.value),
              'operations': a['operations']!,
              'submission': a['submission']!,
              'rationale': a['rationale']!,
            });
          } else if (action == 'submit') {
            p['submission'] = CanonicalString('submitted');
          } else {
            p['withdrawn'] = const CanonicalBool(true);
          }
        }
        _references(p['operations']!, u);
        _references(p['operations']!, u, worlds: true);
        final operations = (p['operations']! as CanonicalArray).items
            .map(DomainOperation.fromWire)
            .toList();
        final proposalWorld = _text(p['world_scope']);
        _writeEnvelope(
          operations,
          proposalWorld == null ? null : WorldId.parse(proposalWorld),
          u,
        );
        p['operation_id'] = CanonicalString(operationId.value);
        p['digest'] = CanonicalString(
          _digest(
            _object({
              'frame': p['base_frame']!,
              for (final k in [
                'world_scope',
                'version',
                'operations',
                'rationale',
                'submission',
                'withdrawn',
              ])
                k: p[k]!,
            }),
          ),
        );
        final proposal = Proposal.fromWire(_object(p));
        _proposals[(proposal.proposalId.value, proposal.version)] = (
          u.id,
          proposal,
        );
        _receipts[key] = _Receipt(fingerprint, proposal);
        return wrap(proposal.toWire());
      case 'universe_get_proposal':
        final get = request as GetProposalRequest;
        if (get.viewGroup != null && get.viewGroup != ProposalView.payload) {
          _unsupported(
            'fixture proposal view supports the payload field group only',
          );
        }
        final p = _proposals[(get.proposalId.value, get.version)];
        if (p == null || p.$1 != u.id) {
          throw const NotFoundOrNotAccessibleError(message: 'proposal version');
        }
        return wrap(p.$2.toWire());
      case 'universe_get_operation':
      case 'universe_cancel_operation':
        final Proposal? p;
        if (_text(a['lookup']) == 'key') {
          p = _text(a['operation_kind']) == 'propose'
              ? _receipts[(u.id, _text(a['idempotency_key'])!)]?.proposal
              : null;
        } else {
          p = _receipts.entries
              .where(
                (e) =>
                    e.key.$1 == u.id &&
                    e.value.proposal.operationId.value ==
                        _text(a['operation_id']),
              )
              .firstOrNull
              ?.value
              .proposal;
        }
        if (p == null) {
          throw const NotFoundOrNotAccessibleError(message: 'operation');
        }
        return wrap(
          OperationStatusV3(
            operationId: p.operationId,
            kind: OperationKind.propose,
            state: OperationState.succeeded,
            proposal: p,
            cancellationRequested: request is CancelOperationRequest,
          ).toWire(),
        );
      case 'universe_commit':
        throw const PolicyDeniedError(
          message: 'fixture cannot commit canon; author approval and durable storage are unavailable',
        );
      case 'universe_read_contracts':
        _unsupported('plain contracts require a persistent installation');
      case 'universe_read_facts':
        _unsupported(
          'plain factual reading requires a persistent installation',
        );
      case 'universe_check_changes':
        _unsupported(
          'plain factual checking requires a persistent installation',
        );
      default:
        _unsupported('store-backed semantic evaluation is not implemented');
    }
  }

  Proposal _bound(UniverseId owner, ProposalRef reference) {
    final entry = _proposals[(reference.proposalId.value, reference.version)];
    if (entry == null ||
        entry.$1 != owner ||
        entry.$2.digest != reference.digest) {
      throw const NotFoundOrNotAccessibleError(message: 'exact proposal');
    }
    if (entry.$2.withdrawn ||
        _proposals.keys.any(
          (k) => k.$1 == reference.proposalId.value && k.$2 > reference.version,
        )) {
      throw const InvalidArgumentError(
        field: 'proposal_reference',
        message: 'stale or withdrawn proposal cannot be changed',
      );
    }
    return entry.$2;
  }
}

String _digest(CanonicalValue value) =>
    canonicalDigest(CanonicalValue.parseJson(value.toText()));
String _label(RecordVersion r) => switch (r.payload) {
  WorldRecord(:final selector) => selector,
  EntityRecord(:final labels) => labels['en'] ?? '',
  WorkRecord(:final title) => title,
  _ => r.identity.recordId.value,
};
List<WorldId> _worlds(RecordVersion r, _Universe u) => switch (r.payload) {
  EntityRecord(:final worldAssociations) =>
    worldAssociations.map((a) => a.world).toList(),
  WorkRecord(:final worldAssociations) =>
    worldAssociations.map((a) => a.world).toList(),
  WorldRecord(:final selector) =>
    u.worlds.where((w) => w.name.value == selector).map((w) => w.id).toList(),
  _ => [],
};
void _references(CanonicalValue v, _Universe u, {bool worlds = false}) {
  switch (v) {
    case CanonicalObject():
      final f = _fields(v);
      if (!worlds &&
          _text(f['universe']) is String &&
          _text(f['universe']) != u.id.value) {
        throw const UniverseScopeMismatchError(message: 'foreign reference');
      }
      void check(String id) {
        if (!u.worlds.any((w) => w.id.value == id)) {
          throw const WorldNotFoundOrNotAccessibleError(
            message: 'referenced world is outside this fixture universe',
          );
        }
      }
      if (worlds &&
          f.containsKey('role') &&
          f.containsKey('validity') &&
          f.containsKey('qualifiers')) {
        if (_text(f['world']) case final String id) check(id);
      }
      if (worlds &&
          _text(f['kind']) == 'worlds' &&
          f['world_ids'] is CanonicalArray) {
        for (final id in (f['world_ids'] as CanonicalArray).items) {
          if (id is CanonicalString) check(id.value);
        }
      }
      for (final child in f.values) {
        _references(child, u, worlds: worlds);
      }
    case CanonicalArray(:final items):
      for (final child in items) {
        _references(child, u, worlds: worlds);
      }
    default:
      break;
  }
}

void _writeEnvelope(
  List<DomainOperation> operations,
  WorldId? world,
  _Universe u,
) {
  if (world == null) return;
  void check(List<WorldId> worlds) {
    if (worlds.isEmpty || worlds.any((id) => id != world)) {
      throw const WorldScopeConflictError(
        message: 'all proposed effects must have explicit applicability within the selected world',
      );
    }
  }

  void existing(Map<String, CanonicalValue> a) {
    final target = RecordRef.fromCanonical(a['record']!);
    final r = u.records
        .where(
          (r) =>
              r.identity.recordId == target.record &&
              (target.universe == null || target.universe == u.id),
        )
        .firstOrNull;
    if (r == null) {
      throw const NotFoundOrNotAccessibleError(message: 'proposal target');
    }
    if (r.recordVersionId.value != _text(a['expected_version'])) {
      throw const InvalidArgumentError(
        field: 'expected_version',
        message: 'fixture target version mismatch',
      );
    }
    check(_worlds(r, u));
  }

  for (final op in operations) {
    final a = _fields(op.toWire());
    switch (_text(a['kind'])) {
      case 'create_entity':
        check(
          (op as CreateEntityOperation).record.worldAssociations
              .map((w) => w.world)
              .toList(),
        );
      case 'create_work':
        check(
          (op as CreateWorkOperation).record.worldAssociations
              .map((w) => w.world)
              .toList(),
        );
      case 'add_name':
      case 'add_type_membership':
      case 'rename_world_selector':
      case 'add_world_alias':
      case 'withdraw_event':
      case 'tombstone_record':
        existing(a);
      case 'associate_work_world':
        existing(a);
        check([(op as AssociateWorkWorldOperation).association.world]);
      default:
        _unsupported(
          "fixture cannot prove this operation's world-scoped write footprint",
        );
    }
  }
}

Never _unsupported(String message) =>
    throw UnsupportedSemanticsError(message: message);
Never _limit() => throw const EvaluationLimitReachedError(
  message: 'fixture capacity reached',
);
final _capabilities = [
  Capability(
    id: 'fixture.read-propose.v1',
    status: CapabilityStatus.implemented,
    limitation: 'Disposable state; no persistence or production authentication',
  ),
  Capability(
    id: 'rule.boolean_evidence.v1',
    status: CapabilityStatus.implemented,
    limitation:
        'Pure literal Boolean expressions only; not store-backed validation',
  ),
  Capability(
    id: 'assertion.qualified.v1',
    status: CapabilityStatus.descriptiveOnly,
    limitation: 'Typed representation; state evaluation unavailable',
  ),
  Capability(
    id: 'canon.commit.v1',
    status: CapabilityStatus.unsupported,
    limitation: 'No canon mutation in fixture mode',
  ),
  Capability(
    id: 'rule.finite_constraints.v1',
    status: CapabilityStatus.unsupported,
    limitation: 'Unsupported operators never claim complete evaluation',
  ),
];
