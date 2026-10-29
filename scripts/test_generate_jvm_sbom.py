import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

from generate_jvm_sbom import build_sbom, render


class ShippedJvmSbomTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.jar = self.root / "api.jar"
        self.metadata = self.root / "verification.xml"
        self.owned = b"owned synthetic library bytes"
        self.library = "owned-1.2.3.jar"
        self.write_jar()
        self.write_metadata()

    def write_jar(self, entries=None):
        with zipfile.ZipFile(self.jar, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, data in entries or [("BOOT-INF/lib/" + self.library, self.owned)]:
                archive.writestr(name, data)
            archive.writestr("BOOT-INF/classes/owned.txt", b"application classes excluded from library components")

    def write_metadata(self, checksum=None, duplicate=False):
        checksum = checksum or hashlib.sha256(self.owned).hexdigest()
        component = f'<component group="example" name="owned" version="1.2.3"><artifact name="{self.library}"><sha256 value="{checksum}"/></artifact></component>'
        self.metadata.write_text('<verification-metadata xmlns="https://schema.gradle.org/dependency-verification"><components>' + component * (2 if duplicate else 1) + '</components></verification-metadata>')

    def test_exact_shipped_bytes_and_coordinates_and_determinism(self):
        first = build_sbom(self.jar, self.metadata, "0.2.0-rc.1")
        component = first["components"][0]
        self.assertEqual(component["purl"], "pkg:maven/example/owned@1.2.3?type=jar")
        self.assertEqual(component["hashes"][0]["content"], hashlib.sha256(self.owned).hexdigest())
        self.assertEqual(first["metadata"]["component"]["hashes"][0]["content"], hashlib.sha256(self.jar.read_bytes()).hexdigest())
        self.assertEqual(render(first), render(build_sbom(self.jar, self.metadata, "0.2.0-rc.1")))
        self.assertNotIn("dependencies", first)
        self.assertNotIn("licenses", component)

    def test_changed_or_unknown_shipped_library_is_rejected(self):
        for entries in [
            [("BOOT-INF/lib/" + self.library, b"tampered")],
            [("BOOT-INF/lib/unknown-1.0.jar", self.owned)],
        ]:
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                self.write_jar(entries)
                build_sbom(self.jar, self.metadata, "0.1.0")

    def test_unreviewed_boot_injected_jarmode_fails_closed(self):
        # Spring Boot 3.5 adds this tool unless bootJar.includeTools is false.
        # A reviewed runtime library must not make the unreviewed tool pass.
        self.write_jar([
            ("BOOT-INF/lib/" + self.library, self.owned),
            ("BOOT-INF/lib/spring-boot-jarmode-tools-3.5.6.jar", b"unreviewed boot tooling"),
        ])
        with self.assertRaisesRegex(ValueError, "spring-boot-jarmode-tools-3.5.6.jar"):
            build_sbom(self.jar, self.metadata, "0.1.0")

    def test_mismatching_reviewed_hash_is_rejected(self):
        self.write_metadata(checksum="0" * 64)
        with self.assertRaises(ValueError):
            build_sbom(self.jar, self.metadata, "0.1.0")

    def test_unsafe_and_duplicate_zip_paths_are_rejected(self):
        for name in ("../owned-1.2.3.jar", "nested/owned-1.2.3.jar", "owned\\1.2.3.jar"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.write_jar([("BOOT-INF/lib/" + name, self.owned)])
                build_sbom(self.jar, self.metadata, "0.1.0")
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            self.write_jar([("BOOT-INF/lib/" + self.library, self.owned)] * 2)
        with self.assertRaises(ValueError):
            build_sbom(self.jar, self.metadata, "0.1.0")

    def test_ambiguous_metadata_is_rejected(self):
        self.write_metadata(duplicate=True)
        with self.assertRaises(ValueError):
            build_sbom(self.jar, self.metadata, "0.1.0")

    def test_classifier_is_preserved_in_maven_identity(self):
        self.library = "owned-1.2.3-linux-x86_64.jar"
        self.write_jar()
        self.write_metadata()
        component = build_sbom(self.jar, self.metadata, "0.1.0")["components"][0]
        self.assertEqual(component["purl"], "pkg:maven/example/owned@1.2.3?classifier=linux-x86_64&type=jar")

    def test_archive_size_count_and_expansion_limits(self):
        for constant, limit in (("MAX_JAR", 1), ("MAX_LIBRARIES", 0), ("MAX_LIBRARY", 1), ("MAX_EXPANDED", 1)):
            with self.subTest(constant=constant), patch("generate_jvm_sbom." + constant, limit), self.assertRaises(ValueError):
                build_sbom(self.jar, self.metadata, "0.1.0")

    def test_no_shipped_libraries_and_invalid_version_fail(self):
        self.write_jar([("BOOT-INF/classes/owned.class", b"owned")])
        with self.assertRaises(ValueError):
            build_sbom(self.jar, self.metadata, "0.1.0")
        for version in ("../escape", "latest", "1.2.3\n"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                build_sbom(self.jar, self.metadata, version)


if __name__ == "__main__":
    unittest.main()
