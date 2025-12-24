# Buck2 + Nix C++ Project Template

A modern C++ project template combining Buck2 (build system) with Nix (dependency management) for reproducible, fast builds.

## Features

- **Reproducible builds** via Nix flakes
- **Fast incremental builds** via Buck2
- **Multiple build variants**: release, debug, ASan/UBSan, coverage
- **IDE support**: clangd integration with automatic compilation database
- **Cross-platform**: macOS and Linux (aarch64, x86_64)

## Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled
- [direnv](https://direnv.net/) (recommended)

### Enable Nix Flakes

Add to `~/.config/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

## Quick Start

### 1. Enter Development Shell

**With direnv (recommended):**

```bash
direnv allow
```

direnv automatically loads the Nix environment when you enter the directory.

**Without direnv:**

```bash
nix develop
```

### 2. Build and Run

```bash
# Build client (3D rotating cube demo)
buck2 build //apps/client

# Run client
buck2 run //apps/client

# Build server
buck2 build //apps/server

# Run tests
buck2 test //libs/core:core_test
```

### 3. Build Variants

Each app has four build variants:

| Variant | Target Suffix | Description |
|---------|---------------|-------------|
| ASan | `:macos_asan` | Address + UB sanitizers (default) |
| Debug | `:macos_debug` | Debug symbols, no optimization |
| Release | `:macos_release` | Optimized with LTO |
| Coverage | `:macos_cov` | Code coverage instrumentation |

```bash
# Build specific variant
buck2 build //apps/client:macos_release
buck2 build //apps/client:macos_debug
buck2 build //apps/client:macos_asan
buck2 build //apps/client:macos_cov
```

## Project Structure

```
.
├── apps/                   # Application binaries
│   ├── client/            # Example: Raylib 3D app
│   └── server/            # Example: Simple app
├── libs/                   # Shared libraries
│   └── core/              # Example: Core utilities
├── nix/                    # Nix-Buck2 integration
│   ├── BUCK               # Nix package declarations
│   └── flake.bzl          # Nix integration rules
├── toolchains/            # Buck2 toolchain config
├── bxl/                   # Build scripts (compdb generation)
├── defs.bzl               # Shared build macros
├── flake.nix              # Nix development environment
└── .buckconfig            # Buck2 configuration
```

## Adding Dependencies

### Adding a Nix Package as C++ Library

Edit `nix/BUCK` to add a new dependency:

```python
load("//nix:flake.bzl", "flake")

flake.cxx_library(
    name = "mylibrary",           # Target name (//nix:mylibrary)
    path = "nixpkgs",             # Flake path
    package = "mylibrary",        # Nix package name
    libs = ["mylib"],             # Library names to link (-lmylib)
    pkg_config = ["mylibrary"],   # pkg-config modules (optional)
    visibility = ["PUBLIC"],
)
```

Then use it in your app's `BUCK` file:

```python
load("//:defs.bzl", "app")

app(deps = [
    "//nix:mylibrary",
    "//libs/core:core",
])
```

### flake.cxx_library Options

| Option | Description | Default |
|--------|-------------|---------|
| `name` | Buck2 target name | required |
| `path` | Nix flake path | `"nixpkgs"` |
| `package` | Nix package name | same as `name` |
| `libs` | Libraries to link | `[name]` |
| `shared_libs` | Shared lib filenames for runtime | `[]` |
| `dev_output` | Nix output for headers (e.g., `"dev"`) | `None` |
| `include_dirs` | Include paths relative to package | `["include"]` |
| `lib_dir` | Library path relative to package | `"lib"` |
| `pkg_config` | pkg-config modules to parse | `[]` |
| `frameworks` | macOS frameworks to link | `[]` |

### Example: Adding SDL2

```python
flake.cxx_library(
    name = "sdl2",
    package = "SDL2",
    libs = ["SDL2"],
    pkg_config = ["sdl2"],
    frameworks = ["Cocoa", "IOKit", "CoreVideo"],  # macOS
    visibility = ["PUBLIC"],
)
```

### Example: Split Package (headers in dev output)

Some Nix packages split headers into a separate `dev` output:

```python
flake.cxx_library(
    name = "openssl",
    package = "openssl",
    dev_output = "dev",           # Headers come from openssl.dev
    libs = ["ssl", "crypto"],
    pkg_config = ["openssl"],
    visibility = ["PUBLIC"],
)
```

### Adding a Binary Tool from Nix

For non-library packages (tools, binaries):

```python
flake.package(
    name = "jq",
    package = "jq",
    binary = "jq",    # Creates runnable target
)
```

```bash
buck2 run //nix:jq -- '.foo' input.json
```

## Creating a New App

### 1. Create Directory Structure

```bash
mkdir -p apps/myapp
```

### 2. Create BUCK File

`apps/myapp/BUCK`:

```python
load("//:defs.bzl", "app")

app(deps = [
    "//libs/core:core",
    # Add more dependencies here
])
```

### 3. Create Source Files

`apps/myapp/main.cpp`:

```cpp
#include "core/core.hpp"
#include <cstdio>

int main() {
    std::printf("Version: %s\n", core::version());
    return 0;
}
```

`apps/myapp/pch.h`:

```cpp
#ifndef PCH_H
#define PCH_H
// Add frequently used headers here for faster compilation
#endif
```

### 4. Build and Run

```bash
buck2 run //apps/myapp
```

## Creating a New Library

### 1. Create Directory Structure

```bash
mkdir -p libs/mylib
```

### 2. Create BUCK File

`libs/mylib/BUCK`:

```python
cxx_library(
    name = "mylib",
    srcs = ["mylib.cpp"],
    header_namespace = "mylib",
    exported_headers = ["mylib.hpp"],
    visibility = ["PUBLIC"],
)

cxx_test(
    name = "mylib_test",
    srcs = ["mylib_test.cpp"],
    deps = [
        ":mylib",
        "//nix:gtest",
    ],
)
```

### 3. Create Source Files

`libs/mylib/mylib.hpp`:

```cpp
#pragma once

namespace mylib {
const char* greet();
}
```

`libs/mylib/mylib.cpp`:

```cpp
#include "mylib/mylib.hpp"

namespace mylib {
const char* greet() { return "Hello"; }
}
```

## IDE Setup

### VS Code / Cursor

The project generates `compile_commands.json` for clangd. After building:

```bash
# Generate compilation database
buck2 bxl //bxl:compdb.bxl:generate -- //...

# Symlink to project root (clangd expects it here)
ln -sf .cache/compdb/compile_commands.json .
```

clangd configuration is already provided in `.clangd`.

### Recommended Extensions

- clangd (C++ language server)
- direnv (automatic environment loading)

## Nix Environment

### What's Included

The `flake.nix` provides:

- LLVM 18 (clang, clang++, lld)
- clang-tools (clangd, clang-format)
- Buck2 + Watchman
- CMake + Ninja
- lldb (macOS) / gdb (Linux)

### Adding Development Tools

Edit `flake.nix`:

```nix
packages = [
    pkgs.buck2
    pkgs.watchman
    # Add more tools here
    pkgs.htop
    pkgs.ripgrep
];
```

Then reload:

```bash
direnv reload
# or
exit && nix develop
```

## direnv Setup

### Installation

```bash
# macOS
brew install direnv

# Add to shell (bash)
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc

# Add to shell (zsh)
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
```

### Usage

```bash
cd /path/to/project
direnv allow    # First time only
```

The environment loads automatically on directory entry.

### Troubleshooting

If direnv is slow, add to `~/.config/direnv/direnv.toml`:

```toml
[global]
hide_env_diff = true
```

## Common Commands

```bash
# Build all
buck2 build //...

# Test all
buck2 test //...

# Clean build outputs
buck2 clean

# List all targets
buck2 targets //...

# Query dependencies
buck2 query "deps(//apps/client)"

# Build with specific variant
buck2 build //apps/client:macos_release
```

## Troubleshooting

### "nix: command not found"

Ensure Nix is installed and in your PATH:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### "experimental feature 'flakes' is disabled"

Add to `~/.config/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

### Buck2 can't find Watchman

Ensure you're in the Nix shell:

```bash
nix develop
# or
direnv allow
```

### clangd not finding headers

Regenerate the compilation database:

```bash
buck2 bxl //bxl:compdb.bxl:generate -- //...
```

## Zed Extensions

### Sync C++ Queries

Sync Tree-sitter queries from Zed's upstream repository while preserving local `runnables.scm`:

```bash
.zed/extensions/cpp-runnables/sync-queries.sh
```

After running, reinstall the dev extension in Zed to apply changes.

## License

[Add your license here]
