{
  description = "Desktop File Search - GTK4 application in Zig";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    zigVersion = "0.15.2";
  in {
    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          zig
          pkg-config
          gtk4
          glib
          pango
          cairo
          gdk-pixbuf
          graphene
          harfbuzz
          wrapGAppsHook4
        ];

        shellHook = ''
          echo "Desktop File Search development environment"
          echo "Zig version: $(zig version)"
          echo "Run 'zig build run' to build and run the app"
        '';
      };
    });

    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.stdenv.mkDerivation {
        pname = "desktop-file-search";
        version = "0.1.0";

        src = ./.;

        nativeBuildInputs = with pkgs; [
          zig
          pkg-config
          wrapGAppsHook4
        ];

        buildInputs = with pkgs; [
          gtk4
          glib
          pango
          cairo
          gdk-pixbuf
          graphene
          harfbuzz
        ];

        buildPhase = ''
          export HOME=$TMPDIR
          zig build -Doptimize=ReleaseSafe
        '';

        installPhase = ''
          mkdir -p $out/bin
          cp zig-out/bin/desktop-file-search $out/bin/
        '';
      };
    });
  };
}