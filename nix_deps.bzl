# pkg-config based external library integration for Buck2
# Adapted from Buck2 prelude: prelude/third-party/pkgconfig.bzl

def external_pkgconfig_library(
        name,
        package = None,
        visibility = ["PUBLIC"],
        deps = []):
    """
    Creates a prebuilt_cxx_library from a pkg-config package.

    Args:
        name: Target name (also used as pkg-config package name if package is None)
        package: pkg-config package name (defaults to name)
        visibility: Target visibility
        deps: Dependencies that are not resolved by pkg-config
    """
    if package == None:
        package = name

    pkg_config_cflags = name + "__pkg_config_cflags"
    native.genrule(
        name = pkg_config_cflags,
        out = "out",
        cmd = "pkg-config --cflags {} > $OUT".format(package),
        remote = False,  # Prevent caching across different machines
    )

    pkg_config_libs = name + "__pkg_config_libs"
    native.genrule(
        name = pkg_config_libs,
        out = "out",
        cmd = "pkg-config --libs {} > $OUT".format(package),
        remote = False,
    )

    native.prebuilt_cxx_library(
        name = name,
        visibility = visibility,
        exported_preprocessor_flags = ["@$(location :{})".format(pkg_config_cflags)],
        exported_linker_flags = ["@$(location :{})".format(pkg_config_libs)],
        exported_deps = deps,
    )
