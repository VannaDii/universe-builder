//! Versioned application contract; independent of MCP and presentation.
pub mod error;
pub mod examples;
pub mod request;
pub mod response;
pub mod wire;
pub use error::{ProtocolError, ProtocolResult};
pub use request::{tool_schemas, Request, ToolSchema};
pub use response::Response;
pub use universe_domain::DomainError;
pub const PROTOCOL_VERSION: &str = "2";
pub const MAX_FRAME_BYTES: usize = 1024 * 1024;
pub const MAX_IN_FLIGHT: usize = 16;

pub mod installation;
