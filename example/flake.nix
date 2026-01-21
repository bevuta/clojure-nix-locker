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
            # Overrides $HOME as well. Great for building, not great for devShells
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

            echo "Current locked classpath:"

            # This will work, but, $HOME will be read-only which is probably not what you want in a devShell
            #source ${my-clojure-nix-locker.shellEnv}
            #${pkgs.clojure}/bin/clojure -Spath

            # Using the provided lockedClojure will do what you want
            # And if pkgs.clojure is referenced anywhere, it may override it
            ${my-clojure-nix-locker.lockedClojure}/bin/clojure -Spath

            set +o xtrace

            echo
            echo "Note that \$HOME will be overriden if you sourced my-clojure-nix-locker.shellEnv: $HOME"
            echo "If you used my-clojure-nix-locker.lockedClojure, it will be left alone and only the clojure and clj commands are overridden and locked"
            echo
            echo "This command should be locked in this shell:"
            echo "clojure -Spath"
            echo
          '';
          inputsFrom = [
            # Will pull in pkgs.clojure, and we want my-clojure-nix-locker.lockedClojure
            #packages.uberjar
          ];
          buildInputs = with pkgs; [
            openjdk
            cacert # for maven and tools.gitlibs
            clj-kondo
            coreutils
            # This provides the standalone `clojure-nix-locker` script in the shell
            # You can use it, or `nix run .#locker`
            # Both does the same
            my-clojure-nix-locker.locker
            # Use the locked clojure
            # A pkgs.clojure reference could override it
            my-clojure-nix-locker.lockedClojure
          ];
        };
      });
}
