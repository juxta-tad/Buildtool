#!/usr/bin/env bash
# Syncs C++ queries from Zed's repo, preserving local runnables.scm
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LANG_DIR="$SCRIPT_DIR/languages/cpp"
ZED_REPO="https://raw.githubusercontent.com/zed-industries/zed/main/crates/languages/src/cpp"

# Backup local runnables.scm
cp "$LANG_DIR/runnables.scm" /tmp/runnables.scm.bak 2>/dev/null || true

# Download all queries from Zed
for file in config.toml highlights.scm brackets.scm indents.scm outline.scm \
            injections.scm overrides.scm embedding.scm textobjects.scm imports.scm; do
    echo "Downloading $file..."
    curl -sL "$ZED_REPO/$file" -o "$LANG_DIR/$file"
done

# Restore local runnables.scm
cp /tmp/runnables.scm.bak "$LANG_DIR/runnables.scm" 2>/dev/null || true

echo "Done. Reinstall the dev extension to apply changes."
