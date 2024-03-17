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