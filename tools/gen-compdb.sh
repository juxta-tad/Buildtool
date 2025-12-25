#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

exec devenv shell -- bash -c '
  output=$(buck2 bxl //bxl:compdb.bxl:generate -- --targets //...)
  mkdir -p .cache/compdb
  cp "$output" .cache/compdb/compile_commands.json
  echo "Generated compile_commands.json"
'
