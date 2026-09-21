//! Build automation entry point (`cargo run -p xtask -- <cmd>`).
//!
//! Subcommands are added as the work packages land (schema emission,
//! silver-gate fixture checks). Not yet a full tool.

use std::process::ExitCode;

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let cmd = args.next();
    match cmd.as_deref() {
        Some("help") | None => {
            println!("usage: xtask <command>\ncommands: help");
            ExitCode::SUCCESS
        }
        Some(other) => {
            eprintln!("xtask: unknown command `{other}` (try `help`)");
            ExitCode::from(2)
        }
    }
}
