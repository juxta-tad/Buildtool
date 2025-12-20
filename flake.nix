{
  description = "Buck2 + Nix C++ project";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = fn: nixpkgs.lib.genAttrs supportedSystems (system: fn nixpkgs.legacyPackages.${system});
    in {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          buildInputs = [
            pkgs.llvmPackages_18.clang
            pkgs.llvmPackages_18.bintools
            pkgs.watchman
          ];
        };
      });
    };
}
