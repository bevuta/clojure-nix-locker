{
  description = "Build clojure projects with nix by creating a lockfile for maven and git dependencies";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }: {

    lib = rec {
      customLocker =
        { pkgs
        , # The directory of this lockfile's project. If specified, a clean
          # version of this repository (including uncommitted changes but
          # without untracked files) will be available for lockfile generation
          src ? null
        , # The path to the lockfile, e.g. `"./deps.lock.json"`
          lockfile
        , # Specify the maven repositories to use, overriding the defaults
          mavenRepos ? [
            "https://repo1.maven.org/maven2/"
            "https://repo.clojars.org/"
          ]
        , # the command to produce the dependencies
          command
        }:
        let locked = ((import ./default.nix { inherit pkgs; }).lockfile { inherit src lockfile mavenRepos; });
        in
        {
          locker = locked.commandLocker command;
          homeDirectory = locked.homeDirectory;
          shellEnv = locked.shellEnv;
          # Function to wrap your own overridden pkgs.clojure into a locked environment, a special case
          wrapClojure = locked.wrapClojure;
          # Provide an already locked clojure
          # You want to ensure that pkgs.clojure are not reference anywhere else
          lockedClojure = locked.wrapClojure pkgs.clojure;
          # Function to wrap other Java classpath aware programs with the locked environment
          wrapPrograms = locked.wrapPrograms;
        };
    };

    overlays.default = final: prev: {
      standaloneLocker = (import ./default.nix { pkgs = final; }).standaloneLocker;
    };

    templates.default = {
      path = ./example;
      description = "A template for using clojure-nix-locker.";
    };
  }
  //
  flake-utils.lib.eachDefaultSystem (system:
    let pkgs = import nixpkgs {
      inherit system;
      overlays = [ self.overlays.default ];
    };
    in
    {
      packages = rec {
        inherit (pkgs) standaloneLocker;
        default = standaloneLocker;
      };
    }
  );
}
