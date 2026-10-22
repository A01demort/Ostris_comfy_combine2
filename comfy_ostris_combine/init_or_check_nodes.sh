#!/bin/bash
export PIP_CONSTRAINT=/workspace/A1/runtime-constraints-v1.0.31.txt
if [ -f /tmp/.a1_sys_pkg_checked ] && ! python3 -c 'from importlib.metadata import version; assert version("jupyter-server") == "2.21.1"' >/dev/null 2>&1; then
    rm -f /tmp/.a1_sys_pkg_checked
fi

# set -e 제거 (중간 실패로 전체 중단 방지)

echo "🌀 RunPod 재시작 시 의존성 복구 시작"

# ── LoRA 훈련용 기본 폴더 생성 ──
mkdir -p /workspace/lora_training/output /workspace/lora_training/datasets

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
    # STEP 2-b: controlnet_aux mediapipe 0.10.x 호환 패치
    # mediapipe 0.9.x는 Python 3.12 미지원 → 0.10.x 사용
    # controlnet_aux 0.0.10은 mp.solutions를 직접 참조하므로 패치 필요
    # ──────────────────────────────────────────
    echo "🔧 [STEP 2-b] controlnet_aux mediapipe 호환 패치 적용..."
    python3 - << 'PYEOF'
import os, sys

# controlnet_aux mediapipe_face_common.py 위치 탐색
search_dirs = []
try:
    import site
    search_dirs = site.getsitepackages()
except Exception:
    pass
search_dirs.append('/usr/local/lib/python3.12/dist-packages')
search_dirs.append('/usr/lib/python3/dist-packages')

patched = False
for d in search_dirs:
    fpath = os.path.join(d, 'controlnet_aux/mediapipe_face/mediapipe_face_common.py')
    if os.path.exists(fpath):
        with open(fpath, 'r') as f:
            content = f.read()
        if '# mediapipe-0.10x-compat-patch' in content:
            print(f"✅ 이미 패치됨: {fpath}")
            patched = True
            break
        # mediapipe 0.10.x에서 mp.solutions는 lazy load → force import로 활성화
        compat_shim = (
            '# mediapipe-0.10x-compat-patch\n'
            'import mediapipe as _mp_compat\n'
            'if not hasattr(_mp_compat, "solutions"):\n'
            '    try:\n'
            '        from mediapipe.python import solutions as _mp_sol\n'
            '        _mp_compat.solutions = _mp_sol\n'
            '    except Exception:\n'
            '        pass\n'
            'del _mp_compat\n'
        )
        new_content = compat_shim + content
        with open(fpath, 'w') as f:
            f.write(new_content)
        print(f"✅ mediapipe 호환 패치 완료: {fpath}")
        patched = True
        break

if not patched:
    print("⚠️ controlnet_aux mediapipe_face_common.py 파일을 찾지 못했습니다 (무시)")
PYEOF


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
    pip install --no-cache-dir \
        jupyterlab==3.6.6 \
        jupyter-server==2.21.1 \
        --break-system-packages \
        || echo '⚠️ JupyterLab 설치 실패'

    mkdir -p /root/.jupyter
    cat > /root/.jupyter/jupyter_notebook_config.py << 'EOF'
c.NotebookApp.allow_origin = '*'
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.open_browser = False
c.NotebookApp.token = ''
c.NotebookApp.password = ''
# cwd 미지정 → JupyterLab 파일 탐색기 현재 폴더 기준으로 터미널 열림
c.NotebookApp.terminado_settings = {'shell_command': ['/bin/bash', '-i']}
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
    pip install rotary-embedding-torch --break-system-packages || echo '⚠️ rotary-embedding-torch 실패'

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
[ ! -d "ComfyUI-SeedVR2_VideoUpscaler" ] && git clone https://github.com/A01demort/ComfyUI-SeedVR2_VideoUpscaler.git  || echo '⏩ SeedVR2_VideoUpscaler 이미 존재'
)

############################################
# 📦 커스텀 노드 의존성 (torch 버전 보호)
############################################
cd /workspace/ComfyUI/custom_nodes || {
    echo "⚠️ custom_nodes 디렉토리 없음"
    exit 0
}

if [ ! -f /tmp/.a1_node_env_id ]; then
    python3 -c 'import uuid; print(uuid.uuid4())' > /tmp/.a1_node_env_id || exit 1
fi
A1_NODE_ENV_ID=$(cat /tmp/.a1_node_env_id)

for d in */; do
    req_file="${d}requirements.txt"
    marker_file="${d}.installed"

    if [ -f "$req_file" ]; then
        if [ -f "$marker_file" ] && [ "$(cat "$marker_file")" = "$A1_NODE_ENV_ID" ]; then
            echo "⏩ $d 이미 설치됨, 건너뜀"
            continue
        fi

        A1_NODE_BUILD_ARGS=()
        if [ "$d" = "ComfyUI-Impact-Pack/" ]; then
            A1_NODE_BUILD_ARGS=(--no-build-isolation)
        fi

        echo "📦 $d 의존성 설치 중..."
        # torch/torchvision/torchaudio 버전 보호 (OSTRIS 2.9.1 유지)
        if grep -v -E '^(torch|torchvision|torchaudio)([><=[:space:]]|$)' "$req_file" \
            | pip install "${A1_NODE_BUILD_ARGS[@]}" -r /dev/stdin --break-system-packages; then
            printf '%s\n' "$A1_NODE_ENV_ID" > "$marker_file"
        else
            echo "⚠️ $d 의존성 설치 실패 (무시하고 진행)"
        fi
    fi
done

echo "✅ 모든 커스텀 노드 의존성 복구 완료"
echo "🚀 다음 단계로 넘어갑니다"
