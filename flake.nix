{
  description = "zigdragon flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    pkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
  in {
    devShells = forAllSystems (system:
    let
      pkgs = pkgsFor.${system};
    in {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [ zig_0_16 ];

        shellHook = ''
          echo "Using zigdragon devShell!"
          echo "Zig version: $(zig version)"
          echo ""
        '';
      };
    });

    packages = forAllSystems (system:
    let
      pkgs = pkgsFor.${system};
    in {
      default = pkgs.stdenv.mkDerivation {
        pname = "zigdragon";
        version = "0.3";
        src = ./.;
        nativeBuildInputs = with pkgs; [ zig_0_16 ];

        buildPhase = ''
          zig build-exe zigdragon.zig \
          -O ReleaseSmall \
          -fstrip \
          -fsingle-threaded \
        '';

        installPhase = ''
          mkdir -p $out/bin
          cp zigdragon $out/bin
        '';
      };
    });
  };
}
