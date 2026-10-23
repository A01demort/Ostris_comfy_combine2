import shutil

FALLBACK = '''if ! declare -F a1_python_install >/dev/null; then
    a1_python_install() {
        local label="$1" seconds="$2" attempts="$3"
        shift 3
        a1_run "$label" "$seconds" "$attempts" pip install "$@"
    }
fi
'''


def upgrade(text):
    if 'a1_python_install()' not in text:
        source = 'source "${A1_HELPER_DIR:-/opt/a1-template/docker}/deploy_helpers.sh" || exit 1\n'
        text = text.replace(source, source + FALLBACK, 1)
    for label in ('OSTRIS Python 설치', 'JupyterLab 설치', '초기 의존성 설치', '추가 Python 설치'):
        text = text.replace(f'a1_run "{label}" 1200 3 pip install', f'a1_python_install "{label}" 1200 3')
    return text


def migrate(workspace):
    for relative in ('A1/init_or_check_nodes.sh', 'ostris/init_or_check_nodes.sh'):
        path = workspace / relative
        original = path.read_bytes()
        text = original.decode('utf-8')
        newline = '\r\n' if '\r\n' in text else '\n'
        updated = upgrade(text.replace('\r\n', '\n')).replace('\n', newline).encode('utf-8')
        if updated == original:
            continue
        backup = workspace / 'A1/.uv-backup-v1.0.32' / relative
        if not backup.exists():
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup)
        path.write_bytes(updated)
