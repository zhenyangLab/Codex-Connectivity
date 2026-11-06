"""Exercise generated launchers against a disposable .app; never launch the real app."""
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import sys
import tempfile
import unittest

INSTALLER = Path(__file__).resolve().parents[1] / 'scripts/install-codex-proxy-shortcut.sh'


@unittest.skipUnless(sys.platform == 'darwin', 'Requires macOS PlistBuddy and nc')
class MacInstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='codex-proxy-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "space ' dollar $ `ticks`"
        self.app = self.root / 'Fake Codex.app'
        (self.app / 'Contents/MacOS').mkdir(parents=True)
        self.desktop = self.root / 'Desktop'
        self.home = self.root / '.codex'
        self.home.mkdir()
        self.config = self.home / 'config.toml'
        self.config.write_text('model_provider = "openai"\n')
        self.history = self.home / 'sessions' / 'sentinel.jsonl'
        self.history.parent.mkdir()
        self.history.write_bytes(b'history stays unchanged')
        self.env = dict(os.environ, CODEX_HOME=str(self.home), CAPTURE=str(self.root / 'capture'))
        self.listener = socket.socket()
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen(20)
        self.addCleanup(self.listener.close)
        self.port = self.listener.getsockname()[1]
        self.set_executable('First')

    def set_executable(self, name):
        with (self.app / 'Contents/Info.plist').open('wb') as f:
            plistlib.dump({'CFBundleExecutable': name}, f)
        exe = self.app / 'Contents/MacOS' / name
        exe.write_text('#!/bin/bash\n/usr/bin/env > "$CAPTURE.env"\nprintf "%s\\n" "$@" > "$CAPTURE.args"\n')
        exe.chmod(0o700)
        return exe

    def install(self, *extra, check=True):
        return subprocess.run(['/bin/bash', str(INSTALLER), '--app-path', str(self.app),
                               '--proxy-port', str(self.port), '--shortcut-directory', str(self.desktop),
                               *extra], env=self.env, text=True, capture_output=True, check=check)

    @property
    def launcher(self):
        return self.desktop / f'Codex-HTTP-Proxy-{self.port}.command'

    def launch(self, env=None):
        return subprocess.run(['/bin/bash', str(self.launcher)], env=env or self.env,
                              text=True, capture_output=True)

    def test_generated_launcher_inherits_proxy_and_preserves_history(self):
        before = dict(os.environ)
        self.install()
        subprocess.run(['/bin/bash', '-n', str(self.launcher)], check=True)
        self.assertEqual(self.launcher.stat().st_mode & 0o777, 0o700)
        result = self.launch()
        self.assertEqual(result.returncode, 0, result.stderr)
        captured = dict(line.split('=', 1) for line in Path(self.env['CAPTURE'] + '.env').read_text().splitlines())
        for name in ['HTTP_PROXY', 'HTTPS_PROXY', 'WS_PROXY', 'WSS_PROXY', 'ALL_PROXY',
                     'http_proxy', 'https_proxy', 'ws_proxy', 'wss_proxy', 'all_proxy']:
            self.assertEqual(captured[name], f'http://127.0.0.1:{self.port}')
        self.assertEqual(captured['CODEX_HOME'], str(self.home))
        self.assertEqual(captured['NO_PROXY'], captured['no_proxy'])
        args = Path(self.env['CAPTURE'] + '.args').read_text().splitlines()
        self.assertIn(f'--proxy-server=http://127.0.0.1:{self.port}', args)
        self.assertIn('--disable-quic', args)
        self.assertEqual(self.config.read_text(), 'model_provider = "openai"\n')
        self.assertEqual(self.history.read_bytes(), b'history stays unchanged')
        self.assertEqual(dict(os.environ), before)

    def test_dry_run_writes_nothing(self):
        self.install('--dry-run')
        self.assertFalse(self.desktop.exists())

    def test_app_update_rereads_executable(self):
        self.install()
        (self.app / 'Contents/MacOS/First').unlink()
        self.set_executable('Updated')
        self.assertEqual(self.launch().returncode, 0)

    def test_running_app_refused(self):
        self.install()
        fake_bin = self.root / 'bin'
        fake_bin.mkdir()
        ps = fake_bin / 'ps'
        ps.write_text('#!/bin/bash\nprintf "%s\\n" "$FAKE_EXE"\n')
        ps.chmod(0o700)
        env = dict(self.env, PATH=f'{fake_bin}:/usr/bin:/bin', FAKE_EXE=str(self.app / 'Contents/MacOS/First'))
        result = self.launch(env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('already running', result.stderr)
        self.assertFalse(Path(self.env['CAPTURE'] + '.env').exists())

    def test_invalid_inputs_write_nothing(self):
        for args in [('--proxy-port', '0'), ('--proxy-port', '65536'), ('--proxy-port', 'x'),
                     ('--proxy-port', '9999999999999999'), ('--proxy-host', 'bad;host'),
                     ('--proxy-host', '192.0.2.1')]:
            with self.subTest(args=args):
                self.assertNotEqual(self.install(*args, check=False).returncode, 0)
                self.assertFalse(self.desktop.exists())

    def test_missing_port(self):
        result = subprocess.run(['/bin/bash', str(INSTALLER)], env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.desktop.exists())

    def test_legacy_configuration_refused_without_writes(self):
        text = 'model_provider = "codex_proxy_http"\n'
        self.config.write_text(text)
        self.assertNotEqual(self.install(check=False).returncode, 0)
        self.assertEqual(self.config.read_text(), text)
        self.assertFalse(self.desktop.exists())

    def test_offline_install_runtime_still_checks_proxy(self):
        self.listener.close()
        self.assertNotEqual(self.install(check=False).returncode, 0)
        self.install('--skip-proxy-check')
        self.assertNotEqual(self.launch().returncode, 0)
        self.assertFalse(Path(self.env['CAPTURE'] + '.env').exists())

    def test_ipv6_url_is_bracketed(self):
        self.install('--proxy-host', '::1', '--skip-proxy-check')
        text = self.launcher.read_text()
        self.assertIn(f'http://\\[::1\\]:{self.port}', text)


if __name__ == '__main__':
    unittest.main()
