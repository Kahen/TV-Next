"""Build-time preflight for the owned provider JAR; never imports provider code."""
import hashlib
import json
from pathlib import Path
import zipfile
from jar_inspect import inspect_jar

jar = Path('/approved.jar')
report = inspect_jar(jar)
if report.status != 'pure-jvm-candidate':
    raise SystemExit('Owned JAR failed static preflight')
with zipfile.ZipFile(jar) as archive:
    for item in archive.namelist():
        if item.endswith('.class') and not item.startswith('com/github/catvod/spider/'):
            raise SystemExit('Owned JAR must not shadow host/platform API classes')
Path('/approved.json').write_text(json.dumps({
    'version': 1, 'status': report.status,
    'sha256': hashlib.sha256(jar.read_bytes()).hexdigest(),
    'provenance': 'TV-Next-owned GPL fixture sources in jvm-spider/fixtures; not an external provider approval',
}))
