import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_store/ub_store.dart';

import 'configuration.dart';

/// Installation key material is carried only to/from the OS credential store.
/// It is never part of the saved settings row or a universe archive.
final class InstallationEncryptionKey {
  InstallationEncryptionKey._(this._key);
  final SecretKey _key;

  static Future<InstallationEncryptionKey> generate() async =>
      InstallationEncryptionKey._(await AesGcm.with256bits().newSecretKey());

  factory InstallationEncryptionKey.fromBytes(List<int> bytes) {
    if (bytes.length != 32 || bytes.any((b) => b < 0 || b > 255)) {
      throw const FormatException('Invalid installation encryption key.');
    }
    return InstallationEncryptionKey._(SecretKey(List<int>.of(bytes)));
  }

  /// Explicit access for the native credential-store adapter only.
  Future<List<int>> exportForCredentialStore() async =>
      List<int>.of(await _key.extractBytes());

  @override
  String toString() => 'InstallationEncryptionKey([redacted])';
}

/// Encrypts only the endpoint scalar, not a configuration document.
/// Persistence and credential-store access belong to the setup service.
final class PostgresEndpointEncryption {
  final AesGcm _cipher = AesGcm.with256bits();

  Future<EncryptedPostgresEndpoint> encrypt({
    required Credential endpoint,
    required String installationId,
    required String keyReference,
    required InstallationEncryptionKey key,
  }) async {
    try {
      final plaintext = _exactUtf8(endpoint.expose());
      final box = await _cipher.encrypt(
        plaintext,
        secretKey: key._key,
        nonce: _cipher.newNonce(),
        aad: _associatedData(installationId, keyReference),
      );
      return EncryptedPostgresEndpoint(
        keyReference: keyReference,
        ciphertext: box.cipherText,
        nonce: box.nonce,
        tag: box.mac.bytes,
      );
    } on Object {
      throw const ConfigurationException(
        ConfigurationFailure.savedEndpointEncryptionFailed,
      );
    }
  }

  Future<Credential> decrypt({
    required EncryptedPostgresEndpoint encrypted,
    required String installationId,
    required InstallationEncryptionKey key,
  }) async {
    try {
      final plaintext = await _cipher.decrypt(
        SecretBox(
          encrypted.ciphertext,
          nonce: encrypted.nonce,
          mac: Mac(encrypted.tag),
        ),
        secretKey: key._key,
        aad: _associatedData(installationId, encrypted.keyReference),
      );
      return Credential(utf8.decode(plaintext));
    } on Object {
      // Do not expose library exceptions, endpoint bytes or key-store details.
      throw const ConfigurationException(
        ConfigurationFailure.savedEndpointUnavailable,
      );
    }
  }

  List<int> _associatedData(String installationId, String keyReference) {
    if (installationId.isEmpty || keyReference.isEmpty) {
      throw const FormatException('Missing encryption context.');
    }
    // Length framing makes identities containing separators unambiguous.
    // The version and fixed field purpose prevent reuse for another field.
    final result = <int>[];
    for (final field in [
      'universe-builder/settings/aes-256-gcm/v1',
      'UB_POSTGRES_ENDPOINT',
      installationId,
      keyReference,
    ]) {
      final bytes = _exactUtf8(field);
      result.addAll(ascii.encode('${bytes.length}:'));
      result.addAll(bytes);
    }
    return result;
  }

  List<int> _exactUtf8(String value) {
    final bytes = utf8.encode(value);
    if (utf8.decode(bytes) != value) {
      throw const FormatException('Invalid Unicode scalar.');
    }
    return bytes;
  }
}
