//! Bounded, correlated fixture IPC. No retry of admitted mutations with a new key.
use futures::{SinkExt, StreamExt};
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::Duration,
};
use tokio::{
    net::UnixStream,
    sync::{mpsc, oneshot, Mutex, Semaphore},
};
use tokio_util::codec::{Framed, LengthDelimitedCodec};
use universe_protocol::{wire::*, MAX_FRAME_BYTES, MAX_IN_FLIGHT, PROTOCOL_VERSION};
pub use universe_protocol::{ProtocolError, Request, Response};
#[derive(Debug, Clone)]
pub struct ClientConfig {
    pub socket_path: PathBuf,
    pub request_timeout: Duration,
    pub max_reconnect_attempts: u32,
}
impl Default for ClientConfig {
    fn default() -> Self {
        Self {
            socket_path: dirs::cache_dir()
                .unwrap_or_else(std::env::temp_dir)
                .join("universe-engine/fixture.sock"),
            request_timeout: Duration::from_secs(10),
            max_reconnect_attempts: 3,
        }
    }
}
impl ClientConfig {
    pub fn with_socket_path(mut self, p: impl Into<PathBuf>) -> Self {
        self.socket_path = p.into();
        self
    }
    pub fn with_request_timeout(mut self, t: Duration) -> Self {
        self.request_timeout = t;
        self
    }
    pub fn with_max_reconnect_attempts(mut self, n: u32) -> Self {
        self.max_reconnect_attempts = n;
        self
    }
}
#[derive(Debug, thiserror::Error)]
pub enum ClientError {
    #[error("I/O: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON: {0}")]
    Json(#[from] serde_json::Error),
    #[error("protocol: {0}")]
    Protocol(#[from] ProtocolError),
    #[error("request timed out; recover mutations using their original idempotency key")]
    Timeout,
    #[error("disconnected; recover mutations using their original idempotency key")]
    Disconnected,
    #[error("invalid handshake or frame: {0}")]
    Invalid(String),
}
pub struct Client {
    config: ClientConfig,
}
impl Default for Client {
    fn default() -> Self {
        Self::new()
    }
}
impl Client {
    pub fn new() -> Self {
        Self {
            config: ClientConfig::default(),
        }
    }
    pub fn with_config(config: ClientConfig) -> Self {
        Self { config }
    }
    pub fn socket_path(&self) -> &Path {
        &self.config.socket_path
    }
    pub async fn connect(&self) -> Result<ConnectedClient, ClientError> {
        tokio::time::timeout(self.config.request_timeout, self.connect_inner())
            .await
            .map_err(|_| ClientError::Timeout)?
    }
    async fn connect_inner(&self) -> Result<ConnectedClient, ClientError> {
        let stream = UnixStream::connect(&self.config.socket_path).await?;
        let mut framed = Framed::new(
            stream,
            LengthDelimitedCodec::builder()
                .max_frame_length(MAX_FRAME_BYTES)
                .new_codec(),
        );
        framed
            .send(
                serde_json::to_vec(&Hello {
                    protocol_version: PROTOCOL_VERSION.into(),
                    fixture: true,
                })?
                .into(),
            )
            .await?;
        let bytes = framed.next().await.ok_or(ClientError::Disconnected)??;
        let reply: HelloReply = decode(&bytes).map_err(ClientError::Invalid)?;
        if reply.protocol_version != PROTOCOL_VERSION
            || !reply.fixture
            || reply.max_frame_bytes != MAX_FRAME_BYTES
            || reply.max_in_flight != MAX_IN_FLIGHT
        {
            return Err(ClientError::Invalid(
                "incompatible contract or server mode".into(),
            ));
        }
        let (mut sink, mut stream) = framed.split();
        let pending: Pending = Arc::new(Mutex::new(HashMap::new()));
        let (tx, mut rx) = mpsc::channel::<ClientMessage>(MAX_IN_FLIGHT * 2);
        let writes = pending.clone();
        let task = tokio::spawn(async move {
            let writer = async {
                while let Some(message) = rx.recv().await {
                    let bytes = match serde_json::to_vec(&message) {
                        Ok(b) if b.len() <= MAX_FRAME_BYTES => b,
                        _ => break,
                    };
                    if sink.send(bytes.into()).await.is_err() {
                        break;
                    }
                }
            };
            let reader = async {
                while let Some(Ok(bytes)) = stream.next().await {
                    let reply: ServerMessage = match decode(&bytes) {
                        Ok(r) => r,
                        Err(_) => break,
                    };
                    if let Some(sender) = writes.lock().await.remove(&reply.id) {
                        let _ = sender.send(reply.result);
                    }
                }
            };
            tokio::select! {_=writer=>{},_=reader=>{}}
            writes.lock().await.clear();
        });
        Ok(ConnectedClient {
            inner: Arc::new(Inner {
                config: self.config.clone(),
                tx,
                pending,
                next: AtomicU64::new(1),
                slots: Semaphore::new(MAX_IN_FLIGHT),
                task,
            }),
        })
    }
    pub async fn connect_with_retry(&self) -> Result<ConnectedClient, ClientError> {
        for attempt in 0..=self.config.max_reconnect_attempts {
            match self.connect().await {
                Ok(c) => return Ok(c),
                Err(ClientError::Io(e))
                    if attempt < self.config.max_reconnect_attempts
                        && matches!(
                            e.kind(),
                            std::io::ErrorKind::NotFound | std::io::ErrorKind::ConnectionRefused
                        ) =>
                {
                    tokio::time::sleep(Duration::from_millis(50 * (attempt + 1) as u64)).await
                }
                Err(e) => return Err(e),
            }
        }
        Err(ClientError::Disconnected)
    }
}
type Pending = Arc<Mutex<HashMap<u64, oneshot::Sender<Result<Response, ProtocolError>>>>>;
struct Inner {
    config: ClientConfig,
    tx: mpsc::Sender<ClientMessage>,
    pending: Pending,
    next: AtomicU64,
    slots: Semaphore,
    task: tokio::task::JoinHandle<()>,
}
impl Drop for Inner {
    fn drop(&mut self) {
        self.task.abort();
    }
}
#[derive(Clone)]
pub struct ConnectedClient {
    inner: Arc<Inner>,
}
impl ConnectedClient {
    pub fn config(&self) -> &ClientConfig {
        &self.inner.config
    }
    pub async fn send(&self, request: Request) -> Result<Response, ClientError> {
        request.validate()?;
        let id = self.inner.next.fetch_add(1, Ordering::Relaxed);
        let message = ClientMessage::Request {
            id,
            request: Box::new(request),
        };
        if serde_json::to_vec(&message)?.len() > MAX_FRAME_BYTES {
            return Err(ClientError::Invalid("request exceeds frame limit".into()));
        }
        let deadline = tokio::time::Instant::now() + self.inner.config.request_timeout;
        let _permit = tokio::time::timeout_at(deadline, self.inner.slots.acquire())
            .await
            .map_err(|_| ClientError::Timeout)?
            .map_err(|_| ClientError::Disconnected)?;
        let (tx, rx) = oneshot::channel();
        self.inner.pending.lock().await.insert(id, tx);
        let mut cleanup = PendingRequest {
            inner: self.inner.clone(),
            id,
            armed: true,
        };
        let result = tokio::time::timeout_at(deadline, async {
            self.inner
                .tx
                .send(message)
                .await
                .map_err(|_| ClientError::Disconnected)?;
            rx.await
                .map_err(|_| ClientError::Disconnected)?
                .map_err(ClientError::Protocol)
        })
        .await;
        self.inner.pending.lock().await.remove(&id);
        match result {
            Ok(r) => {
                cleanup.armed = false;
                r
            }
            Err(_) => Err(ClientError::Timeout),
        }
    }
    pub async fn close(self) {
        self.inner.task.abort();
        self.inner.pending.lock().await.clear();
    }
}

// A caller dropping its future (including MCP cancellation) must not leak a
// pending entry or leave an unbounded abandoned request on this connection.
struct PendingRequest {
    inner: Arc<Inner>,
    id: u64,
    armed: bool,
}
impl Drop for PendingRequest {
    fn drop(&mut self) {
        if self.armed {
            let inner = self.inner.clone();
            let id = self.id;
            let _ = inner.tx.try_send(ClientMessage::Cancel { id });
            tokio::spawn(async move {
                inner.pending.lock().await.remove(&id);
            });
        }
    }
}

#[cfg(test)]
mod transport_tests {
    use super::*;
    use tokio::net::UnixListener;
    fn request(universe: &str) -> Request {
        Request::from_tool(
            "universe_describe",
            serde_json::json!({"universe":universe,"mode":"summary"}),
        )
        .unwrap()
    }
    async fn handshake(listener: UnixListener) -> Framed<UnixStream, LengthDelimitedCodec> {
        let (stream, _) = listener.accept().await.unwrap();
        let mut io = Framed::new(
            stream,
            LengthDelimitedCodec::builder()
                .max_frame_length(MAX_FRAME_BYTES)
                .new_codec(),
        );
        let hello: Hello = decode(&io.next().await.unwrap().unwrap()).unwrap();
        assert_eq!(hello.protocol_version, PROTOCOL_VERSION);
        io.send(
            serde_json::to_vec(&HelloReply {
                protocol_version: PROTOCOL_VERSION.into(),
                fixture: true,
                max_frame_bytes: MAX_FRAME_BYTES,
                max_in_flight: MAX_IN_FLIGHT,
            })
            .unwrap()
            .into(),
        )
        .await
        .unwrap();
        io
    }
    fn setup(timeout: Duration) -> (tempfile::TempDir, UnixListener, Client) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("client.sock");
        let listener = UnixListener::bind(&path).unwrap();
        let client = Client::with_config(
            ClientConfig::default()
                .with_socket_path(path)
                .with_request_timeout(timeout),
        );
        (dir, listener, client)
    }
    #[tokio::test]
    async fn handshake_has_deadline() {
        let (_dir, listener, client) = setup(Duration::from_millis(30));
        let server = tokio::spawn(async move {
            let (_stream, _) = listener.accept().await.unwrap();
            tokio::time::sleep(Duration::from_secs(1)).await;
        });
        assert!(matches!(client.connect().await, Err(ClientError::Timeout)));
        server.abort();
    }
    #[tokio::test]
    async fn incompatible_handshake_is_not_retried() {
        let (_dir, listener, client) = setup(Duration::from_secs(1));
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut io = Framed::new(stream, LengthDelimitedCodec::new());
            io.next().await.unwrap().unwrap();
            io.send(
                serde_json::to_vec(&HelloReply {
                    protocol_version: "999".into(),
                    fixture: true,
                    max_frame_bytes: MAX_FRAME_BYTES,
                    max_in_flight: MAX_IN_FLIGHT,
                })
                .unwrap()
                .into(),
            )
            .await
            .unwrap();
        });
        assert!(matches!(
            client.connect_with_retry().await,
            Err(ClientError::Invalid(_))
        ));
        server.await.unwrap();
    }
    #[tokio::test]
    async fn responses_can_arrive_out_of_order_without_eof() {
        let (_dir, listener, client) = setup(Duration::from_secs(1));
        let server = tokio::spawn(async move {
            let mut io = handshake(listener).await;
            let mut responses = Vec::new();
            for _ in 0..2 {
                let msg: ClientMessage = decode(&io.next().await.unwrap().unwrap()).unwrap();
                if let ClientMessage::Request { id, request } = msg {
                    responses.push(ServerMessage {
                        id,
                        result: Err(ProtocolError::invalid_argument(
                            "echo",
                            &request.universe().0,
                        )),
                    });
                } else {
                    panic!("request expected")
                }
            }
            for reply in responses.into_iter().rev() {
                io.send(serde_json::to_vec(&reply).unwrap().into())
                    .await
                    .unwrap();
            }
            tokio::time::sleep(Duration::from_secs(2)).await;
        });
        let connection = client.connect().await.unwrap();
        let (a, b) = tokio::join!(connection.send(request("A")), connection.send(request("B")));
        assert!(a.unwrap_err().to_string().ends_with("echo: A"));
        assert!(b.unwrap_err().to_string().ends_with("echo: B"));
        server.abort();
    }
    #[tokio::test]
    async fn timeout_cancels_and_removes_pending_entry() {
        let (_dir, listener, client) = setup(Duration::from_millis(100));
        let server = tokio::spawn(async move {
            let mut io = handshake(listener).await;
            let first: ClientMessage = decode(&io.next().await.unwrap().unwrap()).unwrap();
            let id = match first {
                ClientMessage::Request { id, .. } => id,
                _ => panic!(),
            };
            let cancel: ClientMessage = decode(&io.next().await.unwrap().unwrap()).unwrap();
            assert!(matches!(cancel,ClientMessage::Cancel{id:cancelled} if cancelled==id));
        });
        let c = client.connect().await.unwrap();
        assert!(matches!(
            c.send(request("A")).await,
            Err(ClientError::Timeout)
        ));
        server.await.unwrap();
        assert!(c.inner.pending.lock().await.is_empty());
    }
    #[tokio::test]
    async fn oversized_incoming_frame_disconnects_without_reading_payload() {
        use tokio::io::AsyncWriteExt;
        let (_dir, listener, client) = setup(Duration::from_secs(1));
        let server = tokio::spawn(async move {
            let io = handshake(listener).await;
            let mut stream = io.into_inner();
            stream
                .write_all(&((MAX_FRAME_BYTES + 1) as u32).to_be_bytes())
                .await
                .unwrap();
            tokio::time::sleep(Duration::from_secs(2)).await;
        });
        let c = client.connect().await.unwrap();
        assert!(matches!(
            c.send(request("A")).await,
            Err(ClientError::Disconnected)
        ));
        server.abort();
    }
}

pub mod installation;

// Protocol 3 callers inspect execution and submitted scope independently.
pub use universe_protocol::validation_scope::{AssessmentState, SubmittedInput, ValidationV3};
