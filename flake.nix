{
  description = "A Zig project with specific Zig version (0.14.1)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    zig-overlay,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (system: let
      zigVersion = "0.14.1";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (final: prev: {
            zigpkgs = inputs.zig-overlay.packages.${prev.system};
          })
        ];
      };
      zig = pkgs.zigpkgs.${zigVersion};
    in {
      devShells.default = pkgs.mkShell {
        packages = [
          # Core tools
          zig
          pkgs.pkg-config # Helps find libraries (very important)
        ];

        shellHook = ''
          echo "--- Raylib Zig Project Environment ---"
          echo "| Zig compiler:   $(zig version) (from zig-overlay)"
          echo "| Target shell:   Nushell ($(nu --version))"
        '';
      };
    });
}
