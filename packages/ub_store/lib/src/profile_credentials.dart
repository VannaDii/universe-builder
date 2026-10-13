import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'credential_schema.g.dart';
import 'ownership.dart';

enum ProfileCredentialFailure { unavailable, identityMismatch, invalidText }

/// Protected device reconnect hint. Authentication still uses the enrolled
/// profile credential and the service's current authority.
final class DeviceProfileStore {
  static ProfileId? read(String root) {
    final path = '$root/device-profile';
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    protectedFile(path);
    return ProfileId.parse(File(path).readAsStringSync().trim());
  }

  static void write(String root, ProfileId profile) {
    final path = '$root/device-profile';
    final temporary = '$path.${OperationId.generate().value}';
    try {
      protectedFile(temporary, createNew: true);
      File(temporary).writeAsStringSync('${profile.value}\n', flush: true);
      syncPrivateFileAndDirectory(temporary);
      if (FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        publishSnapshot(temporary, path);
      } else {
        // The reconnect hint is replaceable software metadata, not a secret.
        // Refuse unsafe existing files before atomic replacement.
        protectedFile(path);
        File(temporary).renameSync(path);
        syncPrivateFileAndDirectory(path);
      }
    } finally {
      if (File(temporary).existsSync()) File(temporary).deleteSync();
    }
  }
}

/// Never retain driver exceptions: they can contain bound credential values.
final class ProfileCredentialException implements Exception {
  const ProfileCredentialException(this.failure);
  final ProfileCredentialFailure failure;
  @override
  String toString() => 'ProfileCredentialException(${failure.name})';
}

/// Exact existing profiles/{profile}.sqlite format. Files are create-only;
/// registry enrollment publishes a hash only after this durable write returns.
final class ProfileCredentialStore {
  static String _directory(String root) =>
      privateDirectory('${privateDirectory(root)}/profiles');

  static void write({
    required String root,
    required ProfileId profile,
    required String credential,
  }) {
    if (decodeExactUtf8(utf8.encode(credential)) != credential) {
      throw const ProfileCredentialException(
        ProfileCredentialFailure.invalidText,
      );
    }
    try {
      final directory = _directory(root);
      final path = '$directory/${profile.value}.sqlite';
      protectedFile(path, createNew: true);
      final db = sqlite3.open(path, mode: OpenMode.readWrite);
      try {
        db.execute('PRAGMA journal_mode=DELETE');
        db.execute('PRAGMA synchronous=FULL');
        db.execute('BEGIN IMMEDIATE');
        try {
          db.execute(profileCredentialSchema);
          db.execute(
            'INSERT INTO credential(profile_id, credential) VALUES(?, ?)',
            [profile.value, credential],
          );
          db.execute('COMMIT');
        } catch (_) {
          if (!db.autocommit) db.execute('ROLLBACK');
          rethrow;
        }
      } finally {
        db.close();
      }
      syncPrivateFileAndDirectory(path);
    } on Object {
      throw const ProfileCredentialException(
        ProfileCredentialFailure.unavailable,
      );
    }
  }

  /// Explicit secret access for profile authentication setup, never diagnostics.
  static String read({required String root, required ProfileId profile}) {
    try {
      final directory = _directory(root);
      final path = '$directory/${profile.value}.sqlite';
      protectedFile(path);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        db.execute('PRAGMA trusted_schema=OFF');
        final rows = db.select(
          "SELECT profile_id, typeof(credential) AS credential_type, CAST(credential AS BLOB) AS credential_utf8 FROM credential",
        );
        if (rows.length != 1 ||
            rows.single['profile_id'] != profile.value ||
            rows.single['credential_type'] != 'text' ||
            rows.single['credential_utf8'] is! Uint8List) {
          throw const ProfileCredentialException(
            ProfileCredentialFailure.identityMismatch,
          );
        }
        return decodeExactUtf8(rows.single['credential_utf8'] as Uint8List);
      } finally {
        db.close();
      }
    } on ProfileCredentialException {
      rethrow;
    } on Object {
      throw const ProfileCredentialException(
        ProfileCredentialFailure.unavailable,
      );
    }
  }
}
