{
	description = "Tab-indented Racket dialect + converters";

	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
		flake-utils.url = "github:numtide/flake-utils";
	};

	outputs = { self, nixpkgs, flake-utils }:
		flake-utils.lib.eachDefaultSystem (system:
			let
				pkgs = import nixpkgs { inherit system; config.allowUnsupportedSystem = true; };
			in {
			packages.default = pkgs.stdenv.mkDerivation {
				pname = "tab-racket";
				version = "0.0.1";
				src = ./.;
				buildInputs = [ pkgs.racket ];
				installPhase = "mkdir -p $out/src && cp -r src $out/src";
			};

			devShells.default = pkgs.mkShell {
				packages = [ pkgs.racket ];
				shellHook = ''
					echo "Dev shell: racket=$(racket --version)"
				'';
			};
			});
}
