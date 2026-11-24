import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import compare_versions as cv  # noqa: E402


def _write(root: Path, files: dict) -> None:
    for rel, text in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")


class CompareVersionsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old = Path(self.tmp.name) / "alt"
        self.new = Path(self.tmp.name) / "neu"
        base = {
            "scripts/a.gd": "class_name Alpha\nfunc eins() -> void:\n\tpass\nstatic func zwei() -> void:\n\tpass\n",
            "scripts/b.gd": "class_name Beta\nfunc drei():\n\tpass\n",
            "tests/t.gd": '_check("Prüfung A", true)\n_check("Prüfung B", true)\n',
            "data/config/x.json": '{"a": {"b": 1, "c": 2}, "_note": "x"}',
        }
        _write(self.old, base)

    def tearDown(self):
        self.tmp.cleanup()

    def test_nothing_removed(self):
        _write(self.new, {
            "scripts/a.gd": "class_name Alpha\nfunc eins() -> void:\n\tpass\nstatic func zwei() -> void:\n\tpass\nfunc vier():\n\tpass\n",
            "scripts/b.gd": "class_name Beta\nfunc drei():\n\tpass\n",
            "tests/t.gd": '_check("Prüfung A", true)\n_check("Prüfung B", true)\n_check("Prüfung C", true)\n',
            "data/config/x.json": '{"a": {"b": 1, "c": 2, "d": 3}}',
            "scripts/neu.gd": "class_name Gamma\n",
        })
        r = cv.compare(cv.load(str(self.old)), cv.load(str(self.new)))
        self.assertFalse(cv.has_removals(r))
        self.assertIn("scripts/neu.gd", r["added"])

    def test_removals_found(self):
        _write(self.new, {
            "scripts/a.gd": "class_name Alpha\nfunc eins() -> void:\n\tpass\n",
            "tests/t.gd": '_check("Prüfung A", true)\n',
            "data/config/x.json": '{"a": {"b": 1}}',
        })
        r = cv.compare(cv.load(str(self.old)), cv.load(str(self.new)))
        self.assertTrue(cv.has_removals(r))
        self.assertEqual(r["removed"], ["scripts/b.gd"])
        self.assertEqual(r["removed_funcs"], {"scripts/a.gd": ["zwei"]})
        self.assertEqual(r["removed_checks"], ["Prüfung B"])
        self.assertEqual(r["removed_config_keys"], {"data/config/x.json": ["a.c"]})
        self.assertTrue(any("Beta" in c for c in r["removed_classes"]))
        self.assertEqual(cv.main([str(self.old), str(self.new)]), 1)


if __name__ == "__main__":
    unittest.main()
