{
  description = "Build config and development environment for Cadence";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zls-overlay.url = "github:zigtools/zls/0.15.1";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      zig-overlay,
      zls-overlay,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        version = "0.0.0";
        pkgs = nixpkgs.legacyPackages.${system};
        zig = zig-overlay.packages.${system}."0.15.1";
        zls = zls-overlay.packages.${system}.zls;
      in
      {
        packages = {
          default = pkgs.stdenv.mkDerivation {
            inherit version;
            pname = "cadence";

            src = ./.;
            nativeBuildInputs = [
              zig
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              pkgs.autoPatchelfHook
            ];
            buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              pkgs.glibc
            ];

            postPatch = ''
              # This should be unnecessary when https://github.com/ziglang/zig/issues/20976 is closed.
              mkdir -p .cache
              ln -s ${pkgs.callPackage ./deps.nix { }} .cache/p
            '';

            buildPhase = "zig build -Doptimize=ReleaseSafe --global-cache-dir $(pwd)/.cache";
            installPhase = ''
              mkdir -p $out/bin
              cp zig-out/bin/cadence $out/bin/
            '';

            meta = with pkgs.lib; {
              description = "High-performance, cross-platform task orchestration system for any codebase";
              homepage = "https://github.com/meechdw/cadence";
              license = licenses.mit;
              platforms = platforms.all;
              mainProgram = "cadence";
            };
          };

          cadence = self.packages.${system}.default;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bash-language-server
            git
            just
            nixd
            nixfmt
            prettier
            prettierd
            (python3.withPackages (ps: [ ps.mkdocs-material ]))
            taplo
            vscode-json-languageserver
            watchexec
            yaml-language-server
            zig
            zls
          ];
        };
      }
    );
}
