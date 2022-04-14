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

mavenDir = args.home.joinpath('.m2', 'repository')

for f in mavenDir.rglob('*'):
    if f.is_dir() or f.suffix != ".jar" and f.suffix != ".pom":
        continue
    file = f.relative_to(mavenDir).as_posix()
    # We could use `nix-hash` here, but that's much slower and doesn't have any benefits
    sha256_hash = sha256(f.read_bytes()).hexdigest()
    result['maven'][file] = sha256_hash

gitlibsDir = args.home.joinpath('.gitlibs')

for namespace_path in gitlibsDir.joinpath('libs').iterdir():
    for name_path in namespace_path.iterdir():
        for rev_path in name_path.iterdir():
            path = rev_path.relative_to(gitlibsDir, "libs").as_posix()

            obj = {}
            r = Repo(rev_path)
            # This is the path to the corresponding bare repository in ~/.gitlibs/_repos
            obj['common_dir'] = Path(r.common_dir).resolve().relative_to(gitlibsDir, "_repos").as_posix()
            obj['url'] = r.remotes.origin.url
            obj['rev'] = r.head.commit.hexsha

            p = subprocess.run(["nix-prefetch-git", rev_path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
            obj['sha256'] = json.loads(p.stdout)['sha256']

            result['git'][path] = obj

print(json.dumps(result, indent=2, sort_keys=True))
