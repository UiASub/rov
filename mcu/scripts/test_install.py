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
            for name in ("uv", "west", "go"):
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
            command = [str(SCRIPT), "--workspace", str(workspace), "--skip-sdk", "--skip-system"]
            for _ in range(2):
                subprocess.run(command, env=env, check=True, capture_output=True)
            self.assertEqual((workspace / "manifest/west.yml").read_bytes(), MANIFEST.read_bytes())
            calls = log.read_text()
            self.assertEqual(calls.count("west init -l manifest"), 1)
            self.assertEqual(calls.count("west update --narrow --fetch-opt=--depth=1"), 2)
            self.assertNotIn("sdk install", calls)
            self.assertEqual(calls.count("go install github.com/apache/mynewt-mcumgr-cli"), 2)
            (workspace / "manifest/west.yml").write_text("foreign manifest\n")
            before = log.read_text()
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("manifest differs", result.stderr)
            self.assertEqual(log.read_text(), before)

    def test_linux_distro_package_commands(self):
        helper = SCRIPT.with_name("linux-prerequisites.sh")
        cases = [("ubuntu", "debian", "apt-get", "golang-go"),
                 ("arch", "", "pacman", "--needed"),
                 ("cachyos", "arch", "pacman", "go"),
                 ("fedora", "", "dnf", "golang")]
        for distro, related, manager, expected in cases:
            with self.subTest(distro=distro), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                log = root / "calls"
                for name in ("sudo", "apt-get", "pacman", "dnf"):
                    program = root / name
                    program.write_text('#!/bin/bash\nprintf "%s\\n" "$0 $*" >> "$CALL_LOG"\n' +
                                       ('exec "$@"\n' if name == "sudo" else 'exit 0\n'))
                    program.chmod(0o755)
                env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}", CALL_LOG=str(log))
                command = ['bash', '-c',
                           'source "$1"; test_id="$2"; test_like="$3"; '
                           'read_linux_release() { ID="$test_id"; ID_LIKE="$test_like"; }; '
                           'install_linux_prerequisites', 'test', str(helper), distro, related]
                subprocess.run(command, env=env, check=True, capture_output=True)
                calls = log.read_text()
                self.assertIn(manager, calls)
                self.assertIn(expected, calls)
                self.assertNotIn("upgrade", calls)
                self.assertNotIn("-Syu", calls)

    def test_uv_bootstrap_and_reuse(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / "bin"
            tools.mkdir()
            for name in ("mktemp", "rm", "sh", "mkdir", "chmod"):
                import shutil
                (tools / name).symlink_to(shutil.which(name))
            curl = tools / "curl"
            curl.write_text("""#!/bin/bash
while (($#)); do
  if [[ "$1" == --output ]]; then target="$2"; break; fi
  shift
done
printf 'download\\n' >> "$CALL_LOG"
cat_script='mkdir -p "$HOME/.local/bin"
printf "#!/bin/sh\\nexit 0\\n" > "$HOME/.local/bin/uv"
chmod +x "$HOME/.local/bin/uv"'
printf '%s\\n' "$cat_script" > "$target"
""")
            curl.chmod(0o755)
            log = root / "calls"
            env = dict(os.environ, PATH=str(tools), HOME=str(root), CALL_LOG=str(log))
            subprocess.run(['/usr/bin/bash', '-c', 'source "$1"; bootstrap_uv; bootstrap_uv',
                            'test', str(SCRIPT.with_name("linux-prerequisites.sh"))],
                           env=env, check=True, capture_output=True)
            self.assertEqual(log.read_text(), "download\n")
            self.assertTrue((root / ".local/bin/uv").is_file())

    def test_unsupported_distribution(self):
        result = subprocess.run(['bash', '-c', 'source "$1"; linux_family gentoo ""',
                                 'test', str(SCRIPT.with_name("linux-prerequisites.sh"))],
                                capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_invalid_option(self):
        result = subprocess.run([str(SCRIPT), "--invalid"], capture_output=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
