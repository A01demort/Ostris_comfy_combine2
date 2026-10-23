#!/bin/bash
source "${A1_HELPER_DIR:-/opt/a1-template/docker}/deploy_helpers.sh" || exit 1
if [ "${A1_INIT_GUARD:-}" != 1 ]; then
    timeout --signal=TERM --kill-after=30s "${A1_INIT_TIMEOUT:-5400}s" env A1_INIT_GUARD=1 /bin/bash "$0" "$@"
    A1_INIT_RC=$?
    if [ "$A1_INIT_RC" -ne 0 ]; then
        printf '❌ 초기 설치 중단 (종료 코드 %s). /workspace/A1/logs를 확인하세요.\n' "$A1_INIT_RC" >&2
    fi
    exit "$A1_INIT_RC"
fi
trap 'a1_ui_cancel' EXIT
export PIP_CONSTRAINT=/workspace/A1/runtime-constraints-v1.0.31.txt
if [ -f /tmp/.a1_sys_pkg_checked ] && ! a1_core_ready >/dev/null 2>&1; then
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
    a1_run "시스템 패키지 설치" 600 3 bash -c 'apt-get update && apt-get install --no-install-recommends -y \
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
        && rm -rf /var/lib/apt/lists/*' || { echo "⚠️ 일부 apt 패키지 설치 실패 (무시)"; exit 1; }
    touch "/tmp/.a1_apt_checked"
else
    echo "⏩ apt 패키지 확인됨 (스킵)"
fi

############################################
# 📦 핵심 설치 (OSTRIS 우선 → ComfyUI 마지막)
############################################
if [ ! -f "/tmp/.a1_sys_pkg_checked" ]; then
    echo "📦 핵심 파이썬 패키지 설치 시작"
    a1_ui_launch || exit 1

    # ──────────────────────────────────────────
    # STEP 1: PyTorch (OSTRIS 공식 Docker 기준)
    # torch==2.9.1 + cu128 (CUDA 12.8)
    # ──────────────────────────────────────────
    echo "🔥 [STEP 1] PyTorch 2.9.1 + CUDA 12.8 설치 (OSTRIS 공식 Dockerfile 기준)"
    if ! a1_torch_ready; then
        a1_run "PyTorch 정리" 120 1 pip uninstall -y torch torchvision torchaudio 2>/dev/null || true
        a1_run "PyTorch 설치" 1200 3 pip install \
            torch==2.9.1 \
            torchvision==0.24.1 \
            torchaudio==2.9.1 \
            --index-url https://download.pytorch.org/whl/cu128 \
            --break-system-packages \
            || { echo '⚠️ Torch 설치 실패'; exit 1; }
    fi

    # ──────────────────────────────────────────
    # STEP 2: OSTRIS requirements (torch 다음 - 공식 순서)
    # torchao==0.10.0, transformers==4.57.3 등 포함
    # ──────────────────────────────────────────
    echo "🔥 [STEP 2] OSTRIS requirements.txt 설치"
    if [ -f /workspace/ostris/requirements.txt ]; then
        a1_run "OSTRIS Python 설치" 1200 3 pip install -r /workspace/ostris/requirements.txt \
            --break-system-packages \
            || { echo '⚠️ OSTRIS requirements 설치 실패'; exit 1; }
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
        a1_ui_finish || { echo '⚠️ OSTRIS UI 빌드 실패'; exit 1; }
        A1_UI_PREPARED=1
        cd /workspace
    fi

    # ──────────────────────────────────────────
    # STEP 4: JupyterLab 설치 및 설정
    # ──────────────────────────────────────────
    echo "📦 [STEP 4] JupyterLab 설치"
    a1_run "JupyterLab 설치" 1200 3 pip install \
        jupyterlab==3.6.6 \
        jupyter-server==2.21.1 \
        --break-system-packages \
        || { echo '⚠️ JupyterLab 설치 실패'; exit 1; }

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
        a1_clone https://github.com/A01demort/ComfyUI.git /workspace/ComfyUI \
            || { echo '⚠️ ComfyUI 클론 실패'; exit 1; }
    fi

    # ComfyUI 의존성: torch/torchvision/torchaudio/transformers 제외 (OSTRIS 버전 보호)
    if [ -f /workspace/ComfyUI/requirements.txt ]; then
        echo "📦 ComfyUI 의존성 설치 (torch·transformers 제외하여 OSTRIS 버전 보호)"
        a1_pip_requirements "ComfyUI Python 설치" 1200 3 '^(torch|torchvision|torchaudio|transformers)([><=\s]|$)' /workspace/ComfyUI/requirements.txt \
            || { echo '⚠️ ComfyUI requirements 설치 실패'; exit 1; }
    fi

    a1_run "초기 의존성 설치" 1200 3 pip install torchsde av pydantic-settings --break-system-packages \
        || { echo '⚠️ 초기 의존성 설치 실패'; exit 1; }

    # ──────────────────────────────────────────
    # STEP 6: ComfyUI 커스텀 노드용 추가 패키지
    # ──────────────────────────────────────────
    echo "📦 [STEP 6] 추가 파이썬 패키지 설치"
    a1_run "추가 Python 설치" 1200 3 pip install --break-system-packages \
        GitPython onnx onnxruntime opencv-python tqdm requests \
        scikit-image piexif packaging \
        protobuf pandas imageio[ffmpeg] pyzbar pillow numba \
        gguf insightface dill taichi pyloudnorm || { echo '⚠️ 일부 pip 설치 실패'; exit 1; }

    a1_run "ultralytics 설치" 600 3 pip install ultralytics --no-deps --break-system-packages || { echo '⚠️ ultralytics 실패'; exit 1; }
    a1_run "ftfy 설치" 600 3 pip install ftfy --break-system-packages                  || { echo '⚠️ ftfy 실패'; exit 1; }
    a1_run "rotary-embedding-torch 설치" 600 3 pip install rotary-embedding-torch --break-system-packages || { echo '⚠️ rotary-embedding-torch 실패'; exit 1; }

    a1_core_ready || { printf '❌ 핵심 패키지 검증 실패\n' >&2; exit 1; }
    touch "/tmp/.a1_sys_pkg_checked"
    echo "✅ 핵심 패키지 설치 완료"
else
    echo "⏩ 시스템 패키지 설치 확인됨 (스킵)"
fi

############################################
# 📁 커스텀 노드 설치 (중복 방지)
############################################
if [ "${A1_UI_PREPARED:-}" != 1 ]; then a1_ui_prepare || exit 1; fi

echo "📁 커스텀 노드 설치 시작"
mkdir -p /workspace/ComfyUI/custom_nodes

(
cd /workspace/ComfyUI/custom_nodes || exit 1

( [ ! -d "ComfyUI-Manager" ] && { a1_clone https://github.com/A01demort/ComfyUI-Manager.git || exit 1; } || echo '⏩ Manager 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "ComfyUI-Custom-Scripts" ] && { a1_clone https://github.com/A01demort/ComfyUI-Custom-Scripts.git || exit 1; } || echo '⏩ Scripts 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "rgthree-comfy" ] && { a1_clone https://github.com/A01demort/rgthree-comfy.git || exit 1; } || echo '⏩ rgthree 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "was-node-suite-comfyui" ] && { a1_clone https://github.com/A01demort/was-node-suite-comfyui.git || exit 1; } || echo '⏩ WAS 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "ComfyUI-KJNodes" ] && { a1_clone https://github.com/A01demort/ComfyUI-KJNodes.git || exit 1; } || echo '⏩ KJNodes 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "ComfyUI_essentials" ] && { a1_clone https://github.com/A01demort/ComfyUI_essentials.git || exit 1; } || echo '⏩ Essentials 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "ComfyUI_Comfyroll_CustomNodes" ] && { a1_clone https://github.com/A01demort/ComfyUI_Comfyroll_CustomNodes.git || exit 1; } || echo '⏩ Comfyroll 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "ComfyUI-GGUF" ] && { a1_clone https://github.com/A01demort/ComfyUI-GGUF.git || exit 1; } || echo '⏩ GGUF 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "ComfyUI-Easy-Use" ] && { a1_clone https://github.com/A01demort/ComfyUI-Easy-Use.git || exit 1; } || echo '⏩ EasyUse 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "ComfyUI-VideoHelperSuite" ] && { a1_clone https://github.com/A01demort/ComfyUI-VideoHelperSuite.git || exit 1; } || echo '⏩ VideoHelper 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "comfyui_controlnet_aux" ] && { a1_clone https://github.com/A01demort/comfyui_controlnet_aux.git || exit 1; } || echo '⏩ controlnet_aux 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "ComfyUI_LayerStyle" ] && { a1_clone https://github.com/A01demort/ComfyUI_LayerStyle.git || exit 1; } || echo '⏩ LayerStyle 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "ComfyUI-Frame-Interpolation" ] && { a1_clone https://github.com/A01demort/ComfyUI-Frame-Interpolation.git || exit 1; } || echo '⏩ Frame-Interpolation 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "ComfyUI-Impact-Pack" ] && { a1_clone https://github.com/A01demort/ComfyUI-Impact-Pack.git || exit 1; } || echo '⏩ Impact-Pack 이미 존재' ) &
a1_clone_track "$!" || exit 1
( [ ! -d "ComfyUI-SeedVR2_VideoUpscaler" ] && { a1_clone https://github.com/A01demort/ComfyUI-SeedVR2_VideoUpscaler.git || exit 1; } || echo '⏩ SeedVR2_VideoUpscaler 이미 존재' ) &
a1_clone_track "$!" || exit 1
a1_clone_wait || exit 1
) || exit 1

############################################
# 📦 커스텀 노드 의존성 (torch 버전 보호)
############################################
cd /workspace/ComfyUI/custom_nodes || {
    echo "⚠️ custom_nodes 디렉토리 없음"
    exit 1
}

if [ ! -f /tmp/.a1_node_env_id ]; then
    python3 -c 'import uuid; print(uuid.uuid4())' > /tmp/.a1_node_env_id || exit 1
fi
A1_NODE_ENV_ID=$(cat /tmp/.a1_node_env_id)
a1_node_cache || exit 1
A1_FAILED_NODES=0

for d in */; do
    req_file="${d}requirements.txt"
    marker_file="${d}.installed"

    if [ -f "$req_file" ]; then
        A1_NODE_REQ_HASH=$(sha256sum "$req_file")
        A1_NODE_MARKER="$A1_NODE_ENV_ID:${A1_NODE_REQ_HASH%% *}"
        if [ -f "$marker_file" ] && [ "$(cat "$marker_file")" = "$A1_NODE_MARKER" ]; then
            echo "⏩ $d 이미 설치됨, 건너뜀"
            continue
        fi

        A1_NODE_BUILD_ARGS=()
        if [ "$d" = "ComfyUI-Impact-Pack/" ]; then
            A1_NODE_BUILD_ARGS=(--no-build-isolation)
        fi

        echo "📦 $d 의존성 설치 중..."
        # torch/torchvision/torchaudio 버전 보호 (OSTRIS 2.9.1 유지)
        if a1_pip_requirements "$d 의존성 설치" 1800 2 '^(torch|torchvision|torchaudio)([><=\s]|$)' "$req_file" "${A1_NODE_BUILD_ARGS[@]}"; then
            printf '%s\n' "$A1_NODE_MARKER" > "$marker_file"
        else
            echo "⚠️ $d 의존성 설치 실패 (무시하고 진행)"
            A1_FAILED_NODES=$((A1_FAILED_NODES + 1))
        fi
    fi
done

if [ "$A1_FAILED_NODES" -ne 0 ]; then
    printf '❌ %s개 노드 설치 실패. 로그 확인 후 재시도하세요.\n' "$A1_FAILED_NODES" >&2
    exit 1
fi

echo "✅ 모든 커스텀 노드 의존성 복구 완료"
echo "🚀 다음 단계로 넘어갑니다"
