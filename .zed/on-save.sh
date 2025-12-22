#!/bin/bash
# Build on save
# Usage: on-save.sh <buffer_path>
# Note: compdb regeneration is handled by watchman trigger (see .envrc)
# Double-tap save (within 1s) opens error log on failure

dir="$(dirname "$1")"
cd "$dir"
eval "$(direnv export bash 2>/dev/null)"
errlog=/tmp/buck2-error.log
stampfile=/tmp/buck2-save-stamp

# Check for double-tap (save within 1 second of last save)
now=$(date +%s)
if [ -f "$stampfile" ]; then
  last=$(cat "$stampfile")
  if [ $((now - last)) -le 1 ]; then
    double_tap=1
  fi
fi
echo "$now" > "$stampfile"

buck2 build //apps/... > "$errlog" 2>&1

if [ $? -eq 0 ]; then
  afplay -v 0.3 /System/Library/Sounds/Tink.aiff
else
  afplay -v 0.3 /System/Library/Sounds/Basso.aiff &
fi
