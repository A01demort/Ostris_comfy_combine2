import hashlib
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

active_process = None


def terminate(process):
    if process.poll() is not None:
        return
    if os.name == 'posix':
        os.killpg(process.pid, signal.SIGTERM)
    else:
        process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        if os.name == 'posix':
            os.killpg(process.pid, signal.SIGKILL)
        else:
            process.kill()
        process.wait(timeout=2)


def interrupted(signum, frame):
    if active_process is not None:
        terminate(active_process)
    raise SystemExit(128 + signum)


def run(command, seconds, environment):
    global active_process
    if seconds <= 0:
        return 124
    try:
        active_process = subprocess.Popen(command, env=environment, start_new_session=os.name == 'posix')
        try:
            return active_process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            terminate(active_process)
            return 124
    except OSError as error:
        print('⚠️ 설치 도구 실행 실패: ' + type(error).__name__, file=sys.stderr, flush=True)
        return 127
    finally:
        active_process = None


def needs_pip(arguments, environment):
    if environment.get('A1_PYTHON_INSTALLER', 'uv') != 'uv':
        return True
    if '--no-build-isolation' in arguments:
        return True
    text = '\n'.join(arguments).lower()
    for index, argument in enumerate(arguments):
        if re.split(r'[<>=!~\[\s]', argument.lower(), 1)[0] in {'torch', 'torchvision', 'torchaudio'}:
            return True
        if argument in {'-r', '--requirement'} and index + 1 < len(arguments):
            text += '\n' + Path(arguments[index + 1]).read_text(encoding='utf-8').lower()
    if any(name in text for name in ('sam2', 'sam-2', 'flash-attn', 'flash_attn', 'sageattention', 'xformers', 'deepspeed')):
        return True
    if any(environment.get(key) for key in ('PIP_INDEX_URL', 'PIP_EXTRA_INDEX_URL', 'PIP_FIND_LINKS',
                                            'PIP_NO_INDEX', 'PIP_TRUSTED_HOST', 'PIP_REQUIRE_VIRTUALENV',
                                            'PIP_NO_BINARY', 'PIP_ONLY_BINARY', 'PIP_PRE', 'PIP_NO_COMPILE')):
        return True
    config = environment.get('PIP_CONFIG_FILE')
    if config and config != os.devnull:
        return True
    return any(path.is_file() for path in (Path('/etc/pip.conf'), Path.home() / '.config/pip/pip.conf',
                                           Path.home() / '.pip/pip.conf', Path(sys.prefix) / 'pip.conf'))


def uv_environment(environment):
    result = environment.copy()
    result['UV_PYTHON_DOWNLOADS'] = 'never'
    result['UV_HTTP_TIMEOUT'] = environment.get('PIP_DEFAULT_TIMEOUT', '180')
    result['UV_HTTP_RETRIES'] = environment.get('PIP_RETRIES', '2')
    result['UV_HTTP_CONNECT_TIMEOUT'] = '30'
    result['UV_CACHE_DIR'] = environment.get('UV_CACHE_DIR', str(Path(environment.get('PIP_CACHE_DIR', '/workspace/.cache/a1/pip')).parent / 'uv'))
    result['UV_CONCURRENT_BUILDS'] = '1'
    result['UV_CONCURRENT_INSTALLS'] = '4'
    result['UV_CONCURRENT_DOWNLOADS'] = '8'
    constraint = environment.get('PIP_CONSTRAINT')
    if constraint:
        result['UV_CONSTRAINT'] = constraint
        result['UV_BUILD_CONSTRAINT'] = constraint
    return result


def fallback_state(arguments, environment):
    directory = environment.get('A1_STATE_DIR')
    if not directory:
        return None
    digest = hashlib.sha256(('uv-0.13.5\0' + sys.executable + '\0' + environment.get('UV_CACHE_DIR', '')).encode())
    key = environment.get('A1_RUN_KEY')
    digest.update((key or '\0'.join(arguments)).encode())
    for index, argument in enumerate(arguments):
        if argument in {'-r', '--requirement'} and index + 1 < len(arguments):
            digest.update(Path(arguments[index + 1]).read_bytes())
    return Path(directory) / (digest.hexdigest() + '.pip-backend')


def install(seconds, arguments, environment=None):
    environment = dict(os.environ if environment is None else environment)
    deadline = time.monotonic() + seconds - min(5, seconds / 10)
    pip_command = [sys.executable, '-m', 'pip', 'install', *arguments]
    uv = shutil.which('uv', path=environment.get('PATH'))
    state = fallback_state(arguments, environment)
    if uv and not (state and state.is_file()) and not needs_pip(arguments, environment):
        command = [uv, '--no-config', 'pip', 'install', '--python', sys.executable,
                   '--link-mode', 'copy', '--compile-bytecode']
        if sys.prefix == sys.base_prefix:
            command.append('--system')
        command.extend(arguments)
        print('⚡ 일반 Python 의존성: uv 설치 시작', flush=True)
        rc = run(command, max(0, deadline - time.monotonic()) * 0.65, uv_environment(environment))
        if rc == 0:
            return 0
        if state is not None:
            try:
                state.parent.mkdir(parents=True, exist_ok=True)
                state.write_text('pip\n', encoding='utf-8')
            except OSError:
                pass
        print(f'⚠️ uv 설치 실패 또는 시간 초과 ({rc}). 기존 pip 설치로 복귀합니다.', file=sys.stderr, flush=True)
    return run(pip_command, max(0, deadline - time.monotonic()), environment)


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    if len(sys.argv) < 3:
        sys.exit(2)
    try:
        seconds = float(sys.argv[1])
        if not 0 < seconds <= 21600:
            raise ValueError('invalid timeout')
        sys.exit(install(seconds, sys.argv[2:]))
    except (OSError, ValueError):
        print('❌ Python 설치 설정을 확인하세요.', file=sys.stderr)
        sys.exit(1)
