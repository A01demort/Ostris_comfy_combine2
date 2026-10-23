import ctypes
import math
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

stopping = 0


def startup_seconds(value):
    seconds = float(value)
    if not math.isfinite(seconds) or seconds <= 0:
        raise ValueError('invalid startup timeout')
    return min(seconds, 3600)


def stop_requested(signum, frame):
    global stopping
    stopping = signum


def descendants():
    parents = {}
    for entry in Path('/proc').glob('[0-9]*/stat'):
        try:
            fields = entry.read_text().rsplit(')', 1)[1].split()
            parents[int(entry.parent.name)] = int(fields[1])
        except (OSError, ValueError, IndexError):
            continue
    found = {os.getpid()}
    while True:
        expanded = found | {pid for pid, parent in parents.items() if parent in found}
        if expanded == found:
            return found - {os.getpid()}
        found = expanded


def terminate(process, deadline=None):
    pids = descendants()
    if process is not None and process.poll() is None:
        pids.add(process.pid)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    grace = min(1, max(0, deadline - time.monotonic())) if deadline is not None else 1
    time.sleep(grace)
    pids |= descendants()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if process is not None:
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
    if hasattr(os, 'waitpid'):
        try:
            while os.waitpid(-1, os.WNOHANG)[0]:
                pass
        except ChildProcessError:
            pass


def hold():
    while not stopping:
        time.sleep(0.1)
    return 128 + stopping


def main(command):
    global stopping
    stopping = 0
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, stop_requested)
    if sys.platform.startswith('linux'):
        if ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) != 0:
            print('❌ 초기화 프로세스 감시를 시작하지 못했습니다. 진단 대기 상태로 유지합니다.', flush=True)
            return hold()
    try:
        seconds = startup_seconds(os.environ.get('A1_STARTUP_TIMEOUT', '3600'))
    except ValueError:
        print('❌ A1_STARTUP_TIMEOUT 설정 오류. 전체 준비 상한은 최대 3600초입니다.', flush=True)
        return hold()
    deadline = time.monotonic() + seconds
    environment = os.environ.copy()
    environment['A1_STARTUP_DEADLINE'] = str(deadline)
    with tempfile.TemporaryDirectory(prefix='a1-startup-') as directory:
        ready = Path(directory) / 'ready'
        environment['A1_STARTUP_READY_FILE'] = str(ready)
        print(f'📋 전체 준비 상한: {seconds:g}초 (설치·재시도·모델 다운로드·서비스 준비 포함)', flush=True)
        try:
            process = subprocess.Popen(command, env=environment, start_new_session=True)
        except OSError:
            print('❌ 초기화 명령 실행 실패. 진단 대기 상태로 유지합니다.', flush=True)
            return hold()
        prepared = False
        while not stopping:
            remaining = deadline - time.monotonic()
            if not prepared and remaining <= min(1, seconds / 10):
                print('❌ 전체 준비 시간 초과. 최대 1시간 내에 준비를 완료하지 못해 중단합니다. /workspace/A1/logs를 확인하세요. 컨테이너를 진단 대기 상태로 유지합니다.', flush=True)
                terminate(process, deadline)
                return hold()
            if not prepared and ready.is_file():
                prepared = True
            rc = process.poll()
            if rc is not None:
                if prepared:
                    terminate(process)
                    return rc
                print(f'❌ 초기 준비 실패 (종료 코드 {rc}). 자동 재실행 없이 진단 대기 상태로 유지합니다.', flush=True)
                terminate(process, deadline)
                return hold()
            time.sleep(min(0.1, max(0, remaining)) if not prepared else 0.1)
        terminate(process)
    return 128 + stopping


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
