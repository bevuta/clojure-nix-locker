{
  description = "Example clojure project";

  inputs = {
    nixpkgs.url = "nixpkgs";
    cloure-nix-locker.url = "github:bevuta/clojure-nix-locker";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, clojure-nix-locker, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        my-clojure-nix-locker = clojure-nix-locker.lib.customLocker {
          inherit pkgs;
          # XXX: For some reason this command doesn't work. There is some
          #      clojure maven download that happens later in the build process.
          # command = "${pkgs.clojure}/bin/clojure A:build -P";
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

          # XXX: I would like to replace the beginning of this with ${my-clojure-nix-locker.shellEnv}, but that produces a non-writeable home directory. what should we do here?
          #      - make shellEnv work like this
          #      - does this actually need HOME to be writeable?
          #      - make a separate writeableShellEnv
          #      - leave it as is with this just not using shellEnv
          buildPhase = ''
            # Make the home directory writable, needed for babashka and clojure dependencies
            export HOME=$(mktemp -d)

            # java would use `/etc/passwd` to get the home directory, override it manually
            export JAVA_TOOL_OPTIONS="-Duser.home=$HOME"

            # Inject maven and git dependencies
            ln -sv ${my-clojure-nix-locker.homeDirectory}/.{m2,gitlibs} "$HOME"

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
          inputsFrom = [
            packages.uberjar
          ];
          buildInputs = with pkgs; [
            openjdk
            cacert # for maven and tools.gitlibs
            clojure
            clj-kondo
            coreutils
            my-clojure-nix-locker.locker
          ];
        };
      });
}
