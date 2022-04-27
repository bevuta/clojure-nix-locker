# clojure-nix-locker
Simple and flexible tool to build clojure projects with Nix.

## Usage

The [example/](example) directory has a small clojure program and the nix code required to build it.

To generate/update the lockfile:
```sh
nix-shell --run clojure-nix-locker
```

To build:
```sh
nix-build -A uberjar
```

## Why another tool?

There are two existing projects with a similar goal already, [clj2nix](https://github.com/hlolli/clj2nix) and [clj-nix](https://github.com/jlesquembre/clj-nix).
Both of these are designed to be used roughly like this:

- At lock-time, call into `clojure.tools.deps` to resolve all dependencies, then generate a lockfile from this.
- At nix-eval-time, use the information from the lockfile to compute the classpath.
- At build-time, invoke clojure and pass it the precomputed classpath.

By contrast, `clojure-nix-locker` is designed around letting classpath computation happen later, at build-time.
It works roughly like thi:

- At lock-time, call arbitrary user-provided commands (like `clojure -P`) to pre-populate the caches in `.m2` and `.gitlibs`, then crawl those to generate the lockfile.
- At nix-eval-time, use the information from the lockfile to recreate these caches in a way that's "close enough" to the real thing.
- At build-time, invoke clojure as normal. If the prefetching was done correctly, it will resolve its dependencies just fine without hitting the network.

This approach results in a pretty simple implementation and loose coupling to the clojure tooling.
As a consequence, things like aliases "just work" without requiring `clojure-nix-locker` to know about them.

Of course, this has its downsides too:
- If the directory layout of these caches changes, this tool breaks.
- Whatever classpath(s) your clojure tools compute at build-time will only work for the duration of that build.

## License

Distributed under the GNU General Public License, Version 3. See `LICENSE` for more details.
