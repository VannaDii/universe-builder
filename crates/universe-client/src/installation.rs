//! Authenticated persistent-engine client shared by desktop, MCP, and CLI.
use futures::{SinkExt, StreamExt};
use std::{
    io::Read,
    path::{Path, PathBuf},
    time::Duration,
};
use tokio::net::UnixStream;
use tokio_util::codec::{Framed, LengthDelimitedCodec};
use universe_domain::ids::ProfileId;
use universe_protocol::{installation::*, wire::decode, MAX_FRAME_BYTES, PROTOCOL_VERSION};
use universe_store::ownership::{private_dir, protected_file, FileLock};
pub struct EngineClient {
    io: Framed<UnixStream, LengthDelimitedCodec>,
    pub welcome: EngineWelcome,
    next: u64,
    broken: bool,
}
impl EngineClient {
    pub async fn connect(
        root: &Path,
        profile: &ProfileId,
        client_name: &str,
    ) -> anyhow::Result<Self> {
        let root = private_dir(root)?;
        let profiles = private_dir(&root.join("profiles"))?;
        let path = profiles.join(format!("{}.json", profile.as_str()));
        let mut file = protected_file(&path, false)?;
        anyhow::ensure!(file.metadata()?.len() <= 4096, "profile file too large");
        let mut bytes = Vec::new();
        file.read_to_end(&mut bytes)?;
        let loaded: ProfileFile =
            decode(&bytes).map_err(|_| anyhow::anyhow!("invalid protected profile"))?;
        anyhow::ensure!(
            loaded.format_version == 1 && loaded.profile_id == *profile,
            "profile identity mismatch"
        );
        use std::os::unix::fs::FileTypeExt;
        let endpoint = root.join("engine.sock");
        anyhow::ensure!(
            std::fs::symlink_metadata(&endpoint)?
                .file_type()
                .is_socket(),
            "unsafe engine endpoint"
        );
        let stream = UnixStream::connect(endpoint).await?;
        use std::os::unix::fs::MetadataExt;
        anyhow::ensure!(
            stream.peer_cred()?.uid() == std::fs::metadata(&root)?.uid(),
            "engine peer identity mismatch"
        );
        let mut io = Framed::new(
            stream,
            LengthDelimitedCodec::builder()
                .max_frame_length(MAX_FRAME_BYTES)
                .new_codec(),
        );
        let hello = EngineHello {
            protocol_version: PROTOCOL_VERSION.into(),
            profile_id: loaded.profile_id,
            credential: loaded.credential,
            client_name: client_name.into(),
        };
        tokio::time::timeout(
            Duration::from_secs(5),
            io.send(serde_json::to_vec(&hello)?.into()),
        )
        .await??;
        let bytes = tokio::time::timeout(Duration::from_secs(5), io.next())
            .await?
            .ok_or_else(|| anyhow::anyhow!("authentication rejected or engine closed"))??;
        let welcome: EngineWelcome = decode(&bytes).map_err(anyhow::Error::msg)?;
        anyhow::ensure!(
            welcome.protocol_version == PROTOCOL_VERSION
                && welcome.principal == hello.profile_id
                && welcome.max_frame_bytes == MAX_FRAME_BYTES
                && welcome.max_in_flight == 8,
            "incompatible engine handshake"
        );
        Ok(Self {
            io,
            welcome,
            next: 1,
            broken: false,
        })
    }
    pub async fn call(&mut self, request: EngineRequest) -> anyhow::Result<serde_json::Value> {
        anyhow::ensure!(
            !self.broken,
            "connection requires reconnect after interrupted request"
        );
        let id = self.next;
        self.next += 1;
        let message = serde_json::to_vec(&EngineCall { id, request })?;
        anyhow::ensure!(message.len() <= MAX_FRAME_BYTES, "request frame too large");
        self.broken = true;
        let reply = tokio::time::timeout(Duration::from_secs(15), async {
            self.io.send(message.into()).await?;
            let bytes = self.io.next().await.ok_or_else(|| {
                anyhow::anyhow!("engine disconnected; inspect operation outcome before retry")
            })??;
            let reply: EngineReply = decode(&bytes).map_err(anyhow::Error::msg)?;
            anyhow::ensure!(reply.id == id, "response correlation mismatch");
            Ok::<_, anyhow::Error>(reply)
        })
        .await??;
        self.broken = false;
        reply.result.map_err(Into::into)
    }
    pub async fn ensure_running(
        root: &Path,
        profile: &ProfileId,
        helper: &Path,
        client_name: &str,
    ) -> anyhow::Result<Self> {
        match Self::connect(root, profile, client_name).await {
            Ok(c) => return Ok(c),
            Err(e) if unavailable(&e) => {}
            Err(e) => return Err(e),
        }
        let root = private_dir(root)?;
        let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
        let lock = loop {
            match FileLock::acquire(&root.join("bootstrap.lock")) {
                Ok(l) => break l,
                Err(_) if tokio::time::Instant::now() < deadline => {
                    tokio::time::sleep(Duration::from_millis(50)).await
                }
                Err(e) => return Err(e.into()),
            }
        };
        match Self::connect(&root, profile, client_name).await {
            Ok(c) => return Ok(c),
            Err(e) if unavailable(&e) => {}
            Err(e) => return Err(e),
        }
        let helper = helper.canonicalize()?;
        anyhow::ensure!(
            helper.is_absolute()
                && helper.is_file()
                && helper.file_name().is_some_and(|n| n == "universe-engine"),
            "installed engine helper required"
        );
        let mut child = std::process::Command::new(helper)
            .arg("--installation")
            .arg(&root)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()?;
        loop {
            match Self::connect(&root, profile, client_name).await {
                Ok(c) => {
                    drop(lock);
                    return Ok(c);
                }
                Err(e) if unavailable(&e) => {}
                Err(e) => return Err(e),
            }
            anyhow::ensure!(
                child.try_wait()?.is_none(),
                "engine startup failed; run doctor"
            );
            anyhow::ensure!(
                tokio::time::Instant::now() < deadline,
                "engine startup deadline exceeded"
            );
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    }
}
fn unavailable(e: &anyhow::Error) -> bool {
    e.downcast_ref::<std::io::Error>().is_some_and(|e| {
        matches!(
            e.kind(),
            std::io::ErrorKind::NotFound | std::io::ErrorKind::ConnectionRefused
        )
    })
}
pub fn sibling_engine() -> anyhow::Result<PathBuf> {
    // macOS can retain the invoked Homebrew symlink in current_exe(). Resolve it
    // before locating the sealed app and its sibling helpers.
    let executable = std::env::current_exe()?.canonicalize()?;
    // Packaged clients refuse altered bundles before selecting a bundled helper.
    // Loose developer binaries retain the explicit sibling-path development mode.
    if let Some(app) = executable
        .ancestors()
        .find(|p| p.extension().is_some_and(|e| e == "app"))
    {
        anyhow::ensure!(
            app.join("Contents/Resources/release-manifest.json")
                .is_file(),
            "package manifest missing"
        );
        #[cfg(target_os = "macos")]
        anyhow::ensure!(
            std::process::Command::new("/usr/bin/codesign")
                .args(["--verify", "--deep", "--strict"])
                .arg(app)
                .output()?
                .status
                .success(),
            "bundle integrity verification failed"
        );
    }
    Ok(executable
        .parent()
        .ok_or_else(|| anyhow::anyhow!("executable parent missing"))?
        .join("universe-engine"))
}
