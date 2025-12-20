{
  description = "Buck2 + Nix C++ project";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.raylib
          pkgs.pkg-config
        ];

        # clangd needs these for header resolution
        CPLUS_INCLUDE_PATH = builtins.concatStringsSep ":" [
          "${pkgs.libcxx.dev}/include/c++/v1"
          "${pkgs.raylib}/include"
        ];
      };
    };
}
