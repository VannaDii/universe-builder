import 'dart:typed_data';

import 'package:postgres/postgres.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'installation_store.dart'
    show
        InstallationProfile,
        InstallationAuditEntry,
        InstallationException,
        InstallationFailure;
import 'postgres_authority_schema.dart';
import 'postgres_values.dart';

final class PostgresCatalogEntry {
  const PostgresCatalogEntry({
    required this.universeId,
    required this.name,
    required this.namespace,
  });
  final UniverseId universeId;
  final String name;
  final String namespace;
}

/// Internal authority operations within a caller-owned transaction. Every read
/// and mutation holds the installation singleton lock through final commit or
/// rollback, before acquiring any universe lock. This covers absent grant rows
/// as well as replacement/withdrawal and revocation across service processes.
/// No Connection or credentials are exposed; exceptions escape the owning
/// transaction so mutation and administration audit always commit together.
final class PostgresInstallationAuthority {
  PostgresInstallationAuthority(this._session, this.instanceId)
    : _schema = postgresAuthorityNamespace(instanceId);
  final TxSession _session;
  final OperationId instanceId;
  final String _schema;
  bool _locked = false;

  Future<void> lockAuthority() async {
    if (_locked) return;
    final rows = await _rows(
      'SELECT instance_id,normalization,schema_version FROM $_schema.authority WHERE singleton=1 FOR UPDATE',
      [],
    );
    if (rows.length != 1 ||
        rows.single['instance_id'] != instanceId.value ||
        rows.single['normalization'] != selectorNormalizationVersion ||
        rows.single['schema_version'] != 5) {
      throw const InstallationException(InstallationFailure.incompatibleSchema);
    }
    _locked = true;
  }

  Future<InstallationProfile?> profile(ProfileId id) async {
    await lockAuthority();
    final rows = await _rows(
      'SELECT id,hash,author,revoked FROM $_schema.profiles WHERE id=\$1',
      [id.value],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final hash = row['hash'] as String;
    if (hash.length != 64 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const InstallationException(InstallationFailure.incompatibleSchema);
    }
    return InstallationProfile(
      id: ProfileId.parse(row['id'] as String),
      credentialHash: hash,
      author: row['author'] as bool,
      revoked: row['revoked'] as bool,
    );
  }

  Future<void> requireAuthor(ProfileId id) async {
    final actor = await profile(id);
    if (actor == null || actor.revoked || !actor.author) {
      throw const InstallationException(InstallationFailure.denied);
    }
  }

  Future<InstallationProfile> _activeProfile(ProfileId id) async {
    final current = await profile(id);
    if (current == null || current.revoked) {
      throw const InstallationException(InstallationFailure.denied);
    }
    return current;
  }

  Future<bool> get hasProfiles async {
    await lockAuthority();
    return (await _rows(
          'SELECT count(*) AS n FROM $_schema.profiles',
          [],
        )).single['n'] !=
        0;
  }

  Future<ProfileId> currentAuthor() async {
    await lockAuthority();
    final rows = await _rows(
      'SELECT id FROM $_schema.profiles WHERE author AND NOT revoked ORDER BY id',
      [],
    );
    if (rows.isEmpty) {
      throw const InstallationException(InstallationFailure.denied);
    }
    return ProfileId.parse(rows.first['id'] as String);
  }

  Future<void> enroll({
    required ProfileId id,
    required String credentialHash,
    ProfileId? actor,
  }) async {
    if (credentialHash.length != 64 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(credentialHash)) {
      throw const InstallationException(InstallationFailure.incompatibleSchema);
    }
    await lockAuthority();
    if (actor == null) {
      if (await hasProfiles) {
        throw const InstallationException(InstallationFailure.alreadyEnrolled);
      }
    } else {
      await requireAuthor(actor);
    }
    await _execute('INSERT INTO $_schema.profiles VALUES(\$1,\$2,\$3,FALSE)', [
      id.value,
      credentialHash,
      actor == null,
    ]);
    await _audit(actor?.value ?? 'local-bootstrap', 'enroll', id.value);
  }

  Future<void> revoke({
    required ProfileId actor,
    required ProfileId target,
  }) async {
    await requireAuthor(actor);
    if (actor == target) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final result = await _session.execute(
      'UPDATE $_schema.profiles SET revoked=TRUE WHERE id=\$1 AND NOT author',
      parameters: [target.value],
    );
    if (result.affectedRows != 1) {
      throw const InstallationException(InstallationFailure.denied);
    }
    await _audit(actor.value, 'revoke', target.value);
  }

  Future<List<InstallationProfile>> profiles(ProfileId actor) async {
    await requireAuthor(actor);
    return List.unmodifiable([
      for (final row in await _rows(
        'SELECT id FROM $_schema.profiles ORDER BY id',
        [],
      ))
        (await profile(ProfileId.parse(row['id'] as String)))!,
    ]);
  }

  Future<List<InstallationAuditEntry>> audit(ProfileId actor) async {
    await requireAuthor(actor);
    return List.unmodifiable([
      for (final row in await _rows(
        'SELECT sequence,actor,action,target FROM $_schema.audit ORDER BY sequence',
        [],
      ))
        InstallationAuditEntry(
          sequence: BigInt.from(row['sequence'] as int),
          actor: row['actor'] as String,
          action: row['action'] as String,
          target: row['target'] as String,
        ),
    ]);
  }

  Future<void> _audit(String actor, String action, String target) => _execute(
    'INSERT INTO $_schema.audit SELECT coalesce(max(sequence),0)+1,\$1,\$2,\$3 FROM $_schema.audit',
    [actor, action, target],
  );

  Future<void> registerUniverse({
    required ProfileId actor,
    required UniverseId universe,
    required String name,
  }) async {
    await requireAuthor(actor);
    final key = selectorKey(name);
    final location = postgresUniverseSchema(universe);
    final actual = await _rows(
      'SELECT id FROM $location.universes WHERE singleton=1',
      [],
    );
    if (actual.length != 1 || actual.single['id'] != universe.value) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final conflict = await _rows(
      'SELECT universe FROM $_schema.aliases WHERE key=\$1',
      [key],
    );
    if (conflict.isNotEmpty && conflict.single['universe'] != universe.value) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final namespace = location.substring(1, location.length - 1);
    await _execute('INSERT INTO $_schema.catalog VALUES(\$1,\$2,\$3)', [
      universe.value,
      postgresAuthoredText(name),
      namespace,
    ]);
    await _execute(
      'INSERT INTO $_schema.aliases VALUES(\$1,\$2) ON CONFLICT DO NOTHING',
      [key, universe.value],
    );
    await _audit(actor.value, 'register', universe.value);
  }

  /// Retire current access and retained aliases in the caller's purge transaction.
  /// Universe bytes are removed by the same installation session before commit.
  Future<void> retireUniverse({
    required ProfileId actor,
    required UniverseId universe,
  }) async {
    await requireAuthor(actor);
    final rows = await _rows(
      'SELECT id,name,schema_name FROM $_schema.catalog WHERE id=\$1',
      [universe.value],
    );
    if (rows.isEmpty) {
      throw const InstallationException(InstallationFailure.denied);
    }
    _catalogEntry(rows.single);
    for (final table in [
      'grant_worlds',
      'grant_entities',
      'grant_predicates',
      'grant_continuities',
      'grants',
      'aliases',
      'catalog',
    ]) {
      final column = table == 'catalog' ? 'id' : 'universe';
      await _execute('DELETE FROM $_schema.$table WHERE $column=\$1', [
        universe.value,
      ]);
    }
    await _audit(actor.value, 'purge', universe.value);
  }

  Future<void> putGrant({
    required ProfileId actor,
    required GrantSpec grant,
    required BigInt epochSeconds,
  }) async {
    await requireAuthor(actor);
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
    await _execute(
      'INSERT INTO $_schema.grants VALUES(\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8,\$9,\$10,\$11,\$12) ON CONFLICT(profile,universe) DO UPDATE SET worlds_state=excluded.worlds_state,propose=excluded.propose,edit=excluded.edit,protected=excluded.protected,entities_state=excluded.entities_state,predicates_state=excluded.predicates_state,continuities_state=excluded.continuities_state,expires_at=excluded.expires_at,delegated_commit=excluded.delegated_commit,allow_shared=excluded.allow_shared',
      [
        grant.profileId.value,
        grant.universeId.value,
        state(grant.worlds),
        grant.propose,
        grant.edit,
        grant.protected,
        state(limits.entities),
        state(limits.predicates),
        state(limits.continuities),
        limits.expiresAt?.toString(),
        limits.delegatedCommit,
        limits.allowShared,
      ],
    );
    final collections = {
      'grant_worlds': grant.worlds?.map((v) => v.value).toList(),
      'grant_entities': limits.entities?.map((v) => v.value).toList(),
      'grant_predicates': limits.predicates?.map((v) => v.value).toList(),
      'grant_continuities': limits.continuities?.map((v) => v.value).toList(),
    };
    for (final entry in collections.entries) {
      await _execute(
        'DELETE FROM $_schema.${entry.key} WHERE profile=\$1 AND universe=\$2',
        [grant.profileId.value, grant.universeId.value],
      );
      final values = entry.value ?? const <String>[];
      for (var i = 0; i < values.length; i++) {
        await _execute(
          'INSERT INTO $_schema.${entry.key} VALUES(\$1,\$2,\$3,\$4)',
          [grant.profileId.value, grant.universeId.value, i, values[i]],
        );
      }
    }
    await _audit(actor.value, 'grant', grant.profileId.value);
    await _audit(
      actor.value,
      'grant_scope',
      '${grant.profileId.value}:${grant.universeId.value}',
    );
  }

  Future<void> renameUniverse({
    required ProfileId actor,
    required UniverseId id,
    required String name,
  }) async {
    await requireAuthor(actor);
    final key = selectorKey(name);
    final existing = await _rows(
      'SELECT universe FROM $_schema.aliases WHERE key=\$1',
      [key],
    );
    if (existing.isNotEmpty && existing.single['universe'] != id.value) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final updated = await _session.execute(
      'UPDATE $_schema.catalog SET name=\$1 WHERE id=\$2',
      parameters: [postgresAuthoredText(name), id.value],
    );
    if (updated.affectedRows != 1) {
      throw const InstallationException(InstallationFailure.denied);
    }
    await _execute(
      'INSERT INTO $_schema.aliases VALUES(\$1,\$2) ON CONFLICT DO NOTHING',
      [key, id.value],
    );
    await _audit(actor.value, 'rename', id.value);
  }

  Future<List<PostgresCatalogEntry>> catalog(
    ProfileId actor, {
    required BigInt epochSeconds,
  }) async {
    await _activeProfile(actor);
    final rows = await _rows(
      'SELECT id,name,schema_name FROM $_schema.catalog ORDER BY name LIMIT 1001',
      [],
    );
    if (rows.length > 1000) {
      throw const InstallationException(InstallationFailure.unavailable);
    }
    final entries = <PostgresCatalogEntry>[];
    for (final row in rows) {
      final entry = _catalogEntry(row);
      try {
        await universeScope(actor, entry.universeId, epochSeconds);
      } on Object {
        continue;
      }
      entries.add(entry);
    }
    return List.unmodifiable(entries);
  }

  Future<GrantSpec> readGrant(ProfileId profile, UniverseId universe) async {
    await lockAuthority();
    final rows = await _rows(
      'SELECT * FROM $_schema.grants WHERE profile=\$1 AND universe=\$2',
      [profile.value, universe.value],
    );
    if (rows.isEmpty) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final row = rows.single;
    Future<List<String>?> children(
      String state,
      String table,
      String column,
    ) async {
      if (state == 'all') return null;
      if (state != 'listed') {
        throw const InstallationException(InstallationFailure.denied);
      }
      return [
        for (final child in await _rows(
          'SELECT $column FROM $_schema.$table WHERE profile=\$1 AND universe=\$2 ORDER BY ordinal',
          [profile.value, universe.value],
        ))
          child[column] as String,
      ];
    }

    return GrantSpec(
      profileId: profile,
      universeId: universe,
      worlds: (await children(
        row['worlds_state'] as String,
        'grant_worlds',
        'world',
      ))?.map(WorldId.parse),
      propose: row['propose'] as bool,
      edit: row['edit'] as bool,
      protected: row['protected'] as bool,
      limits: GrantLimits(
        entities: (await children(
          row['entities_state'] as String,
          'grant_entities',
          'entity',
        ))?.map(RecordId.parse),
        predicates: (await children(
          row['predicates_state'] as String,
          'grant_predicates',
          'predicate',
        ))?.map(RecordId.parse),
        continuities: (await children(
          row['continuities_state'] as String,
          'grant_continuities',
          'continuity',
        ))?.map(ContinuityId.parse),
        expiresAt: row['expires_at'] == null
            ? null
            : BigInt.parse(row['expires_at'] as String),
        delegatedCommit: row['delegated_commit'] as bool,
        allowShared: row['allow_shared'] as bool,
      ),
    );
  }

  Future<List<GrantSpec>> grants(ProfileId actor) async {
    await requireAuthor(actor);
    return List.unmodifiable([
      for (final row in await _rows(
        'SELECT profile,universe FROM $_schema.grants ORDER BY profile,universe',
        [],
      ))
        await readGrant(
          ProfileId.parse(row['profile'] as String),
          UniverseId.parse(row['universe'] as String),
        ),
    ]);
  }

  Future<void> withdrawGrant({
    required ProfileId actor,
    required ProfileId profile,
    required UniverseId universe,
  }) async {
    await requireAuthor(actor);
    for (final table in [
      'grant_worlds',
      'grant_entities',
      'grant_predicates',
      'grant_continuities',
      'grants',
    ]) {
      await _execute(
        'DELETE FROM $_schema.$table WHERE profile=\$1 AND universe=\$2',
        [profile.value, universe.value],
      );
    }
    await _audit(
      actor.value,
      'withdraw_grant',
      '${profile.value}:${universe.value}',
    );
  }

  Future<BigInt> validationAuthoritySequence(
    ProfileId profile,
    UniverseId universe,
  ) async {
    await lockAuthority();
    final row = (await _rows(
      "SELECT coalesce(max(sequence),0) AS sequence FROM $_schema.audit WHERE (action IN ('grant_scope','withdraw_grant') AND target=\$1) OR (action='revoke' AND target=\$2)",
      ['${profile.value}:${universe.value}', profile.value],
    )).single;
    return BigInt.from(row['sequence'] as int);
  }

  Future<GrantLimits> limits(
    ProfileId profile,
    UniverseId universe,
    BigInt epochSeconds,
  ) async {
    if ((await _activeProfile(profile)).author) return GrantLimits();
    final limits = (await readGrant(profile, universe)).limits;
    if (limits.expiresAt != null && limits.expiresAt! <= epochSeconds) {
      throw const InstallationException(InstallationFailure.denied);
    }
    return limits;
  }

  /// Suspend this source without removing its catalog, aliases or grants.
  /// Exact retries bind to one target installation; no endpoint secrets are stored.
  Future<void> quiesceUniverseForMove({
    required ProfileId actor,
    required UniverseId universe,
    required OperationId operation,
    required OperationId targetInstance,
  }) async {
    await requireAuthor(actor);
    if (targetInstance == instanceId) {
      throw const FormatException('Move target must be another installation');
    }
    final catalog = await _rows(
      'SELECT id FROM $_schema.catalog WHERE id=\$1',
      [universe.value],
    );
    if (catalog.isEmpty) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final existing = await _rows(
      'SELECT operation,target_instance FROM $_schema.move_quiescence WHERE universe=\$1',
      [universe.value],
    );
    if (existing.isNotEmpty) {
      if (existing.single['operation'] != operation.value ||
          existing.single['target_instance'] != targetInstance.value) {
        throw const FormatException('Source is bound to another move');
      }
      return;
    }
    if ((await _rows(
      'SELECT universe FROM $_schema.move_quiescence WHERE operation=\$1',
      [operation.value],
    )).isNotEmpty) {
      throw const FormatException('Move operation belongs to another universe');
    }
    await _execute('INSERT INTO $_schema.move_quiescence VALUES(\$1,\$2,\$3)', [
      universe.value,
      operation.value,
      targetInstance.value,
    ]);
    await _audit(actor.value, 'quiesce_move', universe.value);
  }

  Future<Set<WorldId>?> universeScope(
    ProfileId profile,
    UniverseId universe,
    BigInt epochSeconds,
  ) async {
    final current = await _activeProfile(profile);
    if ((await _rows('SELECT id FROM $_schema.catalog WHERE id=\$1', [
      universe.value,
    ])).isEmpty) {
      throw const InstallationException(InstallationFailure.denied);
    }
    if ((await _rows(
      'SELECT universe FROM $_schema.move_quiescence WHERE universe=\$1',
      [universe.value],
    )).isNotEmpty) {
      throw const InstallationException(InstallationFailure.denied);
    }
    if (current.author) return null;
    await limits(profile, universe, epochSeconds);
    final worlds = (await readGrant(profile, universe)).worlds;
    return worlds == null ? null : Set.unmodifiable(worlds);
  }

  Future<void> authorizeWrite({
    required ProfileId profile,
    required UniverseId universe,
    required Set<WorldId> worlds,
    required bool shared,
    required bool protected,
    required bool commit,
    required BigInt epochSeconds,
  }) async {
    final scope = await universeScope(profile, universe, epochSeconds);
    if ((await _activeProfile(profile)).author) return;
    final grant = await readGrant(profile, universe);
    if ((!commit && !grant.propose) ||
        (commit && !grant.edit) ||
        (protected && !grant.protected) ||
        (scope != null &&
            (shared || worlds.isEmpty || !scope.containsAll(worlds)))) {
      throw const InstallationException(InstallationFailure.denied);
    }
    // Exact entity/predicate/continuity and delegated-publication checks remain
    // responsibilities of the proposal footprint workflow, as in SQLite.
  }

  Future<PostgresCatalogEntry> resolveUniverseAlias({
    required ProfileId actor,
    required String name,
    required BigInt epochSeconds,
  }) async {
    await _activeProfile(actor);
    final rows = await _rows(
      'SELECT c.id,c.name,c.schema_name FROM $_schema.catalog c JOIN $_schema.aliases a ON a.universe=c.id WHERE a.key=\$1',
      [selectorKey(name)],
    );
    if (rows.isEmpty) {
      throw const InstallationException(InstallationFailure.denied);
    }
    final entry = _catalogEntry(rows.single);
    await universeScope(actor, entry.universeId, epochSeconds);
    return entry;
  }

  PostgresCatalogEntry _catalogEntry(Map<String, dynamic> row) {
    final id = UniverseId.parse(row['id'] as String);
    final expected = postgresUniverseSchema(id);
    if (row['schema_name'] != expected.substring(1, expected.length - 1)) {
      throw const InstallationException(InstallationFailure.incompatibleSchema);
    }
    return PostgresCatalogEntry(
      universeId: id,
      name: readPostgresAuthoredText(row['name'] as Uint8List),
      namespace: row['schema_name'] as String,
    );
  }

  Future<void> _execute(String sql, List<Object?> parameters) async {
    await _session.execute(sql, parameters: parameters);
  }

  Future<List<Map<String, dynamic>>> _rows(
    String sql,
    List<Object?> parameters,
  ) async => (await _session.execute(
    sql,
    parameters: parameters,
  )).map((row) => row.toColumnMap()).toList();
}
