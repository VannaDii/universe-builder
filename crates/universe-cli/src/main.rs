//! Installation administration over the same authenticated engine boundary.
use clap::{Parser, Subcommand};
use universe_client::installation::{sibling_engine, EngineClient};
use universe_domain::ids::*;
use universe_protocol::installation::*;
#[derive(Parser)]
struct Args {
    #[arg(long)]
    installation: std::path::PathBuf,
    #[arg(long)]
    profile: Option<String>,
    #[command(subcommand)]
    command: Command,
}
#[derive(Subcommand)]
enum Command {
    Init,
    Status,
    Doctor,
    Create {
        name: String,
        #[arg(long)]
        first_time: String,
        #[arg(long, default_value = "gregorian")]
        calendar: String,
        #[arg(long)]
        tick_label: Option<String>,
        #[arg(long)]
        ticks_per_month: Option<u32>,
    },
    Register {
        path: std::path::PathBuf,
        name: String,
    },
    Rename {
        universe_id: String,
        name: String,
    },
    Enroll,
    Grant {
        profile_id: String,
        universe_id: String,
        #[arg(long)]
        world: Vec<String>,
        #[arg(long)]
        propose: bool,
        #[arg(long)]
        edit: bool,
        #[arg(long)]
        protected: bool,
    },
    Revoke {
        profile_id: String,
    },
    Tool {
        file: std::path::PathBuf,
    },
    Library {
        universe: String,
    },
    Review {
        universe: String,
        proposal: String,
        version: u64,
        digest: String,
    },
    Approve {
        universe: String,
        proposal: String,
        version: u64,
        digest: String,
        validation: String,
    },
    StageSource {
        universe: String,
        label: String,
        file: std::path::PathBuf,
    },
    Backup {
        universe: String,
        destination: std::path::PathBuf,
    },
    Restore {
        source: std::path::PathBuf,
        name: String,
    },
    Maintain {
        universe: String,
        #[arg(long)]
        collect: bool,
    },
    ConvertPackage {
        source: std::path::PathBuf,
        destination: std::path::PathBuf,
    },
    ConvertInstallation {
        source: std::path::PathBuf,
        destination: std::path::PathBuf,
    },
    ConvertCredential {
        source: std::path::PathBuf,
        destination: std::path::PathBuf,
    },
    ConvertLegacy {
        source: std::path::PathBuf,
        destination: std::path::PathBuf,
    },
    Export {
        universe: String,
        destination: std::path::PathBuf,
        #[arg(long)]
        record: Vec<String>,
        #[arg(long)]
        complete_history: bool,
    },
    PreviewImport {
        source: std::path::PathBuf,
        name: String,
        #[arg(long)]
        clone: bool,
    },
    AcceptImport {
        preview: String,
        digest: String,
    },
    Shutdown,
}
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args = Args::parse();
    let converted = match &args.command {
        Command::ConvertPackage {
            source,
            destination,
        } => Some(serde_json::to_value(
            universe_store::kernel::operator_conversion::convert_package(source, destination)?,
        )?),
        Command::ConvertInstallation {
            source,
            destination,
        } => Some(universe_service::conversion::convert_installation(
            source,
            destination,
        )?),
        Command::ConvertCredential {
            source,
            destination,
        } => Some(universe_service::conversion::convert_credential(
            source,
            destination,
        )?),
        _ => None,
    };
    if let Some(report) = converted {
        println!("{}", serde_json::to_string_pretty(&report)?);
        return Ok(());
    }
    let helper = sibling_engine()?;
    if matches!(args.command, Command::Init) {
        let status = std::process::Command::new(helper)
            .arg("--installation")
            .arg(args.installation)
            .arg("--initialize")
            .status()?;
        anyhow::ensure!(status.success(), "initialization failed");
        return Ok(());
    }
    let profile = ProfileId::parse(
        args.profile
            .as_deref()
            .ok_or_else(|| anyhow::anyhow!("--profile required"))?,
    )?;
    let mut client =
        EngineClient::ensure_running(&args.installation, &profile, &helper, "maintenance-cli")
            .await?;
    let request = match args.command {
        Command::Init
        | Command::ConvertPackage { .. }
        | Command::ConvertInstallation { .. }
        | Command::ConvertCredential { .. } => unreachable!(),
        Command::Status => EngineRequest::Status,
        Command::Doctor => EngineRequest::Doctor,
        Command::Create {
            name,
            first_time,
            calendar,
            tick_label,
            ticks_per_month,
        } => {
            let start = if calendar == "gregorian" {
                anyhow::ensure!(
                    tick_label.is_none() && ticks_per_month.is_none(),
                    "Gregorian creation does not accept fictional units"
                );
                universe_domain::chronology::UniverseStart::Gregorian {
                    timestamp: first_time,
                }
            } else {
                universe_domain::chronology::UniverseStart::Fictional {
                    calendar_name: calendar,
                    initial_tick: first_time,
                    tick_label: tick_label.ok_or_else(|| {
                        anyhow::anyhow!("fictional calendars require --tick-label")
                    })?,
                    ticks_per_month,
                }
            };
            EngineRequest::CreateUniverse { name, start }
        }
        Command::Register { path, name } => EngineRequest::RegisterUniverse { path, name },
        Command::Rename { universe_id, name } => EngineRequest::RenameUniverse {
            universe_id: UniverseId::parse(&universe_id)?,
            name,
        },
        Command::Enroll => EngineRequest::Enroll,
        Command::Grant {
            profile_id,
            universe_id,
            world,
            propose,
            edit,
            protected,
        } => EngineRequest::Grant {
            grant: GrantSpec {
                profile_id: ProfileId::parse(&profile_id)?,
                universe_id: UniverseId::parse(&universe_id)?,
                worlds: if world.is_empty() {
                    None
                } else {
                    Some(
                        world
                            .iter()
                            .map(|s| WorldId::parse(s))
                            .collect::<Result<_, _>>()?,
                    )
                },
                propose,
                edit,
                protected,
                limits: Default::default(),
            },
        },
        Command::Revoke { profile_id } => EngineRequest::Revoke {
            profile_id: ProfileId::parse(&profile_id)?,
        },
        Command::Tool { file } => EngineRequest::Tool {
            request: Box::new(serde_json::from_slice(&std::fs::read(file)?)?),
        },
        Command::Library { universe } => EngineRequest::Library {
            universe: universe_protocol::request::Selector(universe),
        },
        Command::Review {
            universe,
            proposal,
            version,
            digest,
        } => EngineRequest::Review {
            universe: universe_protocol::request::Selector(universe),
            proposal_reference: universe_protocol::request::ProposalRef {
                proposal_id: ProposalId::parse(&proposal)?,
                version,
                digest,
            },
        },
        Command::Approve {
            universe,
            proposal,
            version,
            digest,
            validation,
        } => EngineRequest::Approve {
            universe: universe_protocol::request::Selector(universe),
            proposal_reference: universe_protocol::request::ProposalRef {
                proposal_id: ProposalId::parse(&proposal)?,
                version,
                digest,
            },
            validation_run: ValidationRunId::parse(&validation)?,
        },
        Command::StageSource {
            universe,
            label,
            file,
        } => EngineRequest::StageSource {
            universe: universe_protocol::request::Selector(universe),
            label,
            text: std::fs::read_to_string(file)?,
        },
        Command::Backup {
            universe,
            destination,
        } => EngineRequest::Backup {
            universe: universe_protocol::request::Selector(universe),
            destination,
        },
        Command::Restore { source, name } => EngineRequest::Restore { source, name },
        Command::Maintain { universe, collect } => EngineRequest::Maintain {
            universe: universe_protocol::request::Selector(universe),
            collect,
        },
        Command::ConvertLegacy {
            source,
            destination,
        } => EngineRequest::ConvertLegacy {
            source,
            destination,
        },
        Command::Export {
            universe,
            destination,
            record,
            complete_history,
        } => EngineRequest::ExportLogical {
            universe: universe_protocol::request::Selector(universe),
            destination,
            complete_history,
            record_ids: record
                .iter()
                .map(|s| RecordId::parse(s))
                .collect::<Result<_, _>>()?,
        },
        Command::PreviewImport {
            source,
            name,
            clone,
        } => EngineRequest::PreviewImport {
            source,
            name,
            mode: if clone {
                ImportMode::Clone
            } else {
                ImportMode::Restore
            },
        },
        Command::AcceptImport { preview, digest } => EngineRequest::AcceptImport {
            preview_id: OperationId::parse(&preview)?,
            digest,
        },
        Command::Shutdown => EngineRequest::Shutdown,
    };
    println!(
        "{}",
        serde_json::to_string_pretty(&client.call(request).await?)?
    );
    Ok(())
}
