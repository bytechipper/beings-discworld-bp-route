# Being's Discworld BP Route

Track Bes Pelargic NPC kills and suggest routes through high-value rooms using a persistent SQLite database.

Requires Mallard 0.27.0 or later; targets Discworld. Install through the marketplace or import the `.mallardx` archive.

`/bp help` lists route, room, status, export, import, reset, and save commands.

## Permissions

Does not send game commands. Reads the GMCP packages declared in `plugin.toml`. Uses a per-world SQLite database. No external network access.

## Development

Run `python3 -m unittest discover -s tests -v` (requires Lua 5.4 shared library). Panel tests require Python Playwright and Chromium. Build with `python3 scripts/build.py`; the reproducible archive includes only the manifest, license, README, runtime source, panel files, and assets.
