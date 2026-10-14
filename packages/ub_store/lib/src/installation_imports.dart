part of 'installation_store.dart';

/// Installation-owned exact review. It carries no inherited universe authority.
final class InstallationImportPreview {
  const InstallationImportPreview({
    required this.id,
    required this.owner,
    required this.sourceDigest,
    required this.target,
    required this.source,
    required this.name,
    required this.complete,
    required this.omittedRecords,
    required this.records,
    required this.includesWorkflow,
  });
  factory InstallationImportPreview.fromCanonical(CanonicalValue value) {
    final f = WireFields(value, {
      'id',
      'owner',
      'source_digest',
      'target',
      'source',
      'name',
      'complete',
      'omitted_records',
      'records',
      'includes_workflow',
    });
    return InstallationImportPreview(
      id: OperationId.parse(f.string('id')),
      owner: ProfileId.parse(f.string('owner')),
      sourceDigest: f.string('source_digest'),
      target: UniverseId.parse(f.string('target')),
      source: UniverseId.parse(f.string('source')),
      name: f.string('name'),
      complete: f.boolean('complete'),
      omittedRecords: f.u64('omitted_records').toInt(),
      records: f.u64('records').toInt(),
      includesWorkflow: f.boolean('includes_workflow'),
    );
  }
  final OperationId id;
  final ProfileId owner;
  final String sourceDigest;
  final UniverseId target, source;
  final String name;
  final bool complete, includesWorkflow;
  final int omittedRecords, records;

  CanonicalObject toCanonical() => CanonicalObject([
    MapEntry('id', CanonicalString(id.value)),
    MapEntry('owner', CanonicalString(owner.value)),
    MapEntry('source_digest', CanonicalString(sourceDigest)),
    MapEntry('target', CanonicalString(target.value)),
    MapEntry('source', CanonicalString(source.value)),
    MapEntry('name', CanonicalString(name)),
    MapEntry('complete', CanonicalBool(complete)),
    MapEntry('omitted_records', CanonicalNumber('$omittedRecords')),
    MapEntry('records', CanonicalNumber('$records')),
    MapEntry('includes_workflow', CanonicalBool(includesWorkflow)),
  ]);
  String get digest => canonicalDigest(toCanonical());
  String archivePath(String root) => '$root/imports/${id.value}.sqlite';
  CanonicalObject report(List<String> conflicts) => CanonicalObject([
    MapEntry('preview_id', CanonicalString(id.value)),
    MapEntry('digest', CanonicalString(digest)),
    MapEntry('source_universe', CanonicalString(source.value)),
    MapEntry('target_universe', CanonicalString(target.value)),
    MapEntry('name', CanonicalString(name)),
    MapEntry('complete', CanonicalBool(complete)),
    MapEntry('omitted_records', CanonicalNumber('$omittedRecords')),
    MapEntry('record_count', CanonicalNumber('$records')),
    MapEntry('record_ids', CanonicalString('preserved within target universe')),
    MapEntry(
      'version_ids',
      CanonicalString('preserved within target universe'),
    ),
    MapEntry(
      'references',
      CanonicalString(
        'canonical references mapped to target; historical workflow bindings preserved as written',
      ),
    ),
    const MapEntry('includes_history', CanonicalBool(true)),
    MapEntry('includes_workflow', CanonicalBool(includesWorkflow)),
    MapEntry(
      'workflow_and_approvals',
      CanonicalString(
        includesWorkflow
            ? 'preserved as historical evidence; authority remains inactive'
            : 'omitted by canon-only export',
      ),
    ),
    const MapEntry('canonical', CanonicalBool(false)),
    MapEntry('conflicts', CanonicalArray(conflicts.map(CanonicalString.new))),
  ]);
  CanonicalObject get receipt => CanonicalObject([
    MapEntry('preview_id', CanonicalString(id.value)),
    MapEntry('digest', CanonicalString(digest)),
    MapEntry('universe_id', CanonicalString(target.value)),
    MapEntry('name', CanonicalString(name)),
    MapEntry('complete', CanonicalBool(complete)),
    MapEntry('omitted_records', CanonicalNumber('$omittedRecords')),
    const MapEntry('imported', CanonicalBool(true)),
  ]);
}

extension InstallationImports on SqliteInstallationStore {
  InstallationImportPreview prepareImport({
    required ProfileId actor,
    required String source,
    required String name,
    required ImportMode mode,
    OperationId? previewId,
    String? expectedDigest,
  }) {
    requireAuthor(actor);
    selectorKey(name);
    final directory = privateDirectory('$root/imports');
    final archive = OwnedSqliteDatabase.stageLogicalArchive(source, directory);
    try {
      if (expectedDigest != null && archive.digest != expectedDigest) {
        throw const ApprovalStaleError();
      }
      final f = WireFields(archive.manifest, {
        'format',
        'universe',
        'name',
        'complete',
        'omitted_records',
        'includes_history',
        'includes_workflow',
      });
      if (previewId != null) {
        final existing = _db.select(
          'SELECT preview_digest FROM import_preview WHERE id=? AND owner=?',
          [previewId.value, actor.value],
        );
        if (existing.isNotEmpty) {
          final retained = loadImport(
            actor: actor,
            id: previewId,
            digest: existing.single['preview_digest'] as String,
          );
          if (retained.sourceDigest != archive.digest ||
              retained.name != name ||
              (retained.source == retained.target) !=
                  (mode == ImportMode.restore)) {
            throw const ApprovalStaleError();
          }
          return retained;
        }
      }
      final sourceId = UniverseId.parse(f.string('universe'));
      final target = mode == ImportMode.restore
          ? sourceId
          : UniverseId.generate();
      final staged = archive.reconstruct(
        '$root/packages',
        target: target,
        name: name,
      );
      staged.close();
      final preview = InstallationImportPreview(
        id: previewId ?? OperationId.generate(),
        owner: actor,
        sourceDigest: archive.digest,
        target: target,
        source: sourceId,
        name: name,
        complete: f.boolean('complete'),
        omittedRecords: int.parse(
          (f.require('omitted_records') as CanonicalNumber).digits,
        ),
        records:
            archive.package.database
                    .select('SELECT count(*) AS n FROM record_identities')
                    .single['n']
                as int,
        includesWorkflow: f.boolean('includes_workflow'),
      );
      final path = preview.archivePath(root);
      final created =
          FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.notFound;
      if (created) {
        archive.persistReviewedSource(path);
      } else {
        // A crash can retain the deterministic upload archive before its
        // preview transaction commits. Recover only the same protected bytes.
        protectedFile(path);
        final retained = OwnedSqliteDatabase.stageLogicalArchive(
          path,
          directory,
        );
        try {
          if (retained.digest != archive.digest) {
            throw const ApprovalStaleError();
          }
        } finally {
          retained.close();
        }
      }
      try {
        _transaction(() {
          requireAuthor(actor);
          _db.execute(
            'INSERT INTO import_preview VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
            [
              preview.id.value,
              actor.value,
              preview.sourceDigest,
              target.value,
              sourceId.value,
              name,
              preview.complete ? 1 : 0,
              preview.omittedRecords,
              preview.records,
              preview.includesWorkflow ? 1 : 0,
              preview.digest,
              'imports/${preview.id.value}.sqlite',
            ],
          );
        });
      } on Object {
        if (created) {
          File(path).deleteSync();
          syncPrivateDirectory(directory);
        }
        rethrow;
      }
      return preview;
    } finally {
      archive.close();
    }
  }

  InstallationImportPreview loadImport({
    required ProfileId actor,
    required OperationId id,
    required String digest,
  }) {
    requireAuthor(actor);
    final rows = _db.select(
      'SELECT * FROM import_preview WHERE id=? AND owner=?',
      [id.value, actor.value],
    );
    if (rows.isEmpty) {
      throw const NotFoundOrNotAccessibleError(message: 'import preview');
    }
    final row = rows.single;
    final preview = InstallationImportPreview(
      id: OperationId.parse(row['id'] as String),
      owner: ProfileId.parse(row['owner'] as String),
      sourceDigest: row['source_digest'] as String,
      target: UniverseId.parse(row['target'] as String),
      source: UniverseId.parse(row['source'] as String),
      name: row['name'] as String,
      complete: row['complete'] == 1,
      omittedRecords: row['omitted_records'] as int,
      records: row['records'] as int,
      includesWorkflow: row['includes_workflow'] == 1,
    );
    selectorKey(preview.name);
    final relativePath = 'imports/${preview.id.value}.sqlite';
    final stagedPath = row['staged_path'] as String;
    // Older installations retained an absolute sandbox path. Never open that
    // path: the reviewed bytes are always resolved inside the current root and
    // checked against sourceDigest when admitted. iOS may move the app container.
    final knownStagingPath = stagedPath == relativePath ||
        stagedPath.replaceAll('\\', '/').endsWith('/$relativePath');
    if (preview.omittedRecords < 0 ||
        preview.records < 0 ||
        preview.digest != row['preview_digest'] ||
        !knownStagingPath) {
      throw const FormatException('Import preview integrity mismatch');
    }
    if (preview.digest != digest) throw const ApprovalStaleError();
    return preview;
  }
}
