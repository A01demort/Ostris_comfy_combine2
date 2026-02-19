#!/bin/bash
# ============================================================
# start_services.sh
# init_or_check_nodes.sh 완료 후 새 환경에서 서비스들을 시작
# 새 bash 세션에서 실행되므로 PATH, pip 설치 경로가 완전히 반영됨
# ============================================================

# PATH 완전 갱신 (pip로 설치된 bin 경로 포함)
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
hash -r 2>/dev/null || true

# Python 경로 명시 (새 세션에서 확실히 참조)
PYTHON_BIN=$(which python3 || echo "/usr/bin/python3")
JUPYTER_BIN=$(which jupyter || echo "/usr/local/bin/jupyter")

echo "🐍 Python: $PYTHON_BIN"
echo "📓 Jupyter: $JUPYTER_BIN"
echo "🚀 모든 서비스 시작..."

# ── JupyterLab ──────────────────────────────────────────────
"$JUPYTER_BIN" lab \
    --ip=0.0.0.0 \
    --port=8888 \
    --allow-root \
    --ServerApp.root_dir=/workspace \
    --IdentityProvider.token='' \
    --ServerApp.password='' \
    --no-browser &

# ── ComfyUI ─────────────────────────────────────────────────
"$PYTHON_BIN" -u /workspace/ComfyUI/main.py \
    --listen 0.0.0.0 \
    --port=8188 \
    --front-end-version Comfy-Org/ComfyUI_frontend@1.37.2 &

# ── OSTRIS UI ────────────────────────────────────────────────
(cd /workspace/ostris/ui && npm run start) &

# ── 배너 (ComfyUI 준비 완료 후 출력) ────────────────────────
/workspace/A1/Startup+banner.sh &

# 모든 백그라운드 프로세스 대기
wait
