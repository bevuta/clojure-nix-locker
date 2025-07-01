from pathlib import Path
import json
from hashlib import sha256
from git import Repo
import subprocess
import argparse
import re
import xml.etree.ElementTree as ET

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


def stabilize_maven_metadata(orig_file):
    """Accepts a path of a maven-metadata.xml file and transforms its content so that it's stable
    across multiple runs (i.e. server-side changes in the file due to e.g. new releases don't affect
    it) but still sufficient to satisfy version range dependencies within the locked
    repository. Returns the stabilized content as a string."""
    orig = ET.parse(orig_file)
    stable = ET.Element("metadata")
    stable.append(orig.find("./groupId"))
    stable.append(orig.find("./artifactId"))
    versioning = ET.SubElement(stable, "versioning")
    versions = ET.SubElement(versioning, "versions")
    for version_dir in f.parent.iterdir():
        if version_dir.is_dir():
            ET.SubElement(versions, "version").text = version_dir.name
    stable_str = ET.tostring(stable, encoding='utf-8', xml_declaration=True).decode('utf-8')
    return re.sub(r'>\s+<', '><', stable_str).strip()


if mavenDir.exists():
    for f in mavenDir.rglob('*'):
        mvn_meta_file = None
        if (f.is_dir() or
            (f.suffix != ".jar" and
             f.suffix != ".pom" and
             # Needed for dependencies with version ranges (see e.g. https://github.com/fzakaria/mvn2nix/issues/26)
             not (mvn_meta_file := re.fullmatch("maven-metadata-(.+)\\.xml", f.name)))):
            continue
        file = f.relative_to(mavenDir)
        dep = {}
        if mvn_meta_file:
            dep['content'] = stabilize_maven_metadata(f)
        else:
            # We could use `nix-hash` here, but that's much slower and doesn't have any benefits
            dep['sha256'] = sha256(f.read_bytes()).hexdigest()
        result['maven'][file.as_posix()] = dep

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
                path = rev_path.relative_to(gitlibsDir.joinpath("libs")).as_posix()
                repo = Repo(rev_path)
                prefetch = subprocess.run(["nix-prefetch-git", rev_path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
                with open(rev_path / "deps.edn") as deps_edn:
                    prep = subprocess.run(["bb", "-I", "--stream", extractPrepLibInfo], stdin=deps_edn, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
                result['git'][path] = {
                    # This is the path to the corresponding bare repository in ~/.gitlibs/_repos
                    "common_dir": Path(repo.common_dir).resolve().relative_to(gitlibsDir.joinpath("_repos")).as_posix(),
                    "url": repo.remotes.origin.url,
                    "rev": repo.head.commit.hexsha,
                    "sha256": json.loads(prefetch.stdout)['sha256'],
                }
                if preps := prep.stdout:
                    result['git'][path]['prep'] = json.loads(preps)

print(json.dumps(result, indent=2, sort_keys=True))
