load("@prelude//paths.bzl", "paths")

def app(
    srcs = ["main.cpp"],
    deps = [],
    prefix_header = "pch.h",
    default = "asan",
    visibility = ["PUBLIC"],
):
    """
    Defines a standard app with macos, macos_asan, and macos_cov variants.
    Creates an alias using the directory name as the target name.
    """
    name = paths.basename(package_name())

    common = {
        "srcs": srcs,
        "deps": deps,
        "prefix_header": prefix_header,
        "visibility": visibility,
    }

    # Release variant (optimized, LTO enabled via toolchain)
    native.cxx_binary(
        name = "macos_release",
        compiler_flags = [
            "-O3",
            "-DNDEBUG",
        ],
        **common
    )

    # Debug variant (no optimization, full debug info)
    native.cxx_binary(
        name = "macos_debug",
        compiler_flags = [
            "-O0",
            "-g",
            "-fno-lto",
        ],
        linker_flags = [
            "-fno-lto",
        ],
        **common
    )

    # ASan + UBSan variant (no LTO for debuggability)
    native.cxx_binary(
        name = "macos_asan",
        compiler_flags = [
            "-fsanitize=address,undefined",
            "-fno-omit-frame-pointer",
            "-g",
            "-fno-lto",
            "-O0",
            "-ftrivial-auto-var-init=zero",
        ],
        linker_flags = [
            "-fsanitize=address,undefined",
            "-fno-lto",
        ],
        **common
    )

    # Coverage variant
    native.cxx_binary(
        name = "macos_cov",
        compiler_flags = [
            "--coverage",
            "-g",
            "-fno-lto",
        ],
        linker_flags = [
            "--coverage",
            "-fno-lto",
        ],
        **common
    )

    # Default alias
    native.alias(
        name = name,
        actual = ":macos_" + default,
        visibility = visibility,
    )
