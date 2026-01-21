# Generating the lockfile

To generate the lockfile of all the deps:

```sh
nix run .#locker
```

Run this after modifying `deps.edn`.

# Building uberjar using the lockfile classpath

```sh
nix build .#uberjar
```

Run uberjar:

```sh
./result/bin/simple
```

# Starting a devshell with the locked classpath

```
nix develop
```

It will print out the current locked classpath.

# Two ways to get a locked classpath

## Sourcing `shellEnv`

During a `buildPhase` you can source the locked `shellEnv` like this:

```sh
source ${my-clojure-nix-locker.shellEnv}
```

This overrides `$JAVA_TOOL_OPTIONS` and `$HOME` to the locked classpath. Great for building, not great for devShells.

## Using `lockedClojure`

`lockedClojure` wraps `pkgs.clojure`, overriding `$JAVA_TOOL_OPTIONS` and `$HOME` only on `clojure` or `clj` invocation. Great for devShells.

If `pkgs.clojure` is anywhere in the set of inputs for a devShell, it may override the `lockedClojure`. Check with:

```sh
clojure -Spath
```

You should see a classpath with references to `/nix/store`.

# Overriding other programs that are aware of classpaths

`wrapPrograms` is available to wrap other programs into the locked classpath. `wrapClojure` is also available if you want to wrap a custom `pkgs.clojure`.