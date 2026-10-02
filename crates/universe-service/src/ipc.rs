//! Private, bounded fixture transport. Production authentication is WP06.
use crate::fixture::Fixture;
use futures::{SinkExt, StreamExt};
use std::{
    collections::{HashMap, HashSet},
    path::Path,
    sync::Arc,
    time::Duration,
};
use tokio::{
    net::{UnixListener, UnixStream},
    sync::{Mutex, Semaphore},
    task::JoinSet,
};
use tokio_util::{
    codec::{Framed, LengthDelimitedCodec},
    sync::CancellationToken,
};
use universe_protocol::{wire::*, ProtocolError, MAX_FRAME_BYTES, MAX_IN_FLIGHT, PROTOCOL_VERSION};

pub async fn serve(path: &Path, shutdown: CancellationToken) -> anyhow::Result<()> {
    use std::os::unix::fs::{MetadataExt, PermissionsExt};
    let parent = path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("socket parent required"))?;
    let metadata = std::fs::symlink_metadata(parent)?;
    anyhow::ensure!(
        metadata.is_dir() && !metadata.file_type().is_symlink() && metadata.mode() & 0o077 == 0,
        "fixture socket needs an existing private directory (mode 0700)"
    );
    // Bind refuses an occupied name; never delete an existing server's socket.
    let listener = UnixListener::bind(path)?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    let inode = std::fs::symlink_metadata(path)?.ino();
    let _cleanup = SocketGuard {
        path: path.to_path_buf(),
        inode,
    };
    let state = Arc::new(Mutex::new(Fixture::new()));
    let connections = Arc::new(Semaphore::new(16));
    let mut clients = JoinSet::new();
    loop {
        tokio::select! {
         _=shutdown.cancelled()=>break,
         _=clients.join_next(),if !clients.is_empty()=>{},
         accepted=listener.accept()=>{
          let (stream,_)=accepted?;
          if stream.peer_cred()?.uid()!=metadata.uid(){continue}
          let Ok(permit)=connections.clone().try_acquire_owned() else {continue};
          let state=state.clone();clients.spawn(async move{let _permit=permit;let _=connection(stream,state).await;});
         }
        }
    }
    clients.abort_all();
    while clients.join_next().await.is_some() {}
    Ok(())
}
struct SocketGuard {
    path: std::path::PathBuf,
    inode: u64,
}
impl Drop for SocketGuard {
    fn drop(&mut self) {
        use std::os::unix::fs::MetadataExt;
        if std::fs::symlink_metadata(&self.path).is_ok_and(|m| m.ino() == self.inode) {
            let _ = std::fs::remove_file(&self.path);
        }
    }
}
async fn connection(stream: UnixStream, state: Arc<Mutex<Fixture>>) -> anyhow::Result<()> {
    let mut io = Framed::new(
        stream,
        LengthDelimitedCodec::builder()
            .max_frame_length(MAX_FRAME_BYTES)
            .new_codec(),
    );
    let bytes = tokio::time::timeout(Duration::from_secs(5), io.next())
        .await?
        .ok_or_else(|| anyhow::anyhow!("missing handshake"))??;
    let hello: Hello = decode(&bytes).map_err(anyhow::Error::msg)?;
    anyhow::ensure!(
        hello.protocol_version == PROTOCOL_VERSION && hello.fixture,
        "incompatible contract or fixture mode"
    );
    tokio::time::timeout(
        Duration::from_secs(5),
        io.send(
            serde_json::to_vec(&HelloReply {
                protocol_version: PROTOCOL_VERSION.into(),
                fixture: true,
                max_frame_bytes: MAX_FRAME_BYTES,
                max_in_flight: MAX_IN_FLIGHT,
            })?
            .into(),
        ),
    )
    .await??;
    let mut work = JoinSet::new();
    let mut active = HashMap::new();
    let mut seen = HashSet::new();
    loop {
        tokio::select! {
         completed=work.join_next(),if !work.is_empty()=>{
          if let Some(Ok((id,result)))=completed {
           active.remove(&id);
           let mut bytes=serde_json::to_vec(&ServerMessage{id,result})?;
           if bytes.len()>MAX_FRAME_BYTES {bytes=serde_json::to_vec(&ServerMessage{id,result:Err(ProtocolError::EvaluationLimitReached{message:"response exceeds frame limit".into()})})?;}
           tokio::time::timeout(Duration::from_secs(5),io.send(bytes.into())).await??;
          }
         }
         incoming=tokio::time::timeout(Duration::from_secs(60),io.next())=>{
          let Some(bytes)=incoming? else{break};
          match decode::<ClientMessage>(&bytes?).map_err(anyhow::Error::msg)? {
           ClientMessage::Cancel{id}=>{if let Some(handle)=active.remove(&id){tokio::task::AbortHandle::abort(&handle);}},
           ClientMessage::Request{id,request}=>{
            anyhow::ensure!(seen.len()<8192 && seen.insert(id),"duplicate request id or connection request limit reached");
            if active.len()>=MAX_IN_FLIGHT {
             tokio::time::timeout(Duration::from_secs(5),io.send(serde_json::to_vec(&ServerMessage{id,result:Err(ProtocolError::EvaluationLimitReached{message:"too many requests".into()})})?.into())).await??;continue
            }
            let state=state.clone();let handle=work.spawn(async move{let result=state.lock().await.handle(id,*request);(id,result)});active.insert(id,handle);
           }
          }
         }
        }
    }
    Ok(())
}
