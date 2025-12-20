load("//:nix_deps.bzl", "external_pkgconfig_library")

# Declare raylib as a pkg-config library (provided by Nix)
external_pkgconfig_library(
    name = "raylib",
)

# Main demo binary with precompiled header
cxx_binary(
    name = "raylib_demo",
    srcs = ["raylib_demo.cpp"],
    deps = [":raylib"],
    prefix_header = "pch.h",
)

# Sanitizer-enabled build for debugging
cxx_binary(
    name = "raylib_demo_asan",
    srcs = ["raylib_demo.cpp"],
    deps = [":raylib"],
    prefix_header = "pch.h",
    compiler_flags = [
        "-fsanitize=address,undefined",
        "-fno-omit-frame-pointer",
        "-g",
    ],
    linker_flags = [
        "-fsanitize=address,undefined",
    ],
)

# Coverage-enabled build for testing
cxx_binary(
    name = "raylib_demo_cov",
    srcs = ["raylib_demo.cpp"],
    deps = [":raylib"],
    prefix_header = "pch.h",
    compiler_flags = [
        "--coverage",
        "-g",
    ],
    linker_flags = [
        "--coverage",
    ],
)
