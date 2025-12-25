# Buck2 + Nix C++ Template

Reproducible, incremental C++ builds using Buck2 and Nix.

**Features:** Reproducible (devenv/Nix), Incremental (Buck2), Multi-variant (Release/Debug/ASan), Clangd support, Cross-platform (macOS/Linux).

## Prerequisites

1.  **Nix**: [Install](https://nixos.org/download.html). Enable flakes in `~/.config/nix/nix.conf`:
    `experimental-features = nix-command flakes`
2.  **devenv**: [Install](https://devenv.sh/getting-started/)
3.  **direnv**: [Install](https://direnv.net/) (Recommended).

## Quick Start

```bash
# 1. Enter Environment
direnv allow              # Recommended
# OR: devenv shell

# 2. Build & Run
buck2 run //apps/client   # 3D Demo
buck2 run //apps/server
buck2 test //libs/core:core_test
```

## Build Variants

Append suffix to target (e.g., `//apps/client:macos_release`).

| Variant | Suffix | Description |
| :--- | :--- | :--- |
| **ASan** | `:macos_asan` | Address/UB sanitizers (Default) |
| **Debug** | `:macos_debug` | Symbols, no opt |
| **Release** | `:macos_release` | Optimized, LTO |
| **Cov** | `:macos_cov` | Code coverage |

## Structure

*   `apps/`: Binaries
*   `libs/`: Shared libraries
*   `nix/`: Buck2-Nix integration rules
*   `bxl/`: Build scripts (compdb)
*   `devenv.nix`: Dev environment

## Dependencies (Nix)

### Add Library
1.  Edit `nix/BUCK`:
    ```python
    load("//nix:flake.bzl", "flake")

    flake.cxx_library(
        name = "sdl2",
        package = "SDL2",           # Nix package name
        libs = ["SDL2"],            # Link flags
        pkg_config = ["sdl2"],      # Optional
        frameworks = ["Cocoa"],     # macOS only
        visibility = ["PUBLIC"],
    )
    ```
2.  Use in app `BUCK`: `deps = ["//nix:sdl2"]`

**Options**: `dev_output="dev"` (split headers), `include_dirs` (default: "include"), `lib_dir` (default: "lib").

### Add Binary Tool
In `nix/BUCK`:
```python
flake.package(name="jq", binary="jq")
# Run: buck2 run //nix:jq -- args
```

## New Components

### Create App
`apps/myapp/BUCK`:
```python
load("//:defs.bzl", "app")
app(deps = ["//libs/core:core"])
```

### Create Lib
`libs/mylib/BUCK`:
```python
cxx_library(
    name = "mylib",
    srcs = ["mylib.cpp"],
    exported_headers = ["mylib.hpp"],
    visibility = ["PUBLIC"],
)
```

## IDE Setup (Clangd)

1.  **Generate DB**: `buck2 bxl //bxl:compdb.bxl:generate -- //...`
2.  **Link**: `ln -sf .cache/compdb/compile_commands.json .`

**Zed**: Sync queries via `.zed/extensions/cpp-runnables/sync-queries.sh`.

## Environment

**Included**: LLVM 18, Buck2, Watchman, CMake, Ninja, lldb/gdb.
**Customize**: Edit `packages` list in `devenv.nix`.
**Direnv**: Add `eval "$(direnv hook bash)"` to shell config.

## Commands & Troubleshooting

```bash
buck2 build //...               # Build all
buck2 clean                     # Clean artifacts
buck2 query "deps(//apps/client)" # Inspect deps
```

*   **"nix not found"**: Source nix daemon.
*   **"flakes disabled"**: Update `nix.conf`.
*   **Buck2/Watchman error**: Ensure `devenv shell` or `direnv allow` is active.

## Forking

```bash
git clone <url> new-proj && cd new-proj
rm -rf .git && git init
gh repo create new-proj --source=. --push
```
## Cache (speed up builds)
To let devenv set up the caches for you, add yourself to the trusted-users list in /etc/nix/nix.conf:

     trusted-users = root mypc

   Then restart the nix-daemon:

     $ sudo launchctl kickstart -k system/org.nixos.nix-daemon
