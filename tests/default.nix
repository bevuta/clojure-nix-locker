{ pkgs }:
let
  locker = (import ../default.nix { inherit pkgs; }).standaloneLocker;
  utils = import ../utils.nix { inherit pkgs; };
  fixtureLock = {
    git = {};
    maven = {
      "test/excluded/1/excluded-1.jar".content = "unused classpath fixture";
      "test/excluded/1/excluded-1.pom".content = ''
        <project><modelVersion>4.0.0</modelVersion><groupId>test</groupId>
        <artifactId>excluded</artifactId><version>1</version><dependencies>
        <dependency><groupId>org.clojure</groupId><artifactId>clojure</artifactId>
        <version>[1.2.1],[1.3.0]</version></dependency></dependencies></project>
      '';
      "org/clojure/clojure/maven-metadata-private.xml".content = ''
        <metadata><groupId>org.clojure</groupId><artifactId>clojure</artifactId>
        <versioning><versions><version>1.2.1</version></versions></versioning></metadata>
      '';
      "org/clojure/clojure/maven-metadata-central.xml".content = ''
        <metadata><groupId>org.clojure</groupId><artifactId>clojure</artifactId>
        <versioning><versions><version>1.3.0</version><version>1.12.0</version>
        </versions></versioning></metadata>
      '';
    };
  };
  home = lock:
    let lockPath = builtins.toFile "locker-test-lock.json" (builtins.toJSON lock);
    in import ../createHome.nix {
    inherit pkgs;
    src = builtins.dirOf lockPath;
    lockfile = builtins.baseNameOf lockPath;
    mavenRepos = [ "https://repo.maven.apache.org/maven2/" "https://repo.clojars.org/" ];
    extraPrepInputs = [];
  };
  fixtureHome = home fixtureLock;
  resolverHome = home {
    git = {};
    maven = (builtins.fromJSON (builtins.readFile ../example/deps.lock.json)).maven // fixtureLock.maven;
  };
  newerClojure = pkgs.clojure.overrideAttrs (finalAttrs: _: {
    version = "1.12.6.1673";
    src = pkgs.fetchurl {
      url = "https://github.com/clojure/brew-install/releases/download/${finalAttrs.version}/clojure-tools-${finalAttrs.version}.tar.gz";
      hash = "sha256-/pGUhY511a8TwuKv+S1xBnTVvFEF8rQvkKfZTYLsAjw=";
    };
  });
  resolverCheck = clojure: immutableResult:
    let wrappedClojure = utils.wrapClojure resolverHome clojure;
    in pkgs.runCommand "locker-resolver-${clojure.version}-tests" {
      nativeBuildInputs = [ pkgs.python3 ];
      passthru = { inherit wrappedClojure clojure resolverHome; };
    } ''
      python ${./resolver.py} ${wrappedClojure}/bin/clojure ${pkgs.jdk}/bin/java \
        ${clojure}/bin/clojure ${resolverHome} ${immutableResult}
      touch $out
    '';
in {
  metadata = pkgs.runCommand "locker-metadata-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python ${./metadata.py} ${locker}/bin/standalone-clojure-nix-locker
    touch $out
  '';
  environment = pkgs.runCommand "locker-environment-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python ${./environment.py} \
      ${(utils.wrapPrograms fixtureHome "locked-bash" [ "${pkgs.bash}/bin/bash" ])}/bin/bash \
      ${utils.shellEnv fixtureHome} \
      ${(utils.wrapPrograms (home { maven = {}; git = {}; }) "other-locked-bash" [ "${pkgs.bash}/bin/bash" ])}/bin/bash
    touch $out
  '';
  resolver = resolverCheck pkgs.clojure "success";
  resolver-new = resolverCheck newerClojure "failure";
}
