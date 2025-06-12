{
  description = "A flake for the catd Zig project";

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
      pkgs = import nixpkgs {
        inherit system;
        overlays = [zig-overlay.overlays.default];
      };

      zigVersion = "0.14.1";
      projectName = "catd";
      zig = pkgs.zigpkgs.${zigVersion};
    in {
      packages.${projectName} = pkgs.stdenv.mkDerivation {
        pname = projectName;
        version = "0.1.0";
        src = self;

        nativeBuildInputs = [zig];

        buildPhase = ''
          # Set the cache directory to a temporary, writable location
          export ZIG_GLOBAL_CACHE_DIR="$(pwd)/zig-cache"

          # Now run the build command
          zig build -Doptimize=ReleaseFast
        '';

        installPhase = ''
          # Create the bin directory in the output path
          mkdir -p $out/bin
          # Copy the compiled binary from zig's output to the Nix output
          cp zig-out/bin/${projectName} $out/bin/
        '';
      };

      defaultPackage = self.packages.${system}.${projectName};

      devShells.default = pkgs.mkShell {
        packages = [zig pkgs.zls pkgs.pkg-config];
      };
    });
}
