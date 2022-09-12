from pathlib import Path
import json
from hashlib import sha256
from git import Repo
import subprocess
import argparse

parser = argparse.ArgumentParser(
    description='Locks clojure maven and git dependencies')
parser.add_argument(
    'home',
    metavar='HOME',
    type=Path,
    help='the home directory whose dependencies should be locked. All dependencies from the .m2 and .gitlibs folders are taken into account')
args = parser.parse_args()

result = {'maven': {}, 'git': {}}

mavenDir = args.home.joinpath('.m2', 'repository').resolve()

if mavenDir.exists():
    for f in mavenDir.rglob('*'):
        if f.is_dir() or f.suffix != ".jar" and f.suffix != ".pom":
            continue
        file = f.relative_to(mavenDir).as_posix()
        # We could use `nix-hash` here, but that's much slower and doesn't have any benefits
        sha256_hash = sha256(f.read_bytes()).hexdigest()
        result['maven'][file] = sha256_hash

gitlibsDir = args.home.joinpath('.gitlibs').resolve()

extractPrepLibInfo = '''
  (some-> *input*
          :deps/prep-lib
          (select-keys [:alias :fn])
          cheshire.core/generate-string
          println)
'''

if gitlibsDir.exists():
    for namespace_path in gitlibsDir.joinpath('libs').iterdir():
        for name_path in namespace_path.iterdir():
            for rev_path in name_path.iterdir():
                path = rev_path.relative_to(gitlibsDir, "libs").as_posix()
                repo = Repo(rev_path)
                prefetch = subprocess.run(["nix-prefetch-git", rev_path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
                with open(rev_path / "deps.edn") as deps_edn:
                    prep = subprocess.run(["bb", "-I", "--stream", extractPrepLibInfo], stdin=deps_edn, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
                result['git'][path] = {
                    # This is the path to the corresponding bare repository in ~/.gitlibs/_repos
                    "common_dir": Path(repo.common_dir).resolve().relative_to(gitlibsDir, "_repos").as_posix(),
                    "url": repo.remotes.origin.url,
                    "rev": repo.head.commit.hexsha,
                    "sha256": json.loads(prefetch.stdout)['sha256'],
                }
                if preps := prep.stdout:
                    result['git'][path]['prep'] = json.loads(preps)

print(json.dumps(result, indent=2, sort_keys=True))
