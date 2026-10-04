//! Installation-only authority state. Never part of a universe export.
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeSet,
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
        let initialized: bool = db.query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table')",
            [],
            |r| r.get(0),
        )?;
        if initialized {
            let relational: bool = db.query_row("SELECT EXISTS(SELECT 1 FROM pragma_table_info('grants') WHERE name='worlds_state')", [], |r| r.get(0))?;
            anyhow::ensure!(
                relational,
                "legacy installation requires explicit conversion (Goal 27)"
            );
        }
        if initialized {
            let preview_relational:bool=db.query_row("SELECT EXISTS(SELECT 1 FROM pragma_table_info('import_preview') WHERE name='includes_workflow')",[],|r|r.get(0))?;
            anyhow::ensure!(preview_relational,"installation requires explicit relational archive-preview conversion; original preserved");
        }
        db.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; BEGIN IMMEDIATE;")?;
        if !initialized {
            db.execute_batch(include_str!(
                "../../../docs/decisions/relational-storage/installation.sql"
            ))?;
        }
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
        db.execute_batch("COMMIT;")?;
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
        // Persist the exact private credential before publishing its hash.
        universe_store::credentials::write(&self.root, &id, &credential)?;
        let tx = self.db.transaction()?;
        tx.execute(
            "INSERT INTO profiles(id,hash,author,revoked) VALUES(?1,?2,?3,0)",
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
        let pairs = self
            .db
            .prepare("SELECT profile,universe FROM grants ORDER BY profile,universe")?
            .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
            .collect::<Result<Vec<_>, _>>()?;
        for (profile, universe) in pairs {
            grants.push(
                self.read_grant(&ProfileId::parse(&profile)?, &UniverseId::parse(&universe)?)?,
            );
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
        for table in [
            "grant_worlds",
            "grant_entities",
            "grant_predicates",
            "grant_continuities",
        ] {
            tx.execute(
                &format!("DELETE FROM {table} WHERE profile=?1 AND universe=?2"),
                params![profile.as_str(), universe.as_str()],
            )?;
        }
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
        for table in [
            "grant_worlds",
            "grant_entities",
            "grant_predicates",
            "grant_continuities",
        ] {
            tx.execute(
                &format!("DELETE FROM {table} WHERE universe=?1"),
                [u.as_str()],
            )?;
        }
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
        let state = |listed: bool| if listed { "listed" } else { "all" };
        let tx = self.db.transaction()?;
        tx.execute("INSERT INTO grants VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12) ON CONFLICT(profile,universe) DO UPDATE SET worlds_state=excluded.worlds_state,propose=excluded.propose,edit=excluded.edit,protected=excluded.protected,entities_state=excluded.entities_state,predicates_state=excluded.predicates_state,continuities_state=excluded.continuities_state,expires_at=excluded.expires_at,delegated_commit=excluded.delegated_commit,allow_shared=excluded.allow_shared",
            params![grant.profile_id.as_str(),grant.universe_id.as_str(),state(grant.worlds.is_some()),grant.propose,grant.edit,grant.protected,state(limits.entities.is_some()),state(limits.predicates.is_some()),state(limits.continuities.is_some()),limits.expires_at.map(|t| t.to_string()),limits.delegated_commit,limits.allow_shared])?;
        for (table, values) in [
            (
                "grant_worlds",
                grant
                    .worlds
                    .as_ref()
                    .map(|v| v.iter().map(ToString::to_string).collect::<Vec<_>>()),
            ),
            (
                "grant_entities",
                limits
                    .entities
                    .as_ref()
                    .map(|v| v.iter().map(ToString::to_string).collect()),
            ),
            (
                "grant_predicates",
                limits
                    .predicates
                    .as_ref()
                    .map(|v| v.iter().map(ToString::to_string).collect()),
            ),
            (
                "grant_continuities",
                limits
                    .continuities
                    .as_ref()
                    .map(|v| v.iter().map(ToString::to_string).collect()),
            ),
        ] {
            tx.execute(
                &format!("DELETE FROM {table} WHERE profile=?1 AND universe=?2"),
                params![grant.profile_id.as_str(), grant.universe_id.as_str()],
            )?;
            for (ordinal, value) in values.unwrap_or_default().iter().enumerate() {
                tx.execute(
                    &format!("INSERT INTO {table} VALUES(?1,?2,?3,?4)"),
                    params![
                        grant.profile_id.as_str(),
                        grant.universe_id.as_str(),
                        ordinal as i64,
                        value
                    ],
                )?;
            }
        }
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
        let limits = self.read_grant(&p.id, u)?.limits;
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
        Ok(self
            .read_grant(&p.id, u)?
            .worlds
            .map(|v| v.into_iter().collect()))
    }
    pub(crate) fn read_grant(
        &self,
        profile: &ProfileId,
        universe: &UniverseId,
    ) -> anyhow::Result<GrantSpec> {
        let (ws, propose, edit, protected, es, ps, cs, expiry, delegated_commit, allow_shared) = self.db.query_row(
            "SELECT worlds_state,propose,edit,protected,entities_state,predicates_state,continuities_state,expires_at,delegated_commit,allow_shared FROM grants WHERE profile=?1 AND universe=?2",
            params![profile.as_str(),universe.as_str()], |r| Ok((r.get::<_,String>(0)?,r.get::<_,bool>(1)?,r.get::<_,bool>(2)?,r.get::<_,bool>(3)?,r.get::<_,String>(4)?,r.get::<_,String>(5)?,r.get::<_,String>(6)?,r.get::<_,Option<String>>(7)?,r.get::<_,bool>(8)?,r.get::<_,bool>(9)?)))
            .optional()?.ok_or_else(denied)?;
        let children = |state: &str,
                        table: &str,
                        column: &str|
         -> anyhow::Result<Option<Vec<String>>> {
            match state {
                "all" => Ok(None),
                "listed" => Ok(Some(self.db.prepare(&format!("SELECT {column} FROM {table} WHERE profile=?1 AND universe=?2 ORDER BY ordinal"))?
                    .query_map(params![profile.as_str(),universe.as_str()], |r| r.get(0))?.collect::<Result<Vec<_>,_>>()?)),
                _ => Err(denied()),
            }
        };
        Ok(GrantSpec {
            profile_id: profile.clone(),
            universe_id: universe.clone(),
            propose,
            edit,
            protected,
            worlds: children(&ws, "grant_worlds", "world")?
                .map(|v| v.iter().map(|s| WorldId::parse(s)).collect())
                .transpose()?,
            limits: GrantLimits {
                entities: children(&es, "grant_entities", "entity")?
                    .map(|v| v.iter().map(|s| RecordId::parse(s)).collect())
                    .transpose()?,
                predicates: children(&ps, "grant_predicates", "predicate")?
                    .map(|v| v.iter().map(|s| RecordId::parse(s)).collect())
                    .transpose()?,
                continuities: children(&cs, "grant_continuities", "continuity")?
                    .map(|v| v.iter().map(|s| ContinuityId::parse(s)).collect())
                    .transpose()?,
                expires_at: expiry.map(|s| s.parse()).transpose()?,
                delegated_commit,
                allow_shared,
            },
        })
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
