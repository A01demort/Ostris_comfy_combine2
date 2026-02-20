#!/bin/bash
# ============================================================
# start_services.sh
# init_or_check_nodes.sh 완료 후 실행됨
# 실행 순서:
#   1. 서비스들 백그라운드 시작 (JupyterLab / ComfyUI / OSTRIS)
#   2. ComfyUI 완전히 뜰 때까지 대기
#   3. ZIT_tools_ready_banner.sh (TOOLS READY!! 배너)
#   4. HF API 키 확인
#      - 키 있음 → ZIT_down_a1.sh 다운로드 완료 대기 → Startup+banner
#      - 키 없음 → 바로 Startup+banner 출력
# ============================================================

# PATH 완전 갱신 (pip로 설치된 bin 경로 포함)
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
hash -r 2>/dev/null || true

# Python 경로 명시 (새 세션에서 확실히 참조)
PYTHON_BIN=$(which python3 || echo "/usr/bin/python3")
JUPYTER_BIN=$(which jupyter || echo "/usr/local/bin/jupyter")

echo "🐍 Python: $PYTHON_BIN"
echo "📓 Jupyter: $JUPYTER_BIN"
echo "🚀 서비스 시작 중..."

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
# ⏳ ComfyUI 완전히 뜰 때까지 대기
# (포트 8188 응답 확인 - custom node 로딩 완료 포함)
# ====================================
echo ""
echo "⏳ ComfyUI 로딩 대기 중 (custom node 포함, 최대 10분)..."
TIMEOUT=600
ELAPSED=0
while ! curl -s http://localhost:8188 > /dev/null 2>&1; do
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "⚠️ ComfyUI 기동 타임아웃 (계속 진행)"
        break
    fi
done
echo "✅ ComfyUI 응답 확인됨"

# ====================================
# 🎉 TOOLS READY 배너 출력
# (ComfyUI + custom node 완전히 뜬 뒤 출력)
# ====================================
bash /workspace/A1/ZIT_tools_ready_banner.sh

# ====================================
# 🔑 Hugging Face API 키 확인 및 모델 자동 다운로드
# RunPod Environment Variables에서 Huggingface_API_key를 읽어옴
# ====================================
HF_KEY="${Huggingface_API_key:-}"

if [[ -z "$HF_KEY" || "$HF_KEY" == "Huggingface_Token_key" ]]; then
    # ── 키 없음 → 바로 Startup 배너 ────────────────────────
    echo "⚠️  Huggingface_API_key 환경변수가 없습니다. 모델 다운로드를 건너뜁니다."

else
    # ── 키 있음 → ZIT 다운로드 완료까지 대기 후 Startup 배너
    echo "✅ Huggingface_API_key 확인됨. Z-Image-Turbo 모델 다운로드를 시작합니다..."
    bash /workspace/A1/ZIT_down_a1.sh
    echo "✅ 모델 다운로드 완료"
fi

# ── 최종 배너 출력 ───────────────────────────────────────────
bash /workspace/A1/Startup+banner.sh

# 모든 백그라운드 프로세스 대기
wait
