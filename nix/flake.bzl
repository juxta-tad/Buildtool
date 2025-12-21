# flake.bzl - Buck2 rules for building Nix flake packages
#
# Usage:
#   load("//nix:flake.bzl", "flake")
#
#   flake.package(name = "jq", package = "jq", binary = "jq")
#   flake.cxx_library(name = "raylib", libs = ["raylib"], frameworks = ["OpenGL", ...])

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
# pkg-config .pc file parser (pure Starlark)
# -----------------------------------------------------------------------------

def _unescape_pc_value(val: str) -> str:
    """Handle common escape sequences in .pc file values."""
    # Process escapes by splitting on backslash and handling each segment
    # First, replace known escape sequences with placeholders, then restore
    escape_map = [
        ("\\n", "\n"),
        ("\\t", "\t"),
        ("\\\\", "\x00BACKSLASH\x00"),  # Temporary placeholder
        ("\\$", "$"),
        ("\\#", "#"),
    ]

    result = val
    for escape, replacement in escape_map:
        result = result.replace(escape, replacement)

    # Restore backslashes from placeholder
    result = result.replace("\x00BACKSLASH\x00", "\\")

    return result

def _subst_pc_vars(val: str, vars: dict) -> str:
    """Substitute ${var} references, repeating until stable (max 10 iterations)."""
    for _ in range(10):
        new_val = val
        for k, v in vars.items():
            new_val = new_val.replace("${" + k + "}", v)
        if new_val == val:
            break
        val = new_val
    return val

def _join_continued_lines(content: str) -> list[str]:
    """Join lines ending with backslash (line continuation)."""
    lines = content.split("\n")
    result = []
    current = ""

    for line in lines:
        # Check for trailing backslash (line continuation)
        if line.endswith("\\"):
            current += line[:-1]  # Remove backslash, append content
        else:
            current += line
            result.append(current)
            current = ""

    # Handle case where file ends with continuation
    if current:
        result.append(current)

    return result

def _parse_pc_file(content: str, pc_file_loader = None) -> struct:
    """Parse a .pc file and extract Cflags and Libs with variable substitution.

    Handles:
    - Variable substitution (${var})
    - Escaped characters (\\, \$, \#, \n, \t)
    - Multi-line continuations (trailing backslash)
    - Requires/Requires.private directives (returns package names for caller to resolve)

    Filters out -I and -L flags since we provide our own copied paths.
    Keeps other flags like -D, -l, -framework, etc.

    Args:
        content: The .pc file content as a string
        pc_file_loader: Optional function(pkg_name) -> content for loading required .pc files

    Returns:
        struct with cflags, libs, and requires (list of required package names)
    """
    vars = {}
    cflags = []
    libs = []
    requires = []

    lines = _join_continued_lines(content)

    for line in lines:
        # Strip whitespace
        line = line.strip()

        # Skip empty lines and comments
        if not line or line.startswith("#"):
            continue

        # Variable assignment: name=value (no colon before =)
        if "=" in line and ":" not in line.split("=")[0]:
            k, v = line.split("=", 1)
            k = k.strip()
            v = v.strip()
            v = _unescape_pc_value(v)
            vars[k] = _subst_pc_vars(v, vars)

        # Keyword: field: value
        elif ":" in line:
            k, v = line.split(":", 1)
            k = k.strip()
            v = v.strip()
            v = _unescape_pc_value(v)
            v = _subst_pc_vars(v, vars)

            if k == "Cflags":
                # Filter out -I flags (we provide our own include paths)
                cflags.extend([f for f in v.split() if not f.startswith("-I")])

            elif k == "Libs":
                # Filter out -L flags (we provide our own lib paths), keep -l and others
                libs.extend([f for f in v.split() if not f.startswith("-L")])

            elif k == "Libs.private":
                # Private libs needed for static linking
                libs.extend([f for f in v.split() if not f.startswith("-L")])

            elif k in ("Requires", "Requires.private"):
                # Parse required packages: "pkg1, pkg2 >= 1.0, pkg3"
                # Strip version constraints and collect package names
                for dep in v.split(","):
                    dep = dep.strip()
                    if not dep:
                        continue
                    # Extract package name (first token before any version operator)
                    for op in [">=", "<=", "!=", "=", ">", "<"]:
                        if op in dep:
                            dep = dep.split(op)[0].strip()
                            break
                    if dep and dep not in requires:
                        requires.append(dep)

    # Recursively load required .pc files if loader provided
    if pc_file_loader and requires:
        for req_pkg in requires:
            req_content = pc_file_loader(req_pkg)
            if req_content:
                req_parsed = _parse_pc_file(req_content, pc_file_loader)
                # Merge flags (avoid duplicates)
                for flag in req_parsed.cflags:
                    if flag not in cflags:
                        cflags.append(flag)
                for flag in req_parsed.libs:
                    if flag not in libs:
                        libs.append(flag)

    return struct(cflags = cflags, libs = libs, requires = requires)

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

    # Declare a directory for the nix out-link, then reference the result symlink within it
    nix_out_dir = ctx.actions.declare_output("nix_out", dir = True)
    # Nix names the symlink "result" for default output, "result-{output}" for others
    result_name = "result" if output == "out" else "result-{}".format(output)
    nix_build = cmd_args([
        "env", "--",
        "nix", "--extra-experimental-features", "nix-command flakes",
        "build",
        "--out-link", cmd_args(nix_out_dir.as_output(), "result", delimiter = "/"),
        cmd_args(flake_path, attribute, delimiter = "#") if flake_path else attribute,
    ])
    ctx.actions.run(nix_build, category = "nix_build", identifier = attribute, local_only = ctx.attrs.local_only)

    # The result symlink is at nix_out_dir/result (or result-{output} for non-default outputs)
    nix_result = nix_out_dir.project(result_name)

    if ctx.attrs.materialize:
        # Copy to materialize (dereference symlinks)
        out_dir = ctx.actions.declare_output("out", dir = True)
        ctx.actions.run(
            cmd_args(["cp", "-rL", nix_result, out_dir.as_output()]),
            category = "nix_materialize",
            identifier = package,
            local_only = ctx.attrs.local_only,
        )
        out = out_dir
    else:
        out = nix_result

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
        "materialize": attrs.bool(default = False),
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

    # Copy the include tree once, then map subdirs via -isystem flags
    include_dirs_attr = ctx.attrs.include_dirs if ctx.attrs.include_dirs else ["include"]
    lib_path = ctx.attrs.lib_dir if ctx.attrs.lib_dir else "lib"

    # Determine the root include dir to copy (first component of first include_dirs entry)
    include_root_src = include_dirs_attr[0].split("/")[0] if include_dirs_attr else "include"

    # Copy the entire include tree once (from dev package if available)
    include_dir = ctx.actions.declare_output("include", dir = True)
    ctx.actions.run(
        cmd_args(["cp", "-rL", cmd_args(nix_dev_pkg, include_root_src, delimiter = "/"), include_dir.as_output()]),
        category = "nix_copy_include",
        identifier = ctx.label.name,
    )

    # Copy lib directory (from main package)
    lib_dir = ctx.actions.declare_output("lib", dir = True)
    ctx.actions.run(
        cmd_args(["cp", "-rL", cmd_args(nix_pkg, lib_path, delimiter = "/"), lib_dir.as_output()]),
        category = "nix_copy_lib",
        identifier = ctx.label.name,
    )

    # Parse pkg-config .pc files using dynamic_output (pure Starlark parsing)
    pkg_config_cflags_file = None
    pkg_config_ldflags_file = None
    if ctx.attrs.pkg_config:
        pkg_config_cflags_file = ctx.actions.declare_output("pkg_config_cflags.txt")
        pkg_config_ldflags_file = ctx.actions.declare_output("pkg_config_ldflags.txt")

        pc_names = ctx.attrs.pkg_config
        pc_dir = ctx.attrs.pkg_config_dir if ctx.attrs.pkg_config_dir else "lib/pkgconfig"

        # Copy .pc files from dev package (or main package if no dev)
        pc_copied = []
        for pc_name in pc_names:
            pc_out = ctx.actions.declare_output("pkgconfig/{}.pc".format(pc_name))
            ctx.actions.run(
                cmd_args([
                    "cp",
                    cmd_args(nix_dev_pkg, pc_dir, "{}.pc".format(pc_name), delimiter = "/"),
                    pc_out.as_output(),
                ]),
                category = "pkg_config_copy",
                identifier = "{}_{}".format(ctx.label.name, pc_name),
            )
            pc_copied.append(pc_out)

        # Use dynamic_output to read and parse .pc files
        def _make_pkg_config_generator(pc_files, pc_names_list, cflags_out, ldflags_out, pkgconfig_dir_artifact):
            def _generate_pkg_config_flags(ctx, artifacts, outputs):
                all_cflags = []
                all_libs = []

                # Build a map of package name -> content for the packages we have
                pc_contents = {}
                for i, pc_file in enumerate(pc_files):
                    content = artifacts[pc_file].read_string()
                    pc_contents[pc_names_list[i]] = content

                # Create a loader function for transitive deps
                # Note: This only works for deps within the same pkgconfig dir
                def _load_required_pc(pkg_name):
                    if pkg_name in pc_contents:
                        return pc_contents[pkg_name]
                    # Try to load from the pkgconfig directory
                    # This is a best-effort for transitive deps in the same package
                    return None

                for pc_name in pc_names_list:
                    content = pc_contents.get(pc_name)
                    if content:
                        parsed = _parse_pc_file(content, _load_required_pc)
                        # Merge flags (avoid duplicates)
                        for flag in parsed.cflags:
                            if flag not in all_cflags:
                                all_cflags.append(flag)
                        for flag in parsed.libs:
                            if flag not in all_libs:
                                all_libs.append(flag)

                # Write one flag per line for safer response file parsing
                ctx.actions.write(outputs[cflags_out], "\n".join(all_cflags))
                ctx.actions.write(outputs[ldflags_out], "\n".join(all_libs))

            return _generate_pkg_config_flags

        ctx.actions.dynamic_output(
            dynamic = pc_copied,
            inputs = [],
            outputs = [pkg_config_cflags_file.as_output(), pkg_config_ldflags_file.as_output()],
            f = _make_pkg_config_generator(pc_copied, pc_names, pkg_config_cflags_file, pkg_config_ldflags_file, nix_pkg),
        )

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
    # Map each include_dirs entry to the appropriate subdir of our copied include tree
    pre_args = []
    for inc_path in include_dirs_attr:
        # Strip the root component we copied (e.g., "include/foo" -> "foo")
        if "/" in inc_path:
            subdir = "/".join(inc_path.split("/")[1:])
            pre_args.append(cmd_args("-isystem", cmd_args(include_dir, subdir, delimiter = "/"), delimiter = ""))
        else:
            pre_args.append(cmd_args("-isystem", include_dir, delimiter = ""))
    if pkg_config_cflags_file:
        pre_args.append(cmd_args("@", pkg_config_cflags_file, delimiter = ""))

    pre = CPreprocessor(
        args = CPreprocessorArgs(args = pre_args),
    )
    providers.append(cxx_merge_cpreprocessors(ctx.actions, [pre], dep_preprocessors))

    # Linker flags
    link_flags = [cmd_args("-L", lib_dir, delimiter = "")]
    for lib in ctx.attrs.libs:
        link_flags.append("-l{}".format(lib))

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
    providers.append(DefaultInfo(default_output = lib_dir))

    return providers

_flake_cxx_library_rule = rule(
    impl = _flake_cxx_library_impl,
    attrs = {
        "nix_pkg": attrs.dep(providers = [DefaultInfo]),
        "nix_dev_pkg": attrs.option(attrs.dep(providers = [DefaultInfo]), default = None),
        "deps": attrs.list(attrs.dep(), default = []),
        "libs": attrs.list(attrs.string(), default = []),
        "shared_libs": attrs.list(attrs.string(), default = []),
        "include_dirs": attrs.list(attrs.string(), default = []),
        "lib_dir": attrs.option(attrs.string(), default = None),
        "pkg_config": attrs.list(attrs.string(), default = []),
        "pkg_config_dir": attrs.option(attrs.string(), default = None),
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
        libs = None,
        shared_libs = [],
        deps = [],
        include_dirs = [],
        lib_dir = None,
        pkg_config = [],
        pkg_config_dir = None,
        frameworks = [],
        framework_dirs = [],
        visibility = ["PUBLIC"],
        **kwargs):
    """
    Creates a C++ library from a Nix flake package.

    Args:
        name: Target name (also used as default package and lib name)
        path: Flake path (default: "nixpkgs")
        package: Nix package name (default: same as name)
        dev_output: Nix output for headers/pkgconfig (e.g., "dev" for split packages)
        libs: List of library names to link (default: [name])
        shared_libs: List of .dylib/.so filenames for runtime staging
        deps: Buck2 dependencies to merge providers from
        include_dirs: Include paths relative to pkg root (default: ["include"])
        lib_dir: Library path relative to pkg root (default: "lib")
        pkg_config: List of pkg-config package names to query for extra flags
        pkg_config_dir: Directory containing .pc files (default: "lib/pkgconfig")
        frameworks: macOS frameworks to link
        framework_dirs: macOS framework search paths (-F)
    """
    if package == None:
        package = name
    if libs == None:
        libs = [name]

    nix_pkg_name = name + "__nix"
    _flake_package(
        name = nix_pkg_name,
        path = path,
        package = package,
    )

    nix_dev_pkg_ref = None
    if dev_output:
        nix_dev_pkg_name = name + "__nix_dev"
        _flake_package(
            name = nix_dev_pkg_name,
            path = path,
            package = package,
            output = dev_output,
        )
        nix_dev_pkg_ref = ":{}".format(nix_dev_pkg_name)

    _flake_cxx_library_rule(
        name = name,
        nix_pkg = ":{}".format(nix_pkg_name),
        nix_dev_pkg = nix_dev_pkg_ref,
        deps = deps,
        libs = libs,
        shared_libs = shared_libs,
        include_dirs = include_dirs,
        lib_dir = lib_dir,
        pkg_config = pkg_config,
        pkg_config_dir = pkg_config_dir,
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
