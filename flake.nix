{
  description = "Desktop File Search - Qt Quick application in Python";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          python3
          python3Packages.pyside6
          qt6.qtdeclarative
        ];

        shellHook = ''
          echo "Desktop File Search development environment"
          echo "Python version: $(python --version)"
          echo "Run 'python src/main.py' to start the app"
        '';
      };
    });

    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      python = pkgs.python3;
    in {
      default = pkgs.stdenv.mkDerivation {
        pname = "desktop-file-search";
        version = "0.1.0";

        src = builtins.path {
          path = ./.;
          name = "desktop-file-search-src";
        };
        dontWrapQtApps = true;

        nativeBuildInputs = with pkgs; [
          makeWrapper
        ];

        buildInputs = with pkgs; [
          python
          python.pkgs.pyside6
          qt6.qtbase
          qt6.qtdeclarative
          qt6.qtsvg
        ];

        installPhase = ''
          mkdir -p $out/bin
          mkdir -p $out/share/desktop-file-search
          cp -r $src/src $out/share/desktop-file-search/

          makeWrapper ${python}/bin/python $out/bin/desktop-file-search \
            --add-flags $out/share/desktop-file-search/src/main.py \
            --prefix PYTHONPATH : ${python.pkgs.pyside6}/${python.sitePackages} \
            --prefix PYTHONPATH : ${python.pkgs.shiboken6}/${python.sitePackages} \
            --prefix QML2_IMPORT_PATH : ${pkgs.qt6.qtdeclarative}/lib/qt-6/qml \
            --prefix QT_PLUGIN_PATH : ${pkgs.qt6.qtbase}/lib/qt-6/plugins \
            --prefix QT_PLUGIN_PATH : ${pkgs.qt6.qtsvg}/lib/qt-6/plugins \
            --set QSG_RHI_BACKEND software \
            --set QT_QUICK_BACKEND software

          mkdir -p $out/share/applications
          cp $src/desktop-file-search.desktop $out/share/applications/
          substituteInPlace $out/share/applications/desktop-file-search.desktop \
            --replace "Exec=desktop-file-search" "Exec=$out/bin/desktop-file-search"
        '';
      };
    });
  };
}
