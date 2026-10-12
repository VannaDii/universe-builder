-- Separate installation.sqlite. Never import this from a universe package/export.
PRAGMA foreign_keys=ON;
CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT;
CREATE TABLE profiles(id TEXT PRIMARY KEY, hash TEXT NOT NULL, author INTEGER NOT NULL CHECK(author IN(0,1)), revoked INTEGER NOT NULL CHECK(revoked IN(0,1))) STRICT;
CREATE TABLE catalog(id TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE, device TEXT NOT NULL, inode TEXT NOT NULL, UNIQUE(device,inode)) STRICT;
CREATE TABLE move_quiescence(universe TEXT PRIMARY KEY REFERENCES catalog(id) ON DELETE CASCADE, operation TEXT NOT NULL UNIQUE, target_instance TEXT NOT NULL) STRICT;
CREATE TABLE move_review(operation TEXT PRIMARY KEY REFERENCES move_quiescence(operation) ON DELETE CASCADE, preview_id TEXT NOT NULL, owner TEXT NOT NULL, name TEXT NOT NULL, source_digest TEXT NOT NULL, records INTEGER NOT NULL CHECK(records>=0), preview_digest TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN('reviewed','admitting','admitted'))) STRICT;
CREATE TABLE aliases(key TEXT PRIMARY KEY, universe TEXT NOT NULL REFERENCES catalog(id)) STRICT;
CREATE TABLE grants(profile TEXT NOT NULL REFERENCES profiles(id), universe TEXT NOT NULL REFERENCES catalog(id),
 worlds_state TEXT NOT NULL CHECK(worlds_state IN('all','listed')), propose INTEGER NOT NULL CHECK(propose IN(0,1)), edit INTEGER NOT NULL CHECK(edit IN(0,1)), protected INTEGER NOT NULL CHECK(protected IN(0,1)),
 entities_state TEXT NOT NULL CHECK(entities_state IN('all','listed')), predicates_state TEXT NOT NULL CHECK(predicates_state IN('all','listed')), continuities_state TEXT NOT NULL CHECK(continuities_state IN('all','listed')),
 expires_at TEXT, delegated_commit INTEGER NOT NULL CHECK(delegated_commit IN(0,1)), allow_shared INTEGER NOT NULL CHECK(allow_shared IN(0,1)), PRIMARY KEY(profile,universe)) STRICT;
CREATE TABLE grant_worlds(profile TEXT NOT NULL, universe TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), world TEXT NOT NULL, PRIMARY KEY(profile,universe,ordinal), FOREIGN KEY(profile,universe) REFERENCES grants(profile,universe)) STRICT;
CREATE TABLE grant_entities(profile TEXT NOT NULL, universe TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), entity TEXT NOT NULL, PRIMARY KEY(profile,universe,ordinal), FOREIGN KEY(profile,universe) REFERENCES grants(profile,universe)) STRICT;
CREATE TABLE grant_predicates(profile TEXT NOT NULL, universe TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), predicate TEXT NOT NULL, PRIMARY KEY(profile,universe,ordinal), FOREIGN KEY(profile,universe) REFERENCES grants(profile,universe)) STRICT;
CREATE TABLE grant_continuities(profile TEXT NOT NULL, universe TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), continuity TEXT NOT NULL, PRIMARY KEY(profile,universe,ordinal), FOREIGN KEY(profile,universe) REFERENCES grants(profile,universe)) STRICT;
CREATE TABLE purge_pending(universe TEXT PRIMARY KEY, path TEXT NOT NULL, device TEXT NOT NULL, inode TEXT NOT NULL) STRICT;
CREATE TABLE audit(sequence INTEGER PRIMARY KEY, actor TEXT NOT NULL, action TEXT NOT NULL, target TEXT NOT NULL) STRICT;
CREATE TABLE import_preview(id TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES profiles(id), source_digest TEXT NOT NULL, target TEXT NOT NULL, source TEXT NOT NULL, name TEXT NOT NULL, complete INTEGER NOT NULL CHECK(complete IN(0,1)), omitted_records INTEGER NOT NULL, records INTEGER NOT NULL, includes_workflow INTEGER NOT NULL CHECK(includes_workflow IN(0,1)), preview_digest TEXT NOT NULL, staged_path TEXT NOT NULL) STRICT;
CREATE TABLE archive_upload(id TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES profiles(id), source_digest TEXT NOT NULL, bytes INTEGER NOT NULL CHECK(bytes>0 AND bytes<=8589934592)) STRICT;
CREATE TABLE archive_upload_chunk(upload TEXT NOT NULL REFERENCES archive_upload(id) ON DELETE CASCADE, ordinal INTEGER NOT NULL CHECK(ordinal>=0 AND ordinal<32768), content BLOB NOT NULL CHECK(length(content)>0 AND length(content)<=262144), PRIMARY KEY(upload,ordinal)) STRICT;
-- A separate protected per-profile credential.sqlite (0600, directory 0700):
-- credential(profile_id TEXT PK, credential TEXT NOT NULL).
-- Preserve credential and hash exactly; never include them in exports/proof output.
