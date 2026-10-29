#!/usr/bin/env python3
"""Inventory the actual libraries shipped in a Boot JAR against reviewed Gradle hashes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import quote
import xml.etree.ElementTree as ET
import zipfile

MAX_JAR = 256 * 1024 * 1024
MAX_LIBRARY = 128 * 1024 * 1024
MAX_EXPANDED = 512 * 1024 * 1024
MAX_LIBRARIES = 400
NS = "{https://schema.gradle.org/dependency-verification}"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def checksum_index(metadata):
    raw = metadata.read_bytes()
    if len(raw) > 2_000_000 or b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
        raise ValueError("Invalid verification metadata")
    root = ET.fromstring(raw)
    result = {}
    for component in root.findall(NS + "components/" + NS + "component"):
        coordinate = tuple(component.get(key, "") for key in ("group", "name", "version"))
        if not all(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", value) for value in coordinate):
            raise ValueError("Invalid Maven coordinate")
        for artifact in component.findall(NS + "artifact"):
            hashes = list(artifact)
            if len(hashes) != 1 or hashes[0].tag != NS + "sha256" or list(hashes[0]):
                raise ValueError("Expected one reviewed SHA-256 per artifact")
            expected = hashes[0].get("value", "")
            if not re.fullmatch(r"[a-f0-9]{64}", expected):
                raise ValueError("Invalid artifact checksum")
            key = (artifact.get("name", ""), expected)
            if key in result:
                raise ValueError("Ambiguous artifact checksum evidence")
            result[key] = coordinate
    if not result:
        raise ValueError("No reviewed artifact checksums")
    return result


def build_sbom(jar, metadata, version):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?", version):
        raise ValueError("Invalid API version")
    if not jar.is_file() or jar.stat().st_size > MAX_JAR:
        raise ValueError("API JAR missing or over size limit")
    index = checksum_index(metadata)
    components = []
    references = set()
    with zipfile.ZipFile(jar) as archive:
        libraries = [entry for entry in archive.infolist()
                     if entry.filename.startswith("BOOT-INF/lib/") and not entry.is_dir()]
        if not libraries or len(libraries) > MAX_LIBRARIES:
            raise ValueError("Expected bounded Boot JAR library inventory")
        if sum(entry.file_size for entry in libraries) > MAX_EXPANDED:
            raise ValueError("Expanded library inventory exceeds size limit")
        names = set()
        for entry in sorted(libraries, key=lambda value: value.filename):
            name = entry.filename.removeprefix("BOOT-INF/lib/")
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*\.jar", name) or name in names:
                raise ValueError("Unsafe or duplicate embedded library name")
            names.add(name)
            if entry.file_size > MAX_LIBRARY or entry.flag_bits & 1:
                raise ValueError("Oversized or encrypted embedded library")
            actual = hashlib.sha256()
            size = 0
            with archive.open(entry) as stream:
                while chunk := stream.read(65_536):
                    size += len(chunk)
                    if size > MAX_LIBRARY:
                        raise ValueError("Expanded library exceeds size limit")
                    actual.update(chunk)
            if size != entry.file_size:
                raise ValueError("Embedded library size mismatch")
            checksum = actual.hexdigest()
            coordinate = index.get((name, checksum))
            if coordinate is None:
                raise ValueError("Shipped library lacks matching reviewed coordinate/checksum: " + name)
            group, artifact, selected_version = coordinate
            prefix = artifact + "-" + selected_version
            classifier = ""
            if name != prefix + ".jar":
                if not name.startswith(prefix + "-"):
                    raise ValueError("Library filename does not match its Maven coordinate")
                classifier = name[len(prefix) + 1:-4]
                if not classifier:
                    raise ValueError("Empty artifact classifier")
            qualifiers = ("classifier=" + quote(classifier, safe="") + "&" if classifier else "") + "type=jar"
            purl = "pkg:maven/" + quote(group, safe="") + "/" + quote(artifact, safe="") + "@" + quote(selected_version, safe="") + "?" + qualifiers
            if purl in references:
                raise ValueError("Duplicate shipped Maven artifact")
            references.add(purl)
            components.append({
                "type": "library", "bom-ref": purl, "purl": purl,
                "group": group, "name": artifact, "version": selected_version,
                "hashes": [{"alg": "SHA-256", "content": checksum}],
                "properties": [{"name": "tvnext:archive-path", "value": entry.filename}],
            })
    application = "pkg:generic/tv-next-api@" + quote(version, safe="")
    return {
        "$schema": "https://cyclonedx.org/schema/bom-1.6.schema.json",
        "bomFormat": "CycloneDX", "specVersion": "1.6", "version": 1,
        "metadata": {"component": {
            "type": "application", "bom-ref": application, "purl": application,
            "name": "tv-next-api", "version": version,
            "hashes": [{"alg": "SHA-256", "content": digest(jar)}],
        }},
        "components": sorted(components, key=lambda component: component["bom-ref"]),
        "properties": [
            {"name": "tvnext:inventory-scope", "value": "Exact BOOT-INF/lib inventory; no transitive graph, JDK/OS inventory, license or vulnerability assertion"},
            {"name": "tvnext:verification-metadata-sha256", "value": digest(metadata)},
        ],
    }


def render(document):
    return json.dumps(document, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--jar", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, default=Path("services/api/gradle/verification-metadata.xml"))
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    document = build_sbom(args.jar, args.metadata, args.version)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(document), encoding="utf-8")
    print(f"Verified {len(document['components'])} shipped API libraries against committed SHA-256 evidence")
