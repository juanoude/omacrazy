"""Installer checks using a fake build and an isolated home (no app settings touched)."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class InstallTests(unittest.TestCase):
    def test_filtered_install_and_repeat_preserve_user_data(self):
        with tempfile.TemporaryDirectory(prefix='omacrazy-install-') as temporary:
            root = Path(temporary)
            project = root / 'source checkout'
            project.mkdir()
            shutil.copy2(Path(__file__).resolve().parents[1] / 'install.sh', project)
            binary = project / '.build/release/omacrazy'
            binary.parent.mkdir(parents=True)
            binary.write_text('#!/bin/sh\nexit 0\n')
            binary.chmod(0o755)
            theme = project / 'themes/sample'
            used = ['colors.toml', 'alacritty.toml', 'hyprland.conf', 'ghostty.conf',
                    'jankyborders.conf', 'zed.json', 'zed/themes/Test.JSON',
                    'backgrounds/a picture.PNG', 'LICENSE']
            unused = ['vscode.json', 'preview.png', 'apply.sh', 'README.md',
                      'backgrounds/info.txt', 'zed/themes/README.md']
            for name in used + unused:
                file = theme / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(name)
            mock_bin = root / 'mock-bin'
            mock_bin.mkdir()
            swift = mock_bin / 'swift'
            swift.write_text('#!/bin/sh\nexit 0\n')
            swift.chmod(0o755)
            home = root / 'isolated home'
            environment = dict(os.environ, HOME=str(home),
                               PATH=f'{mock_bin}:/usr/bin:/bin',
                               OMACRAZY_INSTALL_DIR=str(home / 'bin'))
            def install():
                subprocess.run(['/bin/sh', str(project / 'install.sh')], cwd=root,
                               env=environment, check=True, capture_output=True)
            install()
            installed = home / '.config/omacrazy/themes/sample'
            self.assertEqual(sorted(str(p.relative_to(installed)) for p in installed.rglob('*') if p.is_file()), sorted(used))
            self.assertTrue(os.access(home / 'bin/omacrazy', os.X_OK))
            config = installed / 'ghostty.conf'
            config.write_text('personal edit')
            custom = installed.parent / 'custom/colors.toml'
            custom.parent.mkdir()
            custom.write_text('custom palette')
            install()
            install()
            self.assertEqual(config.read_text(), 'ghostty.conf')
            self.assertEqual(config.with_name('ghostty.conf.omacrazy-backup').read_text(), 'personal edit')
            self.assertEqual(custom.read_text(), 'custom palette')
            self.assertEqual((theme / 'ghostty.conf').read_text(), 'ghostty.conf')


if __name__ == '__main__':
    unittest.main()
