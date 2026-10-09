//! Public distribution entry point. Helpers stay inside the sealed app bundle.
use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use std::{
    ffi::OsString,
    fs,
    os::unix::{fs::PermissionsExt, process::CommandExt},
    path::{Path, PathBuf},
    process::Command,
};

#[derive(Parser)]
#[command(
    name = "multiverse-mcp",
    version,
    about = "Local universe authoring and MCP server"
)]
struct Args {
    #[command(subcommand)]
    command: Action,
}

#[derive(Subcommand)]
enum Action {
    /// Open the persistent desktop workspace (never the disposable fixture).
    Ux {
        #[arg(long, requires = "profile")]
        installation: Option<PathBuf>,
        #[arg(long, requires = "installation")]
        profile: Option<String>,
    },
    /// Run the stdio MCP server. Pass --installation and an enrolled --profile.
    #[command(disable_help_flag = true)]
    Serve {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<OsString>,
    },
    /// Run installation administration. Use admin --help for commands.
    #[command(disable_help_flag = true)]
    Admin {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<OsString>,
    },
    /// Create a Finder application that runs multiverse-mcp ux.
    Shortcut {
        /// Directory for the shortcut; defaults to ~/Applications.
        #[arg(long)]
        destination: Option<PathBuf>,
        /// Stable installed command path, such as Homebrew's opt/bin path.
        #[arg(long)]
        launcher: Option<PathBuf>,
        #[arg(long, requires = "profile")]
        installation: Option<PathBuf>,
        #[arg(long, requires = "installation")]
        profile: Option<String>,
    },
}

fn ux_args(installation: Option<PathBuf>, profile: Option<String>) -> Result<Vec<OsString>> {
    let mut args = Vec::new();
    if let (Some(root), Some(id)) = (installation, profile) {
        universe_domain::ids::ProfileId::parse(&id)?;
        args.extend([
            "--installation".into(),
            std::path::absolute(root)?.into_os_string(),
            "--profile".into(),
            id.into(),
        ]);
    }
    Ok(args)
}

fn exec_helper(directory: &Path, name: &str, args: &[OsString]) -> Result<()> {
    Err(Command::new(directory.join(name)).args(args).exec())
        .with_context(|| format!("start bundled {name}"))
}

fn shell_word(word: &str) -> String {
    format!("'{}'", word.replace('\'', "'\\''"))
}

fn shortcut_script(launcher: &Path, args: &[OsString]) -> Result<String> {
    let mut words = vec![
        shell_word(launcher.to_str().context("launcher path must be UTF-8")?),
        "ux".into(),
    ];
    for arg in args {
        words.push(shell_word(
            arg.to_str().context("shortcut arguments must be UTF-8")?,
        ));
    }
    Ok(format!("#!/bin/sh\nexec {}\n", words.join(" ")))
}

fn installed_command() -> Result<PathBuf> {
    // Preserve Homebrew's stable symlink instead of baking a Cellar version into a shortcut.
    if let Some(paths) = std::env::var_os("PATH") {
        for path in std::env::split_paths(&paths) {
            let candidate = path.join("multiverse-mcp");
            if candidate.is_file() {
                return Ok(std::path::absolute(candidate)?);
            }
        }
    }
    Ok(std::env::current_exe()?)
}

fn create_shortcut(destination: &Path, launcher: &Path, args: &[OsString]) -> Result<PathBuf> {
    anyhow::ensure!(
        launcher.is_absolute() && launcher.is_file(),
        "launcher must be an existing absolute executable path"
    );
    let script = shortcut_script(launcher, args)?;
    fs::create_dir_all(destination)?;
    let app = destination.join("Multiverse MCP.app");
    // Never replace an existing application, symlink, or shortcut.
    fs::create_dir(&app).context("shortcut already exists or cannot be created")?;
    let result = (|| -> Result<()> {
        let bin = app.join("Contents/MacOS");
        fs::create_dir_all(&bin)?;
        fs::write(bin.join("launch"), script)?;
        fs::set_permissions(bin.join("launch"), fs::Permissions::from_mode(0o755))?;
        let resources = app.join("Contents/Resources");
        fs::create_dir_all(&resources)?;
        fs::write(
            resources.join("universe-builder.icns"),
            include_bytes!("../../../assets/branding/universe-builder.icns"),
        )?;
        fs::write(
            app.join("Contents/Info.plist"),
            r#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>launch</string><key>CFBundleIdentifier</key><string>local.multiverse-mcp.shortcut</string><key>CFBundleName</key><string>Multiverse MCP</string><key>CFBundleIconFile</key><string>universe-builder.icns</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>"#,
        )?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_dir_all(&app);
    }
    result?;
    Ok(app)
}

fn main() -> Result<()> {
    let args = Args::parse();
    // Reuse the existing whole-bundle signature check before executing any sibling.
    let helper = universe_client::installation::sibling_engine()?;
    let directory = helper.parent().context("executable directory missing")?;
    match args.command {
        Action::Serve { args } => exec_helper(directory, "universe-mcp", &args),
        Action::Admin { args } => exec_helper(directory, "universe", &args),
        Action::Ux {
            installation,
            profile,
        } => {
            let args = ux_args(installation, profile)?;
            if let Some(app) = directory
                .ancestors()
                .find(|p| p.extension().is_some_and(|e| e == "app"))
            {
                let status = Command::new("/usr/bin/open")
                    .arg("-n")
                    .arg(app)
                    .arg("--args")
                    .args(args)
                    .status()?;
                anyhow::ensure!(
                    status.success(),
                    "macOS could not open the desktop: {status}"
                );
                Ok(())
            } else {
                exec_helper(directory, "universe-builder", &args)
            }
        }
        Action::Shortcut {
            destination,
            launcher,
            installation,
            profile,
        } => {
            let destination = destination.unwrap_or(
                dirs::home_dir()
                    .context("home directory unavailable")?
                    .join("Applications"),
            );
            let launcher = launcher.map(Ok).unwrap_or_else(installed_command)?;
            let app = create_shortcut(&destination, &launcher, &ux_args(installation, profile)?)?;
            println!("Created {}", app.display());
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn forwarding_keeps_flags_and_literal_arguments() {
        let Args {
            command: Action::Serve { args },
        } = Args::try_parse_from([
            "multiverse-mcp",
            "serve",
            "--installation",
            "/tmp/a b;$(whoami)",
            "--profile",
            "literal",
        ])
        .unwrap()
        else {
            panic!("serve expected")
        };
        assert_eq!(
            args,
            [
                "--installation",
                "/tmp/a b;$(whoami)",
                "--profile",
                "literal"
            ]
            .map(OsString::from)
        );
        let Args {
            command: Action::Admin { args },
        } = Args::try_parse_from(["multiverse-mcp", "admin", "--help"]).unwrap()
        else {
            panic!("admin expected")
        };
        assert_eq!(args, [OsString::from("--help")]);
    }

    #[test]
    fn ux_and_shortcut_require_a_complete_connection() {
        for action in ["ux", "shortcut"] {
            assert!(Args::try_parse_from([
                "multiverse-mcp",
                action,
                "--installation",
                "/tmp/library"
            ])
            .is_err());
            assert!(
                Args::try_parse_from(["multiverse-mcp", action, "--profile", "someone"]).is_err()
            );
            assert!(Args::try_parse_from(["multiverse-mcp", action]).is_ok());
        }
        assert!(ux_args(Some("/tmp/library".into()), Some("invalid".into())).is_err());
    }

    #[test]
    fn shortcut_quotes_shell_metacharacters() {
        let script = shortcut_script(
            Path::new("/tmp/a 'quoted' $(id)/multiverse-mcp"),
            &["--installation".into(), "/tmp/a b;$(id)".into()],
        )
        .unwrap();
        assert_eq!(script, "#!/bin/sh\nexec '/tmp/a '\\''quoted'\\'' $(id)/multiverse-mcp' ux '--installation' '/tmp/a b;$(id)'\n");
    }
}
