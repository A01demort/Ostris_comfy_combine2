#!/bin/bash

A1_HELPER_DIR="${A1_HELPER_DIR:-/opt/a1-template/docker}"
A1_WORKSPACE="${A1_WORKSPACE:-/workspace}"
A1_LOG_DIR="${A1_LOG_DIR:-$A1_WORKSPACE/A1/logs}"
A1_STATE_DIR="${A1_STATE_DIR:-$A1_WORKSPACE/A1/.startup-state}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-$A1_WORKSPACE/.cache/a1/pip}"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$A1_WORKSPACE/.cache/a1/uv}"
export npm_config_cache="${npm_config_cache:-$A1_WORKSPACE/.cache/a1/npm}"
export PIP_DEFAULT_TIMEOUT="${PIP_DEFAULT_TIMEOUT:-180}"
export PIP_RETRIES="${PIP_RETRIES:-2}"
export npm_config_fetch_retries="${npm_config_fetch_retries:-2}"
export npm_config_fetch_timeout="${npm_config_fetch_timeout:-180000}"
export GIT_TERMINAL_PROMPT=0
export A1_WORKSPACE A1_HELPER_DIR A1_LOG_DIR A1_STATE_DIR
mkdir -p "$A1_LOG_DIR" "$A1_STATE_DIR" "$PIP_CACHE_DIR" "$UV_CACHE_DIR" "$npm_config_cache" || { return 1 2>/dev/null || exit 1; }

a1_run() {
    local label="$1" seconds="$2" attempts="$3" key count=0 rc=1 state log_file
    shift 3
    if [ -n "${A1_RUN_KEY:-}" ]; then
        key=$(printf '%s\0' "$A1_RUN_KEY" "$seconds" | sha256sum)
    else
        key=$(printf '%s\0' "$label" "$seconds" "$@" | sha256sum)
    fi
    key=${key%% *}
    state="$A1_STATE_DIR/$key.attempts"
    log_file="$A1_LOG_DIR/$key.log"
    if [ -f "$state" ]; then read -r count < "$state"; fi
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    while [ "$count" -lt "$attempts" ]; do
        count=$((count + 1))
        printf '%s\n' "$count" > "$state" || return 73
        printf '📋 %s (%s/%s, 최대 %s초)\n' "$label" "$count" "$attempts" "$seconds"
        timeout --signal=TERM --kill-after=30s "${seconds}s" "$@" 2>&1 | tee -a "$log_file"
        local statuses=("${PIPESTATUS[@]}")
        rc=${statuses[0]}
        if [ "$rc" -eq 0 ] && [ "${statuses[1]}" -eq 0 ]; then
            rm -f -- "$state"
            return 0
        fi
        [ "$rc" -ne 0 ] || rc=74
        printf '⚠️ %s 실패 (종료 코드 %s)\n' "$label" "$rc" >&2
        [ "$count" -ge "$attempts" ] || sleep "${A1_RETRY_DELAY:-5}"
    done
    printf '❌ %s: 최대 %s회 시도 후 중단. 로그: %s\n' "$label" "$attempts" "$log_file" >&2
    printf '📋 수정 후 수동 재시도: bash "%s/deploy_helpers.sh" reset\n' "$A1_HELPER_DIR" >&2
    return "$rc"
}

a1_clone() {
    local url="$1" destination="${2:-${1##*/}}"
    destination=${destination%.git}
    a1_run "Git 다운로드: ${destination##*/}" "${A1_GIT_TIMEOUT:-1800}" 3 \
        bash -c '
            target="$2"
            stage="${target}.a1-clone-$$"
            trap '\''rm -rf -- "$stage"'\'' EXIT
            git clone "$1" "$stage" && git -C "$stage" rev-parse --verify HEAD >/dev/null && [ ! -e "$target" ] && mv -T -- "$stage" "$target"
        ' a1-clone "$url" "$destination"
}

A1_CLONE_PIDS=()
a1_clone_track() {
    A1_CLONE_PIDS+=("$1")
    [ "${#A1_CLONE_PIDS[@]}" -lt "${A1_CLONE_JOBS:-4}" ] || a1_clone_wait
}

a1_clone_wait() {
    local pid rc=0
    for pid in "${A1_CLONE_PIDS[@]}"; do wait "$pid" || rc=1; done
    A1_CLONE_PIDS=()
    return "$rc"
}

a1_python_install() {
    local label="$1" seconds="$2" attempts="$3"
    shift 3
    a1_run "$label" "$seconds" "$attempts" python3 "$A1_HELPER_DIR/python_install.py" "$seconds" "$@"
}

a1_pip_requirements() {
    local label="$1" seconds="$2" attempts="$3" exclude="$4" requirements="$5" filtered rc digest
    shift 5
    filtered=$(mktemp /tmp/a1-requirements.XXXXXX) || return 1
    digest=$(sha256sum "$requirements") || { rm -f -- "$filtered"; return 1; }
    if ! A1_RUN_KEY="$label:prepare:${digest%% *}:$exclude" a1_run "$label 목록 확인" "${A1_PREPARE_TIMEOUT:-600}" 3 python3 "$A1_HELPER_DIR/requirements_cache.py" \
        "$requirements" "$filtered" "$exclude"; then
        rm -f -- "$filtered"
        return 1
    fi
    digest=$(sha256sum "$filtered") || { rm -f -- "$filtered"; return 1; }
    A1_REAL_GIT="$(command -v git)" PATH="$A1_HELPER_DIR/git-compat:$PATH" \
        A1_RUN_KEY="$label:git-full-v1:${digest%% *}" \
        a1_python_install "$label" "$seconds" "$attempts" "$@" -r "$filtered" --break-system-packages
    rc=$?
    rm -f -- "$filtered"
    return "$rc"
}

a1_node_cache() {
    local key
    key=$(python3 "$A1_HELPER_DIR/requirements_cache.py" --environment) || return 1
    export PIP_CACHE_DIR="$A1_WORKSPACE/.cache/a1/node-pip/$key"
    export UV_CACHE_DIR="$A1_WORKSPACE/.cache/a1/node-uv/$key"
    export TORCH_EXTENSIONS_DIR="$A1_WORKSPACE/.cache/a1/torch-extensions/$key"
    mkdir -p "$PIP_CACHE_DIR" "$UV_CACHE_DIR" "$TORCH_EXTENSIONS_DIR"
}

a1_ui_prepare() {
    local ui="$A1_WORKSPACE/ostris/ui" cache="$A1_HELPER_DIR/deploy_optimizations.py" rebuilt=0
    [ -d "$ui" ] || return 0
    cd "$ui" || return 1
    if ! python3 "$cache" check "$ui"; then
        if python3 "$cache" restore "$ui"; then rebuilt=1; fi
        if ! python3 "$cache" check "$ui"; then
            NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--require=\"$A1_HELPER_DIR/npm_compat.cjs\"" \
                a1_run 'OSTRIS npm 설치' "${A1_NPM_TIMEOUT:-3600}" 3 npm install --prefer-offline || return 1
            a1_run 'OSTRIS UI 빌드' "${A1_UI_TIMEOUT:-3600}" 2 npm run build || return 1
            rebuilt=1
        fi
    fi
    if [ "$rebuilt" -eq 1 ] || ! python3 "$cache" db-ready "$ui"; then
        a1_run 'OSTRIS DB 준비' "${A1_DB_TIMEOUT:-900}" 3 npm run update_db || return 1
    fi
    python3 "$cache" record "$ui"
}

a1_ui_launch() {
    A1_UI_JOB_LOG=$(mktemp /tmp/a1-ui.XXXXXX.log) || return 1
    setsid bash -c 'source "$A1_HELPER_DIR/deploy_helpers.sh" && a1_ui_prepare' > "$A1_UI_JOB_LOG" 2>&1 &
    A1_UI_JOB_PID=$!
}

a1_ui_cancel() {
    [ -n "${A1_UI_JOB_PID:-}" ] || return 0
    kill -TERM -- "-$A1_UI_JOB_PID" 2>/dev/null || true
    local attempt
    for attempt in {1..20}; do
        kill -0 "$A1_UI_JOB_PID" 2>/dev/null || break
        sleep 0.1
    done
    kill -KILL -- "-$A1_UI_JOB_PID" 2>/dev/null || true
    wait "$A1_UI_JOB_PID" 2>/dev/null || true
}

a1_ui_finish() {
    local rc=0
    [ -n "${A1_UI_JOB_PID:-}" ] || return 0
    wait "$A1_UI_JOB_PID" || rc=$?
    cat "$A1_UI_JOB_LOG"
    rm -f -- "$A1_UI_JOB_LOG"
    A1_UI_JOB_PID=
    return "$rc"
}

a1_core_ready() {
    timeout --signal=TERM --kill-after=10s "${A1_CHECK_TIMEOUT:-300}s" python3 - "$A1_WORKSPACE" <<'PY'
import sys
from importlib.metadata import version
from pathlib import Path
expected = {'torch': '2.9.1+cu128', 'torchvision': '0.24.1+cu128', 'torchaudio': '2.9.1+cu128',
            'transformers': '4.57.3', 'jupyter-server': '2.21.1', 'jupyterlab': '3.6.6'}
try:
    assert all(version(name) == value for name, value in expected.items())
    assert (Path(sys.argv[1]) / 'ComfyUI/main.py').is_file()
except Exception:
    sys.exit(1)
PY
}

a1_torch_ready() {
    timeout --signal=TERM --kill-after=10s "${A1_CHECK_TIMEOUT:-300}s" python3 - <<'PY'
import sys
try:
    import torch, torchvision, torchaudio
    assert (torch.__version__, torchvision.__version__, torchaudio.__version__) == ('2.9.1+cu128', '0.24.1+cu128', '2.9.1+cu128')
except Exception:
    sys.exit(1)
PY
}

a1_wait_services() {
    python3 "$A1_HELPER_DIR/deploy_optimizations.py" wait-services "${1:-1800}"
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    if [ "${1:-}" = reset ]; then
        for state in "$A1_STATE_DIR"/*.attempts "$A1_STATE_DIR"/*.pip-backend; do [ ! -f "$state" ] || rm -f -- "$state"; done
        printf '✅ 초기 설치 재시도 횟수를 초기화했습니다.\n'
    else
        exit 2
    fi
fi
