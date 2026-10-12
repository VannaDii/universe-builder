import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/helpers.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/sqlite.dart' show OwnedSqliteDatabase;

import 'validation_binding.dart';

/// Trusted current values, usable only within the owning authority section.
final class CurrentUniverseAuthority {
  CurrentUniverseAuthority._({
    required this.principal,
    required this.approvalAuthor,
    required this.worldScope,
    required this.limits,
    required this.permissions,
    required this.sequence,
  });
  final InstallationPrincipal principal;
  final ProfileId approvalAuthor;
  final Set<WorldId>? worldScope;
  final GrantLimits limits;
  final (bool, bool, bool) permissions;
  final BigInt sequence;
  String get scopeHash {
    final scope = worldScope?.toList()
      ?..sort((a, b) => a.value.compareTo(b.value));
    return canonicalDigest(
      CanonicalArray([
        scope == null
            ? const CanonicalNull()
            : CanonicalArray(scope.map((w) => CanonicalString(w.value))),
        CanonicalArray([
          CanonicalBool(permissions.$1),
          CanonicalBool(permissions.$2),
          CanonicalBool(permissions.$3),
        ]),
        limits.toWire(),
      ]),
    );
  }

  String get validationDigest => validationAuthorityDigest(
    principal: principal.id,
    author: principal.author,
    approvalAuthor: approvalAuthor,
    scopeHash: scopeHash,
  );
}

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

/// Installation profiles, catalog and base universe grant permissions. Exact
/// proposal footprint and publication authority remain separate workflow checks.
final class InstallationAuthority {
  const InstallationAuthority(this._store, {BigInt Function()? epochSeconds})
    : _epochSeconds = epochSeconds ?? _now;
  final SqliteInstallationStore _store;
  final BigInt Function() _epochSeconds;
  static BigInt _now() =>
      BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000);

  /// Grant/revocation routes use the same queue as capture and persistence.
  Future<T> coordinate<T>(
    InstallationPrincipal principal,
    FutureOr<T> Function() action,
  ) => _store.withAuthority(() {
    _requireCurrent(principal);
    return action();
  });

  /// Recheck authentication, expiry, catalog and rights after entering the queue.
  /// Acquire the universe context inside [action], after installation authority.
  Future<T> withUniverseAuthority<T>(
    InstallationPrincipal principal,
    UniverseId universe,
    FutureOr<T> Function(CurrentUniverseAuthority) action,
  ) => coordinate(principal, () {
    final now = _epochSeconds();
    final scope = _store.universeScope(principal.id, universe, now);
    final limits = _store.limits(principal.id, universe, now);
    final grant = principal.author
        ? null
        : _store.readGrant(principal.id, universe);
    return action(
      CurrentUniverseAuthority._(
        principal: principal,
        approvalAuthor: _store.currentAuthor(),
        worldScope: scope,
        limits: limits,
        permissions: grant == null
            ? (true, true, true)
            : (grant.propose, grant.edit, grant.protected),
        sequence: _store.validationAuthoritySequence(principal.id, universe),
      ),
    );
  });

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

  /// Compatibility and credential admission for the private engine handshake.
  /// Transports must call this again for each request; a handshake is not a
  /// lasting permission grant or a reservation of engine capacity.
  InstallationPrincipal authenticateHello(EngineHello hello) {
    final nameBytes = utf8.encode(hello.clientName);
    if (hello.protocolVersion != protocolVersion ||
        nameBytes.length > 128 ||
        utf8.decode(nameBytes) != hello.clientName) {
      throw const FormatException('Incompatible engine handshake');
    }
    return authenticate(profile: hello.profileId, credential: hello.credential);
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

  List<GrantSpec> grants(InstallationPrincipal actor) {
    requireAuthor(actor);
    return _store.grants(actor.id);
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

  String newUniversePath(InstallationPrincipal actor, UniverseId id) {
    return '${universeDirectory(actor)}/${id.value}.sqlite';
  }

  InstallationImportPreview prepareImport(
    InstallationPrincipal actor,
    PreviewImportEngineRequest request,
  ) {
    requireAuthor(actor);
    return _store.prepareImport(
      actor: actor.id,
      source: request.source,
      name: request.name,
      mode: request.mode,
    );
  }

  InstallationImportPreview loadImport(
    InstallationPrincipal actor,
    AcceptImportEngineRequest request,
  ) {
    requireAuthor(actor);
    return _store.loadImport(
      actor: actor.id,
      id: request.previewId,
      digest: request.digest,
    );
  }

  String importArchivePath(
    InstallationPrincipal actor,
    InstallationImportPreview preview,
  ) {
    requireAuthor(actor);
    return preview.archivePath(_store.root);
  }

  String universeDirectory(InstallationPrincipal actor) {
    requireAuthor(actor);
    return '${_store.root}/packages';
  }

  List<String> importConflicts(
    InstallationPrincipal actor, {
    required UniverseId id,
    required String name,
  }) {
    requireAuthor(actor);
    return _store.importConflicts(actor: actor.id, id: id, name: name);
  }

  void beginPurge(InstallationPrincipal actor, UniverseId universe) {
    requireAuthor(actor);
    _store.beginPurge(actor: actor.id, universe: universe);
  }

  void finishPurges(InstallationPrincipal actor) {
    requireAuthor(actor);
    _store.finishPurges(actor: actor.id);
  }

  UniverseId registerOpenedUniverse(
    InstallationPrincipal actor, {
    required String name,
    required OwnedSqliteDatabase package,
  }) {
    requireAuthor(actor);
    return _store.registerOwnedPackage(
      actor: actor.id,
      name: name,
      package: package,
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
    _requireCurrent(actor);
    return _store.resolveUniverseAlias(
      actor: actor.id,
      name: name,
      epochSeconds: _epochSeconds(),
    );
  }

  List<InstallationCatalogEntry> catalog(InstallationPrincipal actor) {
    _requireCurrent(actor);
    return _store.catalog(actor.id, epochSeconds: _epochSeconds());
  }

  void grant(InstallationPrincipal actor, GrantSpec grant) {
    requireAuthor(actor);
    _store.putGrant(
      actor: actor.id,
      grant: grant,
      epochSeconds: _epochSeconds(),
    );
  }

  void withdrawGrant(
    InstallationPrincipal actor, {
    required ProfileId profile,
    required UniverseId universe,
  }) {
    requireAuthor(actor);
    _store.withdrawGrant(actor: actor.id, profile: profile, universe: universe);
  }

  void _requireCurrent(InstallationPrincipal principal) {
    if (principal.instanceId != _store.instanceId) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final current = _store.profile(principal.id);
    if (current == null || current.revoked) {
      throw const InstallationException(InstallationFailure.denied);
    }
  }

  Set<WorldId>? universeScope(
    InstallationPrincipal principal,
    UniverseId universe,
  ) {
    _requireCurrent(principal);
    return _store.universeScope(principal.id, universe, _epochSeconds());
  }

  GrantLimits limits(InstallationPrincipal principal, UniverseId universe) {
    _requireCurrent(principal);
    return _store.limits(principal.id, universe, _epochSeconds());
  }

  BigInt validationAuthoritySequence(
    InstallationPrincipal principal,
    UniverseId universe,
  ) {
    _requireCurrent(principal);
    _store.universeScope(principal.id, universe, _epochSeconds());
    return _store.validationAuthoritySequence(principal.id, universe);
  }

  /// Base world/write permissions only; no proposal footprint, approval or
  /// delegated publication is admitted by this check alone.
  void authorizeWrite(
    InstallationPrincipal principal, {
    required UniverseId universe,
    required Set<WorldId> worlds,
    required bool shared,
    required bool protected,
    required bool commit,
  }) {
    _requireCurrent(principal);
    _store.authorizeWrite(
      profile: principal.id,
      universe: universe,
      worlds: worlds,
      shared: shared,
      protected: protected,
      commit: commit,
      epochSeconds: _epochSeconds(),
    );
  }
}
