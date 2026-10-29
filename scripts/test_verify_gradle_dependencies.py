from pathlib import Path
import tempfile
import unittest

from verify_gradle_dependencies import validate

CONFIGS = "compileClasspath,runtimeClasspath,testCompileClasspath,testRuntimeClasspath"
LOCK = "# Gradle generated\nexample:owned:1.2.3=" + CONFIGS + "\nempty=\n"
XML = """<?xml version="1.0" encoding="UTF-8"?>
<verification-metadata xmlns="https://schema.gradle.org/dependency-verification">
<configuration><verify-metadata>true</verify-metadata><verify-signatures>false</verify-signatures></configuration>
<components><component group="example" name="owned" version="1.2.3">
<artifact name="owned-1.2.3.jar"><sha256 value="HASH"/></artifact>
</component></components></verification-metadata>""".replace("HASH", "a" * 64)


class GradleEvidenceTests(unittest.TestCase):
    def check(self, lock=LOCK, xml=XML):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            api = root / "services/api"
            (api / "gradle").mkdir(parents=True)
            (api / "gradle.lockfile").write_text(lock)
            (api / "gradle/verification-metadata.xml").write_text(xml)
            return validate(root)

    def test_owned_complete_evidence(self):
        self.assertEqual(self.check(), (1, 1))

    def test_missing_lock_module_and_changed_version(self):
        for xml in (XML.replace('name="owned"', 'name="another"'), XML.replace('version="1.2.3"', 'version="1.2.4"')):
            with self.subTest(xml=xml), self.assertRaises(ValueError):
                self.check(xml=xml)

    def test_missing_compile_runtime_or_test_configuration(self):
        with self.assertRaises(ValueError):
            self.check(lock=LOCK.replace("testRuntimeClasspath", "other"))

    def test_dynamic_range_and_snapshot_versions(self):
        for version in ("1.+", "[1,2)", "latest.release", "1-SNAPSHOT"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                self.check(lock=LOCK.replace("1.2.3", version))

    def test_metadata_verification_cannot_be_disabled(self):
        with self.assertRaises(ValueError):
            self.check(xml=XML.replace("<verify-metadata>true", "<verify-metadata>false"))

    def test_blanket_artifact_trust_is_rejected(self):
        with self.assertRaises(ValueError):
            self.check(xml=XML.replace("</configuration>", '<trusted-artifacts><trust group=".*" regex="true"/></trusted-artifacts></configuration>'))

    def test_missing_weak_invalid_or_alternate_hash_is_rejected(self):
        for xml in (
            XML.replace("sha256", "sha1"),
            XML.replace("a" * 64, "x" * 64),
            XML.replace("a" * 64, "a" * 63),
            XML.replace("/></artifact>", '><also-trust value="' + "b" * 64 + '"/></sha256></artifact>'),
            XML.replace('<sha256 value="' + "a" * 64 + '"/>', ""),
        ):
            with self.subTest(xml=xml), self.assertRaises(ValueError):
                self.check(xml=xml)

    def test_duplicate_module_or_artifact_is_rejected(self):
        artifact = '<artifact name="owned-1.2.3.jar"><sha256 value="' + "a" * 64 + '"/></artifact>'
        component = XML.split("<components>")[1].split("</components>")[0]
        for xml in (XML.replace("</component>", artifact + "</component>"), XML.replace("</components>", component + "</components>")):
            with self.subTest(xml=xml), self.assertRaises(ValueError):
                self.check(xml=xml)
        with self.assertRaises(ValueError):
            self.check(lock=LOCK + "example:owned:1.2.3=" + CONFIGS + "\n")

    def test_dtd_is_rejected(self):
        with self.assertRaises(ValueError):
            self.check(xml=XML.replace("<verification-metadata", "<!DOCTYPE x><verification-metadata", 1))


if __name__ == "__main__":
    unittest.main()
