//! Reproducible validation and fixture packaging; explicit native/host gates.
use anyhow::{Context, Result};
use std::{
    fs,
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
    let dir = root().join("contracts");
    if !check {
        fs::create_dir_all(&dir)?;
    }
    let catalog = universe_protocol::tool_schemas();
    let entries = std::iter::once(("tools.json", serde_json::to_value(catalog)?))
        .chain(std::iter::once((
            "examples.json",
            serde_json::Value::Array(
                universe_protocol::examples::valid()
                    .into_iter()
                    .map(|(tool, args)| serde_json::json!({"tool":tool,"args":args}))
                    .collect(),
            ),
        )))
        .chain(std::iter::once((
            "source-assessments.json",
            universe_protocol::assessment::schemas(),
        )));
    for (name, value) in entries {
        let text = serde_json::to_string_pretty(&value)? + "\n";
        let path = dir.join(name);
        if check {
            anyhow::ensure!(
                fs::read_to_string(&path).ok().as_deref() == Some(&text),
                "stale {}: run xtask schemas",
                path.display()
            );
        } else {
            fs::write(path, text)?;
        }
    }
    Ok(())
}
fn package(release: bool) -> Result<()> {
    anyhow::ensure!(cfg!(target_os = "macos"), "native package requires macOS");
    let status = Command::new("cargo")
        .env("MACOSX_DEPLOYMENT_TARGET", "15.0")
        .args([
            "build",
            "--release",
            "--locked",
            "-p",
            "universe-builder-desktop",
            "-p",
            "universe-engine",
            "-p",
            "universe-mcp",
            "-p",
            "universe-cli",
        ])
        .status()?;
    anyhow::ensure!(status.success(), "release build failed: {status}");
    let app = root().join(if release {
        "target/distribution/Multiverse MCP.app"
    } else {
        "target/fixture/Universe Builder Fixture.app"
    });
    if app.exists() {
        fs::remove_dir_all(&app)?;
    }
    let bin = app.join("Contents/MacOS");
    fs::create_dir_all(&bin)?;
    for name in [
        "universe-builder",
        "universe-engine",
        "universe-mcp",
        "universe",
        "multiverse-mcp",
    ] {
        fs::copy(root().join("target/release").join(name), bin.join(name))?;
    }
    fs::write(
        app.join("Contents/Info.plist"),
        format!(
            r#"<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>universe-builder</string><key>CFBundleIdentifier</key><string>local.multiverse-mcp{suffix}</string><key>CFBundleName</key><string>{name}</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>{version}</string><key>CFBundleVersion</key><string>{version}</string><key>LSMinimumSystemVersion</key><string>15.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>"#,
            suffix = if release { "" } else { ".fixture" },
            name = if release {
                "Multiverse MCP"
            } else {
                "Universe Builder Fixture"
            },
            version = env!("CARGO_PKG_VERSION")
        ),
    )?;
    for name in [
        "universe-engine",
        "universe-mcp",
        "universe",
        "multiverse-mcp",
    ] {
        run(
            "/usr/bin/codesign",
            &["--force", "--sign", "-", bin.join(name).to_str().unwrap()],
        )?;
    }
    run(
        &std::env::var("UNIVERSE_PYTHON").unwrap_or_else(|_| "python3".into()),
        &[
            "scripts/release_manifest.py",
            "--bundle",
            app.to_str().unwrap(),
            "--channel",
            if release {
                "preview"
            } else {
                "local-development"
            },
        ],
    )?;
    run(
        "/usr/bin/codesign",
        &["--force", "--sign", "-", app.to_str().unwrap()],
    )?;
    run(
        "/usr/bin/codesign",
        &["--verify", "--deep", "--strict", app.to_str().unwrap()],
    )?;
    println!(
        "Development/preview package; ad-hoc signature, not notarized: {}",
        app.display()
    );
    Ok(())
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
        Some("package-fixture") => package(false),
        Some("package-release") => package(true),
        Some("mcp-config") => {
            let binary = args
                .get(1)
                .context("mcp-config ABSOLUTE_BINARY ABSOLUTE_SOCKET")?;
            let socket = args.get(2).context("socket required")?;
            anyhow::ensure!(
                Path::new(binary).is_absolute() && Path::new(socket).is_absolute(),
                "absolute paths required"
            );
            println!(
                "{}",
                serde_json::to_string_pretty(
                    &serde_json::json!({"mcpServers":{"universe-builder-fixture":{"command":binary,"args":["--fixture","--socket",socket]}}})
                )?
            );
            Ok(())
        }
        None | Some("help") => {
            println!("xtask: check | schemas | check-schemas | validate-contracts | mcp-smoke | installation-smoke | package-fixture | package-release | mcp-config ABSOLUTE_BINARY ABSOLUTE_SOCKET\nNative UI, VoiceOver, and LM Studio gates require recorded host runs; they are not implied by check.");
            Ok(())
        }
        Some(other) => anyhow::bail!("unknown command: {other}"),
    }
}
