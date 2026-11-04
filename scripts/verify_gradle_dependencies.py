"""Fail closed on widened or incomplete committed JVM dependency evidence."""
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

REQUIRED = {"compileClasspath", "runtimeClasspath", "testCompileClasspath", "testRuntimeClasspath"}
EXACT = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
CONFIG = re.compile(r"[A-Za-z0-9_.-]+")
SHA256 = re.compile(r"[a-f0-9]{64}")


def validate(root: Path) -> tuple[int, int]:
    api = root / "services/api"
    lock = api / "gradle.lockfile"
    metadata = api / "gradle/verification-metadata.xml"
    if not lock.is_file() or not metadata.is_file():
        raise ValueError("Missing committed JVM lock or checksum file")
    if lock.stat().st_size > 512_000 or metadata.stat().st_size > 2_000_000:
        raise ValueError("Dependency evidence exceeds its review bound")
    locked = set()
    configurations = set()
    seen = set()
    for line in lock.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError("Invalid lock entry")
        coordinate, names = line.split("=", 1)
        if coordinate in seen:
            raise ValueError("Duplicate lock entry")
        seen.add(coordinate)
        selected = names.split(",") if names else []
        if any(not CONFIG.fullmatch(name) for name in selected) or len(selected) != len(set(selected)):
            raise ValueError("Invalid locked configuration")
        configurations.update(selected)
        if coordinate == "empty":
            continue
        parts = coordinate.split(":")
        if len(parts) != 3 or not all(EXACT.fullmatch(part) for part in parts):
            raise ValueError("Lock versions must be exact module coordinates")
        if "snapshot" in parts[2].lower() or "latest" in parts[2].lower():
            raise ValueError("Mutable JVM version in lock")
        if not selected:
            raise ValueError("Locked module has no configuration")
        locked.add(tuple(parts))
    if not locked or not REQUIRED <= configurations:
        raise ValueError("Compile/runtime/test lock coverage is incomplete")
    raw = metadata.read_bytes()
    if b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
        raise ValueError("XML declarations are not allowed in checksum evidence")
    document = ET.fromstring(raw)
    namespace = "{https://schema.gradle.org/dependency-verification}"
    if document.tag != namespace + "verification-metadata":
        raise ValueError("Unexpected verification metadata root")
    configuration = document.find(namespace + "configuration")
    if configuration is None:
        raise ValueError("Missing verification policy")
    values = {}
    for node in configuration:
        name = node.tag.removeprefix(namespace)
        if name not in {"verify-metadata", "verify-signatures"} or name in values:
            raise ValueError("Broad trust exceptions are not allowed")
        values[name] = (node.text or "").strip()
    if values.get("verify-metadata") != "true":
        raise ValueError("POM/module metadata verification must stay enabled")
    if values.get("verify-signatures") not in {"false", "true"}:
        raise ValueError("Verification signature policy must be explicit")
    components = document.find(namespace + "components")
    if components is None:
        raise ValueError("Missing verified components")
    verified = set()
    artifact_count = 0
    for component in components:
        if component.tag != namespace + "component":
            raise ValueError("Unexpected verification component")
        coordinate = tuple(component.get(name, "") for name in ("group", "name", "version"))
        if not all(EXACT.fullmatch(part) for part in coordinate) or coordinate in verified:
            raise ValueError("Invalid or duplicate verified module")
        verified.add(coordinate)
        artifacts = set()
        for artifact in component:
            name = artifact.get("name", "")
            if artifact.tag != namespace + "artifact" or not name or name in artifacts:
                raise ValueError("Invalid or duplicate verified artifact")
            artifacts.add(name)
            hashes = list(artifact)
            if len(hashes) != 1 or hashes[0].tag != namespace + "sha256":
                raise ValueError("Each artifact must have exactly one reviewed SHA-256")
            if not SHA256.fullmatch(hashes[0].get("value", "")) or list(hashes[0]):
                raise ValueError("Invalid SHA-256 or alternate trust override")
            artifact_count += 1
        if not artifacts:
            raise ValueError("Verified module has no artifacts")
    if not locked <= verified:
        raise ValueError("A locked module has no checksum evidence")
    return len(locked), artifact_count


if __name__ == "__main__":
    try:
        modules, artifacts = validate(Path(__file__).resolve().parents[1])
    except (ValueError, OSError, ET.ParseError) as error:
        print(f"JVM dependency evidence rejected: {error}", file=sys.stderr)
        raise SystemExit(1)
    print(f"Verified exact JVM lock coverage: {modules} modules, {artifacts} artifact checksums")
