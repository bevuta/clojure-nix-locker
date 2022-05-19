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
          mavenRepos ?
          [
            "https://repo1.maven.org/maven2/"
            "https://repo.clojars.org/"
          ]
        , # thecommand to produce the dependencies
          command
        }: {
          locker = ((import ./default.nix { inherit pkgs; }).lockfile { inherit src lockfile mavenRepos; }).commandLocker command;
          homeDirectory = ((import ./default.nix { inherit pkgs; }).lockfile { inherit src lockfile mavenRepos; }).homeDirectory;
          shellEnv = ((import ./default.nix { inherit pkgs; }).lockfile { inherit src lockfile mavenRepos; }).shellEnv;
        };
      };

    overlays.default = final: prev: {
      standaloneLocker = (import ./default.nix { pkgs = final; }).standaloneLocker;
    };

    templates.default = {
      path = ./example;
      description = "A template for using clojure-nix-locker.";
  }
  //
  flake-utils.lib.eachDefaultSystem (system:
    let pkgs = import nixpkgs {
      inherit system;
      overlays = [ self.overlays.default ];
    };
    in {
      packages = rec {
        inherit (pkgs) standaloneLocker;
        default = standaloneLocker;
      };
    }
  );

}
