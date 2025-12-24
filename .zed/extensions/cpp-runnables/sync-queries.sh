#!/usr/bin/env bash
# Syncs C++ queries from Zed's repo, preserving local runnables.scm
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LANG_DIR="$SCRIPT_DIR/languages/cpp"
ZED_RAW="https://raw.githubusercontent.com/zed-industries/zed/main/crates/languages/src/cpp"

mkdir -p "$LANG_DIR"

# Backup local runnables.scm
[[ -f "$LANG_DIR/runnables.scm" ]] && cp "$LANG_DIR/runnables.scm" /tmp/runnables.scm.bak

# Clone sparse checkout of just the cpp directory
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

git clone --depth 1 --filter=blob:none --sparse \
    https://github.com/zed-industries/zed.git "$tmp/zed" 2>/dev/null

cd "$tmp/zed"
git sparse-checkout set crates/languages/src/cpp 2>/dev/null

# Copy all files except runnables.scm
find crates/languages/src/cpp -type f ! -name "runnables.scm" -exec cp {} "$LANG_DIR/" \;

# Restore local runnables.scm
[[ -f /tmp/runnables.scm.bak ]] && cp /tmp/runnables.scm.bak "$LANG_DIR/runnables.scm"

echo "Done. Reinstall the dev extension to apply changes."
