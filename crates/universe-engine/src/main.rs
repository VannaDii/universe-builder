use clap::Parser;
use tokio_util::sync::CancellationToken;
#[derive(Parser)]
#[command(about = "Universe Builder disposable feasibility engine; no canon writes")]
struct Args {
    #[arg(long)]
    exit_on_stdin_close: bool,
    #[arg(long)]
    fixture: bool,
    #[arg(long)]
    socket: Option<std::path::PathBuf>,
    #[arg(long)]
    installation: Option<std::path::PathBuf>,
    #[arg(long)]
    initialize: bool,
}
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args = Args::parse();
    if let Some(root) = args.installation {
        anyhow::ensure!(
            !args.fixture && !args.exit_on_stdin_close && args.socket.is_none(),
            "installation mode cannot use fixture options"
        );
        if args.initialize {
            println!("{}", universe_service::runtime::initialize(&root)?.as_str());
            return Ok(());
        }
        let shutdown = CancellationToken::new();
        let signal = shutdown.clone();
        tokio::spawn(async move {
            let _ = tokio::signal::ctrl_c().await;
            signal.cancel();
        });
        return universe_service::runtime::serve(&root, shutdown).await;
    }
    anyhow::ensure!(
        args.fixture && !args.initialize,
        "choose --fixture or --installation"
    );
    let socket = args
        .socket
        .ok_or_else(|| anyhow::anyhow!("fixture socket required"))?;
    let shutdown = CancellationToken::new();
    let signal = shutdown.clone();
    tokio::spawn(async move {
        let _ = tokio::signal::ctrl_c().await;
        signal.cancel();
    });
    if args.exit_on_stdin_close {
        let parent_exit = shutdown.clone();
        tokio::spawn(async move {
            use tokio::io::AsyncReadExt;
            let mut byte = [0u8; 1];
            while let Ok(n) = tokio::io::stdin().read(&mut byte).await {
                if n == 0 {
                    break;
                }
            }
            parent_exit.cancel();
        });
    }
    let result = universe_service::ipc::serve(&socket, shutdown).await;
    if args.exit_on_stdin_close {
        if let Some(parent) = socket.parent() {
            let _ = std::fs::remove_dir(parent);
        }
    }
    result
}
