import csv
import hashlib
import io
import os
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path


def wheel(directory, version):
    metadata = f'a1_uv_probe-{version}.dist-info'
    files = {'a1_uv_probe/__init__.py': f'VERSION = "{version}"\n',
             metadata + '/METADATA': f'Metadata-Version: 2.1\nName: a1-uv-probe\nVersion: {version}\n',
             metadata + '/WHEEL': 'Wheel-Version: 1.0\nGenerator: a1\nRoot-Is-Purelib: true\nTag: py3-none-any\n'}
    rows = [(name, '', str(len(content.encode()))) for name, content in files.items()]
    record = io.StringIO()
    csv.writer(record).writerows([*rows, (metadata + '/RECORD', '', '')])
    files[metadata + '/RECORD'] = record.getvalue()
    with zipfile.ZipFile(directory / f'a1_uv_probe-{version}-py3-none-any.whl', 'w') as archive:
        for name, content in files.items():
            archive.writestr(name, content)


def main():
    directory = Path(os.environ.get('A1_INSTALLER_TEST_DIR', '/tmp/a1-uv-check'))
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=directory) as temporary:
        root = Path(temporary)
        wheels = root / 'wheels'
        wheels.mkdir()
        wheel(wheels, '1.0')
        wheel(wheels, '2.0')
        requirements = root / 'requirements.txt'
        requirements.write_text('a1-uv-probe>=1.0\n', encoding='utf-8')
        constraints = root / 'constraints.txt'
        constraints.write_text('a1-uv-probe==1.0\n', encoding='utf-8')
        environment = {key: value for key, value in os.environ.items() if not key.startswith(('PIP_', 'UV_'))}
        environment.update({'UV_CACHE_DIR': str(root / 'uv-cache'),
                       'PIP_CACHE_DIR': str(root / 'pip-cache'), 'PIP_CONSTRAINT': 'constraints.txt',
                       'PIP_CONFIG_FILE': os.devnull, 'PYTHONUTF8': '1',
                       'A1_STATE_DIR': str(root / 'state'), 'UV_PYTHON_DOWNLOADS': 'never', 'TMPDIR': str(root)})
        installer = Path(__file__).with_name('python_install.py')
        checksums = (hashlib.sha256(requirements.read_bytes()).hexdigest(), hashlib.sha256(constraints.read_bytes()).hexdigest())
        for backend in ('uv', 'pip'):
            target = root / backend
            subprocess.run(['uv', '--no-config', 'venv', '--python', sys.executable,
                            '--system-site-packages', str(target)], env=environment, check=True, timeout=30)
            python = target / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
            result = subprocess.run([str(python), str(installer), '60', '--no-index', '--find-links', str(wheels),
                                     '-r', str(requirements), '--break-system-packages'],
                                    env={**environment, 'A1_PYTHON_INSTALLER': backend}, cwd=root,
                                    capture_output=True, text=True, timeout=65)
            print(result.stdout, end='')
            print(result.stderr, end='', file=sys.stderr)
            assert result.returncode == 0, backend
            if backend == 'uv':
                assert '⚡' in result.stdout and '복귀' not in result.stderr
            subprocess.run([str(python), '-c', 'import a1_uv_probe; assert a1_uv_probe.VERSION == "1.0"'], check=True, timeout=10)
        assert checksums == (hashlib.sha256(requirements.read_bytes()).hexdigest(), hashlib.sha256(constraints.read_bytes()).hexdigest())
        sys.path.insert(0, str(Path(__file__).parent))
        import python_install
        started = time.monotonic()
        assert python_install.run([sys.executable, '-c', 'import time; time.sleep(5)'], 0.2, environment) == 124
        assert time.monotonic() - started < 3
        print('A1_UV_AND_PIP_CONSTRAINT_CHECK_OK')


if __name__ == '__main__':
    main()
