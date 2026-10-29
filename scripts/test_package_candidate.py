import hashlib
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from package_candidate import archive_directory, version_name


class CandidatePackagingTests(unittest.TestCase):
    def test_archive_is_independent_of_file_mtime_and_has_safe_owned_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'web'
            (source / 'assets').mkdir(parents=True)
            (source / 'index.html').write_text('owned')
            (source / 'assets/app.js').write_text('owned script')
            first, second = root / 'first.tar.gz', root / 'second.tar.gz'
            archive_directory(source, first, 'web', 123456)
            os.utime(source / 'index.html', (999999, 999999))
            archive_directory(source, second, 'web', 123456)
            self.assertEqual(hashlib.sha256(first.read_bytes()).digest(), hashlib.sha256(second.read_bytes()).digest())
            with tarfile.open(first) as archive:
                self.assertEqual(archive.getnames(), ['web/assets/app.js', 'web/index.html'])
                self.assertTrue(all(item.uid == 0 and item.mtime == 123456 for item in archive))
            (source / 'escape').symlink_to(root)
            with self.assertRaises(ValueError):
                archive_directory(source, root / 'bad.tar.gz', 'web', 123456)

    def test_version_cannot_inject_paths_shell_options_or_ambiguous_names(self):
        for value in ['v1.2.3', 'v0.2.0-rc.1']:
            self.assertEqual(version_name(value), value)
        for value in ['../escape', '--help', 'v1.2.3\n', 'v01.2.3', 'v1.2.3-rc.0', 'v1.2.3;id', 'latest']:
            with self.assertRaises(ValueError, msg=value):
                version_name(value)


if __name__ == '__main__':
    unittest.main()
