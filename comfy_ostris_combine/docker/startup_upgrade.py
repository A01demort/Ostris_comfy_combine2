import re
import shutil
from pathlib import Path


def upgrade_init(text):
    if 'A1_INIT_GUARD' in text:
        return text
    guard = '''source "${A1_HELPER_DIR:-/opt/a1-template/docker}/deploy_helpers.sh" || exit 1
if [ "${A1_INIT_GUARD:-}" != 1 ]; then
    timeout --signal=TERM --kill-after=30s "${A1_INIT_TIMEOUT:-5400}s" env A1_INIT_GUARD=1 /bin/bash "$0" "$@"
    A1_INIT_RC=$?
    if [ "$A1_INIT_RC" -ne 0 ]; then
        printf '❌ 초기 설치 중단 (종료 코드 %s). /workspace/A1/logs를 확인하세요.\\n' "$A1_INIT_RC" >&2
    fi
    exit "$A1_INIT_RC"
fi
trap 'a1_ui_cancel' EXIT
'''
    text = text.replace('#!/bin/bash\n', '#!/bin/bash\n' + guard, 1)
    text = text.replace("python3 -c 'from importlib.metadata import version; assert version(\"jupyter-server\") == \"2.21.1\"'", 'a1_core_ready', 1)
    text = text.replace('    apt-get update && apt-get install', '    a1_run "시스템 패키지 설치" 600 3 bash -c \'apt-get update && apt-get install', 1)
    text = text.replace('&& rm -rf /var/lib/apt/lists/* || echo "⚠️ 일부 apt 패키지 설치 실패 (무시)"',
                        '&& rm -rf /var/lib/apt/lists/*\' || { echo "⚠️ 일부 apt 패키지 설치 실패 (무시)"; exit 1; }', 1)
    text = text.replace('    echo "📦 핵심 파이썬 패키지 설치 시작"\n',
                        '    echo "📦 핵심 파이썬 패키지 설치 시작"\n    a1_ui_launch || exit 1\n', 1)
    text = text.replace('    pip uninstall -y torch torchvision torchaudio 2>/dev/null || true\n    pip install --no-cache-dir \\\n',
                        '    if ! a1_torch_ready; then\n    a1_run "PyTorch 정리" 120 1 pip uninstall -y torch torchvision torchaudio 2>/dev/null || true\n    a1_run "PyTorch 설치" 1200 3 pip install \\\n', 1)
    text = text.replace("|| echo '⚠️ Torch 설치 실패'", "|| { echo '⚠️ Torch 설치 실패'; exit 1; }\n    fi", 1)
    start = text.index('    if ! a1_torch_ready; then\n') + len('    if ! a1_torch_ready; then\n')
    end = text.index('    fi\n', start)
    text = text[:start] + ''.join('    ' + line if line.strip() else line for line in text[start:end].splitlines(keepends=True)) + text[end:]
    text = text.replace('        pip install --no-cache-dir -r /workspace/ostris/requirements.txt',
                        '        a1_run "OSTRIS Python 설치" 1200 3 pip install -r /workspace/ostris/requirements.txt', 1)
    text = text.replace("|| echo '⚠️ OSTRIS requirements 설치 실패'", "|| { echo '⚠️ OSTRIS requirements 설치 실패'; exit 1; }", 1)
    after = '''        a1_ui_finish || { echo '⚠️ OSTRIS UI 빌드 실패'; exit 1; }
        A1_UI_PREPARED=1
'''
    start = text.index('        cd /workspace/ostris/ui &&')
    end = text.index('        cd /workspace\n', start)
    text = text[:start] + after + text[end:]
    text = text.replace('    pip install --no-cache-dir \\\n        jupyterlab', '    a1_run "JupyterLab 설치" 1200 3 pip install \\\n        jupyterlab', 1)
    text = text.replace("|| echo '⚠️ JupyterLab 설치 실패'", "|| { echo '⚠️ JupyterLab 설치 실패'; exit 1; }", 1)
    text = text.replace('        git clone https://github.com/A01demort/ComfyUI.git /workspace/ComfyUI',
                        '        a1_clone https://github.com/A01demort/ComfyUI.git /workspace/ComfyUI', 1)
    text = text.replace("|| echo '⚠️ ComfyUI 클론 실패'", "|| { echo '⚠️ ComfyUI 클론 실패'; exit 1; }", 1)
    start = text.index("        grep -v -E '^(torch|torchvision|torchaudio|transformers)")
    end = text.index("|| echo '⚠️ ComfyUI requirements 설치 실패'", start) + len("|| echo '⚠️ ComfyUI requirements 설치 실패'")
    text = text[:start] + '''        a1_pip_requirements "ComfyUI Python 설치" 1200 3 '^(torch|torchvision|torchaudio|transformers)([><=\\s]|$)' /workspace/ComfyUI/requirements.txt \\
            || { echo '⚠️ ComfyUI requirements 설치 실패'; exit 1; }''' + text[end:]
    text = text.replace('    pip install torchsde', '    a1_run "초기 의존성 설치" 1200 3 pip install torchsde', 1)
    text = text.replace('    pip install --no-cache-dir --break-system-packages', '    a1_run "추가 Python 설치" 1200 3 pip install --break-system-packages', 1)
    for name in ('ultralytics', 'ftfy', 'rotary-embedding-torch'):
        text = text.replace('    pip install ' + name, '    a1_run "' + name + ' 설치" 600 3 pip install ' + name, 1)
    for warning in ('⚠️ 초기 의존성 설치 실패', '⚠️ 일부 pip 설치 실패', '⚠️ ultralytics 실패', '⚠️ ftfy 실패', '⚠️ rotary-embedding-torch 실패'):
        text = text.replace("|| echo '" + warning + "'", "|| { echo '" + warning + "'; exit 1; }", 1)
    text = text.replace('    rm -rf /root/.cache/pip\n', '    a1_core_ready || { printf \'❌ 핵심 패키지 검증 실패\\n\' >&2; exit 1; }\n', 1)
    text = text.replace('echo "📁 커스텀 노드 설치 시작"', 'if [ "${A1_UI_PREPARED:-}" != 1 ]; then a1_ui_prepare || exit 1; fi\n\necho "📁 커스텀 노드 설치 시작"', 1)
    text = text.replace('cd /workspace/ComfyUI/custom_nodes || exit 0', 'cd /workspace/ComfyUI/custom_nodes || exit 1', 1)

    def parallel(match):
        condition, url, message = match.groups()
        return f'( {condition} && {{ a1_clone {url} || exit 1; }} || {message} ) &\na1_clone_track "$!" || exit 1'

    text = re.sub(r'^(\[ ! -d "[^"]+" \])\s+&& git clone (\S+)\s+\|\| (echo [^\n]+)$', parallel, text, flags=re.M)
    text = text.replace('\n)\n\n############################################\n# 📦 커스텀 노드 의존성',
                        '\na1_clone_wait || exit 1\n) || exit 1\n\n############################################\n# 📦 커스텀 노드 의존성', 1)
    text = text.replace('    exit 0\n}', '    exit 1\n}', 1)
    text = text.replace('A1_NODE_ENV_ID=$(cat /tmp/.a1_node_env_id)\n',
                        'A1_NODE_ENV_ID=$(cat /tmp/.a1_node_env_id)\na1_node_cache || exit 1\nA1_FAILED_NODES=0\n', 1)
    text = text.replace('    if [ -f "$req_file" ]; then\n',
                        '    if [ -f "$req_file" ]; then\n        A1_NODE_REQ_HASH=$(sha256sum "$req_file")\n        A1_NODE_MARKER="$A1_NODE_ENV_ID:${A1_NODE_REQ_HASH%% *}"\n', 1)
    text = text.replace('"$(cat "$marker_file")" = "$A1_NODE_ENV_ID"', '"$(cat "$marker_file")" = "$A1_NODE_MARKER"', 1)
    text = text.replace('printf \'%s\\n\' "$A1_NODE_ENV_ID" > "$marker_file"', 'printf \'%s\\n\' "$A1_NODE_MARKER" > "$marker_file"', 1)
    start = text.index("        if grep -v -E '^(torch|torchvision|torchaudio)")
    end = text.index('; then\n', start) + len('; then\n')
    text = text[:start] + '''        if a1_pip_requirements "$d 의존성 설치" 1800 2 '^(torch|torchvision|torchaudio)([><=\\s]|$)' "$req_file" "${A1_NODE_BUILD_ARGS[@]}"; then
''' + text[end:]
    text = text.replace('            echo "⚠️ $d 의존성 설치 실패 (무시하고 진행)"',
                        '            echo "⚠️ $d 의존성 설치 실패 (무시하고 진행)"\n            A1_FAILED_NODES=$((A1_FAILED_NODES + 1))', 1)
    text = text.replace('echo "✅ 모든 커스텀 노드 의존성 복구 완료"',
                        'if [ "$A1_FAILED_NODES" -ne 0 ]; then\n    printf \'❌ %s개 노드 설치 실패. 로그 확인 후 재시도하세요.\\n\' "$A1_FAILED_NODES" >&2\n    exit 1\nfi\n\necho "✅ 모든 커스텀 노드 의존성 복구 완료"', 1)
    return text


def upgrade_services(text):
    if 'a1_wait_services' in text:
        return text
    text = text.replace('#!/bin/bash\n', '#!/bin/bash\nsource "${A1_HELPER_DIR:-/opt/a1-template/docker}/deploy_helpers.sh" || exit 1\n', 1)
    text = text.replace('    touch "$MARKER_FILE"\n', '', 1)
    text = text.replace('(cd /workspace/ostris/ui && npm run start) &',
                        '(cd /workspace/ostris/ui && npm run start || { printf \'❌ OSTRIS 실행 실패: 최대 3회 실행 후 중단\\n\' >&2; exit 1; }) &', 1)
    start = text.index('ELAPSED=0\n')
    end = text.index('echo "✅ ComfyUI 응답 확인됨"', start)
    text = text[:start] + '''if ! a1_wait_services "$TIMEOUT"; then
    echo "⚠️ ComfyUI 기동 타임아웃 (계속 진행)"
    printf '❌ 서비스 준비 실패. 준비완료 배너를 중단합니다.\\n' >&2
    exit 1
fi
''' + text[end:]
    text = text.replace('HF_AUTH_CODE=$(curl -s ', 'HF_AUTH_CODE=$(curl --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 5 --retry-max-time 100 -s ', 1)
    text = text.replace('            bash /workspace/A1/ZIT_down_a1.sh\n', '            bash /workspace/A1/ZIT_down_a1.sh || exit 1\n', 1)
    text = text.replace('bash /workspace/A1/Startup+banner.sh', 'touch "$MARKER_FILE"\nbash /workspace/A1/Startup+banner.sh', 1)
    return text


def upgrade_downloader(text):
    if 'A1_DOWNLOAD_ATTEMPT' in text:
        return text
    text = text.replace('#!/bin/bash\n', '''#!/bin/bash
A1_DOWNLOAD_ATTEMPT=${A1_DOWNLOAD_ATTEMPT:-1}
if ! [[ "$A1_DOWNLOAD_ATTEMPT" =~ ^[1-3]$ ]]; then
    printf '❌ 다운로드 재실행은 최대 3회입니다.\\n' >&2
    exit 1
fi
''', 1)
    text = text.replace('    sudo apt update && sudo apt install -y aria2',
                        "    timeout --signal=TERM --kill-after=30s 600s sudo bash -c 'apt update && apt install -y aria2'", 1)
    text = text.replace('test_response=$(curl -s ', 'test_response=$(curl --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 5 --retry-max-time 100 -s ', 1)
    text = text.replace('if [ -f "$path" ]; then', 'if [ -s "$path" ] && [ ! -f "$path.aria2" ]; then')
    text = text.replace('if [ -s "$INPUT_FILE" ]; then', 'A1_DOWNLOAD_RC=0\nif [ -s "$INPUT_FILE" ]; then', 1)
    text = text.replace('  aria2c -x 8', '  timeout --signal=TERM --kill-after=30s 1800s aria2c --max-tries=3 --retry-wait=5 --connect-timeout=10 --timeout=60 -x 8', 1)
    text = text.replace('         | tee -a "$LOG_FILE"\n', '         | tee -a "$LOG_FILE"\n  A1_DOWNLOAD_STATUS=("${PIPESTATUS[@]}")\n  if [ "${A1_DOWNLOAD_STATUS[0]}" -ne 0 ] || [ "${A1_DOWNLOAD_STATUS[1]}" -ne 0 ]; then A1_DOWNLOAD_RC=1; fi\n', 1)
    text = text.replace('  if [[ -f "$path" && ! -s "$path" ]] || [[ -f "$path.aria2" ]]; then',
                        '  if [[ ! -s "$path" ]] || [[ -f "$path.aria2" ]]; then', 1)
    text = text.replace('  read -r confirm_retry', '  confirm_retry=N\n  if [ -t 0 ]; then read -r -t 60 confirm_retry || confirm_retry=N; fi', 1)
    text = text.replace('    echo "🗑️ 삭제 중..."',
                        '    if [ "$A1_DOWNLOAD_ATTEMPT" -ge 3 ]; then\n      printf \'❌ 다운로드 최대 3회 시도 후 중단\\n\' >&2\n      exit 1\n    fi\n    echo "🗑️ 삭제 중..."', 1)
    text = text.replace('    bash "$0"\n    exit 0', '    A1_DOWNLOAD_ATTEMPT=$((A1_DOWNLOAD_ATTEMPT + 1)) bash "$0"\n    exit $?', 1)
    text = text.replace('    echo "⛔ 수동 처리 위해 종료합니다."\n    exit 0', '    echo "⛔ 수동 처리 위해 종료합니다."\n    exit 1', 1)
    text = text.replace('  echo "✅ 모든 파일이 정상적으로 다운되었습니다. (All good)"',
                        '  if [ "$A1_DOWNLOAD_RC" -ne 0 ]; then\n    printf \'❌ 다운로드 명령 실패. 다운로드 로그를 확인하세요.\\n\' >&2\n    exit 1\n  fi\n  echo "✅ 모든 파일이 정상적으로 다운되었습니다. (All good)"', 1)
    return text


def upgrade_package(text):
    return text.replace('concurrently --restart-tries -1 ', 'concurrently --restart-tries 2 --kill-others-on-fail ', 1)


def upgrade_config(text):
    if 'cpus:' not in text:
        text = text.replace('  experimental: {\n', '  experimental: {\n    cpus: 2,\n', 1)
    return text


def migrate(workspace):
    transforms = {'init_or_check_nodes.sh': upgrade_init, 'start_services.sh': upgrade_services,
                  'ZIT_down_a1.sh': upgrade_downloader}
    targets = [(workspace / directory / name, transform) for directory in ('A1', 'ostris') for name, transform in transforms.items()]
    targets += [(workspace / 'ostris/ui/package.json', upgrade_package), (workspace / 'ostris/ui/next.config.ts', upgrade_config)]
    for path, transform in targets:
        if not path.is_file():
            continue
        original = path.read_bytes()
        text = original.decode('utf-8')
        newline = '\r\n' if '\r\n' in text else '\n'
        updated = transform(text.replace('\r\n', '\n')).replace('\n', newline).encode('utf-8')
        if updated == original:
            continue
        backup = workspace / 'A1/.speed-backup-v1.0.31' / path.relative_to(workspace)
        if not backup.exists():
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup)
        path.write_bytes(updated)
