import shutil
from pathlib import Path


def upgrade_init(text):
    for old in ('5400', '21600'):
        text = text.replace('${A1_INIT_TIMEOUT:-' + old + '}', '${A1_INIT_TIMEOUT:-3600}')
    text = text.replace('${A1_TORCH_TIMEOUT:-5400}', '${A1_TORCH_TIMEOUT:-3600}')
    text = text.replace('${A1_NODE_TIMEOUT:-5400}', '${A1_NODE_TIMEOUT:-3600}')
    settings = {'시스템 패키지 설치': ('600', 'A1_APT_TIMEOUT', '1800'),
                'PyTorch 정리': ('120', 'A1_CHECK_TIMEOUT', '300'),
                'PyTorch 설치': ('1200', 'A1_TORCH_TIMEOUT', '3600')}
    for label in ('OSTRIS Python 설치', 'JupyterLab 설치', 'ComfyUI Python 설치', '초기 의존성 설치',
                  '추가 Python 설치', 'ultralytics 설치', 'ftfy 설치', 'rotary-embedding-torch 설치'):
        settings[label] = ('600' if label in ('ultralytics 설치', 'ftfy 설치', 'rotary-embedding-torch 설치') else '1200',
                           'A1_PIP_TIMEOUT', '3600')
    for label, (old, variable, default) in settings.items():
        for command in ('a1_run', 'a1_python_install', 'a1_pip_requirements'):
            text = text.replace(f'{command} "{label}" {old} ', f'{command} "{label}" "${{{variable}:-{default}}}" ')
    return text.replace('a1_pip_requirements "$d 의존성 설치" 1800 ',
                        'a1_pip_requirements "$d 의존성 설치" "${A1_NODE_TIMEOUT:-3600}" ')


def upgrade_services(text):
    for before in ('TIMEOUT=600\n', 'TIMEOUT="${A1_SERVICES_TIMEOUT:-1800}"\n'):
        text = text.replace(before, 'TIMEOUT=$(a1_limit_seconds "${A1_SERVICES_TIMEOUT:-1800}") || exit 1\n')
    text = text.replace('touch "$MARKER_FILE"\nbash /workspace/A1/Startup+banner.sh', 'bash /workspace/A1/Startup+banner.sh || exit 1\ntouch "$MARKER_FILE"\nif [ -n "${A1_STARTUP_READY_FILE:-}" ]; then\n    printf \'ready\\n\' > "$A1_STARTUP_READY_FILE" || exit 1\nfi')
    before = 'if ! a1_wait_services "$TIMEOUT"; then\n'
    notice = 'printf \'📋 실제 서비스 대기 상한: %s초 (Pod 설정값)\\n\' "$TIMEOUT"\n'
    if notice not in text:
        text = text.replace(before, notice + before, 1)
    return text.replace('--connect-timeout 10 --max-time 30 --retry 2 --retry-delay 5 --retry-max-time 100',
                        '--connect-timeout 30 --max-time 120 --retry 2 --retry-delay 5 --retry-max-time 400')


def upgrade_downloader(text):
    text = text.replace('${A1_DOWNLOAD_TIMEOUT:-10800}', '${A1_DOWNLOAD_TIMEOUT:-3600}')
    text = text.replace('timeout --signal=TERM --kill-after=30s 600s sudo bash',
                        'timeout --signal=TERM --kill-after=30s "${A1_APT_TIMEOUT:-1800}s" sudo bash')
    text = text.replace('--connect-timeout 10 --max-time 30 --retry 2 --retry-delay 5 --retry-max-time 100',
                        '--connect-timeout 30 --max-time 120 --retry 2 --retry-delay 5 --retry-max-time 400')
    return text.replace('timeout --signal=TERM --kill-after=30s 1800s aria2c --max-tries=3 --retry-wait=5 --connect-timeout=10 --timeout=60',
                        'timeout --signal=TERM --kill-after=30s "${A1_DOWNLOAD_TIMEOUT:-3600}s" aria2c --max-tries=3 --retry-wait=5 --connect-timeout=30 --timeout=180')


def migrate(workspace):
    transforms = {'init_or_check_nodes.sh': upgrade_init, 'start_services.sh': upgrade_services,
                  'ZIT_down_a1.sh': upgrade_downloader}
    for directory in ('A1', 'ostris'):
        for name, transform in transforms.items():
            path = workspace / directory / name
            if not path.is_file():
                continue
            original = path.read_bytes()
            text = original.decode('utf-8')
            newline = '\r\n' if '\r\n' in text else '\n'
            updated = transform(text.replace('\r\n', '\n')).replace('\n', newline).encode('utf-8')
            if updated != original:
                backup = workspace / 'A1/.timeout-backup-v1.0.31' / path.relative_to(workspace)
                if not backup.exists():
                    backup.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(path, backup)
                path.write_bytes(updated)
