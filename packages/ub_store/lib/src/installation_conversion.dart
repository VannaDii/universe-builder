import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'credential_conversion.dart';
import 'credential_schema.g.dart';
import 'installation_schema.g.dart';
import 'installation_store.dart';
import 'operator_rows.dart';
import 'operator_source.dart';
import 'ownership.dart';
import 'profile_credentials.dart';
import 'relational.dart';

enum InstallationConversionPoint { constructed, verified, beforePublish }

enum InstallationConversionFailure {
  invalidInput,
  destinationExists,
  sourceChanged,
  verificationFailed,
  unavailable,
}

/// Authority and credentials must never appear in parser/driver diagnostics.
final class InstallationConversionException implements Exception {
  const InstallationConversionException(this.failure);
  final InstallationConversionFailure failure;
  @override
  String toString() => 'InstallationConversionException(${failure.name})';
}

CanonicalObject convertInstallation(String source, String destination) =>
    convertInstallationWithHook(source, destination, (_) {});

/// Internal seam for interrupted conversion and exclusive publication cases.
CanonicalObject convertInstallationWithHook(
  String source,
  String destination,
  void Function(InstallationConversionPoint) hook,
) {
  Directory? temporary;
  Database? input, output;
  try {
    if (FileSystemEntity.typeSync(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const InstallationConversionException(
        InstallationConversionFailure.destinationExists,
      );
    }
    final parent = privateDirectory(
      Directory(destination).absolute.parent.path,
    );
    if (FileSystemEntity.typeSync(source, followLinks: false) !=
            FileSystemEntityType.directory ||
        FileSystemEntity.typeSync('$source/profiles', followLinks: false) !=
            FileSystemEntityType.directory) {
      throw const InstallationConversionException(
        InstallationConversionFailure.invalidInput,
      );
    }
    final originalRoot = privateDirectory(source);
    privateDirectory('$originalRoot/profiles');
    final originalPath = '$originalRoot/installation.sqlite';
    final original = openOriginalDatabase(originalPath);
    input = original.database;
    final relational = conversionColumns(
      input,
      'grants',
    ).contains('worlds_state');
    const scalars = [
      'settings',
      'profiles',
      'catalog',
      'aliases',
      'purge_pending',
      'audit',
    ];
    final allowed = {
      ...scalars,
      'grants',
      'import_preview',
      if (relational) ...[
        'grant_worlds',
        'grant_entities',
        'grant_predicates',
        'grant_continuities',
      ] else
        'grant_limits',
    };
    for (final row in input.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    )) {
      if (!allowed.contains(row['name'])) {
        throw const FormatException('Unknown installation evidence table');
      }
    }
    if (!relational &&
        (!sameConversionColumns(conversionColumns(input, 'grants'), [
              'profile',
              'universe',
              'worlds',
              'propose',
              'edit',
              'protected',
            ]) ||
            !sameConversionColumns(conversionColumns(input, 'grant_limits'), [
              'profile',
              'universe',
              'limits',
            ]))) {
      throw const FormatException('Unsupported serialized authority columns');
    }
    if (input.select('SELECT count(*) AS n FROM purge_pending').single['n'] !=
            0 ||
        conversionColumns(input, 'import_preview').isNotEmpty &&
            input
                    .select('SELECT count(*) AS n FROM import_preview')
                    .single['n'] !=
                0) {
      throw const FormatException(
        'Pending purge or legacy preview requires operator recovery',
      );
    }
    temporary = Directory(parent).createTempSync('.installation-conversion-');
    privateDirectory(temporary.path);
    final root = privateDirectory('${temporary.path}/target');
    privateDirectory('$root/profiles');
    privateDirectory('$root/packages');
    final path = '$root/installation.sqlite';
    protectedFile(path, createNew: true);
    output = sqlite3.open(path, mode: OpenMode.readWrite);
    output.execute(installationSchema);
    if (relational && !_sameSchema(input, output)) {
      throw const FormatException('Unsupported relational installation schema');
    }
    final copied = relational ? allowed.toList() : scalars;
    output.execute(
      'PRAGMA synchronous=FULL; BEGIN IMMEDIATE; PRAGMA defer_foreign_keys=ON',
    );
    for (final table in copied) {
      final columns = conversionColumns(output, table);
      if (!sameConversionColumns(columns, conversionColumns(input, table))) {
        throw const FormatException('Unsupported installation scalar columns');
      }
      final write = output.prepare(
        'INSERT INTO ${quoteIdentifier(table)} VALUES(${List.filled(columns.length, '?').join(',')})',
      );
      try {
        conversionRows(
          input,
          table,
          (row) => write.execute([for (final column in columns) row[column]]),
        );
      } finally {
        write.close();
      }
    }
    final grants = <GrantSpec>[];
    final relationalGrants = <(ProfileId, UniverseId)>[];
    if (relational) {
      conversionRows(
        input,
        'grants',
        (row) => relationalGrants.add((
          ProfileId.parse(row['profile'] as String),
          UniverseId.parse(row['universe'] as String),
        )),
      );
    } else {
      conversionRows(input, 'grants', (row) {
        final profile = ProfileId.parse(row['profile'] as String);
        final universe = UniverseId.parse(row['universe'] as String);
        bool flag(String column) {
          if (row[column] != 0 && row[column] != 1) {
            throw const FormatException('Invalid legacy grant flag');
          }
          return row[column] == 1;
        }

        final worldBody = row['worlds'];
        final worlds = worldBody == null ? null : _worlds(worldBody as String);
        final limitsRows = input!.select(
          'SELECT limits FROM grant_limits WHERE profile=? AND universe=?',
          [profile.value, universe.value],
        );
        if (limitsRows.length > 1) {
          throw const FormatException('Duplicate grant limits');
        }
        final limits = limitsRows.isEmpty
            ? GrantLimits()
            : GrantLimits.fromWire(
                _boundedJson(limitsRows.single['limits'] as String),
              );
        final grant = GrantSpec(
          profileId: profile,
          universeId: universe,
          worlds: worlds,
          propose: flag('propose'),
          edit: flag('edit'),
          protected: flag('protected'),
          limits: limits,
        );
        grants.add(grant);
        String state(Object? values) => values == null ? 'all' : 'listed';
        output!.execute('INSERT INTO grants VALUES(?,?,?,?,?,?,?,?,?,?,?,?)', [
          profile.value,
          universe.value,
          state(grant.worlds),
          grant.propose ? 1 : 0,
          grant.edit ? 1 : 0,
          grant.protected ? 1 : 0,
          state(limits.entities),
          state(limits.predicates),
          state(limits.continuities),
          limits.expiresAt?.toString(),
          limits.delegatedCommit ? 1 : 0,
          limits.allowShared ? 1 : 0,
        ]);
        final collections = <String, List<String>?>{
          'grant_worlds': grant.worlds?.map((id) => id.value).toList(),
          'grant_entities': limits.entities?.map((id) => id.value).toList(),
          'grant_predicates': limits.predicates?.map((id) => id.value).toList(),
          'grant_continuities': limits.continuities
              ?.map((id) => id.value)
              .toList(),
        };
        for (final entry in collections.entries) {
          final values = entry.value ?? const <String>[];
          for (var ordinal = 0; ordinal < values.length; ordinal++) {
            output.execute('INSERT INTO ${entry.key} VALUES(?,?,?,?)', [
              profile.value,
              universe.value,
              ordinal,
              values[ordinal],
            ]);
          }
        }
      });
    }
    if (!relational &&
        input
                .select(
                  'SELECT count(*) AS n FROM grant_limits l WHERE NOT EXISTS(SELECT 1 FROM grants g WHERE g.profile=l.profile AND g.universe=l.universe)',
                )
                .single['n'] !=
            0) {
      throw const FormatException('Orphan grant limits');
    }
    for (final table in copied) {
      compareConversionRows(input, output, table);
    }
    // The new handshake requires an identity. Explicit offline cutover establishes
    // it only when absent; ordinary opening never assigns or replaces one.
    final instance = output.select(
      "SELECT value FROM settings WHERE key='installation_instance'",
    );
    final instanceEstablished = instance.isEmpty;
    if (instanceEstablished) {
      output.execute("INSERT INTO settings VALUES('installation_instance',?)", [
        OperationId.generate().value,
      ]);
    } else {
      OperationId.parse(instance.single['value'] as String);
    }
    output.execute('COMMIT');
    final profiles = <ProfileId, String>{};
    conversionRows(input, 'profiles', (row) {
      profiles[ProfileId.parse(row['id'] as String)] = row['hash'] as String;
    });
    final credentials = <String, String>{};
    for (final entry in Directory(
      '$originalRoot/profiles',
    ).listSync(followLinks: false)) {
      final name = entry.uri.pathSegments.last;
      final extension = relational ? '.sqlite' : '.json';
      if (!name.endsWith(extension)) {
        throw const FormatException('Unsupported credential inventory');
      }
      final profile = ProfileId.parse(
        name.substring(0, name.length - extension.length),
      );
      final hash = relational
          ? _copyRelationalCredential(entry.path, root, profile)
          : WireFields(
              convertCredential(
                entry.path,
                '$root/profiles/${profile.value}.sqlite',
              ),
              {'source_sha256', 'original_preserved', 'credential_verified'},
            ).string('source_sha256');
      final credential = ProfileCredentialStore.read(
        root: root,
        profile: profile,
      );
      final expected = profiles[profile];
      if (expected != null &&
          sha256.convert(utf8.encode(credential)).toString() != expected) {
        throw const FormatException('Enrolled credential hash mismatch');
      }
      credentials[entry.path] = hash;
    }
    for (final profile in profiles.keys) {
      if (!credentials.containsKey(
        '$originalRoot/profiles/${profile.value}${relational ? '.sqlite' : '.json'}',
      )) {
        throw const FormatException('Missing enrolled credential');
      }
    }
    hook(InstallationConversionPoint.constructed);
    if (output.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw const FormatException('Installation foreign key mismatch');
    }
    output.close();
    output = null;
    final reader = SqliteInstallationStore.openExisting(root);
    try {
      for (final grant in grants) {
        if (reader
                .readGrant(grant.profileId, grant.universeId)
                .toWire()
                .toText() !=
            grant.toWire().toText()) {
          throw const FormatException('Whole grant comparison failed');
        }
      }
      for (final (profile, universe) in relationalGrants) {
        reader.readGrant(profile, universe);
      }
    } finally {
      reader.close();
    }
    hook(InstallationConversionPoint.verified);
    output = sqlite3.open(path, mode: OpenMode.readWrite);
    output.execute(
      'PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE',
    );
    output.close();
    output = null;
    syncPrivateFileAndDirectory(path);
    syncPrivateDirectory('$root/profiles');
    syncPrivateDirectory('$root/packages');
    syncPrivateDirectory(root);
    hook(InstallationConversionPoint.beforePublish);
    if (originalFileHash(originalPath) != original.hash) {
      throw const InstallationConversionException(
        InstallationConversionFailure.sourceChanged,
      );
    }
    verifyOriginalDatabase(originalPath, original.hash);
    final currentPaths = Directory('$originalRoot/profiles')
        .listSync(followLinks: false)
        .map((entry) => entry.path)
        .toSet();
    if (currentPaths.length != credentials.length ||
        credentials.keys.any((path) => !currentPaths.contains(path))) {
      throw const InstallationConversionException(
        InstallationConversionFailure.sourceChanged,
      );
    }
    for (final entry in credentials.entries) {
      if (originalFileHash(entry.key) != entry.value) {
        throw const InstallationConversionException(
          InstallationConversionFailure.sourceChanged,
        );
      }
    }
    publishConversionDirectory(root, destination);
    return CanonicalObject([
      MapEntry('source_sha256', CanonicalString(original.hash)),
      MapEntry('profiles', CanonicalNumber(profiles.length.toString())),
      MapEntry('credentials', CanonicalNumber(credentials.length.toString())),
      MapEntry(
        'grants',
        CanonicalNumber((grants.length + relationalGrants.length).toString()),
      ),
      MapEntry('compared_tables', CanonicalNumber(copied.length.toString())),
      MapEntry(
        'instance_identity_established',
        CanonicalBool(instanceEstablished),
      ),
      const MapEntry('original_preserved', CanonicalBool(true)),
      const MapEntry('catalog_paths_preserved', CanonicalBool(true)),
    ]);
  } on InstallationConversionException {
    rethrow;
  } on CredentialConversionException {
    throw const InstallationConversionException(
      InstallationConversionFailure.invalidInput,
    );
  } on FormatException {
    throw const InstallationConversionException(
      InstallationConversionFailure.invalidInput,
    );
  } on Object {
    throw const InstallationConversionException(
      InstallationConversionFailure.unavailable,
    );
  } finally {
    try {
      try {
        output?.close();
      } finally {
        try {
          input?.close();
        } finally {
          temporary?.deleteSync(recursive: true);
        }
      }
    } on Object {
      throw const InstallationConversionException(
        InstallationConversionFailure.unavailable,
      );
    }
  }
}

bool _sameSchema(Database input, Database output) {
  List<(String, String, String, String)> schema(Database db) => [
    for (final row in db.select(
      "SELECT type,name,tbl_name,coalesce(sql,'') AS sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name",
    ))
      (
        row['type'] as String,
        row['name'] as String,
        row['tbl_name'] as String,
        row['sql'] as String,
      ),
  ];
  final a = schema(input), b = schema(output);
  return a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
}

String _copyRelationalCredential(
  String source,
  String root,
  ProfileId profile,
) {
  final original = openOriginalDatabase(source);
  final expected = sqlite3.openInMemory();
  try {
    expected.execute(profileCredentialSchema);
    if (!_sameSchema(original.database, expected)) {
      throw const FormatException('Unsupported credential schema');
    }
    final rows = original.database.select(
      'SELECT profile_id, typeof(credential) AS type, CAST(credential AS BLOB) AS bytes FROM credential',
    );
    if (rows.length != 1 ||
        rows.single['profile_id'] != profile.value ||
        rows.single['type'] != 'text') {
      throw const FormatException('Credential identity mismatch');
    }
    final credential = decodeExactUtf8(rows.single['bytes'] as List<int>);
    if (credential.isEmpty) {
      throw const FormatException('Empty retained credential');
    }
    ProfileCredentialStore.write(
      root: root,
      profile: profile,
      credential: credential,
    );
    if (ProfileCredentialStore.read(root: root, profile: profile) !=
        credential) {
      throw const FormatException('Credential comparison failed');
    }
    return original.hash;
  } finally {
    try {
      original.database.close();
    } finally {
      expected.close();
    }
  }
}

CanonicalValue _boundedJson(String body) {
  if (utf8.encode(body).length > 4194304) {
    throw const FormatException('Serialized grant bound exceeded');
  }
  return CanonicalValue.parseWireJson(body);
}

List<WorldId> _worlds(String body) {
  final value = _boundedJson(body);
  if (value is! CanonicalArray) {
    throw const FormatException('Invalid world scope');
  }
  return [for (final id in value.items) WorldId.parse(wireString(id))];
}
