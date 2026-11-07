import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

WRAPPER, SHELL_ENV, OTHER_WRAPPER = sys.argv[1:4]
del sys.argv[1:4]


class EnvironmentTest(unittest.TestCase):
    def setUp(self):
        cache = tempfile.TemporaryDirectory(prefix='locker cache ')
        self.addCleanup(cache.cleanup)
        self.env = dict(os.environ, XDG_CACHE_HOME=cache.name)
        self.env.pop('NIX_BUILD_TOP', None)

    def run_shell(self, command, **kwargs):
        kwargs.setdefault('env', self.env)
        return subprocess.run([WRAPPER, '-c', command], text=True, capture_output=True, **kwargs)

    def test_source_and_wrapper_share_state_without_changing_shell_traps(self):
        env = dict(self.env, JAVA_TOOL_OPTIONS='-Xmx123m -Duser.home=/wrong',
                   GITLIBS='/wrong', CLJ_CONFIG='/wrong', CLJ_CACHE='/wrong')
        result = subprocess.run(['bash', '-c', '''
          set -eu
          trap 'echo original-trap' EXIT
          before=$(trap -p EXIT)
          source "$1"
          first=$HOME
          source "$1"
          test "$first" = "$HOME"
          test "$before" = "$(trap -p EXIT)"
          test -L "$HOME/.m2/repository/test/excluded/1/excluded-1.jar"
          test -L "$HOME/.m2/repository/org/clojure/clojure/maven-metadata-central.xml"
          printf '%s\\n' "$HOME" "$JAVA_TOOL_OPTIONS" "$GITLIBS" "$CLJ_CONFIG" "$CLJ_CACHE"
          "$2" -c 'echo "$HOME"'
        ''', 'test', SHELL_ENV, WRAPPER], env=env, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stderr)
        home, options, gitlibs, config, cache, nested, trap_output = result.stdout.splitlines()
        self.assertEqual('-Duser.home="' + home + '"', options)
        self.assertEqual([home + '/.gitlibs', home + '/.clojure', home + '/.cpcache', home, 'original-trap'],
                         [gitlibs, config, cache, nested, trap_output])
        self.assertEqual(0o700, Path(home).stat().st_mode & 0o777)

    def test_cache_keys_and_invalid_target_rejection(self):
        target = Path(self.run_shell('echo "$HOME"').stdout.strip())
        other = subprocess.check_output([OTHER_WRAPPER, '-c', 'echo "$HOME"'], env=self.env, text=True).strip()
        self.assertNotEqual(str(target), other)
        moved = target.with_name(target.name + '.moved')
        target.rename(moved)
        target.symlink_to(moved, target_is_directory=True)
        self.assertNotEqual(0, self.run_shell('echo "$HOME"').returncode)

    def test_build_cache_takes_priority_over_user_cache(self):
        root = self.env['XDG_CACHE_HOME']
        env = dict(self.env, HOME=root)
        env.pop('XDG_CACHE_HOME')
        home = self.run_shell('echo "$HOME"', env=env).stdout.strip()
        self.assertEqual(Path(root) / '.cache/clojure-nix-locker', Path(home).parent)
        env.update(XDG_CACHE_HOME='/unused', NIX_BUILD_TOP=root)
        build_home = self.run_shell('echo "$HOME"', env=env).stdout.strip()
        self.assertEqual(Path(root) / 'clojure-nix-locker', Path(build_home).parent)

    def test_exec_stdin_and_exit_status(self):
        child = subprocess.Popen([WRAPPER, '-c', 'read -r value; echo $$; echo "$value"; exit 42'],
                                 env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        stdout, _ = child.communicate('hello\n', timeout=10)
        self.assertEqual(42, child.returncode)
        self.assertEqual([str(child.pid), 'hello'], stdout.splitlines())


if __name__ == '__main__':
    unittest.main()
