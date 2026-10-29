#!/usr/bin/env python3
"""Fail if Docker/Compose/CI build inputs drift from reviewed immutable pins."""
import json
from pathlib import Path
import re
import sys


def verify(root: Path) -> list[str]:
    lock = json.loads((root / 'build-inputs.lock.json').read_text())
    if lock.get('version') != 1:
        return ['Unsupported build-input lock version']
    images = {entry['image']: entry['digest'] for entry in lock['images']}
    actions = {entry['action']: entry['commit'] for entry in lock['actions']}
    errors = []
    for image, digest in images.items():
        if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
            errors.append(f'Invalid image digest: {image}')
    for action, commit in actions.items():
        if not re.fullmatch(r'[0-9a-f]{40}', commit):
            errors.append(f'Invalid action commit: {action}')
    workflows = list((root / '.github/workflows').glob('*.yml'))
    dockerfiles = list((root / 'apps').glob('*/Dockerfile')) + list((root / 'services').glob('*/Dockerfile'))
    dockerfiles += list((root / 'services/spider-runtime').glob('*/Dockerfile'))
    for path in workflows + dockerfiles + list(root.glob('compose*.yaml')):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            where = f'{path.relative_to(root)}:{number}'
            use = re.match(r'\s*(?:-\s*)?uses:\s*(\S+)', line)
            if use and not use[1].startswith('./'):
                name, sep, commit = use[1].partition('@')
                if not sep or actions.get(name) != commit:
                    errors.append(f'{where}: unreviewed or mutable action {use[1]}')
            image = re.match(r'\s*(?:FROM|image:)\s+(\S+)', line)
            if image:
                name, sep, digest = image[1].partition('@')
                if not sep or images.get(name) != digest:
                    errors.append(f'{where}: unreviewed or mutable image {image[1]}')
    return errors


if __name__ == '__main__':
    problems = verify(Path(__file__).resolve().parent.parent)
    if problems:
        print('\n'.join(problems), file=sys.stderr)
        sys.exit(1)
    print('All external actions and Docker base/service images match reviewed immutable pins.')
