#!/usr/bin/env python3
"""Bounded static JAR bytecode preflight, with NO code execution.

A 'pure-jvm-candidate' finding means only that *specified known blockers*
were not observed. It is not a safety approval and must not automatically
authorize loading an untrusted artifact.
"""
from __future__ import annotations

import argparse
import json
import os
import struct
import sys
import zipfile
from dataclasses import asdict, dataclass
from pathlib import Path

MAX_JAR_BYTES = 16 * 1024 * 1024
MAX_ENTRIES = 2000
MAX_CLASS_BYTES = 2 * 1024 * 1024
MAX_UNCOMPRESSED = 32 * 1024 * 1024
MAX_ENTRY_BYTES = 4 * 1024 * 1024
MAX_RATIO = 1000
NATIVE_EXTENSIONS = (".so", ".dll", ".dylib", ".jnilib")


class JarInspectionError(ValueError):
    pass


@dataclass(frozen=True)
class JarReport:
    status: str
    reasons: list[str]
    classes: int
    native_methods: int
    entries: int


def _constant_pool_and_methods(payload: bytes) -> tuple[bool, int]:
    """Scan only class constant-pool refs/descriptors and native method flags."""
    view = memoryview(payload)
    offset = 0

    def take(length: int) -> memoryview:
        nonlocal offset
        if length < 0 or offset + length > len(view):
            raise JarInspectionError("truncated-class")
        data = view[offset:offset + length]
        offset += length
        return data

    def integer(width: int) -> int:
        return int.from_bytes(take(width), "big")

    if integer(4) != 0xCAFEBABE:
        raise JarInspectionError("bad-class-magic")
    take(4)  # minor / major
    count = integer(2)
    if count < 1 or count > 65535:
        raise JarInspectionError("invalid-constant-pool")
    refs: list[str] = []
    index = 1
    while index < count:
        tag = integer(1)
        if tag == 1:
            size = integer(2)
            # Java uses modified UTF-8; ASCII API and descriptor references
            # are preserved in both encodings.
            refs.append(bytes(take(size)).decode("utf-8", "replace"))
        elif tag in (3, 4, 9, 10, 11, 12, 17, 18):
            take(4)
        elif tag in (5, 6):
            take(8)
            index += 1
        elif tag in (7, 8, 16, 19, 20):
            take(2)
        elif tag == 15:
            take(3)
        else:
            raise JarInspectionError("unknown-constant-pool-tag")
        index += 1

    # A descriptor may reference Android even when it has no matching Class
    # constant pool entry. Simple substring matching can be conservative.
    android = any(
        "android/" in value or "dalvik/" in value or "androidx/" in value
        or "com/android/" in value or "Landroid/" in value
        for value in refs
    )

    take(6)  # access_flags, this_class, super_class
    interfaces = integer(2)
    take(interfaces * 2)

    def attributes() -> None:
        count_attributes = integer(2)
        for _ in range(count_attributes):
            take(2)
            length = integer(4)
            take(length)

    def members(count_members: int, check_native: bool) -> int:
        native = 0
        for _ in range(count_members):
            flags = integer(2)
            take(4)  # name and descriptor index
            if check_native and flags & 0x0100:
                native += 1
            attributes()
        return native

    members(integer(2), False)  # fields
    native_count = members(integer(2), True)
    attributes()  # class attributes
    if offset != len(view):
        raise JarInspectionError("trailing-class-bytes")
    return android, native_count


def inspect_jar(path: str | os.PathLike[str]) -> JarReport:
    source = Path(path)
    if source.suffix.lower() != ".jar" or not source.is_file():
        raise JarInspectionError("expected-local-jar-file")
    if source.stat().st_size > MAX_JAR_BYTES:
        raise JarInspectionError("jar-file-too-large")
    blockers: set[str] = set()
    class_count = 0
    native_methods = 0
    total = 0
    try:
        with zipfile.ZipFile(source) as archive:
            records = archive.infolist()
            if len(records) > MAX_ENTRIES:
                raise JarInspectionError("too-many-entries")
            if not records:
                raise JarInspectionError("empty-jar")
            seen_names: set[str] = set()
            for entry in records:
                name = entry.filename.replace("\\", "/")
                parts = name.split("/")
                if (name.startswith("/") or any(part in (".", "..") for part in parts)
                        or "\x00" in name):
                    raise JarInspectionError("unsafe-entry-path")
                if name in seen_names:
                    raise JarInspectionError("duplicate-entry-path")
                seen_names.add(name)
                if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                    raise JarInspectionError("symlink-entry")
                if entry.is_dir():
                    continue
                if entry.flag_bits & 1:
                    raise JarInspectionError("encrypted-entry")
                if entry.file_size > MAX_ENTRY_BYTES:
                    raise JarInspectionError("entry-too-large")
                if entry.file_size > 0 and (entry.compress_size == 0 or
                        entry.file_size / entry.compress_size > MAX_RATIO):
                    raise JarInspectionError("suspicious-compression-ratio")
                total += entry.file_size
                if total > MAX_UNCOMPRESSED:
                    raise JarInspectionError("archive-uncompressed-limit")
                if name.lower().endswith(NATIVE_EXTENSIONS):
                    blockers.add("native-library")
                if name.lower().endswith(".dex"):
                    blockers.add("android-dex-bytecode")
                if name.lower().endswith((".jar", ".zip")):
                    blockers.add("nested-archive-not-inspected")
                if name.upper() == "META-INF/MANIFEST.MF":
                    with archive.open(entry) as manifest_stream:
                        manifest = manifest_stream.read(16_384).decode("utf-8", "replace")
                    if any(line.lower().startswith("class-path:") for line in manifest.splitlines()):
                        blockers.add("external-classpath")
                if name.lower().endswith(".class"):
                    if entry.file_size > MAX_CLASS_BYTES:
                        raise JarInspectionError("class-too-large")
                    with archive.open(entry) as data:
                        blob = data.read(MAX_CLASS_BYTES + 1)
                    if len(blob) != entry.file_size:
                        raise JarInspectionError("truncated-entry")
                    has_android, native = _constant_pool_and_methods(blob)
                    native_methods += native
                    if has_android:
                        blockers.add("android-api-reference")
                    if native:
                        blockers.add("jni-native-method")
                    class_count += 1
            if class_count == 0:
                blockers.add("no-java-bytecode")
    except (zipfile.BadZipFile, EOFError, OSError, RuntimeError) as exc:
        raise JarInspectionError("invalid-or-corrupt-jar") from exc

    return JarReport(
        status="unsupported" if blockers else "pure-jvm-candidate",
        reasons=sorted(blockers),
        classes=class_count,
        native_methods=native_methods,
        entries=len(records),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("jar", help="Local JAR filename; never executed")
    args = parser.parse_args()
    try:
        report = inspect_jar(args.jar)
        print(json.dumps(asdict(report), sort_keys=True))
        return 0 if report.status == "pure-jvm-candidate" else 2
    except JarInspectionError as exc:
        print(json.dumps({"status": "rejected", "reason": str(exc)}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
