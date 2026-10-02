//! Persistent desktop by default; the disposable fixture requires --fixture.
use std::{
    path::PathBuf,
    process::{Child, Command, Stdio},
};
struct Helper(Child);
impl Drop for Helper {
    fn drop(&mut self) {
        drop(self.0.stdin.take());
        let _ = self.0.wait();
    }
}
fn main() {
    let helper = universe_client::installation::sibling_engine()
        .expect("the bundled helpers must pass integrity verification");
    let args: Vec<String> = std::env::args().collect();
    if let Some(index) = args.iter().position(|a| a == "--installation") {
        let root = PathBuf::from(args.get(index + 1).expect("--installation needs a path"));
        let profile_index = args
            .iter()
            .position(|a| a == "--profile")
            .expect("--profile required");
        let profile = universe_domain::ids::ProfileId::parse(
            args.get(profile_index + 1).expect("profile ID required"),
        )
        .expect("valid profile ID");
        let rt = tokio::runtime::Runtime::new().expect("client runtime");
        rt.block_on(universe_client::installation::EngineClient::ensure_running(
            &root, &profile, &helper, "desktop",
        ))
        .expect("authenticated engine connection");
        std::env::set_var("UNIVERSE_INSTALLATION", root);
        std::env::set_var("UNIVERSE_PROFILE", profile.as_str());
        dioxus::LaunchBuilder::desktop()
            .with_cfg(
                dioxus::desktop::Config::new().with_window(
                    dioxus::desktop::WindowBuilder::new()
                        .with_title("Universe Builder — Engine ownership"),
                ),
            )
            .launch(universe_ui::EngineApp);
        return;
    }
    if !args.iter().any(|arg| arg == "--fixture") {
        dioxus::LaunchBuilder::desktop()
            .with_cfg(
                dioxus::desktop::Config::new().with_window(
                    dioxus::desktop::WindowBuilder::new().with_title("Multiverse MCP"),
                ),
            )
            .launch(universe_ui::EngineApp);
        return;
    }
    let runtime = tempfile::Builder::new()
        .prefix("universe-fixture-")
        .tempdir()
        .expect("private runtime");
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(runtime.path(), std::fs::Permissions::from_mode(0o700))
        .expect("private runtime permissions");
    let socket: PathBuf = runtime.path().join("fixture.sock");
    let _engine = Helper(
        Command::new(&helper)
            .args(["--fixture", "--exit-on-stdin-close", "--socket"])
            .arg(&socket)
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::inherit())
            .spawn()
            .expect("bundled universe-engine must be next to the desktop executable"),
    );
    std::env::set_var("UNIVERSE_FIXTURE_SOCKET", socket);
    dioxus::LaunchBuilder::desktop()
        .with_cfg(
            dioxus::desktop::Config::new().with_window(
                dioxus::desktop::WindowBuilder::new()
                    .with_title("Universe Builder — Feasibility Fixture")
                    .with_inner_size(dioxus::desktop::LogicalSize::new(1100.0, 800.0)),
            ),
        )
        .launch(universe_ui::App);
}
