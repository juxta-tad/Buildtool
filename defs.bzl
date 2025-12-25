load("@prelude//paths.bzl", "paths")

def app(
    srcs = ["main.cpp"],
    deps = [],
    prefix_header = "pch.h",
    visibility = ["PUBLIC"],
):
    """
    Defines a standard app target with fixed name 'app' for debugger compatibility.
    Use modes for build variants:
      buck2 build //apps/client                              # debug (default)
      buck2 build //apps/client --config-file modes/release.bcfg
      buck2 build //apps/client --config-file modes/asan.bcfg
      buck2 build //apps/client --config-file modes/cov.bcfg
    """
    # Use directory name as the public target name for buck2 run/build
    dir_name = paths.basename(package_name())

    # Main binary with fixed name 'app' for debugger path consistency
    native.cxx_binary(
        name = "app",
        srcs = srcs,
        deps = deps,
        prefix_header = prefix_header,
        visibility = visibility,
    )

    # Alias using directory name for convenience (buck2 build //apps/client)
    native.alias(
        name = dir_name,
        actual = ":app",
        visibility = visibility,
    )
