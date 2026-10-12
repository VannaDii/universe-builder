import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/helpers.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

/// Constructed only by credential authentication and bound to one installation.
final class InstallationPrincipal {
  const InstallationPrincipal._(this.id, this.author, this.instanceId);
  final ProfileId id;
  final bool author;
  final OperationId instanceId;
}

/// Profile listing deliberately excludes credential hashes and secret material.
final class LocalProfileSummary {
  const LocalProfileSummary({
    required this.id,
    required this.author,
    required this.revoked,
  });
  final ProfileId id;
  final bool author;
  final bool revoked;
}

/// Service authority over installation profiles and catalog. This is not universe grant
/// authorization; that scope check is required before exposing universe content.
final class InstallationAuthority {
  const InstallationAuthority(this._store);
  final SqliteInstallationStore _store;

  ProfileId initializeAuthor() {
    if (_store.hasProfiles) {
      throw const InstallationException(InstallationFailure.alreadyEnrolled);
    }
    return _enroll();
  }

  ProfileId enroll(InstallationPrincipal actor) {
    requireAuthor(actor);
    return _enroll(actor: actor.id);
  }

  ProfileId _enroll({ProfileId? actor}) {
    final id = ProfileId.generate();
    final random = Random.secure();
    final credential = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    // Private file + containing directory are durable before hash publication.
    ProfileCredentialStore.write(
      root: _store.root,
      profile: id,
      credential: credential,
    );
    _store.enroll(
      id: id,
      credentialHash: sha256.convert(utf8.encode(credential)).toString(),
      actor: actor,
    );
    return id;
  }

  InstallationPrincipal authenticate({
    required ProfileId profile,
    required Credential credential,
  }) {
    try {
      final exact = utf8.encode(credential.expose());
      if (utf8.decode(exact) != credential.expose()) {
        throw const InstallationException(InstallationFailure.denied);
      }
      final stored = _store.profile(profile);
      final supplied = sha256.convert(exact).toString();
      if (stored == null ||
          stored.revoked ||
          !constantTimeBytesEquality.equals(
            stored.credentialHash.codeUnits,
            supplied.codeUnits,
          )) {
        throw const InstallationException(InstallationFailure.denied);
      }
      return InstallationPrincipal._(
        stored.id,
        stored.author,
        _store.instanceId,
      );
    } on Object {
      // Unknown, revoked and invalid credentials have the same public denial.
      throw const InstallationException(InstallationFailure.denied);
    }
  }

  void requireAuthor(InstallationPrincipal principal) {
    if (principal.instanceId != _store.instanceId) {
      throw const InstallationException(InstallationFailure.denied);
    }
    _store.requireAuthor(principal.id);
  }

  void revoke(InstallationPrincipal actor, ProfileId target) {
    requireAuthor(actor);
    _store.revoke(actor: actor.id, target: target);
  }

  List<LocalProfileSummary> profiles(InstallationPrincipal actor) {
    requireAuthor(actor);
    return List<LocalProfileSummary>.unmodifiable(
      _store
          .profiles(actor.id)
          .map(
            (profile) => LocalProfileSummary(
              id: profile.id,
              author: profile.author,
              revoked: profile.revoked,
            ),
          ),
    );
  }

  UniverseId registerUniverse(
    InstallationPrincipal actor, {
    required String name,
    required String path,
  }) {
    requireAuthor(actor);
    return _store.registerExistingPackage(
      actor: actor.id,
      name: name,
      path: path,
    );
  }

  void renameUniverse(
    InstallationPrincipal actor, {
    required UniverseId id,
    required String name,
  }) {
    requireAuthor(actor);
    _store.renameUniverse(actor: actor.id, id: id, name: name);
  }

  InstallationCatalogEntry resolveUniverseAlias(
    InstallationPrincipal actor,
    String name,
  ) {
    requireAuthor(actor);
    return _store.resolveUniverseAlias(actor: actor.id, name: name);
  }

  List<InstallationCatalogEntry> catalog(InstallationPrincipal actor) {
    requireAuthor(actor);
    return _store.catalog(actor.id);
  }
}
