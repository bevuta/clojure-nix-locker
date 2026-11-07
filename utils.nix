{ pkgs }:

rec {
  shellEnv = homeDirectory:
    let
      prepareHome = pkgs.writeShellScript "prepare-clojure-home" ''
        set -euo pipefail
        umask 077
        cache="$XDG_CACHE_HOME/clojure-nix-locker"
        test ! -L "$cache"
        ${pkgs.coreutils}/bin/mkdir -p "$cache"
        test -O "$cache"
        ${pkgs.coreutils}/bin/chmod 700 "$cache"
        target="$cache/${builtins.baseNameOf homeDirectory}"
        if [ ! -d "$target" ]; then
          home=$(${pkgs.coreutils}/bin/mktemp -d "$cache/.tmp.XXXXXXXXXX")
          trap '${pkgs.coreutils}/bin/rm -rf "$home"' EXIT
          ${pkgs.coreutils}/bin/mkdir -p "$home/.m2"
          ${pkgs.coreutils}/bin/ln -s ${homeDirectory}/.gitlibs "$home/.gitlibs"
          ${pkgs.coreutils}/bin/ln -s ${homeDirectory}/.clojure "$home/.clojure"
          ${pkgs.coreutils}/bin/ln -s ${homeDirectory}/.m2/settings.xml "$home/.m2/settings.xml"
          # Writable directories let Maven replace metadata without copying artifacts.
          ${pkgs.coreutils}/bin/cp -rH --no-preserve=mode ${homeDirectory}/.m2/repository "$home/.m2/"
          # Publish a complete tree atomically; another invocation may win the race.
          ${pkgs.coreutils}/bin/mv -T --no-clobber "$home" "$target"
        fi
        test -d "$target" && test ! -L "$target" && test -O "$target" && test -L "$target/.m2/settings.xml" || exit 1
        printf '%s\n' "$target"
      '';
    in pkgs.writeTextFile {
      name = "clojure-nix-locker.shell-env";
      text = ''
        export XDG_CACHE_HOME="''${NIX_BUILD_TOP:-''${XDG_CACHE_HOME:-''${HOME:?}/.cache}}"
        HOME=$(${prepareHome}) || return 1
        export HOME
        export JAVA_TOOL_OPTIONS="-Duser.home=\"$HOME\""
        export GITLIBS="$HOME/.gitlibs"
        export CLJ_CONFIG="$HOME/.clojure"
        export CLJ_CACHE="$HOME/.cpcache"
      '';
      meta = {
        description = ''
              Can be sourced in shell scripts to export environment
              variables so that `clojure` uses the locked dependencies.
            '';
      };
    };
  wrapPrograms = homeDirectory: name: paths:
    let script = pkgs.lib.concatMapStrings (path: ''
        makeWrapper "${path}" "$out/bin/$(basename "${path}")" \
          --run "source ${shellEnv homeDirectory} || exit 1"
      '')
      paths;
    in
      pkgs.runCommand name { buildInputs = [ pkgs.makeWrapper ]; } ''
          mkdir -p $out/bin
          ${script}
        '';
  wrapClojure = homeDirectory: clojure:
    wrapPrograms homeDirectory "locked-clojure" ["${clojure}/bin/clojure"
                                                 "${clojure}/bin/clj"];
}
