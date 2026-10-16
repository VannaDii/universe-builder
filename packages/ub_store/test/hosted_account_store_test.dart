@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/hosted_account.dart';
import 'package:ub_store/installation.dart';

void main() {
  test('hosted identities survive reopen and conflicting account/profile changes are atomic', () {
    final root = Directory('/tmp').createTempSync('ub-hosted-store-');
    final profile = ProfileId.generate(), other = ProfileId.generate();
    final binding = HostedIdentityBinding(
      issuer: 'https://issuer.example',
      subject: '作者 😀',
      profile: profile,
    );
    var store = HostedAccountStore.open(root.path, create: true);
    try {
      store.configure(accountId: 'account-a', binding: binding);
      store.configure(accountId: 'account-a', binding: binding);
      store.close();
      store = HostedAccountStore.open(root.path);
      expect(store.read()!.accountId, 'account-a');
      expect(store.read()!.bindings.single.subject, '作者 😀');
      expect(store.read()!.bindings.single.profile, profile);
      expect(
        () => store.configure(accountId: 'account-b', binding: binding),
        throwsFormatException,
      );
      expect(
        () => store.configure(
          accountId: 'account-a',
          binding: HostedIdentityBinding(
            issuer: binding.issuer,
            subject: binding.subject,
            profile: other,
          ),
        ),
        throwsFormatException,
      );
      expect(store.read()!.bindings.single.profile, profile);
      store.configure(accountId: 'account-a', binding: binding, remove: true);
      store.configure(accountId: 'account-a', binding: binding, remove: true);
      expect(store.read()!.bindings, isEmpty);
      expect(store.read()!.accountId, 'account-a');
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });

  test(
    'incompatible hosted configuration is rejected without modification',
    () {
      final root = Directory('/tmp').createTempSync('ub-hosted-format-');
      final path = '${root.path}/hosting.sqlite';
      protectedFile(path, createNew: true);
      final db = sqlite3.open(path);
      db.execute('CREATE TABLE unknown(value TEXT); PRAGMA user_version=42;');
      db.close();
      final before = File(path).readAsBytesSync();
      try {
        expect(
          () => HostedAccountStore.open(root.path, create: true),
          throwsFormatException,
        );
        expect(File(path).readAsBytesSync(), before);
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );
}
