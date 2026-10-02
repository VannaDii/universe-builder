use clap::Parser;
use futures::{SinkExt, StreamExt};
use rmcp::{model::*, service::RequestContext, ErrorData, RoleServer, ServerHandler, ServiceExt};
use universe_client::{Client, ClientConfig, ConnectedClient};
use universe_protocol::{tool_schemas, Request};
mod instructions;
#[derive(Parser)]
#[command(
    about = "Universe Builder MCP adapter for an authenticated installation or disposable fixture"
)]
struct Args {
    #[arg(long)]
    fixture: bool,
    #[arg(long)]
    socket: Option<std::path::PathBuf>,
    #[arg(long)]
    installation: Option<std::path::PathBuf>,
    #[arg(long)]
    profile: Option<String>,
}
#[derive(Clone)]
struct Adapter {
    client: Backend,
}
#[derive(Clone)]
enum Backend {
    Fixture(ConnectedClient),
    Installation {
        root: std::path::PathBuf,
        profile: universe_domain::ids::ProfileId,
    },
}
impl Backend {
    async fn send(
        &self,
        request: Request,
    ) -> Result<serde_json::Value, universe_client::ClientError> {
        match self {
            Self::Fixture(c) => c.send(request).await.map(|r| r.body_json()),
            Self::Installation { root, profile } => {
                use universe_client::installation::EngineClient;
                let result = async {
                    let mut c = EngineClient::connect(root, profile, "mcp-adapter").await?;
                    c.call(universe_protocol::installation::EngineRequest::Tool {
                        request: Box::new(request),
                    })
                    .await
                }
                .await;
                result.map_err(|e: anyhow::Error| {
                    e.downcast_ref::<universe_protocol::ProtocolError>()
                        .cloned()
                        .map(universe_client::ClientError::Protocol)
                        .unwrap_or(universe_client::ClientError::Disconnected)
                })
            }
        }
    }
}
impl ServerHandler for Adapter {
    fn get_info(&self) -> ServerConfig {
        let mut config = ServerConfig::default();
        config.instructions = Some(instructions::instructions(matches!(
            self.client,
            Backend::Fixture(_)
        )));
        config.capabilities = ServerCapabilities::builder().enable_tools().build();
        config
    }
    async fn list_tools(
        &self,
        _: Option<PaginatedRequestParams>,
        _: RequestContext<RoleServer>,
    ) -> Result<ListToolsResult, ErrorData> {
        let tools = tool_schemas()
            .into_iter()
            .map(|s| {
                let mut tool = Tool::new(
                    s.name,
                    s.description,
                    s.input_schema.as_object().unwrap().clone(),
                );
                tool.output_schema = Some(std::sync::Arc::new(
                    s.output_schema.as_object().unwrap().clone(),
                ));
                tool
            })
            .collect();
        Ok(ListToolsResult {
            tools,
            ..Default::default()
        })
    }
    async fn call_tool(
        &self,
        args: CallToolRequestParams,
        context: RequestContext<RoleServer>,
    ) -> Result<CallToolResponse, ErrorData> {
        let request = match Request::from_tool(
            &args.name,
            serde_json::Value::Object(args.arguments.unwrap_or_default()),
        ) {
            Ok(r) => r,
            Err(e) => {
                return Ok(
                    CallToolResult::structured_error(serde_json::to_value(e).unwrap()).into(),
                )
            }
        };
        tokio::select! {
         _=context.ct.cancelled()=>Ok(CallToolResult::error(vec![ContentBlock::text("Request cancelled. Recover admitted mutations using their original idempotency key.")]).into()),
         result=self.client.send(request)=>match result {
          Ok(r)=>Ok(CallToolResult::structured(r).into()),
          Err(universe_client::ClientError::Protocol(e))=>Ok(CallToolResult::structured_error(serde_json::to_value(e).unwrap()).into()),
          Err(e)=>Ok(CallToolResult::error(vec![ContentBlock::text(e.to_string())]).into()),
         }
        }
    }
}
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args = Args::parse();
    let client = if args.fixture {
        anyhow::ensure!(
            args.installation.is_none() && args.profile.is_none(),
            "fixture and installation options are exclusive"
        );
        Backend::Fixture(
            Client::with_config(
                ClientConfig::default().with_socket_path(
                    args.socket
                        .ok_or_else(|| anyhow::anyhow!("fixture socket required"))?,
                ),
            )
            .connect_with_retry()
            .await?,
        )
    } else {
        anyhow::ensure!(
            args.socket.is_none(),
            "installation endpoint is discovered automatically"
        );
        let root = args
            .installation
            .ok_or_else(|| anyhow::anyhow!("--installation required"))?;
        let id = universe_domain::ids::ProfileId::parse(
            &args
                .profile
                .ok_or_else(|| anyhow::anyhow!("--profile required"))?,
        )?;
        universe_client::installation::EngineClient::ensure_running(
            &root,
            &id,
            &universe_client::installation::sibling_engine()?,
            "mcp-adapter",
        )
        .await?;
        // Only the profile ID is retained; credentials are read through the protected client loader.
        Backend::Installation { root, profile: id }
    };
    // The SDK's default AsyncRead transport has an unbounded line buffer.
    // Bound and strictly decode stdin before the MCP dispatcher receives it.
    use rmcp::{
        service::{RxJsonRpcMessage, TxJsonRpcMessage},
        transport::async_rw::JsonRpcMessageCodec,
    };
    use tokio_util::codec::{FramedRead, FramedWrite, LinesCodec};
    let input = FramedRead::new(
        tokio::io::stdin(),
        LinesCodec::new_with_max_length(universe_protocol::MAX_FRAME_BYTES),
    )
    .map(|line| {
        line.map_err(|e| e.to_string()).and_then(|line| {
            universe_protocol::wire::decode::<RxJsonRpcMessage<RoleServer>>(line.as_bytes())
        })
    })
    .take_while(|message| futures::future::ready(message.is_ok()))
    .map(Result::unwrap)
    .boxed();
    let output = FramedWrite::new(
        tokio::io::stdout(),
        JsonRpcMessageCodec::<TxJsonRpcMessage<RoleServer>>::default(),
    )
    .sink_map_err(std::io::Error::from);
    let service = Adapter { client }.serve((output, input)).await?;
    service.waiting().await?;
    Ok(())
}
