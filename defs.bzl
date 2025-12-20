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

    # Base variant
    native.cxx_binary(
        name = "macos",
        **common
    )

    # ASan + UBSan variant
    native.cxx_binary(
        name = "macos_asan",
        compiler_flags = [
            "-fsanitize=address,undefined",
            "-fno-omit-frame-pointer",
            "-g",
        ],
        linker_flags = [
            "-fsanitize=address,undefined",
        ],
        **common
    )

    # Coverage variant
    native.cxx_binary(
        name = "macos_cov",
        compiler_flags = [
            "--coverage",
            "-g",
        ],
        linker_flags = [
            "--coverage",
        ],
        **common
    )

    # Default alias
    native.alias(
        name = name,
        actual = ":macos_" + default if default != "release" else ":macos",
        visibility = visibility,
    )
