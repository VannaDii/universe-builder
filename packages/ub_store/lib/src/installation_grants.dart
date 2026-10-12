part of 'installation_store.dart';

/// The fixed grant tables share installation transactions and audit ordering.
extension InstallationGrants on SqliteInstallationStore {
  List<GrantSpec> grants(ProfileId actor) {
    requireAuthor(actor);
    return List<GrantSpec>.unmodifiable(
      _db
          .select(
            'SELECT profile,universe FROM grants ORDER BY profile,universe',
          )
          .map(
            (row) => readGrant(
              ProfileId.parse(row['profile'] as String),
              UniverseId.parse(row['universe'] as String),
            ),
          ),
    );
  }

  void putGrant({
    required ProfileId actor,
    required GrantSpec grant,
    required BigInt epochSeconds,
  }) {
    requireAuthor(actor);
    final limits = grant.limits;
    for (final size in [
      grant.worlds?.length,
      limits.entities?.length,
      limits.predicates?.length,
      limits.continuities?.length,
    ]) {
      if (size != null && (size < 1 || size > 100)) {
        throw const InstallationException(InstallationFailure.invalidGrant);
      }
    }
    if ((limits.expiresAt != null && limits.expiresAt! <= epochSeconds) ||
        (limits.delegatedCommit &&
            (!grant.edit ||
                limits.entities == null ||
                limits.predicates == null ||
                limits.continuities == null ||
                limits.expiresAt == null))) {
      throw const InstallationException(InstallationFailure.invalidGrant);
    }
    String state(Object? values) => values == null ? 'all' : 'listed';
    _transaction(() {
      requireAuthor(actor);
      _db.execute(
        'INSERT INTO grants VALUES(?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(profile,universe) DO UPDATE SET worlds_state=excluded.worlds_state,propose=excluded.propose,edit=excluded.edit,protected=excluded.protected,entities_state=excluded.entities_state,predicates_state=excluded.predicates_state,continuities_state=excluded.continuities_state,expires_at=excluded.expires_at,delegated_commit=excluded.delegated_commit,allow_shared=excluded.allow_shared',
        [
          grant.profileId.value,
          grant.universeId.value,
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
        ],
      );
      final collections = <String, List<String>?>{
        'grant_worlds': grant.worlds?.map((v) => v.value).toList(),
        'grant_entities': limits.entities?.map((v) => v.value).toList(),
        'grant_predicates': limits.predicates?.map((v) => v.value).toList(),
        'grant_continuities': limits.continuities?.map((v) => v.value).toList(),
      };
      for (final entry in collections.entries) {
        _db.execute('DELETE FROM ${entry.key} WHERE profile=? AND universe=?', [
          grant.profileId.value,
          grant.universeId.value,
        ]);
        final values = entry.value ?? const <String>[];
        for (var i = 0; i < values.length; i++) {
          _db.execute('INSERT INTO ${entry.key} VALUES(?,?,?,?)', [
            grant.profileId.value,
            grant.universeId.value,
            i,
            values[i],
          ]);
        }
      }
      _db.execute(
        "INSERT INTO audit(actor,action,target) VALUES(?,'grant',?)",
        [actor.value, grant.profileId.value],
      );
      _db.execute(
        "INSERT INTO audit(actor,action,target) VALUES(?,'grant_scope',?)",
        [actor.value, '${grant.profileId.value}:${grant.universeId.value}'],
      );
    });
  }

  GrantSpec readGrant(ProfileId profile, UniverseId universe) {
    _ensureOpen();
    final rows = _db.select(
      'SELECT * FROM grants WHERE profile=? AND universe=?',
      [profile.value, universe.value],
    );
    if (rows.isEmpty) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final row = rows.single;
    List<String>? children(
      String state,
      String table,
      String column,
    ) => switch (state) {
      'all' => null,
      'listed' =>
        _db
            .select(
              'SELECT $column FROM $table WHERE profile=? AND universe=? ORDER BY ordinal',
              [profile.value, universe.value],
            )
            .map((r) => r[column] as String)
            .toList(),
      _ => throw const InstallationException(InstallationFailure.denied),
    };
    return GrantSpec(
      profileId: profile,
      universeId: universe,
      worlds: children(
        row['worlds_state'] as String,
        'grant_worlds',
        'world',
      )?.map(WorldId.parse),
      propose: row['propose'] == 1,
      edit: row['edit'] == 1,
      protected: row['protected'] == 1,
      limits: GrantLimits(
        entities: children(
          row['entities_state'] as String,
          'grant_entities',
          'entity',
        )?.map(RecordId.parse),
        predicates: children(
          row['predicates_state'] as String,
          'grant_predicates',
          'predicate',
        )?.map(RecordId.parse),
        continuities: children(
          row['continuities_state'] as String,
          'grant_continuities',
          'continuity',
        )?.map(ContinuityId.parse),
        expiresAt: row['expires_at'] == null
            ? null
            : BigInt.parse(row['expires_at'] as String),
        delegatedCommit: row['delegated_commit'] == 1,
        allowShared: row['allow_shared'] == 1,
      ),
    );
  }

  void withdrawGrant({
    required ProfileId actor,
    required ProfileId profile,
    required UniverseId universe,
  }) {
    _transaction(() {
      requireAuthor(actor);
      for (final table in [
        'grant_worlds',
        'grant_entities',
        'grant_predicates',
        'grant_continuities',
        'grants',
      ]) {
        _db.execute('DELETE FROM $table WHERE profile=? AND universe=?', [
          profile.value,
          universe.value,
        ]);
      }
      _db.execute(
        "INSERT INTO audit(actor,action,target) VALUES(?,'withdraw_grant',?)",
        [actor.value, '${profile.value}:${universe.value}'],
      );
    });
  }

  BigInt validationAuthoritySequence(ProfileId profile, UniverseId universe) {
    _ensureOpen();
    final row = _db.select(
      "SELECT coalesce(max(sequence),0) AS sequence FROM audit WHERE (action IN ('grant_scope','withdraw_grant') AND target=?) OR (action='revoke' AND target=?)",
      ['${profile.value}:${universe.value}', profile.value],
    ).single;
    return BigInt.from(row['sequence'] as int);
  }

  InstallationProfile _activeProfile(ProfileId id) {
    final current = profile(id);
    if (current == null || current.revoked) {
      throw const InstallationException(InstallationFailure.denied);
    }
    return current;
  }

  GrantLimits limits(
    ProfileId profile,
    UniverseId universe,
    BigInt epochSeconds,
  ) {
    if (_activeProfile(profile).author) return GrantLimits();
    final limits = readGrant(profile, universe).limits;
    if (limits.expiresAt != null && limits.expiresAt! <= epochSeconds) {
      throw const InstallationException(InstallationFailure.denied);
    }
    return limits;
  }

  Set<WorldId>? universeScope(
    ProfileId profile,
    UniverseId universe,
    BigInt epochSeconds,
  ) {
    final current = _activeProfile(profile);
    if (_db.select('SELECT id FROM catalog WHERE id=?', [
      universe.value,
    ]).isEmpty) {
      throw const InstallationException(InstallationFailure.denied);
    }
    if (_db.select('SELECT universe FROM move_quiescence WHERE universe=?', [
      universe.value,
    ]).isNotEmpty) {
      throw const InstallationException(InstallationFailure.denied);
    }
    if (current.author) return null;
    limits(profile, universe, epochSeconds);
    final worlds = readGrant(profile, universe).worlds;
    return worlds == null ? null : Set<WorldId>.unmodifiable(worlds);
  }

  void authorizeWrite({
    required ProfileId profile,
    required UniverseId universe,
    required Set<WorldId> worlds,
    required bool shared,
    required bool protected,
    required bool commit,
    required BigInt epochSeconds,
  }) {
    final scope = universeScope(profile, universe, epochSeconds);
    if (_activeProfile(profile).author) return;
    final grant = readGrant(profile, universe);
    if ((!commit && !grant.propose) ||
        (commit && !grant.edit) ||
        (protected && !grant.protected) ||
        (scope != null &&
            (shared || worlds.isEmpty || !scope.containsAll(worlds)))) {
      throw const InstallationException(InstallationFailure.denied);
    }
    // Entity/predicate/continuity and delegated-publication checks belong to the
    // exact proposal footprint workflow, not this base world/permission gate.
  }
}
