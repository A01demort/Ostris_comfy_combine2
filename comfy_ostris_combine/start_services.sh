#!/bin/bash
# ============================================================
# start_services.sh
# init_or_check_nodes.sh 완료 후 실행됨
#
# ▶ 최초 실행 (Fresh Pod):
#   1. 서비스들 백그라운드 시작 (JupyterLab / ComfyUI / OSTRIS)
#   2. ComfyUI 완전히 뜰 때까지 대기
#   3. ZIT_tools_ready_banner.sh (TOOLS READY!! 배너)
#   4. HF API 키 확인 → 다운로드
#   5. Startup+banner.sh (준비완료)
#
# ▶ Restart Pod:
#   1. 서비스들 백그라운드 시작
#   2. ComfyUI 완전히 뜰 때까지 대기
#   3. (TOOLS READY 배너 스킵)
#   4. (HF 다운로드 스킵)
#   5. Startup+banner.sh (준비완료)
# ============================================================

# PATH 완전 갱신 (pip로 설치된 bin 경로 포함)
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
hash -r 2>/dev/null || true

# Python 경로 명시 (새 세션에서 확실히 참조)
PYTHON_BIN=$(which python3 || echo "/usr/bin/python3")
JUPYTER_BIN=$(which jupyter || echo "/usr/local/bin/jupyter")

# ============================================================
# 🔁 Restart 여부 판단
#    마커 파일이 있으면 → Restart
#    없으면           → 최초 실행 (Fresh)
# ============================================================
MARKER_FILE="/workspace/.pod_initialized"

if [ -f "$MARKER_FILE" ]; then
    IS_RESTART=true
    echo "♻️  Restart Pod 감지됨 — 다운로드 및 TOOLS READY 배너를 건너뜁니다."
else
    IS_RESTART=false
    echo "🆕 최초 실행(Fresh Pod) 감지됨."
    # 마커 파일 생성 (다음 재시작 시 Restart로 인식)
    touch "$MARKER_FILE"
fi

echo ""
echo "🐍 Python: $PYTHON_BIN"
echo "📓 Jupyter: $JUPYTER_BIN"
echo "🚀 서비스 시작 중..."

# ── 이전에 생성된 broken config 삭제 ────────────────────────
rm -f /root/.jupyter/jupyter_server_config.py

# ── JupyterLab ──────────────────────────────────────────────
"$JUPYTER_BIN" lab \
    --ip=0.0.0.0 \
    --port=8888 \
    --allow-root \
    --notebook-dir=/workspace \
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
# → Restart 시에는 완전히 스킵
# ====================================
if [ "$IS_RESTART" = false ]; then
    bash /workspace/A1/ZIT_tools_ready_banner.sh

    # ====================================
    # 🔑 Hugging Face API 키 실제 인증 확인
    # RunPod Environment Variables에서 Huggingface_API_key를 읽어옴
    # whoami-v2 API로 토큰 유효성 실제 검증
    # ====================================
    HF_KEY="${Huggingface_API_key:-}"

    if [[ -z "$HF_KEY" || "$HF_KEY" == "Huggingface_Token_key" ]]; then
        # ── 키 자체가 없음 → 건너뜀 ────────────────────────────
        echo "⚠️  Huggingface_API_key 환경변수가 없습니다. 모델 다운로드를 건너뜁니다."

    else
        # ── 키가 입력됐어도 실제로 HF 서버에서 유효한지 검증 ──────
        echo "🔍 Hugging Face API 키 실제 인증 검사 중..."
        HF_AUTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $HF_KEY" \
            "https://huggingface.co/api/whoami-v2")

        if [[ "$HF_AUTH_CODE" == "200" ]]; then
            echo "✅ HF 토큰 인증 성공 (HTTP $HF_AUTH_CODE). Z-Image-Turbo 모델 다운로드를 시작합니다..."
            bash /workspace/A1/ZIT_down_a1.sh
            echo "✅ 모델 다운로드 완료"
        else
            echo "🚫 HF 토큰 인증 실패 (HTTP $HF_AUTH_CODE). 잘못된 키이므로 다운로드를 건너뜁니다."
        fi
    fi
fi

# ── 최종 배너 출력 ───────────────────────────────────────────
# Restart / Fresh 모두 여기서 준비완료 출력
bash /workspace/A1/Startup+banner.sh

# 모든 백그라운드 프로세스 대기
wait
