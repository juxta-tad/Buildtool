{ pkgs, lib, config, ... }:

{
  # Disable cachix auto-management (requires trusted-users)
  #cachix.enable = false;

  # C/C++ language support
  languages.c.enable = true;
  languages.cplusplus.enable = true;

  # Packages
  packages = [
    pkgs.buck2
    pkgs.watchman

    # WebAssembly
    pkgs.wamr

    # Tooling
    pkgs.cmake
    pkgs.ninja
    pkgs.pkg-config
    pkgs.git
  ] ++ lib.optionals pkgs.stdenv.isDarwin [
    pkgs.darwin.cctools
  ];

  # Shell initialization
  enterShell = ''
    echo "Buck2 + Nix C++ development environment"
  '';
}
