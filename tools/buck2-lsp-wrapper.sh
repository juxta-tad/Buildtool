#!/bin/bash
cd "$(dirname "$0")/.."
exec nix --extra-experimental-features "nix-command flakes" develop --command buck2 lsp "$@"
