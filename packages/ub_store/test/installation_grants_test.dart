@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/src/journal.dart';
import 'package:ub_store/src/owned_database.dart';

void main() {
  late Directory directory;
  late SqliteInstallationStore store;
  late ProfileId author, agent;
  late UniverseId universe;
  final w1 = WorldId.generate(), w2 = WorldId.generate();
  final r1 = RecordId.generate(), r2 = RecordId.generate();
  final c1 = ContinuityId.generate();
  final now = BigInt.from(100);
  setUp(() {
    directory = Directory.systemTemp.createTempSync('universe-builder-grants-');
    store = SqliteInstallationStore.create(directory.path);
    author = ProfileId.generate();
    agent = ProfileId.generate();
    universe = UniverseId.generate();
    store.enroll(id: author, credentialHash: '0' * 64);
    store.enroll(id: agent, credentialHash: '1' * 64, actor: author);
    final path = '${directory.path}/packages/universe.sqlite';
    final package = OwnedSqliteDatabase.create(path);
    package.database.execute('BEGIN IMMEDIATE');
    SqliteJournal(package.database, universe).initialize(
      'Disposable grant universe',
      ContinuityId.generate(),
      PrincipalId.generate(),
    );
    package.database.execute('COMMIT');
    package.close();
    store.registerExistingPackage(actor: author, name: 'World', path: path);
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });
  GrantSpec grant({
    List<WorldId>? worlds,
    GrantLimits? limits,
    bool edit = true,
  }) => GrantSpec(
    profileId: agent,
    universeId: universe,
    worlds: worlds,
    propose: true,
    edit: edit,
    protected: false,
    limits: limits,
  );
  void put(GrantSpec value) =>
      store.putGrant(actor: author, grant: value, epochSeconds: now);
  Matcher failure(InstallationFailure expected) => throwsA(
    isA<InstallationException>().having((e) => e.failure, 'failure', expected),
  );

  test('ordered typed scopes and unsigned expiry survive restart without JSON authority', () {
    final value = grant(
      worlds: [w2, w1, w2],
      limits: GrantLimits(
        entities: [r2, r1],
        predicates: [r1],
        continuities: [c1],
        expiresAt: BigInt.parse('18446744073709551615'),
        delegatedCommit: true,
        allowShared: true,
      ),
    );
    put(value);
    expect(
      store.readGrant(agent, universe).toWire().toText(),
      value.toWire().toText(),
    );
    store.close();
    store = SqliteInstallationStore.openExisting(directory.path);
    expect(
      store.readGrant(agent, universe).toWire().toText(),
      value.toWire().toText(),
    );
    expect(store.universeScope(agent, universe, now), {w1, w2});
    final db = sqlite3.open(
      '${directory.path}/installation.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      expect(
        db.select('SELECT expires_at FROM grants').single['expires_at'],
        '18446744073709551615',
      );
      expect(
        db
            .select('SELECT world FROM grant_worlds ORDER BY ordinal')
            .map((r) => r['world'])
            .toList(),
        [w2.value, w1.value, w2.value],
      );
    } finally {
      db.close();
    }
  });

  test(
    'replacement removes old child scopes and retains unrestricted nulls',
    () {
      put(
        grant(
          worlds: [w1],
          limits: GrantLimits(
            entities: [r1],
            predicates: [r2],
            continuities: [c1],
          ),
        ),
      );
      final unrestricted = grant();
      put(unrestricted);
      expect(
        store.readGrant(agent, universe).toWire().toText(),
        unrestricted.toWire().toText(),
      );
      expect(store.universeScope(agent, universe, now), isNull);
      expect(store.limits(agent, universe, now).entities, isNull);
    },
  );

  test('invalid bounds, expired grants and incomplete delegation do not mutate authority', () {
    put(grant(worlds: [w1]));
    final before = store.audit(author).length;
    for (final value in [
      grant(worlds: []),
      grant(worlds: List.filled(101, w1)),
      grant(limits: GrantLimits(entities: [])),
      grant(limits: GrantLimits(predicates: List.filled(101, r1))),
      grant(limits: GrantLimits(continuities: [])),
      grant(limits: GrantLimits(expiresAt: now)),
      grant(limits: GrantLimits(delegatedCommit: true)),
      grant(
        edit: false,
        limits: GrantLimits(
          entities: [r1],
          predicates: [r2],
          continuities: [c1],
          expiresAt: now + BigInt.one,
          delegatedCommit: true,
        ),
      ),
    ]) {
      expect(() => put(value), failure(InstallationFailure.invalidGrant));
    }
    expect(store.audit(author).length, before);
    expect(store.readGrant(agent, universe).worlds, [w1]);
  });

  test('withdrawal, identical regrant and revocation advance only the relevant authority sequence', () {
    final value = grant(worlds: [w1]);
    put(value);
    final first = store.validationAuthoritySequence(agent, universe);
    store.withdrawGrant(actor: author, profile: agent, universe: universe);
    final withdrawn = store.validationAuthoritySequence(agent, universe);
    expect(withdrawn, greaterThan(first));
    expect(
      () => store.readGrant(agent, universe),
      failure(InstallationFailure.denied),
    );
    put(value);
    expect(
      store.validationAuthoritySequence(agent, universe),
      greaterThan(withdrawn),
    );
    expect(
      store.readGrant(agent, universe).toWire().toText(),
      value.toWire().toText(),
    );
    final before = store.validationAuthoritySequence(agent, universe);
    store.withdrawGrant(
      actor: author,
      profile: agent,
      universe: UniverseId.generate(),
    );
    expect(store.validationAuthoritySequence(agent, universe), before);
    store.revoke(actor: author, target: agent);
    expect(
      store.validationAuthoritySequence(agent, universe),
      greaterThan(before),
    );
    expect(
      () => store.universeScope(agent, universe, now),
      failure(InstallationFailure.denied),
    );
  });

  test('failed audit append rolls back grant fields and every ordered child collection', () {
    final original = grant(
      worlds: [w1],
      limits: GrantLimits(entities: [r1], predicates: [r2], continuities: [c1]),
    );
    put(original);
    final count = store.audit(author).length;
    store.close();
    final db = sqlite3.open('${directory.path}/installation.sqlite');
    db.execute(
      "CREATE TRIGGER refuse_grant_audit BEFORE INSERT ON audit BEGIN SELECT RAISE(ABORT,'disposable failure'); END",
    );
    db.close();
    store = SqliteInstallationStore.openExisting(directory.path);
    expect(
      () => put(grant(worlds: [w2], edit: false)),
      failure(InstallationFailure.unavailable),
    );
    expect(
      store.readGrant(agent, universe).toWire().toText(),
      original.toWire().toText(),
    );
    expect(store.audit(author).length, count);
  });

  test('non-author grant mutations are refused', () {
    expect(
      () => store.putGrant(actor: agent, grant: grant(), epochSeconds: now),
      failure(InstallationFailure.denied),
    );
    expect(
      () =>
          store.withdrawGrant(actor: agent, profile: agent, universe: universe),
      failure(InstallationFailure.denied),
    );
  });
}
