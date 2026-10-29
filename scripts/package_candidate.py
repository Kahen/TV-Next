#!/usr/bin/env python3
"""Package verified unsigned Web/API/container candidates with exact source and hashes."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile


def version_name(value: str) -> str:
    if not re.fullmatch(r'v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-rc\.[1-9][0-9]*)?', value):
        raise ValueError('Version must be vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-rc.N')
    return value


def sha256(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def archive_directory(source: Path, destination: Path, prefix: str, epoch: int) -> None:
    if not source.is_dir():
        raise ValueError('Build directory missing')
    with destination.open('wb') as raw, gzip.GzipFile(fileobj=raw, mode='wb', filename='', mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode='w|', format=tarfile.PAX_FORMAT) as archive:
            for file in sorted(source.rglob('*')):
                if file.is_symlink():
                    raise ValueError('Build output must not contain symlinks')
                if not file.is_file():
                    continue
                info = archive.gettarinfo(str(file), arcname=prefix + '/' + file.relative_to(source).as_posix())
                info.uid = info.gid = 0
                info.uname = info.gname = ''
                info.mode = 0o644
                info.mtime = epoch
                info.pax_headers = {}
                with file.open('rb') as content:
                    archive.addfile(info, content)


def package(root: Path, output: Path, version: str, web: Path, jar: Path,
            images: Path, image_ids: Path) -> None:
    version = version_name(version)
    if not jar.is_file() or not images.is_file() or not image_ids.is_file():
        raise ValueError('Required API/container build artifacts missing')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    epoch = int(subprocess.check_output(['git', 'show', '-s', '--format=%ct', 'HEAD'], cwd=root, text=True))
    ids = json.loads(image_ids.read_text())
    if set(ids) != {'api', 'web'} or not all(re.fullmatch(r'sha256:[a-f0-9]{64}', value) for value in ids.values()):
        raise ValueError('Expected exact API/Web OCI image identities')
    output.mkdir(parents=True, exist_ok=False)
    source = subprocess.check_output(['git', 'archive', '--format=tar', '--prefix=tv-next-source/', 'HEAD'], cwd=root)
    (output / f'tv-next-{version}-source.tar.gz').write_bytes(gzip.compress(source, mtime=0))
    archive_directory(web, output / f'tv-next-{version}-web.tar.gz', 'web', epoch)
    shutil.copyfile(jar, output / f'tv-next-{version}-api.jar')
    shutil.copyfile(images, output / f'tv-next-{version}-linux-amd64-images.tar.gz')
    for name in ['LICENSE.md', 'NOTICE.md', 'build-inputs.lock.json']:
        shutil.copyfile(root / name, output / name)
    for name in ['npm-audit.json', 'sbom-web.cdx.json']:
        shutil.copyfile(root / 'apps/web' / name, output / name)
    files = {file.name: sha256(file) for file in sorted(output.iterdir())}
    manifest = {
        'schema': 1, 'version': version, 'source_commit': commit,
        'source_date_epoch': epoch, 'container_platform': 'linux/amd64',
        'image_ids': ids, 'files': files, 'signed': False,
        'limitations': ['Experimental subset; see source docs/IMPLEMENTATION_STATUS.md',
                        'No signed iOS IPA, TestFlight, physical-device or real Spider acceptance',
                        'Docker archive is not claimed bit-reproducible; OCI identities are recorded'],
    }
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    (output / 'SHA256SUMS').write_text(''.join(f'{sha256(file)}  {file.name}\n' for file in sorted(output.iterdir()) if file.name != 'SHA256SUMS'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--web', type=Path, default=Path('apps/web/dist'))
    parser.add_argument('--jar', type=Path, required=True)
    parser.add_argument('--images', type=Path, required=True)
    parser.add_argument('--image-ids', type=Path, required=True)
    args = parser.parse_args()
    package(Path.cwd(), args.output, args.version, args.web, args.jar, args.images, args.image_ids)
