"""Fingerprint normalized FongMi init inputs; does not approve or execute code."""
import hashlib
import json


def fingerprint(site, inherited_jar="", flags=None):
    ext = site.get("ext", "")
    if isinstance(ext, (dict, list)):
        ext = json.dumps(ext, ensure_ascii=False, separators=(",", ":"))
    elif ext is None:
        ext = ""
    else:
        ext = str(ext).strip()
    flags = flags or []
    if not all(isinstance(flag, str) for flag in flags):
        raise ValueError("flags-must-be-strings")
    fields = [site.get("key", ""), site.get("api", ""),
              site.get("jar") or inherited_jar, ext, str(len(flags))] + flags
    digest = hashlib.sha256()
    for field in fields:
        data = field.encode("utf-8")
        digest.update(str(len(data)).encode("ascii") + b":" + data)
    return digest.hexdigest()
