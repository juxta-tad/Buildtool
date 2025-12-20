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

        # pkg-config finds raylib automatically via PKG_CONFIG_PATH (set by mkShell)
        # clangd finds headers via CPLUS_INCLUDE_PATH
        CPLUS_INCLUDE_PATH = "${pkgs.raylib}/include";
      };
    };
}
