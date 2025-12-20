#!/bin/bash
# Build on save
# Usage: on-save.sh <buffer_path>
# Note: compdb regeneration is handled by watchman trigger (see .envrc)

dir="$(dirname "$1")"
cd "$dir"
eval "$(direnv export bash 2>/dev/null)"
errlog=/tmp/buck2-error.log

buck2 build //apps/... > "$errlog" 2>&1

if [ $? -eq 0 ]; then
  afplay -v 0.3 /System/Library/Sounds/Tink.aiff
else
  afplay -v 0.3 /System/Library/Sounds/Basso.aiff &
  zed "$errlog"
fi
