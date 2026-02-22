{
  description = "A Nix-flake-based development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f: lib.genAttrs supportedSystems (system: f rec {
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
      });
    in
    {
      packages = forEachSupportedSystem ({ pkgs }: {
        default = pkgs.rustPlatform.buildRustPackage {
          pname = "trolley";
          version = (lib.importTOML ./cli/Cargo.toml).package.version;
          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./cli
              ./config
            ];
          };
          cargoLock.lockFile = ./cli/Cargo.lock;
          buildAndTestSubdir = "cli";
          postUnpack = ''
            cp source/cli/Cargo.lock source/Cargo.lock
          '';
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = [ pkgs.xz ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              pkgs.darwin.apple_sdk.frameworks.Security
              pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
            ];
        };
      });

      devShells = forEachSupportedSystem ({ pkgs }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            # trolley build toolchain
            zig
            pkg-config

            # Rust (trolley CLI)
            cargo
            rustc
            rustfmt
            clippy
            rust-analyzer

            # Task runner
            just

            # X11 / windowing (for GLFW wrapper)
            glfw
            libxkbcommon
            libx11
            libxcursor
            libxext
            libxi
            libxinerama
            libxrandr
          ];

          shellHook = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
            # Ghostty's build.zig eagerly builds for iOS even when we only need
            # macOS. Nix only ships a macOS SDK, so we unset Nix's SDK env vars
            # and let Zig discover the system Xcode which has all Apple SDKs.
            unset SDKROOT
            unset DEVELOPER_DIR
            export PATH=$(echo "$PATH" | awk -v RS=: -v ORS=: '$0 !~ /xcrun/ || $0 == "/usr/bin" {print}' | sed 's/:$//')
          '';
        };
      });
    };
}
