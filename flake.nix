{
  description = "Buck2 + Nix C++ project";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = fn:
        nixpkgs.lib.genAttrs supportedSystems (system:
          fn nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs:
        let
          llvm = pkgs.llvmPackages_18;

          # Only expose the compiler from clang, not the tools.
          # clang-tools provides properly wrapped versions of clangd, clang-format, etc.
          # See: https://github.com/NixOS/nixpkgs/issues/76486
          clangOnly = pkgs.runCommand "clang-only" { } ''
            mkdir -p $out/bin
            ln -s ${llvm.clang}/bin/clang $out/bin/
            ln -s ${llvm.clang}/bin/clang++ $out/bin/
            ln -s ${llvm.clang}/bin/clang-cpp $out/bin/
          '';
        in {
        default = pkgs.mkShell {
          packages =
            [
              pkgs.buck2
              pkgs.watchman

              # LLVM toolchain
              llvm.clang-tools
              clangOnly
              llvm.lld

              # nice-to-have tooling
              pkgs.cmake
              pkgs.ninja
              pkgs.pkg-config
              pkgs.git
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              llvm.lldb
              pkgs.darwin.cctools
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
              llvm.bintools
              pkgs.gdb
            ];

          shellHook = ''
            export CC=clang
            export CXX=clang++

            if [ "$(uname -s)" = "Darwin" ]; then
              export LD=ld64.lld
              # Use Xcode's debugserver for lldb (Nix lldb lacks signed debugserver)
              export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
            else
              export LD=ld.lld
            fi
          '';
        };
      });

      templates.default = {
        path = ./.;
        description = "Buck2 + Nix C++ project template";
      };
    };
}
