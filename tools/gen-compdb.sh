#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

exec nix --extra-experimental-features "nix-command flakes" develop --command bash -c '
  output=$(buck2 bxl //bxl:compdb.bxl:generate -- --targets //...)
  mkdir -p .cache/compdb
  cp "$output" .cache/compdb/compile_commands.json
  echo "Generated .cache/compdb/compile_commands.json"
'
