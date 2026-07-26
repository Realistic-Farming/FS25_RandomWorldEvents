#!/usr/bin/env bash
# build.sh — FS25_RandomWorldEvents
# Usage: bash build.sh [--deploy]
set -e

MOD_NAME="FS25_RandomWorldEvents"
OUT_ZIP="${MOD_NAME}.zip"
DEPLOY_DIR="/c/Users/tison/Documents/My Games/FarmingSimulator2025/mods"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[build] Building ${OUT_ZIP}..."

py - <<'PYEOF'
import zipfile, os, sys

out_zip = os.environ.get('OUT_ZIP', 'FS25_RandomWorldEvents.zip')

root_files = [
    'modDesc.xml',
    'RandomWorldEvents.lua',
    'guiProfiles.xml',
    'icon.dds',
    'README.md',
]
subdirs = ['icons', 'gui', 'xml', 'utils', 'api', 'integrations']

with zipfile.ZipFile(out_zip, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
    for f in root_files:
        if os.path.exists(f):
            zf.write(f, f)
    for d in subdirs:
        if not os.path.isdir(d):
            continue
        for root, dirs, files in os.walk(d):
            for file in files:
                full = os.path.join(root, file)
                arc = full.replace(os.sep, '/')
                zf.write(full, arc)

print(f'[build] Created {out_zip}')
PYEOF

if [[ "$1" == "--deploy" ]]; then
    echo "[build] Deploying to ${DEPLOY_DIR}..."
    cp "$OUT_ZIP" "$DEPLOY_DIR/$OUT_ZIP"
    echo "[build] Deploy complete."
fi
