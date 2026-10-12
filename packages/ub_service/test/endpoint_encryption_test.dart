import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_service/ub_service.dart';

void main() {
  const endpoint = Credential(
    'postgresql://disposable_user:p%40ss@localhost/世界?password=秘密',
  );
  const installation = 'disposable-installation';
  const reference = 'disposable-key-reference';
  late InstallationEncryptionKey key;
  late PostgresEndpointEncryption cipher;
  late EncryptedPostgresEndpoint encrypted;
  final unavailable = throwsA(
    isA<ConfigurationException>().having(
      (e) => e.failure,
      'failure',
      ConfigurationFailure.savedEndpointUnavailable,
    ),
  );

  setUp(() async {
    key = await InstallationEncryptionKey.generate();
    cipher = PostgresEndpointEncryption();
    encrypted = await cipher.encrypt(
      endpoint: endpoint,
      installationId: installation,
      keyReference: reference,
      key: key,
    );
  });

  Future<Credential> unlock(EncryptedPostgresEndpoint value) =>
      cipher.decrypt(encrypted: value, installationId: installation, key: key);

  test(
    'AES-256 key and exact endpoint survive explicit key-store transfer',
    () async {
      final bytes = await key.exportForCredentialStore();
      expect(bytes.length, 32);
      final restoredKey = InstallationEncryptionKey.fromBytes(bytes);
      bytes.fillRange(0, bytes.length, 0);
      final restored = await cipher.decrypt(
        encrypted: encrypted,
        installationId: installation,
        key: restoredKey,
      );
      expect(restored.expose(), endpoint.expose());
      expect(encrypted.nonce.length, 12);
      expect(encrypted.tag.length, 16);
      expect(encrypted.ciphertext, isNot(utf8.encode(endpoint.expose())));
    },
  );

  test('each save generates a fresh nonce and ciphertext', () async {
    final second = await cipher.encrypt(
      endpoint: endpoint,
      installationId: installation,
      keyReference: reference,
      key: key,
    );
    expect(second.nonce, isNot(encrypted.nonce));
    expect(second.ciphertext, isNot(encrypted.ciphertext));
    expect((await unlock(second)).expose(), endpoint.expose());
  });

  test(
    'wrong key and another installation cannot unlock the endpoint',
    () async {
      await expectLater(
        cipher.decrypt(
          encrypted: encrypted,
          installationId: installation,
          key: await InstallationEncryptionKey.generate(),
        ),
        unavailable,
      );
      await expectLater(
        cipher.decrypt(
          encrypted: encrypted,
          installationId: '$installation-other',
          key: key,
        ),
        unavailable,
      );
    },
  );

  test('ciphertext, nonce, tag and key reference are authenticated', () async {
    List<int> changed(List<int> bytes) => List<int>.of(bytes)..[0] ^= 1;
    for (final corrupted in [
      EncryptedPostgresEndpoint(
        keyReference: reference,
        ciphertext: changed(encrypted.ciphertext),
        nonce: encrypted.nonce,
        tag: encrypted.tag,
      ),
      EncryptedPostgresEndpoint(
        keyReference: reference,
        ciphertext: encrypted.ciphertext,
        nonce: changed(encrypted.nonce),
        tag: encrypted.tag,
      ),
      EncryptedPostgresEndpoint(
        keyReference: reference,
        ciphertext: encrypted.ciphertext,
        nonce: encrypted.nonce,
        tag: changed(encrypted.tag),
      ),
      EncryptedPostgresEndpoint(
        keyReference: '$reference-other',
        ciphertext: encrypted.ciphertext,
        nonce: encrypted.nonce,
        tag: encrypted.tag,
      ),
    ]) {
      await expectLater(unlock(corrupted), unavailable);
    }
  });

  test(
    'another encrypted field purpose cannot substitute for an endpoint',
    () async {
      final aad = <int>[];
      for (final field in [
        'universe-builder/settings/aes-256-gcm/v1',
        'some_other_field',
        installation,
        reference,
      ]) {
        final bytes = utf8.encode(field);
        aad.addAll(ascii.encode('${bytes.length}:'));
        aad.addAll(bytes);
      }
      final box = await AesGcm.with256bits().encrypt(
        utf8.encode(endpoint.expose()),
        secretKey: SecretKey(await key.exportForCredentialStore()),
        aad: aad,
      );
      await expectLater(
        unlock(
          EncryptedPostgresEndpoint(
            keyReference: reference,
            ciphertext: box.cipherText,
            nonce: box.nonce,
            tag: box.mac.bytes,
          ),
        ),
        unavailable,
      );
    },
  );

  test('saved columns are independent immutable byte copies', () async {
    final ciphertext = List<int>.of(encrypted.ciphertext);
    final nonce = List<int>.of(encrypted.nonce);
    final tag = List<int>.of(encrypted.tag);
    final saved = EncryptedPostgresEndpoint(
      keyReference: reference,
      ciphertext: ciphertext,
      nonce: nonce,
      tag: tag,
    );
    ciphertext[0] ^= 1;
    nonce[0] ^= 1;
    tag[0] ^= 1;
    expect((await unlock(saved)).expose(), endpoint.expose());
    for (final column in [saved.ciphertext, saved.nonce, saved.tag]) {
      expect(() => column[0] = 0, throwsUnsupportedError);
    }
  });

  test('invalid key/column lengths and byte ranges fail without values', () {
    for (final bytes in [
      <int>[],
      List<int>.filled(31, 1),
      List<int>.filled(33, 1),
      List<int>.filled(32, 256),
      List<int>.filled(32, -1),
    ]) {
      expect(
        () => InstallationEncryptionKey.fromBytes(bytes),
        throwsFormatException,
      );
    }
    expect(
      () => EncryptedPostgresEndpoint(
        keyReference: reference,
        ciphertext: [256],
        nonce: encrypted.nonce,
        tag: encrypted.tag,
      ),
      throwsFormatException,
    );
    expect(
      () => EncryptedPostgresEndpoint(
        keyReference: reference,
        ciphertext: encrypted.ciphertext,
        nonce: [],
        tag: encrypted.tag,
      ),
      throwsFormatException,
    );
    expect(
      () => EncryptedPostgresEndpoint(
        keyReference: reference,
        ciphertext: encrypted.ciphertext,
        nonce: encrypted.nonce,
        tag: [],
      ),
      throwsFormatException,
    );
    expect(
      () => EncryptedPostgresEndpoint(
        keyReference: '',
        ciphertext: encrypted.ciphertext,
        nonce: encrypted.nonce,
        tag: encrypted.tag,
      ),
      throwsFormatException,
    );
  });

  test(
    'diagnostics redact credentials, key material and encrypted columns',
    () async {
      expect('$key', 'InstallationEncryptionKey([redacted])');
      expect('$encrypted', 'EncryptedPostgresEndpoint([redacted])');
      try {
        await cipher.decrypt(
          encrypted: encrypted,
          installationId: 'wrong',
          key: key,
        );
        fail('Expected unlock failure');
      } on ConfigurationException catch (error) {
        expect('$error', isNot(contains('disposable_user')));
        expect('$error', isNot(contains('秘密')));
        expect('$error', isNot(contains(reference)));
      }
    },
  );

  test(
    'invalid Unicode or missing context cannot save a lossy endpoint',
    () async {
      final cannotSave = throwsA(
        isA<ConfigurationException>().having(
          (e) => e.failure,
          'failure',
          ConfigurationFailure.savedEndpointEncryptionFailed,
        ),
      );
      await expectLater(
        cipher.encrypt(
          endpoint: Credential(String.fromCharCode(0xd800)),
          installationId: installation,
          keyReference: reference,
          key: key,
        ),
        cannotSave,
      );
      await expectLater(
        cipher.encrypt(
          endpoint: endpoint,
          installationId: '',
          keyReference: reference,
          key: key,
        ),
        cannotSave,
      );
      await expectLater(
        cipher.encrypt(
          endpoint: endpoint,
          installationId: installation,
          keyReference: '',
          key: key,
        ),
        cannotSave,
      );
    },
  );

  test(
    'resolver uses an unlocked saved endpoint without rewriting its URI',
    () async {
      final configured = await BackendConfiguration.resolve(
        environment: {},
        savedUsePostgres: true,
        readSavedEndpoint: () => unlock(encrypted),
      ) as PostgresConfiguration;
      expect(configured.endpoint.expose(), endpoint.expose());
      await expectLater(
        BackendConfiguration.resolve(
          environment: {},
          savedUsePostgres: true,
          readSavedEndpoint: () => cipher.decrypt(
            encrypted: encrypted,
            installationId: 'replacement',
            key: key,
          ),
        ),
        unavailable,
      );
    },
  );
}
