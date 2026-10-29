import json
from pathlib import Path
import tempfile
import unittest
from verify_build_pins import verify


class BuildPinsTests(unittest.TestCase):
    def test_actions_images_and_local_reusable_workflows(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.github/workflows').mkdir(parents=True)
            (root / 'apps/web').mkdir(parents=True)
            (root / 'build-inputs.lock.json').write_text(json.dumps({
                'version': 1,
                'images': [{'image': 'node:22', 'digest': 'sha256:' + 'a' * 64}],
                'actions': [{'action': 'actions/checkout', 'commit': 'b' * 40}],
            }))
            dockerfile = root / 'apps/web/Dockerfile'
            dockerfile.write_text('FROM node:22@sha256:' + 'a' * 64 + ' AS build\n')
            workflow = root / '.github/workflows/ci.yml'
            workflow.write_text('  uses: ./.github/workflows/test.yml\n  - uses: actions/checkout@' + 'b' * 40 + ' # v4\n')
            self.assertEqual(verify(root), [])
            dockerfile.write_text('FROM node:22\n')
            self.assertEqual(len(verify(root)), 1)
            workflow.write_text(' - uses: actions/checkout@v4\n')
            self.assertEqual(len(verify(root)), 2)
            workflow.write_text(' - uses: actions/checkout@' + 'c' * 40 + '\n')
            self.assertEqual(len(verify(root)), 2)
            (root / 'compose.yaml').write_text('    image: unreviewed:latest\n')
            self.assertEqual(len(verify(root)), 3)


if __name__ == '__main__':
    unittest.main()
