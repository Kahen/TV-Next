#!/usr/bin/env python3
"""Publish exact API test counts, keeping skipped checks distinct from passed checks."""
from pathlib import Path
import os
import sys
import xml.etree.ElementTree as ET


def main():
    files = list(Path(sys.argv[1]).glob("TEST-*.xml"))
    if not files:
        raise SystemExit("No JUnit reports found")
    totals = dict.fromkeys(("tests", "failures", "errors", "skipped"), 0)
    for path in files:
        suite = ET.parse(path).getroot()
        for key in totals:
            totals[key] += int(suite.get(key, "0"))
    passed = totals["tests"] - totals["failures"] - totals["errors"] - totals["skipped"]
    message = f"API tests: {passed} passed; {totals['failures']} failed; {totals['errors']} errors; {totals['skipped']} skipped; {totals['tests']} total."
    print(message)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as output:
            output.write(message + "\n\nSkipped checks are not counted as passed. Physical media and real cloud-provider acceptance remain separate.\n")
    if totals["failures"] or totals["errors"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
