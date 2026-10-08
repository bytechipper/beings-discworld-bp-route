#!/usr/bin/env python3
"""Build a reproducible Mallard archive; optional argument selects the output path."""
from pathlib import Path
import sys
import tomllib
import zipfile

root = Path(__file__).resolve().parent.parent
manifest = tomllib.loads((root / "plugin.toml").read_text())
output = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "dist" / (
    root.name + "-" + manifest["version"] + ".mallardx"
)
output.parent.mkdir(parents=True, exist_ok=True)
files = [root / name for name in ("plugin.toml", "LICENSE", "README.md")]
extensions = {"src": {".lua"}, "ui": {".html", ".css", ".js"}, "assets": {".png"}}
for directory, allowed in extensions.items():
    for path in (root / directory).rglob("*"):
        if path.is_symlink():
            raise ValueError("Symlinks are not allowed: " + str(path))
        if path.is_file() and path.suffix in allowed:
            files.append(path)
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(files):
        entry = zipfile.ZipInfo(path.relative_to(root).as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
        entry.compress_type = zipfile.ZIP_DEFLATED
        entry.create_system = 3
        entry.external_attr = 0o100644 << 16
        archive.writestr(entry, path.read_bytes(), compresslevel=9)
print(output)
