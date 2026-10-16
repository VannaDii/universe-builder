import 'dart:io';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/hosted_account.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

import 'hosted_providers.dart';

/// Local operator setup, separate from database selection and universe canon.
/// Configuration cannot change beneath an installation-owned running engine.
void configureHostedAccount({
  required String root,
  required String accountId,
  required String issuer,
  required String subject,
  required ProfileId profile,
  bool remove = false,
}) {
  if (!Directory(root).existsSync()) {
    throw const FileSystemException('Existing installation required');
  }
  final directory = privateDirectory(root);
  final lock = OwnedFileLock.acquire('$directory/service.lock');
  HostedAccountStore? store;
  try {
    if (!remove) ProfileCredentialStore.read(root: directory, profile: profile);
    store = HostedAccountStore.open(directory, create: !remove);
    store.configure(
      accountId: accountId,
      binding: HostedIdentityBinding(
        issuer: issuer,
        subject: subject,
        profile: profile,
      ),
      remove: remove,
    );
  } finally {
    store?.close();
    lock.close();
  }
}

/// The caller already owns service.lock. No missing configuration is created,
/// and credential loss or invalid configuration never produces a new identity.
HostedAccountAccess? loadHostedAccountAccess(
  String root, {
  HostedSignInProvider signIn = const StubHostedSignInProvider(),
  HostedBillingProvider billing = const StubHostedBillingProvider(),
}) {
  if (FileSystemEntity.typeSync('$root/hosting.sqlite', followLinks: false) ==
      FileSystemEntityType.notFound) {
    return null;
  }
  final store = HostedAccountStore.open(root);
  try {
    final saved = store.read();
    if (saved == null) return null;
    return HostedAccountAccess(
      accountId: saved.accountId,
      signIn: signIn,
      billing: billing,
      profiles: {
        for (final binding in saved.bindings)
          HostedIdentity(
            issuer: binding.issuer,
            subject: binding.subject,
          ): EngineHello(
            protocolVersion: protocolVersion,
            profileId: binding.profile,
            credential: Credential(
              ProfileCredentialStore.read(root: root, profile: binding.profile),
            ),
            clientName: 'Hosted account session',
          ),
      },
    );
  } finally {
    store.close();
  }
}
