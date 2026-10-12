@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/proposal_state.dart';
import 'package:ub_service/validation_binding.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/src/journal.dart';
import 'package:ub_store/src/owned_database.dart';
import 'package:ub_store/src/workflow_storage.dart';

import 'proposal_state_test.dart' as proposals;

void main() {
  late Directory directory;
  late SqliteInstallationStore store;
  late InstallationAuthority authority;
  late InstallationPrincipal author, writer;
  late UniverseId universe;
  late ContinuityId continuity;
  var now = BigInt.from(100);
  final world = WorldId.generate();
  setUp(() {
    now = BigInt.from(100);
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-current-authority-',
    );
    store = SqliteInstallationStore.create(directory.path);
    authority = InstallationAuthority(store, epochSeconds: () => now);
    InstallationPrincipal authenticate(ProfileId id) => authority.authenticate(
      profile: id,
      credential: Credential(
        ProfileCredentialStore.read(root: directory.path, profile: id),
      ),
    );
    author = authenticate(authority.initializeAuthor());
    writer = authenticate(authority.enroll(author));
    universe = UniverseId.generate();
    continuity = ContinuityId.generate();
    final path = '${directory.path}/packages/universe.sqlite';
    final package = OwnedSqliteDatabase.create(path);
    package.database.execute('BEGIN IMMEDIATE');
    SqliteJournal(package.database, universe).initialize(
      'Disposable authority universe',
      continuity,
      PrincipalId.generate(),
    );
    package.database.execute('COMMIT');
    package.close();
    authority.registerUniverse(author, name: 'World', path: path);
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });
  GrantSpec grant({bool propose = true, BigInt? expiry}) => GrantSpec(
    profileId: writer.id,
    universeId: universe,
    worlds: [world],
    propose: propose,
    edit: true,
    protected: false,
    limits: GrantLimits(expiresAt: expiry),
  );
  final denied = throwsA(
    isA<InstallationException>().having(
      (e) => e.failure,
      'failure',
      InstallationFailure.denied,
    ),
  );

  test('live authority produces a capture that an identical regrant invalidates before retention', () async {
    authority.grant(
      author,
      GrantSpec(
        profileId: writer.id,
        universeId: universe,
        worlds: null,
        propose: true,
        edit: true,
        protected: false,
      ),
    );
    final package = OwnedSqliteDatabase.openExisting(
      '${directory.path}/packages/universe.sqlite',
    );
    try {
      package.recover();
      final journal = SqliteJournal(package.database, universe);
      final workflow = WorkflowStorage(package.database);
      final proposal = proposals.prepare(
        principal: writer.id,
        frame: Frame(
          universe: universe,
          continuity: continuity,
          revision: journal.head(continuity),
          context: RecordRef(universe: universe, record: RecordId.generate()),
          time: const TimelessFrameTime(),
          perspective: const AuthorPerspective(),
        ),
      );
      workflow.compareAppend({}, [MapEntry(proposal.key, proposal.toWire())]);
      Future<ValidationCapture> capture() =>
          authority.withUniverseAuthority(writer, universe, (current) {
            authorizeStoredProposal(
              stored: proposal,
              reference: proposal.reference,
              principal: current.principal.id,
              author: current.principal.author,
              scope: current.worldScope,
            );
            authority.authorizeWrite(
              writer,
              universe: universe,
              worlds: proposal.footprint.worlds,
              shared: proposal.footprint.shared,
              protected: proposal.footprint.protected,
              commit: false,
            );
            return captureValidationBinding(
              proposal: proposal,
              authorityDigest: current.validationDigest,
              authoritySequence: current.sequence,
              readLatestKey: workflow.latestKey,
              readWorkflow: workflow.get,
              readHead: journal.head,
              resolveSelected: (_) => throw StateError('Unexpected assessment'),
            );
          });
      final captured = await capture();
      expect(captured.head, journal.head(continuity));
      expect(captured.latestProposalKey, proposal.key);
      await authority.coordinate(
        author,
        () => authority.grant(
          author,
          GrantSpec(
            profileId: writer.id,
            universeId: universe,
            worlds: null,
            propose: true,
            edit: true,
            protected: false,
          ),
        ),
      );
      final current = await capture();
      expect(current.authorityDigest, captured.authorityDigest);
      expect(
        () => verifyValidationAuthority(captured, current.authoritySequence),
        throwsA(isA<ApprovalStaleError>()),
      );
      expect(workflow.keys('validation:'), isEmpty);
    } finally {
      package.close();
    }
  });

  test('authenticated current authority binds scope, permissions, limits and author', () async {
    authority.grant(author, grant());
    await authority.withUniverseAuthority(writer, universe, (current) {
      expect(current.principal.id, writer.id);
      expect(current.approvalAuthor, author.id);
      expect(current.worldScope, {world});
      expect(current.permissions, (true, true, false));
      expect(current.sequence, greaterThan(BigInt.zero));
      expect(current.validationDigest, matches(r'^[0-9a-f]{64}$'));
      expect(() => current.worldScope!.clear(), throwsUnsupportedError);
    });
    await authority.withUniverseAuthority(author, universe, (current) {
      expect(current.worldScope, isNull);
      expect(current.permissions, (true, true, true));
      expect(current.sequence, BigInt.zero);
    });
  });

  test(
    'identical regrant changes sequence while permission change changes digest',
    () async {
      authority.grant(author, grant());
      final first = await authority.withUniverseAuthority(
        writer,
        universe,
        (current) => (current.sequence, current.validationDigest),
      );
      await authority.coordinate(
        author,
        () => authority.grant(author, grant()),
      );
      final second = await authority.withUniverseAuthority(
        writer,
        universe,
        (current) => (current.sequence, current.validationDigest),
      );
      expect(second.$1, greaterThan(first.$1));
      expect(second.$2, first.$2);
      await authority.coordinate(
        author,
        () => authority.grant(author, grant(propose: false)),
      );
      final third = await authority.withUniverseAuthority(
        writer,
        universe,
        (current) => current.validationDigest,
      );
      expect(third, isNot(first.$2));
    },
  );

  test('queued revocation is rechecked before a waiting workflow obtains current values', () async {
    authority.grant(author, grant());
    final entered = Completer<void>(), release = Completer<void>();
    final held = authority.withUniverseAuthority(writer, universe, (
      current,
    ) async {
      entered.complete();
      await release.future;
      expect(
        store.validationAuthoritySequence(writer.id, universe),
        current.sequence,
      );
    });
    await entered.future;
    final revoke = authority.coordinate(
      author,
      () => authority.revoke(author, writer.id),
    );
    final next = authority.withUniverseAuthority(
      writer,
      universe,
      (_) => fail('Revoked writer admitted'),
    );
    final rejected = expectLater(next, denied);
    release.complete();
    await held;
    await revoke;
    await rejected;
  });

  test(
    'expiry is rechecked at entry and unknown universes do not run callbacks',
    () async {
      authority.grant(author, grant(expiry: BigInt.from(101)));
      now = BigInt.from(101);
      await expectLater(
        authority.withUniverseAuthority(
          writer,
          universe,
          (_) => fail('Expired grant admitted'),
        ),
        denied,
      );
      await expectLater(
        authority.withUniverseAuthority(
          author,
          UniverseId.generate(),
          (_) => fail('Unknown universe admitted'),
        ),
        denied,
      );
    },
  );
}
