# flake.bzl - Buck2 rules for building Nix flake packages
#
# Usage:
#   load("//nix:flake.bzl", "flake")
#
#   flake.package(name = "jq", package = "jq", binary = "jq")
#   flake.cxx_library(name = "raylib", libs = ["raylib"], frameworks = ["OpenGL", ...])

load("@prelude//cxx:cxx_context.bzl", "get_cxx_toolchain_info")
load("@prelude//cxx:cxx_toolchain_types.bzl", "PicBehavior")
load(
    "@prelude//cxx:preprocessor.bzl",
    "CPreprocessor",
    "CPreprocessorArgs",
    "CPreprocessorInfo",
    "cxx_merge_cpreprocessors",
)
load(
    "@prelude//linking:link_info.bzl",
    "LibOutputStyle",
    "LinkInfo",
    "LinkInfos",
    "LinkedObject",
    "MergedLinkInfo",
    "create_merged_link_info",
)
load("@prelude//linking:types.bzl", "Linkage")
load(
    "@prelude//linking:linkable_graph.bzl",
    "create_linkable_graph",
    "create_linkable_graph_node",
    "create_linkable_node",
)
load(
    "@prelude//linking:shared_libraries.bzl",
    "SharedLibraries",
    "SharedLibraryInfo",
    "merge_shared_libraries",
)
load(
    "@prelude//linking:link_groups.bzl",
    "merge_link_group_lib_info",
)
load("@prelude//os_lookup:defs.bzl", "Os", "OsLookup")
load("@prelude//decls/common.bzl", "buck")
load("@prelude//decls:toolchains_common.bzl", "toolchains_common")

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

def _get_nix_system(os_lookup: OsLookup) -> str:
    if os_lookup.os == Os("macos"):
        os = "darwin"
    elif os_lookup.os == Os("linux"):
        os = "linux"
    else:
        fail("Unsupported OS: {}".format(os_lookup.os))

    if os_lookup.cpu == "arm64":
        cpu = "aarch64"
    elif os_lookup.cpu == "x86_64":
        cpu = "x86_64"
    else:
        fail("Unsupported CPU: {}".format(os_lookup.cpu))

    return "{}-{}".format(cpu, os)

# -----------------------------------------------------------------------------
# flake.package - Generic nix package rule
# -----------------------------------------------------------------------------

def _flake_package_impl(ctx: AnalysisContext) -> list[Provider]:
    os_lookup = ctx.attrs._target_os_type[OsLookup]
    system = _get_nix_system(os_lookup)

    package = ctx.attrs.package or ctx.label.name
    output = ctx.attrs.output
    flake_path = ctx.attrs.path

    package_set = "legacyPackages" if ctx.attrs.legacy else "packages"
    attribute = "{}.{}.{}".format(package_set, system, package)
    if output != "out":
        attribute = "{}.{}".format(attribute, output)

    link_suffix = "result" if output == "out" else "result-{}".format(output)
    out_link = ctx.actions.declare_output("out/{}".format(link_suffix))

    nix_build = cmd_args([
        "env", "--",
        "nix", "--extra-experimental-features", "nix-command flakes",
        "build",
        "--out-link", cmd_args(out_link.as_output(), parent = 1, absolute_suffix = "/result"),
        cmd_args(flake_path, attribute, delimiter = "#") if flake_path else attribute,
    ])

    ctx.actions.run(nix_build, category = "nix_build", identifier = package, local_only = True)

    run_info = []
    if ctx.attrs.binary:
        run_info.append(RunInfo(args = cmd_args(out_link, "bin", ctx.attrs.binary, delimiter = "/")))

    sub_targets = {
        bin: [DefaultInfo(default_output = out_link), RunInfo(args = cmd_args(out_link, "bin", bin, delimiter = "/"))]
        for bin in ctx.attrs.binaries
    }

    return [DefaultInfo(default_output = out_link, sub_targets = sub_targets)] + run_info

_flake_package = rule(
    impl = _flake_package_impl,
    attrs = {
        "path": attrs.option(attrs.string(), default = None),
        "package": attrs.option(attrs.string(), default = None),
        "output": attrs.string(default = "out"),
        "binary": attrs.option(attrs.string(), default = None),
        "binaries": attrs.list(attrs.string(), default = []),
        "legacy": attrs.bool(default = True),
        "_target_os_type": buck.target_os_type_arg(),
    },
)

# -----------------------------------------------------------------------------
# flake.cxx_library - C++ library from nix package with proper providers
# -----------------------------------------------------------------------------

def _flake_cxx_library_impl(ctx: AnalysisContext) -> list[Provider]:
    nix_pkg = ctx.attrs.nix_pkg[DefaultInfo].default_outputs[0]
    os_lookup = ctx.attrs._target_os_type[OsLookup]
    is_macos = os_lookup.os == Os("macos")

    # Create symlinks within buck-out for include and lib directories
    # This gives us relative paths that buck2 can track
    include_dir = ctx.actions.declare_output("include", dir = True)
    lib_dir = ctx.actions.declare_output("lib", dir = True)

    # Copy directories from nix package to buck-out
    # This makes the outputs cacheable (no local_only) and gives relative paths
    ctx.actions.run(
        cmd_args([
            "sh", "-c",
            cmd_args(
                "cp -rL \"", nix_pkg, "/include/.\" \"$1\" && cp -rL \"", nix_pkg, "/lib/.\" \"$2\"",
                delimiter = "",
            ),
            "--",
            include_dir.as_output(),
            lib_dir.as_output(),
        ]),
        category = "nix_copy",
        identifier = ctx.label.name,
    )

    providers = []

    # Get toolchain info
    toolchain = get_cxx_toolchain_info(ctx)
    linker_type = toolchain.linker_info.type

    # Create preprocessor info with include directory
    pre = CPreprocessor(
        args = CPreprocessorArgs(args = [
            cmd_args(include_dir, format = "-isystem{}"),
        ]),
    )
    preprocessor_info = cxx_merge_cpreprocessors(ctx.actions, [pre], [])
    providers.append(preprocessor_info)

    # Build linker flags
    link_flags = [cmd_args(lib_dir, format = "-L{}")]
    for lib in ctx.attrs.libs:
        link_flags.append("-l{}".format(lib))

    # Frameworks are macOS-only
    if is_macos:
        for framework in ctx.attrs.frameworks:
            link_flags.append("-framework")
            link_flags.append(framework)

    # Create link info for different output styles
    link_info = LinkInfo(
        pre_flags = link_flags,
    )

    link_infos = {
        LibOutputStyle("archive"): LinkInfos(default = link_info),
        LibOutputStyle("pic_archive"): LinkInfos(default = link_info),
        LibOutputStyle("shared_lib"): LinkInfos(default = link_info),
    }

    # Create merged link info
    merged_link_info = create_merged_link_info(
        ctx,
        toolchain.pic_behavior,
        link_infos,
        preferred_linkage = Linkage("any"),
    )
    providers.append(merged_link_info)

    # Create shared library info (empty, we don't provide shared libs directly)
    providers.append(merge_shared_libraries(
        ctx.actions,
        SharedLibraries(libraries = []),
        [],
    ))

    # Create linkable graph
    linkable_graph = create_linkable_graph(
        ctx,
        node = create_linkable_graph_node(
            ctx,
            linkable_node = create_linkable_node(
                ctx = ctx,
                default_soname = None,
                preferred_linkage = Linkage("any"),
                link_infos = link_infos,
                shared_libs = SharedLibraries(libraries = []),
            ),
        ),
    )
    providers.append(linkable_graph)

    # Link group lib info (required by cxx_binary)
    providers.append(merge_link_group_lib_info(deps = []))

    # Default info with both directories as outputs
    providers.append(DefaultInfo(default_outputs = [include_dir, lib_dir]))

    return providers

_flake_cxx_library_rule = rule(
    impl = _flake_cxx_library_impl,
    attrs = {
        "nix_pkg": attrs.dep(providers = [DefaultInfo]),
        "libs": attrs.list(attrs.string(), default = []),
        "frameworks": attrs.list(attrs.string(), default = []),
        "labels": attrs.list(attrs.string(), default = []),
        "_cxx_toolchain": toolchains_common.cxx(),
        "_target_os_type": buck.target_os_type_arg(),
    },
)

def _flake_cxx_library(
        name,
        path = "nixpkgs",
        package = None,
        libs = None,
        frameworks = [],
        legacy = True,
        visibility = ["PUBLIC"],
        **kwargs):
    """
    Creates a C++ library from a Nix flake package.

    Features:
    - Copies include/lib to buck-out for relative paths
    - Proper CPreprocessorInfo and MergedLinkInfo providers
    - Cacheable (no local_only on the library rule itself)
    - Works with buck2's cxx dependency system
    """
    if package == None:
        package = name
    if libs == None:
        libs = [name]

    # Build the nix package (this is still local_only)
    nix_pkg_name = name + "__nix"
    _flake_package(
        name = nix_pkg_name,
        path = path,
        package = package,
        legacy = legacy,
    )

    # Create the library with proper providers
    _flake_cxx_library_rule(
        name = name,
        nix_pkg = ":{}".format(nix_pkg_name),
        libs = libs,
        frameworks = frameworks,
        visibility = visibility,
        **kwargs
    )

# -----------------------------------------------------------------------------
# Exported struct
# -----------------------------------------------------------------------------

flake = struct(
    package = _flake_package,
    cxx_library = _flake_cxx_library,
)
