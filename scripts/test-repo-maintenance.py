#!/usr/bin/env python3
"""Regression checks for CI policy, release gates and GitHub digest limits."""

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import subprocess
import textwrap
import unittest


def load(name):
    loader = importlib.machinery.SourceFileLoader(name, str(Path(__file__).parent / name))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


digest = load("compose-upstream-watch-issue")
notes = load("verify-release-notes")
client_watch = load("upstream-client-watch")


class CIValidationPolicyTests(unittest.TestCase):
    """Execute the actual workflow classifier with deterministic GitHub responses."""

    root = Path(__file__).resolve().parent.parent
    workflow = (root / ".github/workflows/pr-ci.yml").read_text()

    def classify(self, files, labels="", branch="issue/42-mac-fix", patch="", fail_api=False):
        script = textwrap.dedent(self.workflow.split("        run: |\n", 1)[1]
                                 .split("\n  maintenance:", 1)[0])
        script = script.replace("${{ github.repository }}", "fixture/repo")
        script = script.replace("${{ github.event.pull_request.number }}", "42")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            gh = root / "gh"
            gh.write_text("#!/usr/bin/env python3\n" + textwrap.dedent('''\
                import json, os, sys
                fixture = json.loads(os.environ["CI_POLICY_FIXTURE"])
                if fixture["fail_api"]:
                    sys.exit(1)
                query = sys.argv[-1]
                key = "patch" if "select(.filename" in query else "files" if "filename" in query else "labels"
                print(fixture[key])
                '''))
            gh.chmod(0o755)
            output = root / "outputs"
            result = subprocess.run(["bash", "-c", script], text=True, capture_output=True,
                env={**os.environ, "PATH": f"{root}{os.pathsep}{os.environ['PATH']}",
                     "HEAD_REF": branch, "GITHUB_OUTPUT": str(output),
                     "CI_POLICY_FIXTURE": json.dumps(dict(files=files, labels=labels,
                                                          patch=patch, fail_api=fail_api))})
            if fail_api:
                self.assertNotEqual(result.returncode, 0)
                return
            self.assertEqual(result.returncode, 0, result.stderr)
            return dict(line.split("=", 1) for line in output.read_text().splitlines())

    def expected(self, mac=False, compile=False, full=False):
        return {"run_tests": str(mac).lower(), "run_iphone_compile": str(compile).lower(),
                "run_iphone_tests": str(full).lower()}

    def test_ordinary_shared_changes_run_mac_only(self):
        self.assertEqual(self.classify("HermesMobile/Features/Chat/ChatView.swift"),
                         self.expected(mac=True))

    def test_upstream_integrations_compile_without_full_suite(self):
        for labels, branch in [("upstream-integration", "issue/42-upstream"),
                               ("", "upstream/v1.7"), ("", "sync/upstream-20260909")]:
            with self.subTest(labels=labels, branch=branch):
                self.assertEqual(self.classify("HermesMobile/Models/Message.swift", labels, branch),
                                 self.expected(mac=True, compile=True))

    def test_full_suite_is_explicit_even_without_app_changes(self):
        for files, mac in [("HermesMobile/Models/Message.swift", True), ("README.md", False)]:
            with self.subTest(files=files):
                self.assertEqual(self.classify(files, "bug\nfull-iphone-tests"),
                                 self.expected(mac=mac, compile=True, full=True))

    def test_documentation_and_workflow_changes_skip_app_jobs(self):
        files = "AGENTS.md\n.github/workflows/pr-ci.yml\nscripts/test-repo-maintenance.py"
        self.assertEqual(self.classify(files), self.expected())
        self.assertEqual(self.classify(files, "upstream-integration", "upstream/docs"), self.expected())

    def test_version_only_exception_preserves_other_project_checks(self):
        project = "HermesMobile.xcodeproj/project.pbxproj"
        version = "- CURRENT_PROJECT_VERSION = 1;\n+ CURRENT_PROJECT_VERSION = 2;"
        self.assertEqual(self.classify(project, patch=version), self.expected())
        for patch in ("", version + "\n+ SWIFT_VERSION = 6.0;"):
            with self.subTest(patch=patch):
                self.assertEqual(self.classify(project, patch=patch), self.expected(mac=True))

    def test_unknown_paths_and_similar_labels_do_not_skip_mac_or_opt_in_iphone(self):
        self.assertEqual(self.classify("Config/Unrecognized.xcconfig",
                                       "not-full-iphone-tests\nnot-upstream-integration"),
                         self.expected(mac=True))

    def test_api_failure_fails_classification(self):
        self.classify("README.md", fail_api=True)

    def test_job_wiring_and_manual_only_compatibility_workflow(self):
        iphone = self.workflow.split("  test_ios:\n", 1)[1].split("  test_mac:\n", 1)[0]
        mac = self.workflow.split("  test_mac:\n", 1)[1].split("  gate:\n", 1)[0]
        self.assertIn("if: needs.changes.outputs.run_iphone_compile == 'true'", iphone)
        self.assertIn("if: needs.changes.outputs.run_iphone_tests == 'true'", iphone)
        self.assertIn("if: needs.changes.outputs.run_tests == 'true'", mac)
        self.assertIn("needs: [changes, maintenance, test_ios, test_mac]", self.workflow)
        manual = (self.root / ".github/workflows/iphone-compatibility.yml").read_text()
        triggers = manual.split("\non:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertEqual(triggers.strip(), "workflow_dispatch:")

    def test_base_edits_validate_without_metadata_edits_replacing_the_gate(self):
        triggers = self.workflow.split("\non:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertIn("edited", triggers)
        changes = self.workflow.split("  changes:\n", 1)[1].split("    steps:", 1)[0]
        maintenance = self.workflow.split("  maintenance:\n", 1)[1].split("    steps:", 1)[0]
        gate = self.workflow.split("  gate:\n", 1)[1]
        group = next(line for line in self.workflow.splitlines() if line.startswith("  group:"))
        name = next(line for line in gate.splitlines() if line.startswith("    name:"))
        # Execute the boolean/string subset used by these actual workflow
        # expressions. Payload fields are substituted as Python literals; no
        # API data or workflow shell is evaluated by this test.
        def evaluate(expression, action, base):
            expression = expression.replace("github.event.action", repr(action))
            expression = expression.replace("github.event.changes.base", repr(base))
            expression = expression.replace("null", "None").replace("&&", "and").replace("||", "or")
            return eval(expression, {"__builtins__": {}}, {})

        cases = [("opened", None, True), ("synchronize", None, True),
                 ("labeled", None, True), ("unlabeled", None, True),
                 ("reopened", None, True), ("edited", None, False),
                 ("edited", {"ref": {"from": "issue/previous-base"}}, True)]
        for action, base, validates in cases:
            with self.subTest(action=action, base=base):
                for job in (changes, maintenance):
                    condition = next(line.split("if: ", 1)[1] for line in job.splitlines() if "if: " in line)
                    self.assertEqual(evaluate(condition, action, base), validates)
                gate_condition = next(line.split("if: ", 1)[1] for line in gate.splitlines()
                                      if line.startswith("        if:"))
                self.assertEqual(evaluate(gate_condition, action, base), validates)
                gate_name = evaluate(name.split("${{", 1)[1].split("}}", 1)[0], action, base)
                self.assertEqual(gate_name, "CI Gate" if validates else "PR metadata update")
                group_suffix = evaluate(group.rsplit("${{", 1)[1].split("}}", 1)[0], action, base)
                self.assertEqual(group_suffix, "validation" if validates else "metadata")
        self.assertIn("    if: always()", gate)


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
