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

# ====================================
# 🔑 Hugging Face API 키 확인 및 모델 자동 다운로드
# RunPod Environment Variables에서 Huggingface_API_key를 읽어옴
# ====================================
echo ""
echo "🔑 Hugging Face API 키 환경변수 확인 중..."

HF_KEY="${Huggingface_API_key:-}"

if [[ -z "$HF_KEY" || "$HF_KEY" == "Huggingface_Token_key" ]]; then
    # ── 키 없음 → PASS 배너 출력 ────────────────────────────
    echo "⚠️  Huggingface_API_key 환경변수가 없습니다. 모델 다운로드를 건너뜁니다."
    bash /workspace/A1/ZIT_no_key_banner.sh
else
    # ── 키 있음 → ZIT 다운로드 자동 시작 ───────────────────
    echo "✅ Huggingface_API_key 확인됨. Z-Image-Turbo 모델 다운로드를 시작합니다..."
    bash /workspace/A1/ZIT_down_a1.sh
fi

# ── 배너 (ComfyUI 준비 완료 후 출력) ────────────────────────
# 다운로드(또는 PASS) 완료 후 최종 배너 표시
/workspace/A1/Startup+banner.sh

# 모든 백그라운드 프로세스 대기
wait
