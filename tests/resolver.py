from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.request

CLOJURE, JAVA, RAW_CLOJURE, IMMUTABLE_HOME, IMMUTABLE_RESULT = sys.argv[1:6]
del sys.argv[1:6]
BASIS = '''{:deps {org.clojure/clojure {:mvn/version "1.12.0"}
                  test/excluded {:mvn/version "1" :exclusions [org.clojure/clojure]}}}'''


class ResolverTest(unittest.TestCase):
    def environment(self, cwd):
        env = dict(os.environ, CLOJURE_CLI_ALLOW_HTTP_REPO='true', TMPDIR=cwd,
                   XDG_CACHE_HOME=os.path.join(cwd, '.cache'))
        env.pop('NIX_BUILD_TOP', None)
        return env

    def resolve(self, extra, cwd):
        return subprocess.run([CLOJURE, '-Srepro', '-Sforce', '-Sdeps', extra, '-Spath'],
                              cwd=cwd, text=True, capture_output=True, timeout=60, env=self.environment(cwd))

    def test_immutable_repository_control(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(self.environment(tmp), HOME=IMMUTABLE_HOME,
                       JAVA_TOOL_OPTIONS='-Duser.home="' + IMMUTABLE_HOME + '"',
                       CLJ_CONFIG=IMMUTABLE_HOME + '/.clojure', CLJ_CACHE=tmp + '/classpath',
                       GITLIBS=IMMUTABLE_HOME + '/.gitlibs')
            result = subprocess.run([RAW_CLOJURE, '-Srepro', '-Sforce', '-Sdeps', BASIS, '-Spath'],
                                    cwd=tmp, env=env, text=True, capture_output=True, timeout=60)
        if IMMUTABLE_RESULT == 'failure':
            self.assertNotEqual(0, result.returncode)
            self.assertIn('resolver-status.properties', result.stderr)
        else:
            self.assertEqual(0, result.returncode, result.stderr)

    def test_repeated_and_concurrent_resolution_without_artifact_changes(self):
        with tempfile.TemporaryDirectory(prefix='locker test ') as tmp:
            with ThreadPoolExecutor(max_workers=4) as pool:
                results = list(pool.map(lambda _: self.resolve(BASIS, tmp), range(4)))
            results.append(self.resolve(BASIS, tmp))
            for result in results:
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertIn('clojure-1.12.0.jar', result.stdout)
                self.assertNotIn('clojure-1.3.0.jar', result.stdout)
            self.assertEqual(1, len({result.stdout for result in results}))
            cache = Path(tmp) / '.cache/clojure-nix-locker'
            repository = cache / Path(IMMUTABLE_HOME).name / '.m2/repository'
            original = Path(IMMUTABLE_HOME) / '.m2/repository'
            for artifact in original.rglob('*'):
                if artifact.suffix in ('.jar', '.pom'):
                    cached = repository / artifact.relative_to(original)
                    self.assertTrue(cached.is_symlink(), str(cached))
                    self.assertEqual(artifact.resolve(), cached.resolve())
            self.assertFalse((repository / 'org/clojure/clojure/1.3.0').exists())
            self.assertEqual([], list(cache.glob('.tmp.*')))

    def test_classpath_works_after_wrapper_exits(self):
        with tempfile.TemporaryDirectory(prefix='locker classpath ') as tmp:
            result = self.resolve('{:deps {org.clojure/clojure {:mvn/version "1.12.0"}}}', tmp)
            self.assertEqual(0, result.returncode, result.stderr)
            launched = subprocess.run([JAVA, '-cp', result.stdout.strip(), 'clojure.main', '--help'],
                                      cwd=tmp, text=True, capture_output=True, timeout=30)
            self.assertEqual(0, launched.returncode, launched.stderr)
            self.assertIn('clojure.main', launched.stdout)

    def test_metadata_is_scoped_to_its_repository(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self.resolve('''
              {:deps {org.clojure/clojure {:mvn/version "[1.2.1],[1.3.0]"}}
               :mvn/repos {"central" nil "clojars" nil
                           "private" {:url "https://unused.invalid/"
                                      :releases {:checksum :fail}}}}
            ''', tmp)
        self.assertNotEqual(0, result.returncode)
        self.assertIn('1.2.1', result.stderr)
        self.assertIn('file:///nix/store/', result.stderr)
        self.assertNotIn('Checksum validation failed', result.stderr)
        self.assertNotIn('clojure-1.3.0.pom', result.stderr)

    def test_missing_artifact_cannot_be_downloaded_even_outside_sandbox(self):
        requests = []

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'<project><modelVersion>4.0.0</modelVersion>'
                                 b'<groupId>test</groupId><artifactId>missing</artifactId>'
                                 b'<version>1</version></project>')

            do_HEAD = do_GET

            def log_message(self, *_):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            url = 'http://127.0.0.1:' + str(server.server_port) + '/'
            with urllib.request.urlopen(url) as response:
                self.assertEqual(200, response.status)
            requests.clear()
            with tempfile.TemporaryDirectory() as tmp:
                # Maven must mirror arbitrary additional repositories, not only central.
                extra = '''{:deps {org.clojure/clojure {:mvn/version "1.12.0"}
                                   test/missing {:mvn/version "1"}}
                            :mvn/repos {"custom" {:url %s}
                                        "central" {:url %s}}}''' % (json.dumps(url), json.dumps(url))
                cached = extra.replace('test/missing {:mvn/version "1"}',
                                       'test/excluded {:mvn/version "1" :exclusions [org.clojure/clojure]}')
                cached_result = self.resolve(cached, tmp)
                self.assertEqual(0, cached_result.returncode, cached_result.stderr)
                result = self.resolve(extra, tmp)
            self.assertNotEqual(0, result.returncode)
            self.assertIn('test:missing', result.stderr)
            self.assertEqual([], requests)
        finally:
            server.shutdown()
            thread.join()
            server.server_close()


if __name__ == '__main__':
    unittest.main()
