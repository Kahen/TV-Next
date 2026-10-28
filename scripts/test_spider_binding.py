import unittest
from spider_binding import fingerprint


class BindingTests(unittest.TestCase):
    def test_multibyte_fields_and_boundaries_match_jvm_contract(self):
        site = {"key": "fixture", "api": "csp_Fixture", "ext": {"name": "测试"}}
        jar = "https://example.org/worker.jpg;md5;" + "a" * 32
        self.assertEqual("915f90debc5c3d822c2abdf2b64f5ea865c1146f7f5a0ae47a074754204a02f4", fingerprint(site, jar, ["own"]))
        self.assertNotEqual(fingerprint({"key": "ab", "api": "c"}), fingerprint({"key": "a", "api": "bc"}))
        self.assertNotEqual(fingerprint(site, jar, ["own"]), fingerprint(site, jar, ["other"]))


if __name__ == "__main__":
    unittest.main()
