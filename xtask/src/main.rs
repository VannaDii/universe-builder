//! Transitional Rust checks; public schemas and application packaging are Dart-owned.
use anyhow::{Context, Result};
use std::{
    path::{Path, PathBuf},
    process::Command,
};
fn run(program: &str, args: &[&str]) -> Result<()> {
    let status = Command::new(program)
        .args(args)
        .status()
        .with_context(|| format!("start {program}"))?;
    anyhow::ensure!(status.success(), "{program} failed: {status}");
    Ok(())
}
fn root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf()
}
fn schemas(check: bool) -> Result<()> {
    let mut args = vec!["run", "tool/build_contracts.dart"];
    if check {
        args.push("--check");
    }
    run("dart", &args)
}

fn main() -> Result<()> {
    std::env::set_current_dir(root())?;
    let args: Vec<_> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("schemas") => schemas(false),
        Some("check-schemas") => schemas(true),
        Some("check") => {
            run("cargo", &["fmt", "--all", "--", "--check"])?;
            run(
                "cargo",
                &[
                    "clippy",
                    "--workspace",
                    "--all-targets",
                    "--locked",
                    "--",
                    "-D",
                    "warnings",
                ],
            )?;
            run("cargo", &["test", "--workspace", "--locked"])?;
            schemas(true)
        }
        Some("mcp-smoke") => {
            run(
                "cargo",
                &[
                    "build",
                    "--locked",
                    "-p",
                    "universe-engine",
                    "-p",
                    "universe-mcp",
                ],
            )?;
            run(
                &std::env::var("UNIVERSE_PYTHON").unwrap_or_else(|_| "python3".into()),
                &["scripts/mcp_smoke.py"],
            )
        }
        Some("installation-smoke") => {
            run(
                "cargo",
                &[
                    "build",
                    "--locked",
                    "-p",
                    "universe-engine",
                    "-p",
                    "universe-mcp",
                    "-p",
                    "universe-cli",
                ],
            )?;
            run(
                &std::env::var("UNIVERSE_PYTHON").unwrap_or_else(|_| "python3".into()),
                &["scripts/installation_smoke.py"],
            )
        }
        Some("validate-contracts") => {
            schemas(true)?;
            run(
                &std::env::var("UNIVERSE_PYTHON").unwrap_or_else(|_| "python3".into()),
                &["scripts/validate_contracts.py"],
            )?;
            run(
                &std::env::var("UNIVERSE_PYTHON").unwrap_or_else(|_| "python3".into()),
                &["scripts/test_source_assessment_contracts.py"],
            )?;
            run(
                &std::env::var("UNIVERSE_PYTHON").unwrap_or_else(|_| "python3".into()),
                &["scripts/test_action_consequence_contracts.py"],
            )
        }
        Some("package-fixture") | Some("package-release") => anyhow::bail!(
            "Rust application packaging is retired. Use `dart run apps/ub_cli/tool/package_macos.dart` (add `--mode release` for an optimized bundle). For the disposable workspace, launch its `multiverse-mcp ux --fixture`."
        ),
        Some("mcp-config") => {
            let mut command = vec!["run", "tool/mcp_config.dart"];
            command.extend(args.iter().skip(1).map(String::as_str));
            run("dart", &command)
        }
        None | Some("help") => {
            println!("xtask: check | schemas | check-schemas | validate-contracts | mcp-smoke | installation-smoke | mcp-config ABSOLUTE_BINARY ABSOLUTE_SOCKET\nApplication packaging: dart run apps/ub_cli/tool/package_macos.dart [--mode debug|release]\nNative UI, accessibility and external model host checks are separate from these automated checks.");
            Ok(())
        }
        Some(other) => anyhow::bail!("unknown command: {other}"),
    }
}
