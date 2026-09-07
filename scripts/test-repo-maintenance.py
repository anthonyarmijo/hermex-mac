#!/usr/bin/env python3
"""Regression checks for release gates and GitHub digest size limits."""

import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import subprocess
import unittest


def load(name):
    loader = importlib.machinery.SourceFileLoader(name, str(Path(__file__).parent / name))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


digest = load("compose-upstream-watch-issue")
notes = load("verify-release-notes")
client_watch = load("upstream-client-watch")


class DigestTests(unittest.TestCase):
    def compose(self, report):
        return digest.compose(report, "https://github.com/example/repo/actions/runs/1", "abc123", "origin/master")

    def test_small_report_is_preserved(self):
        body = self.compose("## Changes\nA fix\n")
        self.assertIn("> ## Changes\n> A fix", body)
        self.assertNotIn("Preview truncated", body)

    def test_oversized_ascii_and_unicode_reports_remain_bounded(self):
        for report in ("x" * 100_000, "漢字😀\n" * 30_000, "\n" * 100_000):
            with self.subTest(prefix=report[:10]):
                body = self.compose(report)
                self.assertLessEqual(len(body.encode("utf-8")), 60_000)
                self.assertIn("Preview truncated", body)
                self.assertIn("upstream-watch-report", body)
                self.assertNotIn("\ufffd", body)

    def test_footer_is_outside_quoted_unclosed_fence(self):
        body = self.compose("```python\n" + "x" * 100_000)
        self.assertIn("> ```python\n> ", body)
        self.assertIn("\n\n_Preview truncated", body)

    def test_empty_report_is_bounded(self):
        self.assertLess(len(self.compose("")), 60_000)

    def test_oversized_metadata_fails(self):
        with self.assertRaises(ValueError):
            digest.compose("x", "x" * 70_000, "abc", "origin/master")


class ClientDigestTests(unittest.TestCase):
    def test_client_issue_has_distinct_identity_and_unicode_budget(self):
        body = digest.compose("漢字😀\n" * 30_000, "https://example.test/run", "abc", "origin/master", "client")
        self.assertIn("upstream-client-watch-digest", body)
        self.assertIn("upstream-client-watch-report", body)
        self.assertIn("Hermex Client", body)
        self.assertNotIn("Hermes-WebUI Watch Digest", body)
        self.assertLessEqual(len(body.encode("utf-8")), 60_000)
        self.assertNotIn("\ufffd", body)

    def fixture(self, root):
        subprocess.run(["git", "init", "-q", str(root)], check=True)
        commits = []
        for index, title in enumerate(["Stable", "Applied fix", "Next Unicode 改善"]):
            (root / "fixture.txt").write_text(str(index))
            subprocess.run(["git", "-C", str(root), "add", "fixture.txt"], check=True)
            subprocess.run(["git", "-C", str(root), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test",
                            "commit", "-qm", title], check=True)
            commits.append(client_watch.git(root, "rev-parse", "HEAD"))
        return commits

    def test_report_excludes_exact_applied_patch_and_links_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            baseline, applied, target = self.fixture(root)
            report = client_watch.report(root, baseline, target, [applied], limit=1)
            self.assertIn("Commits requiring triage: 1", report)
            self.assertIn("Next Unicode 改善", report)
            self.assertNotIn(") Applied fix", report)
            self.assertIn(baseline + "..." + target, report)
            self.assertIn("not the running backend", report)

    def test_non_descendant_target_fails_instead_of_claiming_current(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first, second, third = self.fixture(root)
            with self.assertRaises(ValueError):
                client_watch.report(root, third, first)


class ReleaseNotesTests(unittest.TestCase):
    def validate(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "notes.md"
            path.write_text(text, encoding="utf-8")
            notes.validate(path)

    def test_curated_notes_pass(self):
        self.validate("## Highlights\n\n- Faster streaming.\n\n## Known issues\n\n- Manual updates.\n")

    def test_invalid_notes_fail(self):
        for text in ("", " \n", "## Highlights\nA fix", "## Highlights\nREPLACE\n## Known issues\nNone", "## Highlights\n\n## Known issues\nNone", "## Highlights\nA fix\n## Known issues\n"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.validate(text)

    def test_missing_file_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileNotFoundError):
                notes.validate(Path(directory) / "missing.md")


if __name__ == "__main__":
    unittest.main()
