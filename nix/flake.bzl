# flake.bzl - Buck2 rules for building Nix flake packages
#
# Usage:
#   load("//nix:flake.bzl", "flake")
#
#   flake.package(name = "jq", package = "jq", binary = "jq")
#   flake.cxx_library(name = "raylib", libs = ["raylib"], pkg_config = ["raylib"])

load("@prelude//cxx:cxx_context.bzl", "get_cxx_toolchain_info")
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
    "LinkableGraph",
    "create_linkable_graph",
    "create_linkable_graph_node",
    "create_linkable_node",
)
load(
    "@prelude//linking:shared_libraries.bzl",
    "SharedLibraries",
    "SharedLibraryInfo",
    "create_shlib",
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
# flake.package - Generic nix package rule
# -----------------------------------------------------------------------------

def _flake_package_impl(ctx: AnalysisContext) -> list[Provider]:
    package = ctx.attrs.package or ctx.label.name
    output = ctx.attrs.output
    flake_path = ctx.attrs.path

    # Build attribute path - nix automatically resolves the current system
    attribute = package
    if output != "out":
        attribute = "{}.{}".format(attribute, output)

    # Build nix package and copy to buck-out (required for buck2 to track as artifact)
    # We use cp -rL to dereference symlinks from the Nix store, and chmod to make writable
    out_dir = ctx.actions.declare_output("out", dir = True)
    flake_ref = cmd_args(flake_path, attribute, delimiter = "#") if flake_path else attribute
    nix_build = cmd_args([
        "sh", "-c",
        # Build with --no-link (no symlink), get path via --print-out-paths, copy, and fix permissions
        "set -e; store_path=$(nix --extra-experimental-features 'nix-command flakes' build --no-link --print-out-paths \"$1\"); cp -rL \"$store_path\" \"$2\"; chmod -R u+w \"$2\"",
        "--",
        flake_ref,
        out_dir.as_output(),
    ])
    ctx.actions.run(nix_build, category = "nix_build", identifier = attribute, local_only = ctx.attrs.local_only)
    out = out_dir

    run_info = []
    if ctx.attrs.binary:
        run_info.append(RunInfo(args = cmd_args(out, "bin", ctx.attrs.binary, delimiter = "/")))

    # Build sub_targets with [run] subtarget when binary is set
    sub_targets = {}
    if ctx.attrs.binary:
        sub_targets["run"] = [
            DefaultInfo(default_output = out),
            RunInfo(args = cmd_args(out, "bin", ctx.attrs.binary, delimiter = "/")),
        ]
    for bin in ctx.attrs.binaries:
        sub_targets[bin] = [
            DefaultInfo(default_output = out),
            RunInfo(args = cmd_args(out, "bin", bin, delimiter = "/")),
        ]

    return [DefaultInfo(default_output = out, sub_targets = sub_targets)] + run_info

_flake_package = rule(
    impl = _flake_package_impl,
    attrs = {
        "path": attrs.option(attrs.string(), default = None),
        "package": attrs.option(attrs.string(), default = None),
        "output": attrs.string(default = "out"),
        "binary": attrs.option(attrs.string(), default = None),
        "binaries": attrs.list(attrs.string(), default = []),
        "local_only": attrs.bool(default = True),
    },
)

# -----------------------------------------------------------------------------
# flake.cxx_library - C++ library from nix package with proper providers
# -----------------------------------------------------------------------------

def _flake_cxx_library_impl(ctx: AnalysisContext) -> list[Provider]:
    nix_pkg = ctx.attrs.nix_pkg[DefaultInfo].default_outputs[0]
    # Use dev package for includes/pkgconfig if provided, otherwise use main package
    nix_dev_pkg = ctx.attrs.nix_dev_pkg[DefaultInfo].default_outputs[0] if ctx.attrs.nix_dev_pkg else nix_pkg
    os_lookup = ctx.attrs._target_os_type[OsLookup]
    is_macos = os_lookup.os == Os("macos")

    # Reference include and lib directories directly from copied Nix package
    include_dirs_attr = ctx.attrs.include_dirs if ctx.attrs.include_dirs else ["include"]
    lib_path = ctx.attrs.lib_dir if ctx.attrs.lib_dir else "lib"

    # Reference lib directory from copied package
    lib_dir = nix_pkg.project(lib_path) if ctx.attrs.pkg_config else None

    # Use real pkg-config via nix-shell to resolve transitive dependencies (including frameworks)
    pkg_config_cflags_file = None
    pkg_config_ldflags_file = None
    if ctx.attrs.pkg_config:
        pkg_config_cflags_file = ctx.actions.declare_output("pkg_config_cflags.txt")
        pkg_config_ldflags_file = ctx.actions.declare_output("pkg_config_ldflags.txt")

        pc_names = ctx.attrs.pkg_config
        nix_pkg_name = ctx.attrs.nix_pkg_name

        # Run pkg-config inside nix-shell with package + its buildInputs for transitive deps
        # Uses mkShell to ensure all transitive dependencies (like glfw for raylib) are in PKG_CONFIG_PATH
        nix_expr = "with import <nixpkgs> {{}}; mkShell {{ buildInputs = [ {pkg} pkg-config ] ++ {pkg}.buildInputs or []; }}".format(pkg = nix_pkg_name)

        # Get cflags (filter -I since we provide our own include paths)
        cflags_cmd = cmd_args([
            "sh", "-c",
            '''nix-shell -E "$1" --run "pkg-config --cflags --static $2" 2>/dev/null | tr ' ' '\n' | grep -v '^-I' | grep -v '^$' > "$3" || true''',
            "--",
            nix_expr,
            " ".join(pc_names),
            pkg_config_cflags_file.as_output(),
        ])
        ctx.actions.run(cflags_cmd, category = "pkg_config", identifier = "{}_cflags".format(ctx.label.name), local_only = True)

        # Get ldflags (keep -L for transitive deps, -l, and -framework)
        ldflags_cmd = cmd_args([
            "sh", "-c",
            '''nix-shell -E "$1" --run "pkg-config --libs --static $2" 2>/dev/null | tr ' ' '\n' | grep -v '^$' > "$3" || true''',
            "--",
            nix_expr,
            " ".join(pc_names),
            pkg_config_ldflags_file.as_output(),
        ])
        ctx.actions.run(ldflags_cmd, category = "pkg_config", identifier = "{}_ldflags".format(ctx.label.name), local_only = True)

    providers = []
    toolchain = get_cxx_toolchain_info(ctx)

    # Collect dep providers
    dep_preprocessors = []
    dep_link_infos = []
    dep_shared_libs = []
    dep_linkable_graphs = []
    for dep in ctx.attrs.deps:
        if CPreprocessorInfo in dep:
            dep_preprocessors.append(dep[CPreprocessorInfo])
        if MergedLinkInfo in dep:
            dep_link_infos.append(dep[MergedLinkInfo])
        if SharedLibraryInfo in dep:
            dep_shared_libs.append(dep[SharedLibraryInfo])
        if LinkableGraph in dep:
            dep_linkable_graphs.append(dep[LinkableGraph])

    # Preprocessor info with include directories
    # Reference paths directly from Nix dev package
    pre_args = []
    for inc_path in include_dirs_attr:
        inc_dir = nix_dev_pkg.project(inc_path)
        pre_args.append(cmd_args("-isystem", inc_dir, delimiter = ""))
    if pkg_config_cflags_file:
        pre_args.append(cmd_args("@", pkg_config_cflags_file, delimiter = ""))

    pre = CPreprocessor(
        args = CPreprocessorArgs(args = pre_args),
    )
    providers.append(cxx_merge_cpreprocessors(ctx, [pre], dep_preprocessors))

    # Linker flags (all from pkg-config: -L, -l, -framework)
    link_flags = []

    if is_macos:
        for fwk_dir in ctx.attrs.framework_dirs:
            link_flags.append("-F{}".format(fwk_dir))
        for framework in ctx.attrs.frameworks:
            link_flags.append("-framework")
            link_flags.append(framework)

    if pkg_config_ldflags_file:
        link_flags.append(cmd_args("@", pkg_config_ldflags_file, delimiter = ""))

    link_info = LinkInfo(pre_flags = link_flags)
    link_infos = {
        LibOutputStyle("archive"): LinkInfos(default = link_info),
        LibOutputStyle("pic_archive"): LinkInfos(default = link_info),
        LibOutputStyle("shared_lib"): LinkInfos(default = link_info),
    }

    providers.append(create_merged_link_info(
        ctx,
        toolchain.pic_behavior,
        link_infos,
        deps = dep_link_infos,
        preferred_linkage = Linkage("any"),
    ))

    # Build SharedLibrary records for runtime shared libs
    shared_lib_records = []
    for shlib_name in ctx.attrs.shared_libs:
        shlib_artifact = lib_dir.project(shlib_name)
        shared_lib_records.append(create_shlib(
            soname = shlib_name,
            lib = LinkedObject(output = shlib_artifact, unstripped_output = shlib_artifact),
            label = ctx.label,
        ))

    our_shared_libs = SharedLibraries(libraries = shared_lib_records)

    providers.append(merge_shared_libraries(
        ctx.actions,
        our_shared_libs if shared_lib_records else None,
        dep_shared_libs,
    ))

    linkable_graph = create_linkable_graph(
        ctx,
        node = create_linkable_graph_node(
            ctx,
            linkable_node = create_linkable_node(
                ctx = ctx,
                default_soname = None,
                preferred_linkage = Linkage("any"),
                link_infos = link_infos,
                shared_libs = our_shared_libs,
            ),
        ),
        deps = dep_linkable_graphs,
    )
    providers.append(linkable_graph)
    providers.append(merge_link_group_lib_info(deps = []))
    providers.append(DefaultInfo(default_output = lib_dir if lib_dir else nix_pkg))

    return providers

_flake_cxx_library_rule = rule(
    impl = _flake_cxx_library_impl,
    attrs = {
        "nix_pkg": attrs.dep(providers = [DefaultInfo]),
        "nix_dev_pkg": attrs.option(attrs.dep(providers = [DefaultInfo]), default = None),
        "nix_pkg_name": attrs.string(),
        "deps": attrs.list(attrs.dep(), default = []),
        "shared_libs": attrs.list(attrs.string(), default = []),
        "include_dirs": attrs.list(attrs.string(), default = []),
        "lib_dir": attrs.option(attrs.string(), default = None),
        "pkg_config": attrs.list(attrs.string(), default = []),
        "frameworks": attrs.list(attrs.string(), default = []),
        "framework_dirs": attrs.list(attrs.string(), default = []),
        "labels": attrs.list(attrs.string(), default = []),
        "_cxx_toolchain": toolchains_common.cxx(),
        "_target_os_type": buck.target_os_type_arg(),
    },
)

def _flake_cxx_library(
        name,
        path = "nixpkgs",
        package = None,
        dev_output = None,
        shared_libs = [],
        deps = [],
        include_dirs = [],
        lib_dir = None,
        pkg_config = None,
        frameworks = [],
        framework_dirs = [],
        visibility = ["PUBLIC"],
        **kwargs):
    """
    Creates a C++ library from a Nix flake package.

    All library names (-l flags) and frameworks are auto-resolved via pkg-config.

    Args:
        name: Target name (also used as default package name)
        path: Flake path (default: "nixpkgs")
        package: Nix package name (default: same as name)
        dev_output: Nix output for headers/pkgconfig (e.g., "dev" for split packages)
        shared_libs: List of .dylib/.so filenames for runtime staging
        deps: Buck2 dependencies to merge providers from
        include_dirs: Include paths relative to pkg root (default: ["include"])
        lib_dir: Library path relative to pkg root (default: "lib")
        pkg_config: List of pkg-config names to query (default: [package])
        frameworks: macOS frameworks to link (manual override, prefer pkg_config)
        framework_dirs: macOS framework search paths (-F)
    """
    if package == None:
        package = name
    if pkg_config == None:
        pkg_config = [package]

    nix_pkg_target = name + "__nix"
    _flake_package(
        name = nix_pkg_target,
        path = path,
        package = package,
    )

    nix_dev_pkg_ref = None
    if dev_output:
        nix_dev_pkg_target = name + "__nix_dev"
        _flake_package(
            name = nix_dev_pkg_target,
            path = path,
            package = package,
            output = dev_output,
        )
        nix_dev_pkg_ref = ":{}".format(nix_dev_pkg_target)

    _flake_cxx_library_rule(
        name = name,
        nix_pkg = ":{}".format(nix_pkg_target),
        nix_dev_pkg = nix_dev_pkg_ref,
        nix_pkg_name = package,
        deps = deps,
        shared_libs = shared_libs,
        include_dirs = include_dirs,
        lib_dir = lib_dir,
        pkg_config = pkg_config,
        frameworks = frameworks,
        framework_dirs = framework_dirs,
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
