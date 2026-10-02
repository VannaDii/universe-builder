//! Universe Builder in-app client: unix-socket transport, framing,
//! version handshake, request multiplexing.
//!
//! Placeholder: not yet implemented (see IMPLEMENTATION_STATUS.md, WP04).

// Protocol 3 callers inspect execution and submitted scope independently.
pub use universe_protocol::validation_scope::{AssessmentState, SubmittedInput, ValidationV3};
