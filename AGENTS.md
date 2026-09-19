# Working notes

## FL Studio MCP

- MCP server project: `C:\Users\TheTaZe\Documents\fl-studio-mcp` (run via `uv run --directory ... fl-studio-mcp`).
- If the `fl_*` MCP tools are not exposed in-session, drive FL through the server's Python API over the shell:
  `uv run python -c "from fl_studio_mcp.utils.connection import get_connection, reset_connection; ..."`
- Windows virtual MIDI port is `OpenCode Port 1` (output) -> `OpenCode Port 0` (input); FL's controller script is `FLStudioMCP`.
- `transport.setSongPos` modes: 0 = ms, 1 = seconds, 2 = absolute ticks. Always pass `mode=1` when using seconds.
- `mixer.getTrackPeaks` is reliable for a single track read; bulk/rapid reads can return garbage. Poll slowly.

## Mixing preferences

- **Never set the master OTT (Fruity Multiband Compressor "OTT") Depth above 15%.**
- Prefer fixing balance/loudness with gain staging and per-track EQ over heavy master compression.
- Do not change mixer stereo separation/width unless explicitly requested.
- `mixer.setTrackStereoSep` sign: **positive merges toward mono, negative widens** (verified). Default is 0.0.
