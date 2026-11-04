"""Exercise actual Gradle rejection in disposable project copies, using its warm cache."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

API = Path(__file__).resolve().parents[1] / "services/api"


def run(project):
    return subprocess.run(
        ["gradle", "-p", str(project), "help", "--offline", "--no-daemon",
         "--dependency-verification", "strict"], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=120,
    )


with tempfile.TemporaryDirectory(prefix="tvnext-gradle-integrity-") as folder:
    project = Path(folder)
    for name in ("build.gradle.kts", "settings.gradle.kts", "gradle.lockfile"):
        shutil.copy2(API / name, project / name)
    shutil.copytree(API / "gradle", project / "gradle")
    metadata = project / "gradle/verification-metadata.xml"
    original = metadata.read_text()
    positive = run(project)
    if positive.returncode:
        raise RuntimeError("Untampered offline dependency probe failed:\n" + positive.stdout[-5000:])
    poisoned, count = re.subn(r'(<sha256 value=")[a-f0-9]{64}', lambda match: match[1] + "0" * 64, original)
    if not count:
        raise RuntimeError("No artifact checksum available for negative probe")
    metadata.write_text(poisoned)
    negative = run(project)
    if not negative.returncode or "Dependency verification failed" not in negative.stdout:
        raise RuntimeError("Gradle accepted wrong checksums or failed for another reason:\n" + negative.stdout[-5000:])
    print("Actual Gradle checksum mismatch rejected (including warm artifact caches)")
    metadata.write_text(original)
    (project / "gradle.lockfile").unlink()
    with (project / "build.gradle.kts").open("a") as output:
        output.write('\ntasks.named("help") { doLast { configurations.getByName("runtimeClasspath").resolve() } }\n')
    missing_lock = run(project)
    if not missing_lock.returncode or "Locking strict mode" not in missing_lock.stdout:
        raise RuntimeError("Gradle accepted missing lock state or failed for another reason:\n" + missing_lock.stdout[-5000:])
    print("Actual Gradle resolution without committed lock state rejected")
