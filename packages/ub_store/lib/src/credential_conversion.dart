import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';
import 'profile_credentials.dart';

enum CredentialConversionFailure {
  invalidInput,
  destinationExists,
  sourceChanged,
  verificationFailed,
  unavailable,
}

/// Never retain a parser or driver exception containing credential data.
final class CredentialConversionException implements Exception {
  const CredentialConversionException(this.failure);
  final CredentialConversionFailure failure;
  @override
  String toString() => 'CredentialConversionException(${failure.name})';
}

/// Offline conversion only. It preserves the exact secret and identity without
/// enrolling a profile, opening installation authority, or replacing an input.
CanonicalObject convertCredential(String source, String destination) {
  Directory? temporary;
  try {
    if (FileSystemEntity.typeSync(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const CredentialConversionException(
        CredentialConversionFailure.destinationExists,
      );
    }
    final original = readOriginalCredential(source);
    final sourceHash = sha256.convert(original).toString();
    late ProfileId profile;
    late String credential;
    try {
      final fields = WireFields(
        CanonicalValue.parseWireJson(decodeExactUtf8(original)),
        {'format_version', 'profile_id', 'credential'},
      );
      if (fields.require('format_version') is! CanonicalNumber ||
          (fields.require('format_version') as CanonicalNumber).digits != '1') {
        throw const FormatException('Unsupported credential format');
      }
      profile = ProfileId.parse(fields.string('profile_id'));
      credential = fields.string('credential');
      if (credential.isEmpty ||
          decodeExactUtf8(utf8.encode(credential)) != credential) {
        throw const FormatException('Invalid credential text');
      }
    } on Object {
      throw const CredentialConversionException(
        CredentialConversionFailure.invalidInput,
      );
    }
    final parent = privateDirectory(File(destination).absolute.parent.path);
    temporary = privateTemporaryDirectory(parent, '.credential-conversion-');
    privateDirectory(temporary.path);
    ProfileCredentialStore.write(
      root: temporary.path,
      profile: profile,
      credential: credential,
    );
    if (ProfileCredentialStore.read(root: temporary.path, profile: profile) !=
        credential) {
      throw const CredentialConversionException(
        CredentialConversionFailure.verificationFailed,
      );
    }
    if (sha256.convert(readOriginalCredential(source)).toString() !=
        sourceHash) {
      throw const CredentialConversionException(
        CredentialConversionFailure.sourceChanged,
      );
    }
    publishConversionFile(
      '${temporary.path}/profiles/${profile.value}.sqlite',
      destination,
    );
    return CanonicalObject([
      MapEntry('source_sha256', CanonicalString(sourceHash)),
      const MapEntry('original_preserved', CanonicalBool(true)),
      const MapEntry('credential_verified', CanonicalBool(true)),
    ]);
  } on CredentialConversionException {
    rethrow;
  } on Object {
    throw const CredentialConversionException(
      CredentialConversionFailure.unavailable,
    );
  } finally {
    // Cleanup failures must also avoid exposing credential-bearing exceptions.
    try {
      temporary?.deleteSync(recursive: true);
    } on Object {
      throw const CredentialConversionException(
        CredentialConversionFailure.unavailable,
      );
    }
  }
}
