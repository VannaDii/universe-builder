import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

final class HostedIdentityBinding {
  const HostedIdentityBinding({
    required this.issuer,
    required this.subject,
    required this.profile,
  });
  final String issuer, subject;
  final ProfileId profile;
}

final class SavedHostedAccount {
  SavedHostedAccount({
    required this.accountId,
    required Iterable<HostedIdentityBinding> bindings,
  }) : bindings = List.unmodifiable(bindings);
  final String accountId;
  final List<HostedIdentityBinding> bindings;
}

/// Installation-local operator configuration. Callers hold service.lock while
/// reading or changing bindings, so a running server retains one configuration.
/// Stores identities/profile IDs only; credentials stay in their existing store.
final class HostedAccountStore {
  HostedAccountStore._(this._db);
  final Database _db;

  static HostedAccountStore open(String root, {bool create = false}) {
    final path = '${Directory(root).absolute.path}/hosting.sqlite';
    Database? db;
    try {
      protectedFile(path, create: create);
      for (final suffix in ['-wal', '-shm']) {
        if (FileSystemEntity.typeSync('$path$suffix', followLinks: false) !=
            FileSystemEntityType.notFound) {
          protectedFile('$path$suffix');
        }
      }
      db = sqlite3.open(path, mode: OpenMode.readWrite);
      final tables = db
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )
          .map((row) => row['name'])
          .toList();
      final version = db.select('PRAGMA user_version').single.values.single;
      if (tables.isEmpty && create && version == 0) {
        db.execute('''
BEGIN IMMEDIATE;
CREATE TABLE hosted_account (
 singleton INTEGER PRIMARY KEY CHECK(singleton=1), account_id TEXT NOT NULL
) STRICT;
CREATE TABLE hosted_identity (
 issuer TEXT NOT NULL, subject TEXT NOT NULL, profile_id TEXT NOT NULL,
 PRIMARY KEY(issuer,subject)
) STRICT;
PRAGMA user_version=1;
COMMIT;
''');
      } else if (version != 1 ||
          tables.join(',') != 'hosted_account,hosted_identity' ||
          _columns(db, 'hosted_account') !=
              'singleton:INTEGER,account_id:TEXT' ||
          _columns(db, 'hosted_identity') !=
              'issuer:TEXT,subject:TEXT,profile_id:TEXT') {
        throw const FormatException(
          'Incompatible hosted account configuration',
        );
      }
      db.execute(
        'PRAGMA trusted_schema=OFF; PRAGMA busy_timeout=2000; PRAGMA synchronous=FULL; PRAGMA journal_mode=DELETE',
      );
      final store = HostedAccountStore._(db);
      store.read();
      return store;
    } on Object {
      if (db != null && !db.autocommit) db.execute('ROLLBACK');
      db?.close();
      rethrow;
    }
  }

  static String _columns(Database db, String table) => db
      .select('PRAGMA table_info($table)')
      .map((row) => '${row['name']}:${row['type']}')
      .join(',');

  static void _text(String value) {
    if (value.isEmpty ||
        value.contains('\u0000') ||
        decodeExactUtf8(utf8.encode(value)) != value) {
      throw const FormatException('Invalid hosted account identity');
    }
  }

  SavedHostedAccount? read() {
    final accounts = _db.select(
      'SELECT singleton, CAST(account_id AS BLOB) AS account_id FROM hosted_account',
    );
    final identities = _db.select(
      'SELECT CAST(issuer AS BLOB) AS issuer, CAST(subject AS BLOB) AS subject, CAST(profile_id AS BLOB) AS profile_id FROM hosted_identity ORDER BY issuer,subject',
    );
    if (accounts.isEmpty) {
      if (identities.isNotEmpty) {
        throw const FormatException('Hosted account missing');
      }
      return null;
    }
    if (accounts.length != 1 || accounts.single['singleton'] != 1) {
      throw const FormatException('Ambiguous hosted account');
    }
    final account = _checked(accounts.single['account_id']);
    return SavedHostedAccount(
      accountId: account,
      bindings: [
        for (final row in identities)
          HostedIdentityBinding(
            issuer: _checked(row['issuer']),
            subject: _checked(row['subject']),
            profile: ProfileId.parse(_checked(row['profile_id'])),
          ),
      ],
    );
  }

  static String _checked(Object? bytes) {
    if (bytes is! List<int>) {
      throw const FormatException('Invalid hosted identity text');
    }
    final text = decodeExactUtf8(bytes);
    _text(text);
    return text;
  }

  /// Exact retries are harmless. Rebinding an identity to a different profile
  /// requires explicit removal. The installation's account identity is stable.
  void configure({
    required String accountId,
    required HostedIdentityBinding binding,
    bool remove = false,
  }) {
    _text(accountId);
    _text(binding.issuer);
    _text(binding.subject);
    _db.execute('BEGIN IMMEDIATE');
    try {
      final saved = read();
      if (saved != null && saved.accountId != accountId) {
        throw const FormatException(
          'Installation belongs to another hosted account',
        );
      }
      final existing = _db.select(
        'SELECT profile_id FROM hosted_identity WHERE issuer=? AND subject=?',
        [binding.issuer, binding.subject],
      );
      if (existing.isNotEmpty &&
          existing.single['profile_id'] != binding.profile.value) {
        throw const FormatException(
          'Hosted identity already bound to another profile',
        );
      }
      if (remove) {
        _db.execute(
          'DELETE FROM hosted_identity WHERE issuer=? AND subject=? AND profile_id=?',
          [binding.issuer, binding.subject, binding.profile.value],
        );
      } else {
        _db.execute(
          'INSERT OR IGNORE INTO hosted_account(singleton,account_id) VALUES(1,?)',
          [accountId],
        );
        _db.execute(
          'INSERT OR IGNORE INTO hosted_identity(issuer,subject,profile_id) VALUES(?,?,?)',
          [binding.issuer, binding.subject, binding.profile.value],
        );
      }
      _db.execute('COMMIT');
    } on Object {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => _db.close();
}
