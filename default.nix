{ pkgs ? import <nixpkgs> {} }:
let
  lib = pkgs.lib;
  es = lib.escapeShellArg;

  standaloneLocker = pkgs.writers.writePython3Bin "standalone-clojure-nix-locker" {
    libraries = [ pkgs.python3Packages.GitPython ];
    flakeIgnore = [
      "E501" # We don't care about lines being too long
      "W504" # Allow line breaks after binary operators for multi-line conditionals
    ];
  } ./locker.py;

  utils = import ./utils.nix { inherit pkgs; };
in {
  inherit standaloneLocker;

  lockfile =
    { # The git repository of this lockfile's project. If specified, a clean
      # version of this repository (including uncommitted changes but without
      # untracked files) will be available for lockfile generation
      src ? null
    , # The path to the lockfile, e.g. `./deps.lock.json`
      lockfile
    , # Specify the maven repositories to use, overriding the defaults
      mavenRepos ?
      [
        "https://repo1.maven.org/maven2/"
        "https://repo.clojars.org/"
      ]
    , # Extra inputs for the dependency "prep" phase
      extraPrepInputs ? [ ]
    }: rec {
      commandLocker = command: pkgs.writeShellApplication {
        name = "clojure-nix-locker";
        runtimeInputs = [
          pkgs.babashka
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
          pushd "$tmp/root"

          ${lib.optionalString (src != null)
            (if builtins.pathExists (src + "/.git") then ''
              # Copies all git-tracked files (including uncommitted changes and submodules)
              # Why not `git archive $(git stash create)`? Because that doesn't include submodules
              # Why not `git worktree create`? Because that doesn't include uncommitted changes
              # Why --ignore-failed-read? Because `git ls-files` includes deleted files
              git -C ${es (toString src)} ls-files -z \
                | tar -C ${es (toString src)} --ignore-failed-read -cz --null -T - \
                | tar -xzf -
            '' else ''
              cp -rT ${es (toString src)} .
            '')
          }

          # flakes are copied to the nix store first and the files are therefore RO
          chmod -R +w .

          # Ensures that clojure creates all the caches in our empty separate home directory
          export JAVA_TOOL_OPTIONS="-Duser.home=$tmp/home"

          ${command}

           popd

          ${standaloneLocker}/bin/standalone-clojure-nix-locker "$tmp/home" > ${es (toString lockfile)}
        '';
      };
      homeDirectory = import ./createHome.nix {
        inherit pkgs src lockfile mavenRepos extraPrepInputs;
      };
      shellEnv = utils.shellEnv homeDirectory;
      wrapClojure = utils.wrapClojure homeDirectory;
      wrapPrograms = utils.wrapPrograms homeDirectory;
    };
}
