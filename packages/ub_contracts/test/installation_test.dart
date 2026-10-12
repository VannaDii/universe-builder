import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalValue wire(String raw) => CanonicalValue.parseWireJson(raw);
final profile = ProfileId.parse('prf_000000000000000000000001');
final universe = UniverseId.parse('unv_000000000000000000000001');
final record = RecordId.parse('rec_000000000000000000000001');
final continuity = ContinuityId.parse('cont_000000000000000000000001');
final max = BigInt.parse('18446744073709551615');
GrantSpec grant({Iterable<WorldId>? worlds, GrantLimits? limits}) => GrantSpec(
  profileId: profile,
  universeId: universe,
  worlds: worlds,
  propose: true,
  edit: false,
  protected: false,
  limits: limits,
);
DraftContent draft({
  Iterable<DomainOperation> operations = const [],
  ProposalRef? proposal,
}) => DraftContent(
  baseRevision: RevisionId.parse('rev_000000000000000000000001'),
  representedContext: record,
  operations: operations,
  rationale: 'Authored revision',
  proposal: proposal,
);
void main() {
  test('credential diagnostics redact while explicit private serialization preserves exact secret', () {
    const credential = Credential('disposable test secret é');
    expect('$credential', '[redacted]');
    expect(credential.expose(), 'disposable test secret é');
    final hello = EngineHello(
      protocolVersion: '3',
      profileId: profile,
      credential: credential,
      clientName: 'Desktop',
    );
    final back = EngineHello.fromWire(hello.toWire());
    expect(back.credential.expose(), credential.expose());
    expect('${back.credential}', isNot(contains('disposable')));
    expect(back.profileId, profile);
    expect(
      back.toWire().toText(),
      contains('"credential":"disposable test secret é"'),
    );
    expect(
      () => Credential.fromWire(const CanonicalNull()),
      throwsFormatException,
    );
  });
  test('welcome carries exact installation principal limits and author flag without inferring authority', () {
    final welcome = EngineWelcome(
      protocolVersion: '3',
      serviceInstance: 'installation-one',
      principal: profile,
      author: false,
      maxFrameBytes: max,
      maxInFlight: max,
    );
    final back = EngineWelcome.fromWire(welcome.toWire());
    expect(back.principal, profile);
    expect(back.serviceInstance, 'installation-one');
    expect(back.maxFrameBytes, max);
    expect(back.maxInFlight, max);
    expect(back.author, isFalse);
  });
  test('omitted grant limits default to no delegation while null and empty scope lists remain distinct', () {
    final none = GrantSpec.fromWire(grant().toWire());
    expect(none.worlds, isNull);
    expect(none.limits.entities, isNull);
    expect(none.limits.delegatedCommit, isFalse);
    expect(none.limits.allowShared, isFalse);
    final empty = GrantSpec.fromWire(
      grant(
        worlds: [],
        limits: GrantLimits(entities: [], predicates: [], continuities: []),
      ).toWire(),
    );
    expect(empty.worlds, isEmpty);
    expect(empty.limits.entities, isEmpty);
    expect(empty.limits.predicates, isEmpty);
    expect(empty.limits.continuities, isEmpty);
    expect(empty.edit, isFalse);
    expect(empty.protected, isFalse);
    final absent = CanonicalObject(
      grant().toWire().fields.where((e) => e.key != 'limits'),
    );
    expect(GrantSpec.fromWire(absent).limits.delegatedCommit, isFalse);
    expect(
      () => GrantSpec.fromWire(
        CanonicalObject([
          ...absent.fields,
          const MapEntry('limits', CanonicalNull()),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => GrantLimits.fromWire(wire('{"delegated_commit":null}')),
      throwsFormatException,
    );
  });
  test('grant scope and expiry preserve immutable caller selections without sorting or widening', () {
    final entities = [record, record];
    final continuities = [continuity];
    final worlds = [WorldId.parse('wld_000000000000000000000001')];
    final selected = grant(
      worlds: worlds,
      limits: GrantLimits(
        entities: entities,
        predicates: [],
        continuities: continuities,
        expiresAt: max,
        delegatedCommit: true,
        allowShared: true,
      ),
    );
    entities.clear();
    continuities.clear();
    worlds.clear();
    final back = GrantSpec.fromWire(selected.toWire());
    expect(back.limits.entities, [record, record]);
    expect(back.worlds, hasLength(1));
    expect(back.limits.continuities, [continuity]);
    expect(back.limits.expiresAt, max);
    expect(back.limits.delegatedCommit, isTrue);
    expect(() => back.limits.entities!.clear(), throwsUnsupportedError);
    expect(() => back.worlds!.clear(), throwsUnsupportedError);
    expect(() => back.limits.continuities!.clear(), throwsUnsupportedError);
  });
  test('draft captures pinned authored operations and exact proposal version independently of publication', () {
    final operations = <DomainOperation>[
      CreateWorldOperation(
        clientRef: 'earth',
        record: WorldRecord(selector: 'Earth'),
      ),
    ];
    final ref = ProposalRef(
      proposalId: ProposalId.parse('prp_000000000000000000000001'),
      version: max,
      digest: 'retained digest',
    );
    final saved = SavedDraft(
      version: max,
      content: draft(operations: operations, proposal: ref),
    );
    operations.clear();
    final back = SavedDraft.fromWire(saved.toWire());
    expect(back.version, max);
    expect(back.content.proposal, ref);
    expect(back.content.representedContext, record);
    expect(back.content.operations.single, isA<CreateWorldOperation>());
    expect(back.content.toWire().toText(), isNot(contains('approval')));
    expect(() => back.content.operations.clear(), throwsUnsupportedError);
    expect(draft().toWire().toText(), isNot(contains('proposal')));
    expect(DraftContent.fromWire(draft().toWire()).proposal, isNull);
    expect(
      () => DraftContent.fromWire(
        wire(
          '{"base_revision":"rev_000000000000000000000001","represented_context":"rec_000000000000000000000001","rationale":"authored"}',
        ),
      ),
      throwsFormatException,
    );
  });
  test('expiry draft versions and handshake limits reject rounding negative and overflow', () {
    for (final number in ['-1', '1.0', '1e2', '18446744073709551616', '"1"']) {
      expect(
        () => GrantLimits.fromWire(wire('{"expires_at":$number}')),
        throwsFormatException,
      );
      expect(
        () => SavedDraft.fromWire(
          CanonicalObject([
            MapEntry('version', wire(number)),
            MapEntry('content', draft().toWire()),
          ]),
        ),
        throwsFormatException,
      );
      expect(
        () => EngineWelcome.fromWire(
          CanonicalObject([
            ...EngineWelcome(
              protocolVersion: '3',
              serviceInstance: 'test',
              principal: profile,
              author: false,
              maxFrameBytes: max,
              maxInFlight: max,
            ).toWire().fields.where((e) => e.key != 'max_in_flight'),
            MapEntry('max_in_flight', wire(number)),
          ]),
        ),
        throwsFormatException,
      );
    }
    expect(() => GrantLimits(expiresAt: -BigInt.one), throwsFormatException);
    expect(
      () => SavedDraft(version: max + BigInt.one, content: draft()),
      throwsFormatException,
    );
  });
  test('private contracts reject unknown authority fields and import modes stay explicit', () {
    expect(
      () => GrantSpec.fromWire(
        CanonicalObject([
          ...grant().toWire().fields,
          const MapEntry('author', CanonicalBool(true)),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => EngineHello.fromWire(
        wire(
          '{"protocol_version":"3","profile_id":"prf_000000000000000000000001","credential":"disposable test secret","client_name":"Desktop","author":true}',
        ),
      ),
      throwsFormatException,
    );
    expect(ImportMode.fromName('restore'), ImportMode.restore);
    expect(ImportMode.fromName('clone'), ImportMode.clone);
    expect(() => ImportMode.fromName('merge'), throwsFormatException);
  });
}
