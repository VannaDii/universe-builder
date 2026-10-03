//! Installation-only authority state. Never part of a universe export.
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeSet,
    io::Write,
    path::{Path, PathBuf},
};
use universe_domain::ids::*;
use universe_protocol::installation::*;
use universe_store::{
    ownership::{private_dir, protected_file},
    selector::selector_key,
};
fn denied() -> anyhow::Error {
    anyhow::anyhow!("not found or not accessible")
}
#[derive(Clone)]
pub struct Principal {
    pub id: ProfileId,
    pub author: bool,
}
pub struct Registry {
    db: rusqlite::Connection,
    pub root: PathBuf,
}
impl Registry {
    pub fn open(root: &Path) -> anyhow::Result<Self> {
        let root = private_dir(root)?;
        private_dir(&root.join("profiles"))?;
        private_dir(&root.join("packages"))?;
        let db_path = root.join("installation.sqlite");
        protected_file(&db_path, true)?;
        let db = rusqlite::Connection::open(db_path)?;
        db.busy_timeout(std::time::Duration::from_secs(2))?;
        let version: i64 = db.query_row("PRAGMA user_version", [], |r| r.get(0))?;
        anyhow::ensure!(
            (0..=2).contains(&version),
            "unsupported installation schema version"
        );
        db.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; BEGIN IMMEDIATE;
        CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS profiles(id TEXT PRIMARY KEY,hash TEXT NOT NULL,author INTEGER NOT NULL,revoked INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS catalog(id TEXT PRIMARY KEY,name TEXT NOT NULL,path TEXT NOT NULL UNIQUE,device TEXT NOT NULL,inode TEXT NOT NULL,UNIQUE(device,inode));
        CREATE TABLE IF NOT EXISTS aliases(key TEXT PRIMARY KEY,universe TEXT NOT NULL REFERENCES catalog(id));
        CREATE TABLE IF NOT EXISTS grants(profile TEXT NOT NULL REFERENCES profiles(id),universe TEXT NOT NULL REFERENCES catalog(id),worlds TEXT,propose INTEGER NOT NULL,edit INTEGER NOT NULL,protected INTEGER NOT NULL,PRIMARY KEY(profile,universe));
        CREATE TABLE IF NOT EXISTS grant_limits(profile TEXT NOT NULL,universe TEXT NOT NULL,limits TEXT NOT NULL,PRIMARY KEY(profile,universe),FOREIGN KEY(profile,universe) REFERENCES grants(profile,universe));
        CREATE TABLE IF NOT EXISTS purge_pending(universe TEXT PRIMARY KEY,path TEXT NOT NULL,device TEXT NOT NULL,inode TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS audit(sequence INTEGER PRIMARY KEY,actor TEXT NOT NULL,action TEXT NOT NULL,target TEXT NOT NULL);")?;
        let version: Option<String> = db
            .query_row(
                "SELECT value FROM settings WHERE key='normalization'",
                [],
                |r| r.get(0),
            )
            .optional()?;
        if version
            .as_deref()
            .is_some_and(|v| v != universe_store::selector::NORMALIZATION_VERSION)
        {
            anyhow::bail!("unsupported installation normalization version")
        }
        db.execute(
            "INSERT OR IGNORE INTO settings VALUES('normalization',?1)",
            [universe_store::selector::NORMALIZATION_VERSION],
        )?;
        db.execute_batch("PRAGMA user_version=2; COMMIT;")?;
        let mut registry = Self { db, root };
        registry.finish_purges()?;
        Ok(registry)
    }
    pub fn initialize_author(&mut self) -> anyhow::Result<ProfileId> {
        let count: i64 = self
            .db
            .query_row("SELECT count(*) FROM profiles", [], |r| r.get(0))?;
        anyhow::ensure!(count == 0, "installation already enrolled");
        self.enroll_inner(None, true)
    }
    fn enroll_inner(
        &mut self,
        actor: Option<&Principal>,
        author: bool,
    ) -> anyhow::Result<ProfileId> {
        let id = ProfileId::generate(&mut rand::rng());
        let bytes: [u8; 32] = rand::random();
        let credential = hex::encode(bytes);
        let config = ProfileFile {
            format_version: 1,
            profile_id: id.clone(),
            credential: Credential::new(credential.clone()),
        };
        let path = self
            .root
            .join("profiles")
            .join(format!("{}.json", id.as_str()));
        // Write the credential before publishing its hash. An interrupted write
        // cannot create a usable enrolled identity with an unknown credential.
        use std::os::unix::fs::OpenOptionsExt;
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)?;
        file.write_all(&serde_json::to_vec(&config)?)?;
        file.sync_all()?;
        std::fs::File::open(path.parent().unwrap())?.sync_all()?;
        let tx = self.db.transaction()?;
        tx.execute(
            "INSERT INTO profiles(id,hash,author) VALUES(?1,?2,?3)",
            params![
                id.as_str(),
                hex::encode(Sha256::digest(credential.as_bytes())),
                author
            ],
        )?;
        tx.execute(
            "INSERT INTO audit(actor,action,target) VALUES(?1,'enroll',?2)",
            params![
                actor.map(|a| a.id.as_str()).unwrap_or("local-bootstrap"),
                id.as_str()
            ],
        )?;
        tx.commit()?;
        Ok(id)
    }
    pub fn authenticate(&self, hello: &EngineHello) -> anyhow::Result<Principal> {
        let row: Option<(String, bool, bool)> = self
            .db
            .query_row(
                "SELECT hash,author,revoked FROM profiles WHERE id=?1",
                [hello.profile_id.as_str()],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()?;
        let supplied = hex::encode(Sha256::digest(hello.credential.expose().as_bytes()));
        let (stored, author, revoked) = row.ok_or_else(denied)?;
        let diff = stored
            .bytes()
            .zip(supplied.bytes())
            .fold(0u8, |a, (b, c)| a | (b ^ c));
        if revoked || stored.len() != supplied.len() || diff != 0 {
            return Err(denied());
        }
        Ok(Principal {
            id: hello.profile_id.clone(),
            author,
        })
    }
    pub fn require_author(p: &Principal) -> anyhow::Result<()> {
        if !p.author {
            return Err(denied());
        }
        Ok(())
    }
    /// Approval authority belongs to this installation, never to package history.
    pub fn current_author(&self) -> anyhow::Result<ProfileId> {
        let id: String = self.db.query_row(
            "SELECT id FROM profiles WHERE author=1 AND revoked=0",
            [],
            |r| r.get(0),
        )?;
        Ok(ProfileId::parse(&id)?)
    }
    /// Existing append-only audit sequences fence validation against grant ABA.
    pub(crate) fn validation_authority_sequence(
        &self,
        profile: &ProfileId,
        universe: &UniverseId,
    ) -> anyhow::Result<i64> {
        Ok(self.db.query_row(
            "SELECT coalesce(max(sequence),0) FROM audit WHERE (action IN ('grant_scope','withdraw_grant') AND target=?1) OR (action='revoke' AND target=?2)",
            params![format!("{profile}:{universe}"), profile.as_str()], |r| r.get(0),
        )?)
    }
    pub fn enroll(&mut self, p: &Principal) -> anyhow::Result<ProfileId> {
        Self::require_author(p)?;
        self.enroll_inner(Some(p), false)
    }
    pub fn revoke(&mut self, p: &Principal, id: &ProfileId) -> anyhow::Result<()> {
        Self::require_author(p)?;
        anyhow::ensure!(p.id != *id, "cannot revoke current author");
        let tx = self.db.transaction()?;
        anyhow::ensure!(
            tx.execute(
                "UPDATE profiles SET revoked=1 WHERE id=?1 AND author=0",
                [id.as_str()]
            )? == 1,
            "profile unavailable"
        );
        tx.execute(
            "INSERT INTO audit(actor,action,target) VALUES(?1,'revoke',?2)",
            params![p.id.as_str(), id.as_str()],
        )?;
        tx.commit()?;
        Ok(())
    }
    pub fn profiles(&self, p: &Principal) -> anyhow::Result<serde_json::Value> {
        Self::require_author(p)?;
        let profiles=self.db.prepare("SELECT id,author,revoked FROM profiles ORDER BY id")?.query_map([],|r|Ok(serde_json::json!({"profile_id":r.get::<_,String>(0)?,"author":r.get::<_,bool>(1)?,"revoked":r.get::<_,bool>(2)?})))?.collect::<Result<Vec<_>,_>>()?;
        let mut grants = Vec::new();
        let rows=self.db.prepare("SELECT g.profile,g.universe,g.worlds,g.propose,g.edit,g.protected,l.limits FROM grants g LEFT JOIN grant_limits l ON g.profile=l.profile AND g.universe=l.universe ORDER BY g.profile,g.universe")?.query_map([],|r|Ok((r.get::<_,String>(0)?,r.get::<_,String>(1)?,r.get::<_,Option<String>>(2)?,r.get::<_,bool>(3)?,r.get::<_,bool>(4)?,r.get::<_,bool>(5)?,r.get::<_,Option<String>>(6)?)))?.collect::<Result<Vec<_>,_>>()?;
        for (profile, universe, worlds, propose, edit, protected, limits) in rows {
            grants.push(GrantSpec {
                profile_id: ProfileId::parse(&profile)?,
                universe_id: UniverseId::parse(&universe)?,
                worlds: worlds.map(|v| serde_json::from_str(&v)).transpose()?,
                propose,
                edit,
                protected,
                limits: limits
                    .map(|v| serde_json::from_str(&v))
                    .transpose()?
                    .unwrap_or_default(),
            });
        }
        Ok(serde_json::json!({"profiles":profiles,"grants":grants}))
    }
    pub fn withdraw_grant(
        &mut self,
        p: &Principal,
        profile: &ProfileId,
        universe: &UniverseId,
    ) -> anyhow::Result<()> {
        Self::require_author(p)?;
        let tx = self.db.transaction()?;
        tx.execute(
            "DELETE FROM grant_limits WHERE profile=?1 AND universe=?2",
            params![profile.as_str(), universe.as_str()],
        )?;
        tx.execute(
            "DELETE FROM grants WHERE profile=?1 AND universe=?2",
            params![profile.as_str(), universe.as_str()],
        )?;
        tx.execute(
            "INSERT INTO audit(actor,action,target) VALUES(?1,'withdraw_grant',?2)",
            params![p.id.as_str(), format!("{profile}:{universe}")],
        )?;
        tx.commit()?;
        Ok(())
    }
    pub fn begin_purge(&mut self, p: &Principal, u: &UniverseId) -> anyhow::Result<()> {
        Self::require_author(p)?;
        let tx = self.db.transaction()?;
        tx.execute(
            "INSERT INTO purge_pending SELECT id,path,device,inode FROM catalog WHERE id=?1",
            [u.as_str()],
        )?;
        tx.execute("DELETE FROM grant_limits WHERE universe=?1", [u.as_str()])?;
        tx.execute("DELETE FROM grants WHERE universe=?1", [u.as_str()])?;
        tx.execute("DELETE FROM aliases WHERE universe=?1", [u.as_str()])?;
        tx.execute("DELETE FROM catalog WHERE id=?1", [u.as_str()])?;
        tx.execute(
            "INSERT INTO audit(actor,action,target) VALUES(?1,'purge',?2)",
            params![p.id.as_str(), u.as_str()],
        )?;
        tx.commit()?;
        self.finish_purges()
    }
    fn finish_purges(&mut self) -> anyhow::Result<()> {
        use std::os::unix::fs::MetadataExt;
        let pending = self
            .db
            .prepare("SELECT universe,path,device,inode FROM purge_pending")?
            .query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, String>(3)?,
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        for (id, path, device, inode) in pending {
            match std::fs::symlink_metadata(&path) {
                Ok(meta) => {
                    anyhow::ensure!(
                        !meta.file_type().is_symlink()
                            && meta.nlink() == 1
                            && meta.dev().to_string() == device
                            && meta.ino().to_string() == inode,
                        "pending purge package identity changed"
                    );
                    std::fs::remove_file(&path)?;
                }
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                Err(e) => return Err(e.into()),
            }
            for suffix in ["-wal", "-shm"] {
                match std::fs::remove_file(format!("{path}{suffix}")) {
                    Ok(()) => {}
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                    Err(e) => return Err(e.into()),
                }
            }
            if let Some(parent) = Path::new(&path).parent() {
                std::fs::File::open(parent)?.sync_all()?;
            }
            self.db
                .execute("DELETE FROM purge_pending WHERE universe=?1", [id])?;
        }
        Ok(())
    }
    pub fn grant(&mut self, p: &Principal, grant: &GrantSpec) -> anyhow::Result<()> {
        Self::require_author(p)?;
        if let Some(worlds) = &grant.worlds {
            anyhow::ensure!(
                !worlds.is_empty() && worlds.len() <= 100,
                "invalid grant world set"
            )
        }
        let limits = &grant.limits;
        for size in [
            limits.entities.as_ref().map(Vec::len),
            limits.predicates.as_ref().map(Vec::len),
            limits.continuities.as_ref().map(Vec::len),
        ]
        .into_iter()
        .flatten()
        {
            anyhow::ensure!(
                (1..=100).contains(&size),
                "grant boundary must contain 1..100 identities"
            );
        }
        if limits.delegated_commit {
            anyhow::ensure!(grant.edit && limits.entities.is_some() && limits.predicates.is_some() && limits.continuities.is_some() && limits.expires_at.is_some(), "delegated commits require edit, entity, predicate, continuity and expiry boundaries");
        }
        anyhow::ensure!(
            limits.expires_at.is_none_or(|t| t > epoch()),
            "grant expiry must be in the future"
        );
        let worlds = grant
            .worlds
            .as_ref()
            .map(serde_json::to_string)
            .transpose()?;
        let tx = self.db.transaction()?;
        tx.execute("INSERT INTO grants VALUES(?1,?2,?3,?4,?5,?6) ON CONFLICT(profile,universe) DO UPDATE SET worlds=excluded.worlds,propose=excluded.propose,edit=excluded.edit,protected=excluded.protected",params![grant.profile_id.as_str(),grant.universe_id.as_str(),worlds,grant.propose,grant.edit,grant.protected])?;
        tx.execute("INSERT INTO grant_limits VALUES(?1,?2,?3) ON CONFLICT(profile,universe) DO UPDATE SET limits=excluded.limits",params![grant.profile_id.as_str(),grant.universe_id.as_str(),serde_json::to_string(limits)?])?;
        tx.execute(
            "INSERT INTO audit(actor,action,target) VALUES(?1,'grant',?2)",
            params![p.id.as_str(), grant.profile_id.as_str()],
        )?;
        tx.execute(
            "INSERT INTO audit(actor,action,target) VALUES(?1,'grant_scope',?2)",
            params![
                p.id.as_str(),
                format!("{}:{}", grant.profile_id, grant.universe_id)
            ],
        )?;
        tx.commit()?;
        Ok(())
    }
    pub fn limits(&self, p: &Principal, u: &UniverseId) -> anyhow::Result<GrantLimits> {
        if p.author {
            return Ok(GrantLimits::default());
        }
        let raw: Option<String> = self
            .db
            .query_row(
                "SELECT limits FROM grant_limits WHERE profile=?1 AND universe=?2",
                params![p.id.as_str(), u.as_str()],
                |r| r.get(0),
            )
            .optional()?;
        let limits: GrantLimits = raw
            .map(|s| serde_json::from_str(&s))
            .transpose()?
            .unwrap_or_default();
        if limits.expires_at.is_some_and(|t| t <= epoch()) {
            return Err(denied());
        }
        Ok(limits)
    }
    pub fn scope(
        &self,
        p: &Principal,
        u: &UniverseId,
    ) -> anyhow::Result<Option<BTreeSet<WorldId>>> {
        let exists: bool = self.db.query_row(
            "SELECT EXISTS(SELECT 1 FROM catalog WHERE id=?1)",
            [u.as_str()],
            |r| r.get(0),
        )?;
        if !exists {
            return Err(denied());
        }
        if p.author {
            return Ok(None);
        }
        self.limits(p, u)?;
        let worlds: Option<String> = self
            .db
            .query_row(
                "SELECT worlds FROM grants WHERE profile=?1 AND universe=?2",
                params![p.id.as_str(), u.as_str()],
                |r| r.get(0),
            )
            .optional()?
            .ok_or_else(denied)?;
        worlds
            .map(|v| serde_json::from_str(&v).map_err(Into::into))
            .transpose()
    }
    pub fn write_permissions(
        &self,
        p: &Principal,
        u: &UniverseId,
    ) -> anyhow::Result<(bool, bool, bool)> {
        if p.author {
            return Ok((true, true, true));
        }
        Ok(self.db.query_row(
            "SELECT propose,edit,protected FROM grants WHERE profile=?1 AND universe=?2",
            params![p.id.as_str(), u.as_str()],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )?)
    }
    /// Called under the same authority gate as a future final commit. World
    /// omission never expands a stored grant; shared writes require universe scope.
    pub fn authorize_write(
        &self,
        p: &Principal,
        u: &UniverseId,
        worlds: &BTreeSet<WorldId>,
        shared: bool,
        protected: bool,
        commit: bool,
    ) -> anyhow::Result<()> {
        let scope = self.scope(p, u)?;
        if p.author {
            return Ok(());
        }
        let (propose, edit, allow_protected): (bool, bool, bool) = self.db.query_row(
            "SELECT propose,edit,protected FROM grants WHERE profile=?1 AND universe=?2",
            params![p.id.as_str(), u.as_str()],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )?;
        if (!commit && !propose)
            || (commit && !edit)
            || (protected && !allow_protected)
            || scope
                .as_ref()
                .is_some_and(|allowed| shared || worlds.is_empty() || !worlds.is_subset(allowed))
        {
            return Err(denied());
        }
        Ok(())
    }
    pub fn register(
        &mut self,
        p: &Principal,
        id: &UniverseId,
        name: &str,
        path: &Path,
    ) -> anyhow::Result<()> {
        Self::require_author(p)?;
        let key = selector_key(name)?;
        let path = path.canonicalize()?;
        use std::os::unix::fs::MetadataExt;
        let meta = std::fs::metadata(&path)?;
        anyhow::ensure!(
            meta.is_file() && meta.nlink() == 1,
            "package alias is unsafe"
        );
        let tx = self.db.transaction()?;
        tx.execute(
            "INSERT INTO catalog VALUES(?1,?2,?3,?4,?5)",
            params![
                id.as_str(),
                name,
                path.to_str().ok_or_else(denied)?,
                meta.dev().to_string(),
                meta.ino().to_string()
            ],
        )?;
        tx.execute(
            "INSERT INTO aliases VALUES(?1,?2)",
            params![key, id.as_str()],
        )?;
        tx.execute(
            "INSERT INTO audit(actor,action,target) VALUES(?1,'register',?2)",
            params![p.id.as_str(), id.as_str()],
        )?;
        tx.commit()?;
        Ok(())
    }
    pub fn import_conflicts(&self, id: &UniverseId, name: &str) -> anyhow::Result<Vec<String>> {
        let mut conflicts = Vec::new();
        if self.db.query_row(
            "SELECT EXISTS(SELECT 1 FROM catalog WHERE id=?1)",
            [id.as_str()],
            |r| r.get::<_, bool>(0),
        )? {
            conflicts.push("Universe identity already registered; choose a named clone".into());
        }
        if self.db.query_row(
            "SELECT EXISTS(SELECT 1 FROM aliases WHERE key=?1)",
            [selector_key(name)?],
            |r| r.get::<_, bool>(0),
        )? {
            conflicts.push("Universe name or alias is already reserved".into());
        }
        Ok(conflicts)
    }
    pub fn rename(&mut self, p: &Principal, id: &UniverseId, name: &str) -> anyhow::Result<()> {
        Self::require_author(p)?;
        let key = selector_key(name)?;
        let tx = self.db.transaction()?;
        let owner: Option<String> = tx
            .query_row("SELECT universe FROM aliases WHERE key=?1", [&key], |r| {
                r.get(0)
            })
            .optional()?;
        anyhow::ensure!(
            owner.as_deref().is_none_or(|u| u == id.as_str()),
            "selector name unavailable"
        );
        anyhow::ensure!(
            tx.execute(
                "UPDATE catalog SET name=?2 WHERE id=?1",
                params![id.as_str(), name]
            )? == 1,
            "universe unavailable"
        );
        tx.execute(
            "INSERT OR IGNORE INTO aliases VALUES(?1,?2)",
            params![key, id.as_str()],
        )?;
        tx.execute(
            "INSERT INTO audit(actor,action,target) VALUES(?1,'rename',?2)",
            params![p.id.as_str(), id.as_str()],
        )?;
        tx.commit()?;
        Ok(())
    }
    pub fn resolve(&self, p: &Principal, name: &str) -> anyhow::Result<CatalogEntry> {
        let key = selector_key(name)?;
        let entry=self.db.query_row("SELECT c.id,c.name,c.path,c.device,c.inode FROM catalog c JOIN aliases a ON a.universe=c.id WHERE a.key=?1",[key],|r|Ok((r.get::<_,String>(0)?,r.get::<_,String>(1)?,r.get::<_,String>(2)?,r.get::<_,String>(3)?,r.get::<_,String>(4)?))).optional()?.ok_or_else(denied)?;
        let id = UniverseId::parse(&entry.0)?;
        self.scope(p, &id)?;
        use std::os::unix::fs::MetadataExt;
        let m = std::fs::symlink_metadata(&entry.2)?;
        anyhow::ensure!(
            !m.file_type().is_symlink()
                && m.nlink() == 1
                && m.dev().to_string() == entry.3
                && m.ino().to_string() == entry.4,
            "registered package identity changed"
        );
        Ok(CatalogEntry {
            universe_id: id,
            name: entry.1,
            path: PathBuf::from(entry.2),
        })
    }
    pub fn catalog(&self, p: &Principal) -> anyhow::Result<Vec<CatalogEntry>> {
        let rows: Vec<(String, String, String)> = self
            .db
            .prepare("SELECT id,name,path FROM catalog ORDER BY name LIMIT 1001")?
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
            .collect::<Result<_, _>>()?;
        anyhow::ensure!(rows.len() <= 1000, "catalog limit exceeded");
        let mut entries = Vec::new();
        for (id, name, path) in rows {
            let universe_id = UniverseId::parse(&id)?;
            if self.scope(p, &universe_id).is_ok() {
                entries.push(CatalogEntry {
                    universe_id,
                    name,
                    path: PathBuf::from(path),
                })
            }
        }
        Ok(entries)
    }
}
#[derive(Clone, Serialize, Deserialize)]
pub struct CatalogEntry {
    pub universe_id: UniverseId,
    pub name: String,
    pub path: PathBuf,
}

fn epoch() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("clock after epoch")
        .as_secs()
}
