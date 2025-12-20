load("//:nix_deps.bzl", "external_pkgconfig_library")

# Declare raylib as a pkg-config library (provided by Nix)
external_pkgconfig_library(
    name = "raylib",
)

cxx_binary(
    name = "raylib_demo",
    srcs = ["raylib_demo.cpp"],
    deps = [":raylib"],
)
