"""No-network static JAR scanner tests with synthetic JVM classfile bytes."""
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from jar_inspect import JarInspectionError, _constant_pool_and_methods, inspect_jar


def fake_class(android=False, native=False):
    def u1(x): return struct.pack(">B", x)
    def u2(x): return struct.pack(">H", x)
    def u4(x): return struct.pack(">I", x)
    def utf8(value):
        payload = value.encode()
        return u1(1) + u2(len(payload)) + payload
    entries = [
        utf8("Fixture"), u1(7) + u2(1),
        utf8("java/lang/Object"), u1(7) + u2(3),
        utf8("getValue"), utf8("()V"),
    ]
    if android:
        entries.extend([utf8("android/content/Context"), u1(7) + u2(7)])
    # Abstract or native methods have no Code attribute.
    method_flags = 0x0101 if native else 0x0401
    return (
        b"\xca\xfe\xba\xbe" + u2(0) + u2(61) +
        u2(len(entries) + 1) + b"".join(entries) +
        u2(0x0421) + u2(2) + u2(4) +
        u2(0) + u2(0) + u2(1) +
        u2(method_flags) + u2(5) + u2(6) + u2(0) +
        u2(0)
    )


class JavaCompatibilityTests(unittest.TestCase):
    def with_jar(self, entries):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        filename = Path(temp.name) / "fixture.jar"
        with zipfile.ZipFile(filename, "w") as archive:
            for name, blob in entries:
                archive.writestr(name, blob)
        return filename

    def test_compilable_pure_jvm_bytecode_is_only_a_candidate(self):
        filename = self.with_jar([("Fixture.class", fake_class())])
        report = inspect_jar(filename)
        self.assertEqual(report.status, "pure-jvm-candidate")
        self.assertEqual(report.classes, 1)
        self.assertEqual(report.reasons, [])

    def test_rejects_android_api_constant_pool_descriptors(self):
        filename = self.with_jar([("Fixture.class", fake_class(android=True))])
        report = inspect_jar(filename)
        self.assertEqual(report.status, "unsupported")
        self.assertIn("android-api-reference", report.reasons)

    def test_rejects_jni_methods_or_bundled_native_libraries(self):
        file = self.with_jar([("Fixture.class", fake_class(native=True)),
                              ("lib/x86_64/libnative.so", b"opaque")])
        report = inspect_jar(file)
        self.assertEqual(report.status, "unsupported")
        self.assertIn("jni-native-method", report.reasons)
        self.assertIn("native-library", report.reasons)
        self.assertEqual(report.native_methods, 1)

    def test_malformed_class_fails_closed(self):
        filename = self.with_jar([("Fixture.class", b"\xca\xfe\xba\xbe\x00")])
        with self.assertRaisesRegex(JarInspectionError, "truncated"):
            inspect_jar(filename)

    def test_zip_slip_is_rejected_before_reading_files(self):
        filename = self.with_jar([("../escape.class", fake_class())])
        with self.assertRaisesRegex(JarInspectionError, "unsafe-entry-path"):
            inspect_jar(filename)

    def test_no_class_and_unrecognized_file(self):
        file = self.with_jar([("readme.txt", b"No classes")])
        report = inspect_jar(file)
        self.assertEqual(report.status, "unsupported")
        self.assertIn("no-java-bytecode", report.reasons)
        with self.assertRaises(JarInspectionError):
            inspect_jar(str(file) + ".not-a-jar")

    def test_class_parser_rejects_unknown_constant_pool_tag(self):
        damaged = bytearray(fake_class())
        damaged[10] = 0xFF
        with self.assertRaisesRegex(JarInspectionError, "unknown-constant-pool"):
            _constant_pool_and_methods(bytes(damaged))


if __name__ == "__main__":
    unittest.main(verbosity=2)
