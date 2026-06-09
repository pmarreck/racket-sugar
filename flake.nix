{
	description = "Tab-indented Racket dialect + converters";

	inputs = {
		# Pinned to nixos-24.11: its aarch64-darwin racket-8.14 is a cached binary on
		# cache.nixos.org. nixos-unstable / 25.05 racket-8.18 are NOT cached on darwin,
		# which forced an hours-long source build on `direnv allow`.
		nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
		flake-utils.url = "github:numtide/flake-utils";
	};

	outputs = { self, nixpkgs, flake-utils }:
		flake-utils.lib.eachDefaultSystem (system:
			let
				pkgs = import nixpkgs { inherit system; config.allowUnsupportedSystem = true; };
			in {
			packages.default = pkgs.stdenv.mkDerivation {
				pname = "racket-sugar";
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
