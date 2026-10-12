@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  late Directory directory;
  late SqliteInstallationStore store;
  late InstallationAuthority authority;
  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-authority-',
    );
    store = SqliteInstallationStore.create(directory.path);
    authority = InstallationAuthority(store);
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });
  Credential credential(ProfileId id) => Credential(
    ProfileCredentialStore.read(root: directory.path, profile: id),
  );
  Matcher failure(InstallationFailure expected) => throwsA(
    isA<InstallationException>().having((e) => e.failure, 'failure', expected),
  );

  test('retained BOM credential authenticates only its exact stored bytes', () {
    final id = ProfileId.generate();
    const secret = '\uFEFF\uFEFFDisposable café 😀\r\n\u0000';
    ProfileCredentialStore.write(
      root: directory.path,
      profile: id,
      credential: secret,
    );
    store.enroll(
      id: id,
      credentialHash: sha256.convert(utf8.encode(secret)).toString(),
    );
    final principal = authority.authenticate(
      profile: id,
      credential: credential(id),
    );
    expect(principal.id, id);
    expect(principal.author, isTrue);
    for (final changed in [
      secret.substring(1),
      secret.substring(2),
      secret.trim(),
    ]) {
      expect(
        () => authority.authenticate(
          profile: id,
          credential: Credential(changed),
        ),
        failure(InstallationFailure.denied),
      );
    }
  });

  test(
    'engine handshake admits current credentials with the exact protocol',
    () {
      final id = authority.initializeAuthor();
      final hello = EngineHello(
        protocolVersion: protocolVersion,
        profileId: id,
        credential: credential(id),
        clientName: 'External writer',
      );
      final principal = authority.authenticateHello(hello);
      expect(principal.id, id);
      expect(principal.author, isTrue);
      expect(principal.instanceId, store.instanceId);
      expect(store.audit(id).length, 1);
    },
  );

  test(
    'handshake name bound counts UTF-8 bytes and diagnostics omit inputs',
    () {
      final id = authority.initializeAuthor();
      InstallationPrincipal admit(
        String name, {
        String version = protocolVersion,
      }) => authority.authenticateHello(
        EngineHello(
          protocolVersion: version,
          profileId: id,
          credential: credential(id),
          clientName: name,
        ),
      );
      expect(admit('é' * 64).id, id);
      expect(admit('').id, id);
      for (final name in ['é' * 65, 'x' * 129, '\ud800']) {
        expect(() => admit(name), throwsFormatException);
      }
      expect(
        () => admit('writer', version: 'secret-in-version'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'redacted diagnostic',
            isNot(contains('secret-in-version')),
          ),
        ),
      );
    },
  );

  test('repeating handshake authentication refuses withdrawn credentials', () {
    final ownerId = authority.initializeAuthor();
    final owner = authority.authenticate(
      profile: ownerId,
      credential: credential(ownerId),
    );
    final agent = authority.enroll(owner);
    final hello = EngineHello(
      protocolVersion: protocolVersion,
      profileId: agent,
      credential: credential(agent),
      clientName: 'writer',
    );
    expect(authority.authenticateHello(hello).author, isFalse);
    authority.revoke(owner, agent);
    expect(
      () => authority.authenticateHello(hello),
      failure(InstallationFailure.denied),
    );
  });

  test('bootstrap persists exact credentials, hash and audit before authenticating', () {
    final id = authority.initializeAuthor();
    final secret = credential(id);
    expect(secret.expose(), matches(r'^[0-9a-f]{64}$'));
    expect(
      store.profile(id)!.credentialHash,
      sha256.convert(utf8.encode(secret.expose())).toString(),
    );
    final principal = authority.authenticate(profile: id, credential: secret);
    expect(principal.id, id);
    expect(principal.author, isTrue);
    expect(principal.instanceId, store.instanceId);
    expect(store.currentAuthor(), id);
    final audit = store.audit(id).single;
    expect(audit.sequence, BigInt.one);
    expect(audit.actor, 'local-bootstrap');
    expect(audit.action, 'enroll');
    expect(audit.target, id.value);
    final files = Directory('${directory.path}/profiles').listSync().length;
    expect(
      authority.initializeAuthor,
      failure(InstallationFailure.alreadyEnrolled),
    );
    expect(Directory('${directory.path}/profiles').listSync().length, files);
  });

  test(
    'enrollment, revocation and stable installation identity survive restart',
    () {
      final author = authority.initializeAuthor();
      final principal = authority.authenticate(
        profile: author,
        credential: credential(author),
      );
      final agent = authority.enroll(principal);
      final secret = credential(agent);
      expect(
        authority.authenticate(profile: agent, credential: secret).author,
        isFalse,
      );
      final instance = store.instanceId;
      authority.revoke(principal, agent);
      expect(
        () => authority.authenticate(profile: agent, credential: secret),
        failure(InstallationFailure.denied),
      );
      store.close();
      store = SqliteInstallationStore.openExisting(directory.path);
      authority = InstallationAuthority(store);
      expect(store.instanceId, instance);
      expect(
        () => authority.authenticate(profile: agent, credential: secret),
        failure(InstallationFailure.denied),
      );
      final restored = authority.authenticate(
        profile: author,
        credential: credential(author),
      );
      expect(
        authority.profiles(restored).map((p) => p.id),
        containsAll([author, agent]),
      );
      expect(store.audit(author).map((r) => r.action).toList(), [
        'enroll',
        'enroll',
        'revoke',
      ]);
      expect(store.audit(author).map((r) => r.sequence).toList(), [
        BigInt.one,
        BigInt.two,
        BigInt.from(3),
      ]);
    },
  );

  test('agents cannot administer and author revocation is refused without an audit append', () {
    final author = authority.initializeAuthor();
    final owner = authority.authenticate(
      profile: author,
      credential: credential(author),
    );
    final agent = authority.enroll(owner);
    final restricted = authority.authenticate(
      profile: agent,
      credential: credential(agent),
    );
    final before = store.audit(author).length;
    expect(
      () => authority.enroll(restricted),
      failure(InstallationFailure.denied),
    );
    expect(
      () => authority.revoke(restricted, author),
      failure(InstallationFailure.denied),
    );
    expect(
      () => authority.profiles(restricted),
      failure(InstallationFailure.denied),
    );
    expect(
      () => authority.revoke(owner, author),
      failure(InstallationFailure.denied),
    );
    expect(
      () => authority.revoke(owner, ProfileId.generate()),
      failure(InstallationFailure.denied),
    );
    expect(store.audit(author).length, before);
  });

  test('unknown and altered credentials give the same redacted denial', () {
    final id = authority.initializeAuthor();
    final secret = credential(id);
    for (final supplied in [
      const Credential('wrong-disposable-secret'),
      Credential(' ${secret.expose()}'),
      Credential('${secret.expose()}\n'),
      Credential(String.fromCharCode(0xd800)),
    ]) {
      expect(
        () => authority.authenticate(profile: id, credential: supplied),
        failure(InstallationFailure.denied),
      );
    }
    expect(
      () => authority.authenticate(
        profile: ProfileId.generate(),
        credential: secret,
      ),
      failure(InstallationFailure.denied),
    );
  });

  test('existing credential hash semantics retain exact UTF-8 text', () {
    final id = ProfileId.generate();
    const secret = 'Synthetic exact credential: punctuation, spaces, café\n';
    ProfileCredentialStore.write(
      root: directory.path,
      profile: id,
      credential: secret,
    );
    store.enroll(
      id: id,
      credentialHash: sha256.convert(utf8.encode(secret)).toString(),
    );
    expect(
      authority
          .authenticate(profile: id, credential: const Credential(secret))
          .author,
      isTrue,
    );
    expect(
      () => authority.authenticate(
        profile: id,
        credential: Credential(secret.trim()),
      ),
      failure(InstallationFailure.denied),
    );
  });

  test('another installation cannot reuse an authenticated author even with the same restored profile', () {
    final id = authority.initializeAuthor();
    final principal = authority.authenticate(
      profile: id,
      credential: credential(id),
    );
    final otherDirectory = Directory.systemTemp.createTempSync(
      'universe-builder-other-authority-',
    );
    final otherStore = SqliteInstallationStore.create(otherDirectory.path);
    try {
      otherStore.enroll(
        id: id,
        credentialHash: store.profile(id)!.credentialHash,
      );
      expect(
        () => InstallationAuthority(otherStore).enroll(principal),
        failure(InstallationFailure.denied),
      );
      expect(otherStore.profiles(id).length, 1);
    } finally {
      otherStore.close();
      otherDirectory.deleteSync(recursive: true);
    }
  });
}
