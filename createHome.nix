# Creates a home directory populated with caches in ~/.m2
# (for maven dependencies) and ~/.gitlibs (for git dependencies) according
# to a lockfile generated with ./locker.py

{ pkgs, src, mavenRepos, lockfile }:
let
  lib = pkgs.lib;
  # Fall back to no dependencies if the lockfile hasn't been generated yet
  # Useful when your nix-shell evaluates this code, but the nix-shell also
  # provides the binary to produce the lockfile
  contents =
    if builtins.pathExists (src + "/${lockfile}")
    then lib.importJSON (src + "/${lockfile}")
    else { maven = {}; git = {}; };

  fetchMaven = file: sha256: {
    name = file;
    path = pkgs.fetchurl {
      # Try to fetch this maven dependency from all given maven repositories
      urls = map (repo: repo + file) mavenRepos;
      inherit sha256;
    };
  };

  handleGit = path: { url, rev, sha256, common_dir }: {
    name = path;
    path = pkgs.fetchgit {
      inherit url rev sha256;
    };
  };

  # Corresponds to the ~/.m2/repository directory
  mavenRepoCache = pkgs.linkFarm "maven-repo-cache" (lib.mapAttrsToList fetchMaven contents.maven);

  # This corresponds to the ~/.gitlibs/libs directory, containing git worktrees
  gitWorktreeCache = pkgs.linkFarm "git-worktree-cache" (lib.mapAttrsToList handleGit contents.git);

  # This corresponds to the ~/.gitlibs/_repos directory, containing git directories for the above worktrees
  gitFakeRepoCache = pkgs.runCommandNoCC "git-fake-repo-cache" {}
    # We don't actually need these, however clojure has a check for the existence of a
    # `config` file in these directories, so let's create empty ones

    # Note that we aren't using `linkFarm` for this because that would
    # give collisions for multiple entries at the same path
    ((lib.concatMapStringsSep "\n" (item: ''
      mkdir -p "$out"/${lib.escapeShellArg item.common_dir}
      touch "$out"/${lib.escapeShellArg item.common_dir}/config
    '') (lib.attrValues contents.git)) +
    # just so we don't fail in the 0-gitlibs case
    "mkdir -p $out");

  # Provides a ~/.clojure directory which clojure will accept read-only
  configDir = pkgs.runCommandNoCC "config-dir" {} ''
    mkdir -p $out/tools
    echo '{}' > $out/deps.edn
    echo '{}' > $out/tools/tools.edn
  '';

  # Creates the final home directory, combining all parts together
  result = pkgs.linkFarm "clojure-home" [
    {
      name = ".m2/repository";
      path = mavenRepoCache;
    }
    {
      name = ".gitlibs/libs";
      path = gitWorktreeCache;
    }
    {
      name = ".gitlibs/_repos";
      path = gitFakeRepoCache;
    }
    {
      name = ".clojure";
      path = configDir;
    }
  ];

in result
