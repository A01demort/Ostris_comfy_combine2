#!/bin/bash
# set -e 제거 (중간 실패로 전체 중단 방지)

echo "🌀 RunPod 재시작 시 의존성 복구 시작"

############################################
# 🛠️ 시스템 패키지 (런타임 설치 - 빌드 경량화)
############################################
if [ ! -f "/tmp/.a1_apt_checked" ]; then
    echo "🛠️ 추가 시스템 패키지 설치 중..."
    apt-get update && apt-get install --no-install-recommends -y \
        cmake \
        tmux \
        htop \
        nvtop \
        python3-venv \
        python3-wheel \
        python3-setuptools \
        rsync \
        unzip \
        openssh-client \
        openssh-server \
        openssl \
        locales \
        sudo \
        tzdata \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/* || echo "⚠️ 일부 apt 패키지 설치 실패 (무시)"
    touch "/tmp/.a1_apt_checked"
else
    echo "⏩ apt 패키지 확인됨 (스킵)"
fi

############################################
# 📦 핵심 설치 (OSTRIS 우선 → ComfyUI 마지막)
############################################
if [ ! -f "/tmp/.a1_sys_pkg_checked" ]; then
    echo "📦 핵심 파이썬 패키지 설치 시작"

    # ──────────────────────────────────────────
    # STEP 1: PyTorch (OSTRIS 공식 Docker 기준)
    # torch==2.9.1 + cu128 (CUDA 12.8)
    # ──────────────────────────────────────────
    echo "🔥 [STEP 1] PyTorch 2.9.1 + CUDA 12.8 설치 (OSTRIS 공식 Dockerfile 기준)"
    pip uninstall -y torch torchvision torchaudio 2>/dev/null || true
    pip install --no-cache-dir \
        torch==2.9.1 \
        torchvision==0.24.1 \
        torchaudio==2.9.1 \
        --index-url https://download.pytorch.org/whl/cu128 \
        --break-system-packages \
        || echo '⚠️ Torch 설치 실패'

    # ──────────────────────────────────────────
    # STEP 2: OSTRIS requirements (torch 다음 - 공식 순서)
    # torchao==0.10.0, transformers==4.57.3 등 포함
    # ──────────────────────────────────────────
    echo "🔥 [STEP 2] OSTRIS requirements.txt 설치"
    if [ -f /workspace/ostris/requirements.txt ]; then
        pip install --no-cache-dir -r /workspace/ostris/requirements.txt \
            --break-system-packages \
            || echo '⚠️ OSTRIS requirements 설치 실패'
    fi

    # ──────────────────────────────────────────
    # STEP 3: OSTRIS UI 빌드
    # ──────────────────────────────────────────
    if [ -d /workspace/ostris/ui ]; then
        echo "🔨 [STEP 3] OSTRIS UI 빌드 중..."
        cd /workspace/ostris/ui && \
            npm install && \
            npm run build && \
            npm run update_db && \
            npm cache clean --force || echo '⚠️ OSTRIS UI 빌드 실패'
        cd /workspace
    fi

    # ──────────────────────────────────────────
    # STEP 4: JupyterLab 설치 및 설정
    # ──────────────────────────────────────────
    echo "📦 [STEP 4] JupyterLab 설치"
    pip install --no-cache-dir jupyterlab==4.3.5 jupyter-server==2.15.0 \
        --break-system-packages \
        || echo '⚠️ JupyterLab 설치 실패'

    mkdir -p /root/.jupyter
    cat > /root/.jupyter/jupyter_server_config.py << 'EOF'
c.ServerApp.allow_origin = '*'
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.open_browser = False
c.ServerApp.token = ''
c.ServerApp.password = ''
c.ServerApp.root_dir = '/workspace'
EOF

    # ──────────────────────────────────────────
    # STEP 5: ComfyUI 설치 (마지막 - OSTRIS 우선 정책)
    # torch/transformers는 OSTRIS 버전(2.9.1 / 4.57.3)으로 고정 유지
    # ──────────────────────────────────────────
    echo "🔥 [STEP 5] ComfyUI 설치 (OSTRIS 이후)"
    if [ ! -d "/workspace/ComfyUI" ]; then
        echo "📥 ComfyUI 클론 중..."
        git clone https://github.com/A01demort/ComfyUI.git /workspace/ComfyUI \
            || echo '⚠️ ComfyUI 클론 실패'
    fi

    # ComfyUI 의존성: torch/torchvision/torchaudio/transformers 제외 (OSTRIS 버전 보호)
    if [ -f /workspace/ComfyUI/requirements.txt ]; then
        echo "📦 ComfyUI 의존성 설치 (torch·transformers 제외하여 OSTRIS 버전 보호)"
        grep -v -E '^(torch|torchvision|torchaudio|transformers)([><=[:space:]]|$)' \
            /workspace/ComfyUI/requirements.txt \
            | pip install -r /dev/stdin --break-system-packages \
            || echo '⚠️ ComfyUI requirements 설치 실패'
    fi

    pip install torchsde av pydantic-settings --break-system-packages \
        || echo '⚠️ 초기 의존성 설치 실패'

    # ──────────────────────────────────────────
    # STEP 6: ComfyUI 커스텀 노드용 추가 패키지
    # ──────────────────────────────────────────
    echo "📦 [STEP 6] 추가 파이썬 패키지 설치"
    pip install --no-cache-dir --break-system-packages \
        GitPython onnx onnxruntime opencv-python tqdm requests \
        scikit-image piexif packaging \
        protobuf pandas imageio[ffmpeg] pyzbar pillow numba \
        gguf insightface dill taichi pyloudnorm || echo '⚠️ 일부 pip 설치 실패'

    pip install ultralytics --no-deps --break-system-packages || echo '⚠️ ultralytics 실패'
    pip install ftfy --break-system-packages                  || echo '⚠️ ftfy 실패'

    rm -rf /root/.cache/pip
    touch "/tmp/.a1_sys_pkg_checked"
    echo "✅ 핵심 패키지 설치 완료"
else
    echo "⏩ 시스템 패키지 설치 확인됨 (스킵)"
fi

############################################
# 📁 커스텀 노드 설치 (중복 방지)
############################################
echo "📁 커스텀 노드 설치 시작"
mkdir -p /workspace/ComfyUI/custom_nodes

(
cd /workspace/ComfyUI/custom_nodes || exit 0

[ ! -d "ComfyUI-Manager" ]               && git clone https://github.com/A01demort/ComfyUI-Manager.git               || echo '⏩ Manager 이미 존재'
[ ! -d "ComfyUI-Custom-Scripts" ]        && git clone https://github.com/A01demort/ComfyUI-Custom-Scripts.git        || echo '⏩ Scripts 이미 존재'
[ ! -d "rgthree-comfy" ]                 && git clone https://github.com/A01demort/rgthree-comfy.git                 || echo '⏩ rgthree 이미 존재'
[ ! -d "was-node-suite-comfyui" ]        && git clone https://github.com/A01demort/was-node-suite-comfyui.git        || echo '⏩ WAS 이미 존재'
[ ! -d "ComfyUI-KJNodes" ]               && git clone https://github.com/A01demort/ComfyUI-KJNodes.git               || echo '⏩ KJNodes 이미 존재'
[ ! -d "ComfyUI_essentials" ]            && git clone https://github.com/A01demort/ComfyUI_essentials.git            || echo '⏩ Essentials 이미 존재'
[ ! -d "ComfyUI_Comfyroll_CustomNodes" ] && git clone https://github.com/A01demort/ComfyUI_Comfyroll_CustomNodes.git || echo '⏩ Comfyroll 이미 존재'
[ ! -d "ComfyUI-GGUF" ]                 && git clone https://github.com/A01demort/ComfyUI-GGUF.git                  || echo '⏩ GGUF 이미 존재'
[ ! -d "ComfyUI-Easy-Use" ]             && git clone https://github.com/A01demort/ComfyUI-Easy-Use.git              || echo '⏩ EasyUse 이미 존재'
[ ! -d "ComfyUI-VideoHelperSuite" ]     && git clone https://github.com/A01demort/ComfyUI-VideoHelperSuite.git      || echo '⏩ VideoHelper 이미 존재'
[ ! -d "comfyui_controlnet_aux" ]       && git clone https://github.com/A01demort/comfyui_controlnet_aux.git        || echo '⏩ controlnet_aux 이미 존재'
[ ! -d "ComfyUI_LayerStyle" ]           && git clone https://github.com/A01demort/ComfyUI_LayerStyle.git            || echo '⏩ LayerStyle 이미 존재'
[ ! -d "ComfyUI-Frame-Interpolation" ]  && git clone https://github.com/A01demort/ComfyUI-Frame-Interpolation.git   || echo '⏩ Frame-Interpolation 이미 존재'
[ ! -d "ComfyUI-Impact-Pack" ]          && git clone https://github.com/A01demort/ComfyUI-Impact-Pack.git           || echo '⏩ Impact-Pack 이미 존재'
)

############################################
# 📦 커스텀 노드 의존성 (torch 버전 보호)
############################################
cd /workspace/ComfyUI/custom_nodes || {
    echo "⚠️ custom_nodes 디렉토리 없음"
    exit 0
}

for d in */; do
    req_file="${d}requirements.txt"
    marker_file="${d}.installed"

    if [ -f "$req_file" ]; then
        if [ -f "$marker_file" ]; then
            echo "⏩ $d 이미 설치됨, 건너뜀"
            continue
        fi

        echo "📦 $d 의존성 설치 중..."
        # torch/torchvision/torchaudio 버전 보호 (OSTRIS 2.9.1 유지)
        if grep -v -E '^(torch|torchvision|torchaudio)([><=[:space:]]|$)' "$req_file" \
            | pip install -r /dev/stdin --break-system-packages; then
            touch "$marker_file"
        else
            echo "⚠️ $d 의존성 설치 실패 (무시하고 진행)"
        fi
    fi
done

echo "✅ 모든 커스텀 노드 의존성 복구 완료"
echo "🚀 다음 단계로 넘어갑니다"
echo -e "\n====🎓 AI 교육 & 커뮤니티 안내====\n"
echo -e "1. Youtube : https://www.youtube.com/@A01demort"
echo "2. 교육 문의 : https://a01demort.com"
echo "3. CLASSU 강의 : https://classu.co.kr/me/19375"
echo "4. Stable AI KOREA : https://cafe.naver.com/sdfkorea"
echo "5. 카카오톡 오픈채팅방 : https://open.kakao.com/o/gxvpv2Mf"
echo "6. CIVITAI : https://civitai.com/user/a01demort"
echo -e "\n==================================="
