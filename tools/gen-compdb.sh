#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

exec nix --extra-experimental-features "nix-command flakes" develop --command bash -c '
  output=$(buck2 bxl //bxl:compdb.bxl:generate -- --targets //...)
  ln -sf "$output" compile_commands.json
  echo "Generated compile_commands.json"
'
