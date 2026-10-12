@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/src/journal.dart';
import 'package:ub_store/src/owned_database.dart';

void main() {
  late Directory directory;
  late SqliteInstallationStore store;
  late InstallationAuthority authority;
  late InstallationPrincipal owner, agent;
  late UniverseId universe;
  var now = BigInt.from(100);
  final world = WorldId.generate();
  setUp(() {
    now = BigInt.from(100);
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-grant-authority-',
    );
    store = SqliteInstallationStore.create(directory.path);
    authority = InstallationAuthority(store, epochSeconds: () => now);
    InstallationPrincipal login(ProfileId id) => authority.authenticate(
      profile: id,
      credential: Credential(
        ProfileCredentialStore.read(root: directory.path, profile: id),
      ),
    );
    owner = login(authority.initializeAuthor());
    agent = login(authority.enroll(owner));
    final path = '${directory.path}/packages/universe.sqlite';
    final package = OwnedSqliteDatabase.create(path);
    universe = UniverseId.generate();
    package.database.execute('BEGIN IMMEDIATE');
    SqliteJournal(package.database, universe).initialize(
      'Disposable universe',
      ContinuityId.generate(),
      PrincipalId.generate(),
    );
    package.database.execute('COMMIT');
    package.close();
    expect(
      authority.registerUniverse(owner, name: 'World', path: path),
      universe,
    );
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });
  Matcher denied() => throwsA(
    isA<InstallationException>().having(
      (e) => e.failure,
      'failure',
      InstallationFailure.denied,
    ),
  );
  GrantSpec grant({
    List<WorldId>? worlds,
    bool edit = false,
    bool protected = false,
    BigInt? expiry,
  }) => GrantSpec(
    profileId: agent.id,
    universeId: universe,
    worlds: worlds,
    propose: true,
    edit: edit,
    protected: protected,
    limits: GrantLimits(expiresAt: expiry),
  );
  void write({
    Set<WorldId>? worlds,
    bool shared = false,
    bool protected = false,
    bool commit = false,
  }) => authority.authorizeWrite(
    agent,
    universe: universe,
    worlds: worlds ?? {world},
    shared: shared,
    protected: protected,
    commit: commit,
  );

  test(
    'agent catalog and alias access require a current unexpired universe grant',
    () {
      expect(authority.catalog(agent), isEmpty);
      expect(() => authority.resolveUniverseAlias(agent, 'World'), denied());
      authority.grant(owner, grant(worlds: [world], expiry: now + BigInt.one));
      expect(authority.catalog(agent).single.universeId, universe);
      expect(
        authority.resolveUniverseAlias(agent, 'world').universeId,
        universe,
      );
      expect(authority.universeScope(agent, universe), {world});
      now += BigInt.one;
      expect(authority.catalog(agent), isEmpty);
      expect(() => authority.resolveUniverseAlias(agent, 'World'), denied());
      expect(() => write(), denied());
    },
  );

  test('world omission, shared changes and propose/edit/protected permissions follow the base gate', () {
    authority.grant(owner, grant(worlds: [world]));
    write();
    expect(() => write(worlds: {}), denied());
    expect(() => write(worlds: {WorldId.generate()}), denied());
    expect(() => write(shared: true), denied());
    expect(() => write(commit: true), denied());
    expect(() => write(protected: true), denied());
    authority.grant(owner, grant(edit: true, protected: true));
    write(shared: true, protected: true, commit: true);
    // This checks permissions only; it does not publish or admit delegation.
    expect(authority.limits(agent, universe).delegatedCommit, isFalse);
  });

  test(
    'withdrawal and revocation invalidate cached principal access immediately',
    () {
      authority.grant(owner, grant(worlds: [world]));
      final first = authority.validationAuthoritySequence(agent, universe);
      authority.withdrawGrant(owner, profile: agent.id, universe: universe);
      expect(authority.catalog(agent), isEmpty);
      expect(() => write(), denied());
      authority.grant(owner, grant(worlds: [world]));
      expect(
        authority.validationAuthoritySequence(agent, universe),
        greaterThan(first),
      );
      authority.revoke(owner, agent.id);
      expect(() => authority.catalog(agent), denied());
      expect(() => write(), denied());
      expect(() => authority.grant(agent, grant()), denied());
    },
  );
}
