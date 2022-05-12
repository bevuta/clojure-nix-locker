{ pkgs ? import <nixpkgs> {} }:
let
  lib = pkgs.lib;
  es = lib.escapeShellArg;

  standaloneLocker = pkgs.writers.writePython3Bin "standalone-clojure-nix-locker" {
    libraries = [ pkgs.python3Packages.GitPython ];
    # We don't care about lines being too long
    flakeIgnore = [ "E501" ];
  } ./locker.py;
in {
  inherit standaloneLocker;

  lockfile =
    { # The git repository of this lockfile's project. If specified, a clean
      # version of this repository (including uncommitted changes but without
      # untracked files) will be available for lockfile generation
      gitRepo ? null
    , # The path to the lockfile, e.g. `./deps.lock.json`
      lockfile
    , # Specify the maven repositories to use, overriding the defaults
      mavenRepos ?
      [
        "https://repo1.maven.org/maven2/"
        "https://repo.clojars.org/"
      ]
    }: rec {
      commandLocker = command: pkgs.writeShellApplication {
        name = "clojure-nix-locker";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.gnutar
          pkgs.gzip
          pkgs.nix-prefetch-git
        ];
        text = ''
          tmp=$(mktemp -d)
          trap 'rm -rf "$tmp"' exit
          mkdir "$tmp"/{root,home}
          cd "$tmp/root"

          ${lib.optionalString (gitRepo != null)
            (if builtins.pathExists (gitRepo + "/.git") then ''
              # Copies all git-tracked files (including uncommitted changes and submodules)
              # Why not `git archive $(git stash create)`? Because that doesn't include submodules
              # Why not `git worktree create`? Because that doesn't include uncommitted changes
              # Why --ignore-failed-read? Because `git ls-files` includes deleted files
              git -C ${es (toString gitRepo)} ls-files -z \
                | tar -C ${es (toString gitRepo)} --ignore-failed-read -cz --null -T - \
                | tar -xzf -
            '' else ''
              cp -rT ${es (toString gitRepo)} .
            '')
          }

          # Ensures that clojure creates all the caches in our empty separate home directory
          export JAVA_TOOL_OPTIONS="-Duser.home=$tmp/home"

          ${command}

          ${standaloneLocker}/bin/standalone-clojure-nix-locker "$tmp/home" > ${es (toString lockfile)}
        '';
      };
      homeDirectory = import ./createHome.nix {
        inherit pkgs lockfile mavenRepos;
      };
      shellEnv = pkgs.writeTextFile {
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
      wrapClojure = clojure:
        (pkgs.runCommandNoCC "locked-clojure" { buildInputs = [ pkgs.makeWrapper ]; } ''
          mkdir -p $out/bin
          makeWrapper ${clojure}/bin/clojure $out/bin/clojure \
            --run "source ${shellEnv}"
          makeWrapper ${clojure}/bin/clj $out/bin/clj \
            --run "source ${shellEnv}"
        '');
  };
}
