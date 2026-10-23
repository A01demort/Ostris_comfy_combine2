import importlib.util
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.dont_write_bytecode = True
script = Path(__file__).with_name('startup_deadline.py')
spec = importlib.util.spec_from_file_location('startup_deadline_check', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert module.startup_seconds('3600') == 3600
assert module.startup_seconds('21600') == 3600
for value in ('0', '-1', 'nan', 'inf', 'bad'):
    try:
        module.startup_seconds(value)
    except ValueError:
        pass
    else:
        raise AssertionError(value)


def wait_for(predicate, seconds=8):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.02)
    raise AssertionError('startup deadline verification timed out')


def running(pid):
    try:
        return Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[0] != 'Z'
    except FileNotFoundError:
        return False


with tempfile.TemporaryDirectory(prefix='a1-startup-check-') as directory:
    root = Path(directory)
    fake = root / 'fake.py'
    fake.write_text('''import os, subprocess, sys, time
from pathlib import Path
mode, directory = sys.argv[1:]
root = Path(directory)
root.joinpath('started').write_text('1')
if mode == 'ready':
    Path(os.environ['A1_STARTUP_READY_FILE']).write_text('ready')
    time.sleep(4.2)
    root.joinpath('after-limit').write_text('1')
    time.sleep(30)
if mode == 'failure':
    sys.exit(19)
if mode == 'orphan':
    child = subprocess.Popen([sys.executable, '-c', 'import signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)'], start_new_session=True)
    root.joinpath('child').write_text(str(child.pid))
    sys.exit(19)
if mode == 'hang':
    child = subprocess.Popen([sys.executable, '-c', 'import signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)'], start_new_session=True)
    root.joinpath('child').write_text(str(child.pid))
    time.sleep(30)
''', encoding='utf-8')
    for mode in ('hang', 'failure', 'orphan', 'ready'):
        target = root / mode
        target.mkdir()
        environment = dict(os.environ, A1_STARTUP_TIMEOUT='3')
        with (target / 'log').open('w+', encoding='utf-8') as log:
            started = time.monotonic()
            process = subprocess.Popen([sys.executable, str(script), sys.executable, str(fake), mode, str(target)],
                                       env=environment, stdout=log, stderr=subprocess.STDOUT)
            try:
                wait_for(lambda: (target / 'started').is_file())
                if mode == 'ready':
                    wait_for(lambda: (target / 'after-limit').is_file())
                    assert process.poll() is None
                else:
                    wait_for(lambda: '진단 대기' in (target / 'log').read_text(encoding='utf-8'))
                    if mode in ('hang', 'orphan'):
                        pid = int((target / 'child').read_text())
                        wait_for(lambda: not running(pid))
                    assert process.poll() is None
                    if mode == 'hang':
                        assert time.monotonic() - started < 5
                process.send_signal(signal.SIGTERM)
                assert process.wait(timeout=5) == 128 + signal.SIGTERM
                text = (target / 'log').read_text(encoding='utf-8')
                assert ('전체 준비 시간 초과' in text) == (mode == 'hang')
                assert ('초기 준비 실패' in text) == (mode in ('failure', 'orphan'))
                assert (target / 'started').read_text() == '1'
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                if (target / 'child').is_file():
                    try:
                        os.kill(int((target / 'child').read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass

print('A1_STARTUP_DEADLINE_CHECK_OK', flush=True)
