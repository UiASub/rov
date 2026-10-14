"""Exercise installer safety and reruns without downloads or system changes."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("install-zephyr.sh").resolve()
MANIFEST = SCRIPT.parents[1] / "west.yml"


class InstallTest(unittest.TestCase):
    def test_install_rerun_and_foreign_workspace(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / "bin"
            tools.mkdir()
            log = root / "calls"
            for name in ("uv", "west"):
                program = tools / name
                program.write_text('''#!/bin/bash
printf '%s\\n' "$0 $*" >> "$CALL_LOG"
if [[ "$1" == venv ]]; then
  mkdir -p "$4/bin"
  printf '#!/bin/bash\\n' > "$4/bin/python"
  chmod +x "$4/bin/python"
fi
if [[ "$1" == init ]]; then mkdir -p .west; fi
''')
                program.chmod(0o755)
            env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}", CALL_LOG=str(log))
            workspace = root / "workspace with spaces"
            command = [str(SCRIPT), "--workspace", str(workspace), "--skip-sdk"]
            for _ in range(2):
                subprocess.run(command, env=env, check=True, capture_output=True)
            self.assertEqual((workspace / "manifest/west.yml").read_bytes(), MANIFEST.read_bytes())
            calls = log.read_text()
            self.assertEqual(calls.count("west init -l manifest"), 1)
            self.assertEqual(calls.count("west update --narrow --fetch-opt=--depth=1"), 2)
            self.assertNotIn("sdk install", calls)
            (workspace / "manifest/west.yml").write_text("foreign manifest\n")
            before = log.read_text()
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("manifest differs", result.stderr)
            self.assertEqual(log.read_text(), before)

    def test_invalid_option(self):
        result = subprocess.run([str(SCRIPT), "--invalid"], capture_output=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
