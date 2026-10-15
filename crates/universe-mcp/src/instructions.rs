//! Authoring guidance advertised during MCP initialization, not an authority grant.
const ADVANCED: &str = include_str!("../../../contracts/mcp-instructions/advanced.txt");
const ORDINARY: &str = include_str!("../../../contracts/mcp-instructions/ordinary.txt");

pub fn instructions(fixture: bool, advanced: bool) -> String {
    let mode = if fixture {
        include_str!("../../../contracts/mcp-instructions/fixture.txt")
    } else {
        include_str!("../../../contracts/mcp-instructions/persistent.txt")
    };
    format!("{mode}\n\n{}", if advanced { ADVANCED } else { ORDINARY })
}
