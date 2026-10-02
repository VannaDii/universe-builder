Versioned macOS preview containing the native author workspace, MCP adapter,
engine and administration CLI in one complete app bundle. Separate archives
are provided for Apple Silicon and Intel Macs running macOS 15 or later.

The attached `multiverse-mcp.rb` is generated from these exact archives and
contains their SHA256 checksums. After publishing this preview, copy the formula
into `Formula/multiverse-mcp.rb` in your Homebrew tap and commit it there.
Draft release assets are not publicly installable.

Installed commands:

- `multiverse-mcp ux` opens the persistent author workspace.
- `multiverse-mcp shortcut` creates a Finder/Dock shortcut in `~/Applications`.
- `multiverse-mcp serve --installation PATH --profile PROFILE_ID` runs the MCP server.
- `multiverse-mcp admin --help` lists installation administration commands.

This preview is ad-hoc signed, not Developer ID signed or notarized. Packaging
and automated checks do not complete the outstanding native UX, accessibility,
model-host, clean-machine, security or workload acceptance gates. See the
release runbook and bundled manifest before distribution. Close the desktop
and perform authenticated engine shutdown before an upgrade; retain verified
backups and never replace individual helpers in a running installation.
