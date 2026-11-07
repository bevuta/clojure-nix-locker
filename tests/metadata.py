import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

LOCKER = sys.argv.pop(1)


class MetadataTest(unittest.TestCase):
    def lock(self, versions, timestamp):
        with tempfile.TemporaryDirectory() as home:
            artifact = Path(home) / '.m2/repository/org/clojure/clojure'
            (artifact / '1.12.6').mkdir(parents=True)
            (artifact / '1.12.6/clojure-1.12.6.jar').write_bytes(b'locked artifact')
            (artifact / 'maven-metadata-central.xml').write_text(
                '<metadata><groupId>org.clojure</groupId><artifactId>clojure</artifactId>'
                '<versioning><versions>' + ''.join('<version>' + v + '</version>' for v in versions)
                + '</versions><lastUpdated>' + timestamp + '</lastUpdated></versioning></metadata>')
            return json.loads(subprocess.check_output([LOCKER, home]))

    def test_preserves_versions_consulted_but_not_downloaded(self):
        locked = self.lock(['1.3.0', '1.12.6', '1.2.1'], '20260101000000')
        metadata = locked['maven']['org/clojure/clojure/maven-metadata-central.xml']['content']
        self.assertEqual(['1.12.6', '1.2.1', '1.3.0'],
                         [v.text for v in ET.fromstring(metadata).findall('./versioning/versions/version')])
        self.assertEqual(['org/clojure/clojure/1.12.6/clojure-1.12.6.jar'],
                         [name for name in locked['maven'] if name.endswith('.jar')])

    def test_order_duplicates_and_timestamps_do_not_change_snapshot(self):
        self.assertEqual(self.lock(['1.3.0', '1.12.6', '1.3.0'], '20260101000000'),
                         self.lock(['1.12.6', '1.3.0'], '20260102000000'))


if __name__ == '__main__':
    unittest.main()
