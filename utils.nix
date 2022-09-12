{ pkgs }:

rec {
  shellEnv = homeDirectory: pkgs.writeTextFile {
    name = "clojure-nix-locker.shell-env";
    text = ''
          export HOME="${homeDirectory}"
          export JAVA_TOOL_OPTIONS="-Duser.home=${homeDirectory}"
        '';
    meta = {
      description = ''
            Can be sourced in shell scripts to export environment
            variables so that `clojure` uses the locked dependencies.
          '';
    };
  };
  wrapClojure = homeDirectory: clojure:
    (pkgs.runCommandNoCC "locked-clojure" { buildInputs = [ pkgs.makeWrapper ]; } ''
          mkdir -p $out/bin
          makeWrapper ${clojure}/bin/clojure $out/bin/clojure \
            --run "source ${shellEnv homeDirectory}"
          makeWrapper ${clojure}/bin/clj $out/bin/clj \
            --run "source ${shellEnv homeDirectory}"
        '');
}
