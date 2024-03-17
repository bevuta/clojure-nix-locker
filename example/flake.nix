{
  description = "Example clojure project";

  inputs = {
    nixpkgs.url = "nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";

    clojure-nix-locker.url = "github:bevuta/clojure-nix-locker";
    clojure-nix-locker.inputs.nixpkgs.follows = "nixpkgs";
    clojure-nix-locker.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, clojure-nix-locker, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        my-clojure-nix-locker = clojure-nix-locker.lib.customLocker {
          inherit pkgs;
          command = "${pkgs.clojure}/bin/clojure -T:build uber";
          lockfile = "./deps.lock.json";
          src = ./.;
        };
      in rec {
        packages.uberjar = pkgs.stdenv.mkDerivation {
          pname = "clojure-nix-locker-example";
          version = "0.1";

          src = ./.;

          nativeBuildInputs = with pkgs; [
            makeWrapper
            clojure
            git
          ];

          buildPhase = ''
            source ${my-clojure-nix-locker.shellEnv}

            # Now compile as in https://clojure.org/guides/tools_build#_compiled_uberjar_application_build
            clojure -T:build uber
          '';

          installPhase = ''
            mkdir -p $out
            mv target/uber.jar $out/uber.jar

            makeWrapper ${pkgs.openjdk}/bin/java $out/bin/simple \
                --argv0 simple \
                --add-flags "-jar $out/uber.jar"
          '';
        };
        # use via `nix run .#locker`
        apps.locker = flake-utils.lib.mkApp {
          drv = my-clojure-nix-locker.locker;
        };
        devShells.default = pkgs.mkShell {
          shellHook = ''
            # Trace all Bash executions
            set -o xtrace

            source ${my-clojure-nix-locker.shellEnv}

            echo "Current locked classpath:"
            ${pkgs.clojure}/bin/clojure -Spath

            set +o xtrace

            echo
            echo "Note that \$HOME is overridden and read-only: $HOME"
            echo
          '';
          inputsFrom = [
            packages.uberjar
          ];
          buildInputs = with pkgs; [
            openjdk
            cacert # for maven and tools.gitlibs
            clojure
            clj-kondo
            coreutils
            # This provides the standalone `clojure-nix-locker` script in the shell
            # You can use it, or `nix run .#locker`
            # Both does the same
            my-clojure-nix-locker.locker
          ];
        };
      });
}
