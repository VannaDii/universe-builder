part of 'installation_authority.dart';

/// Current service authority within the store's owning PostgreSQL transaction.
/// All checks retain the installation singleton lock until outer completion;
/// universe access inside the callback must follow this lock. A previous
/// handshake, principal or validation capture never confers lasting rights.
/// Endpoint discovery/connection ownership and exact proposal footprint/approval
/// remain separate service work. This adapter exposes no database Connection.
final class PostgresServiceAuthority {
  PostgresServiceAuthority(this._store, {BigInt Function()? epochSeconds})
    : _epochSeconds = epochSeconds ?? InstallationAuthority._now;
  final PostgresInstallationAuthority _store;
  final BigInt Function() _epochSeconds;

  /// Explicit local setup only; never invoked implicitly by connection/startup.
  Future<ProfileId> initializeAuthor({required String profileRoot}) async {
    if (await _store.hasProfiles) {
      throw const InstallationException(InstallationFailure.alreadyEnrolled);
    }
    return _enroll(profileRoot: profileRoot);
  }

  Future<ProfileId> enroll(
    InstallationPrincipal actor, {
    required String profileRoot,
  }) async {
    await requireAuthor(actor);
    return _enroll(actor: actor.id, profileRoot: profileRoot);
  }

  Future<ProfileId> _enroll({
    ProfileId? actor,
    required String profileRoot,
  }) async {
    final (id, hash) = _writeProfileCredential(profileRoot);
    await _store.enroll(id: id, credentialHash: hash, actor: actor);
    return id;
  }

  Future<InstallationPrincipal> authenticate({
    required ProfileId profile,
    required Credential credential,
  }) async {
    try {
      return _authenticateInstallationProfile(
        await _store.profile(profile),
        credential,
        _store.instanceId,
      );
    } on Object {
      // Credential denials and driver details are not disclosed publicly.
      throw const InstallationException(InstallationFailure.denied);
    }
  }

  Future<InstallationPrincipal> authenticateHello(EngineHello hello) {
    _validateEngineHello(hello);
    return authenticate(profile: hello.profileId, credential: hello.credential);
  }

  Future<void> _requireCurrent(InstallationPrincipal principal) async {
    if (principal.instanceId != _store.instanceId) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final current = await _store.profile(principal.id);
    if (current == null || current.revoked) {
      throw const InstallationException(InstallationFailure.denied);
    }
  }

  Future<T> coordinate<T>(
    InstallationPrincipal principal,
    FutureOr<T> Function() action,
  ) async {
    await _requireCurrent(principal);
    return action();
  }

  Future<T> withUniverseAuthority<T>(
    InstallationPrincipal principal,
    UniverseId universe,
    FutureOr<T> Function(CurrentUniverseAuthority) action,
  ) => coordinate(principal, () async {
    final now = _epochSeconds();
    final scope = await _store.universeScope(principal.id, universe, now);
    final limits = await _store.limits(principal.id, universe, now);
    final grant = principal.author
        ? null
        : await _store.readGrant(principal.id, universe);
    return action(
      CurrentUniverseAuthority._(
        principal: principal,
        approvalAuthor: await _store.currentAuthor(),
        worldScope: scope,
        limits: limits,
        permissions: grant == null
            ? (true, true, true)
            : (grant.propose, grant.edit, grant.protected),
        sequence: await _store.validationAuthoritySequence(
          principal.id,
          universe,
        ),
      ),
    );
  });

  Future<void> requireAuthor(InstallationPrincipal principal) async {
    await _requireCurrent(principal);
    await _store.requireAuthor(principal.id);
  }

  /// Trusted move coordinator entry. Ordinary universe routes remain suspended
  /// after this transaction commits, including already connected workers.
  Future<void> quiesceUniverseForMove(
    InstallationPrincipal principal, {
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
  }) => coordinate(
    principal,
    () => _store.quiesceUniverseForMove(
      actor: principal.id,
      universe: universe,
      operation: operation,
      targetInstance: targetInstance,
    ),
  );

  Future<Set<WorldId>?> universeScope(
    InstallationPrincipal principal,
    UniverseId universe,
  ) => coordinate(
    principal,
    () => _store.universeScope(principal.id, universe, _epochSeconds()),
  );

  Future<GrantLimits> limits(
    InstallationPrincipal principal,
    UniverseId universe,
  ) => coordinate(
    principal,
    () => _store.limits(principal.id, universe, _epochSeconds()),
  );

  Future<BigInt> validationAuthoritySequence(
    InstallationPrincipal principal,
    UniverseId universe,
  ) => coordinate(principal, () async {
    await _store.universeScope(principal.id, universe, _epochSeconds());
    return _store.validationAuthoritySequence(principal.id, universe);
  });

  /// Base grant check only. Exact entity/predicate/continuity footprints and
  /// delegated publication/approval are still checked by the proposal workflow.
  Future<void> authorizeWrite(
    InstallationPrincipal principal, {
    required UniverseId universe,
    required Set<WorldId> worlds,
    required bool shared,
    required bool protected,
    required bool commit,
  }) => coordinate(
    principal,
    () => _store.authorizeWrite(
      profile: principal.id,
      universe: universe,
      worlds: worlds,
      shared: shared,
      protected: protected,
      commit: commit,
      epochSeconds: _epochSeconds(),
    ),
  );

  Future<void> revoke(InstallationPrincipal actor, ProfileId target) async {
    await requireAuthor(actor);
    await _store.revoke(actor: actor.id, target: target);
  }

  Future<List<LocalProfileSummary>> profiles(
    InstallationPrincipal actor,
  ) async {
    await requireAuthor(actor);
    return List.unmodifiable([
      for (final profile in await _store.profiles(actor.id))
        LocalProfileSummary(
          id: profile.id,
          author: profile.author,
          revoked: profile.revoked,
        ),
    ]);
  }

  Future<List<GrantSpec>> grants(InstallationPrincipal actor) async {
    await requireAuthor(actor);
    return _store.grants(actor.id);
  }

  Future<void> putGrant(InstallationPrincipal actor, GrantSpec grant) async {
    await requireAuthor(actor);
    await _store.putGrant(
      actor: actor.id,
      grant: grant,
      epochSeconds: _epochSeconds(),
    );
  }

  Future<void> withdrawGrant(
    InstallationPrincipal actor,
    ProfileId profile,
    UniverseId universe,
  ) async {
    await requireAuthor(actor);
    await _store.withdrawGrant(
      actor: actor.id,
      profile: profile,
      universe: universe,
    );
  }
}
