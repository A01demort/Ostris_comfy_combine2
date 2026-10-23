#!/bin/bash
source "${A1_HELPER_DIR:-/opt/a1-template/docker}/deploy_helpers.sh" || exit 1
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
    --port=8188 &

# ── OSTRIS UI ────────────────────────────────────────────────
(cd /workspace/ostris/ui && npm run start || { printf '❌ OSTRIS 실행 실패: 최대 3회 실행 후 중단\n' >&2; exit 1; }) &

# ====================================
# ⏳ ComfyUI 완전히 뜰 때까지 대기
# (포트 8188 응답 확인 - custom node 로딩 완료 포함)
# ====================================
echo ""
echo "⏳ ComfyUI 로딩 대기 중 (custom node 포함, 최대 10분)..."
TIMEOUT=$(a1_limit_seconds "${A1_SERVICES_TIMEOUT:-1800}") || exit 1
printf '📋 실제 서비스 대기 상한: %s초 (Pod 설정값)\n' "$TIMEOUT"
if ! a1_wait_services "$TIMEOUT"; then
    echo "⚠️ ComfyUI 기동 타임아웃 (계속 진행)"
    printf '❌ 서비스 준비 실패. 준비완료 배너를 중단합니다.\n' >&2
    exit 1
fi
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
        HF_AUTH_CODE=$(curl --connect-timeout 30 --max-time 120 --retry 2 --retry-delay 5 --retry-max-time 400 -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $HF_KEY" \
            "https://huggingface.co/api/whoami-v2")

        if [[ "$HF_AUTH_CODE" == "200" ]]; then
            echo "✅ HF 토큰 인증 성공 (HTTP $HF_AUTH_CODE). Z-Image-Turbo 모델 다운로드를 시작합니다..."
            bash /workspace/A1/ZIT_down_a1.sh || exit 1
            echo "✅ 모델 다운로드 완료"
        else
            echo "🚫 HF 토큰 인증 실패 (HTTP $HF_AUTH_CODE). 잘못된 키이므로 다운로드를 건너뜁니다."
        fi
    fi
fi

# ── 최종 배너 출력 ───────────────────────────────────────────
# Restart / Fresh 모두 여기서 준비완료 출력
bash /workspace/A1/Startup+banner.sh || exit 1
touch "$MARKER_FILE"
if [ -n "${A1_STARTUP_READY_FILE:-}" ]; then
    printf 'ready\n' > "$A1_STARTUP_READY_FILE" || exit 1
fi

# 모든 백그라운드 프로세스 대기
wait
