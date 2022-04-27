{ pkgs ? import <nixpkgs> {} }:
let
  # normally you'd use e.g. fetchGit to get clojure-nix-locker.
  # inside this repo we can just use a local import.
  clojure-nix-locker = import ./.. { inherit pkgs; };

  lockfile = clojure-nix-locker.lockfile {
    gitRepo = ./.;
    lockfile = ./deps.lock.json;
  };

  locker = lockfile.commandLocker ''
    clojure -A:build -P
  '';

  src = ./.;

  uberjar = pkgs.runCommandNoCC "simple" {
    nativeBuildInputs = with pkgs; [
      makeWrapper
      clojure
      git
    ];
  } ''
    # Make the home directory writable, needed for babashka and clojure dependencies
    export HOME=$(mktemp -d)

    # java would use `/etc/passwd` to get the home directory, override it manually
    export JAVA_TOOL_OPTIONS="-Duser.home=$HOME"

    # Inject maven and git dependencies
    ln -sv ${lockfile.homeDirectory}/.{m2,gitlibs} "$HOME"

    # Copy sources
    # Not needed if you're using mkDerivation, the unpackPhase handles this.
    cp -r --no-preserve=mode ${./.}/* ./

    # Now compile as in https://clojure.org/guides/tools_build#_compiled_uberjar_application_build
    clj -T:build uber

    mkdir -p $out
    mv target/uber.jar $out/uber.jar

    makeWrapper ${pkgs.openjdk}/bin/java $out/bin/simple \
        --argv0 simple \
        --add-flags "-jar $out/uber.jar"
  '';

  shell = pkgs.mkShell {
    name = "devshell";
    inputsFrom = [
      uberjar
    ];
    buildInputs = with pkgs; [
      openjdk
      cacert # for maven and tools.gitlibs
      clojure
      clj-kondo
      coreutils
      locker
    ];
  };
in {
  inherit uberjar shell;
}
