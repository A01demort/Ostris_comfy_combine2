#!/bin/bash
# set -e 제거 (중간 실패로 전체 중단 방지)

echo "🌀 RunPod 재시작 시 의존성 복구 시작"

############################################
# 📦 코어 파이썬 패키지 (ComfyUI 필수)
############################################
if [ ! -f "/tmp/.a1_sys_pkg_checked" ]; then
    echo '📦 코어 파이썬 패키지 설치'

    # Torch 2.6.0 + CUDA 12.6 고정 설치
    pip uninstall -y torch torchvision torchaudio 2>/dev/null || true
    pip install torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 --index-url https://download.pytorch.org/whl/cu126 || echo '⚠️ Torch 설치 실패'

    # ComfyUI 필수 의존성 설치 (sqlalchemy, alembic 등)
    # torch/torchvision/torchaudio/transformers는 버전 충돌 방지를 위해 제외
    if [ -f /workspace/ComfyUI/requirements.txt ]; then
        grep -v -E '^(torch|torchvision|torchaudio|transformers)([><=[:space:]]|$)' /workspace/ComfyUI/requirements.txt \
            | pip install -r /dev/stdin || echo '⚠️ ComfyUI requirements 설치 실패'
        pip install transformers==4.57.3 || echo '⚠️ transformers 설치 실패'
    fi

    pip install torchsde av pydantic-settings || echo '⚠️ 초기 의존성 설치 실패'

    echo '📦 파이썬 패키지 설치'
    pip install --no-cache-dir \
        GitPython onnx onnxruntime opencv-python tqdm requests \
        scikit-image piexif packaging \
        protobuf pandas imageio[ffmpeg] pyzbar pillow numba \
        gguf insightface dill taichi pyloudnorm || echo '⚠️ 일부 pip 설치 실패'

    pip install timm || echo '⚠️ timm 실패'
    pip install ultralytics --no-deps || echo '⚠️ ultralytics 실패'
    pip install ftfy || echo '⚠️ ftfy 실패'
    pip install bitsandbytes || echo '⚠️ bitsandbytes 실패'

    touch "/tmp/.a1_sys_pkg_checked"
else
    echo "⏩ 시스템 패키지 설치 확인됨 (스킵)"
fi

############################################
# 📁 커스텀 노드 설치
############################################
echo '📁 커스텀 노드 설치 시작'
mkdir -p /workspace/ComfyUI/custom_nodes

(
cd /workspace/ComfyUI/custom_nodes || exit 0

git clone https://github.com/A01demort/ComfyUI-Manager.git || echo '⚠️ Manager 실패 (1)'
git clone https://github.com/A01demort/ComfyUI-Custom-Scripts.git || echo '⚠️ Scripts 실패(2)'
git clone https://github.com/A01demort/rgthree-comfy.git || echo '⚠️ rgthree 실패(3)'
git clone https://github.com/A01demort/was-node-suite-comfyui.git || echo '⚠️ WAS 실패(4)'
git clone https://github.com/A01demort/ComfyUI-KJNodes.git || echo '⚠️ KJNodes 실패(5)'
git clone https://github.com/A01demort/ComfyUI_essentials.git || echo '⚠️ Essentials 실패(6)'
git clone https://github.com/A01demort/ComfyUI_Comfyroll_CustomNodes.git || echo '⚠️ Comfyroll 실패(7)'
git clone https://github.com/A01demort/ComfyUI-GGUF.git || echo '⚠️ GGUF 실패(8)'
git clone https://github.com/A01demort/ComfyUI-Easy-Use.git || echo '⚠️ EasyUse 실패(9)'
git clone https://github.com/A01demort/ComfyUI-VideoHelperSuite.git || echo '⚠️ VideoHelper 실패(10)'
git clone https://github.com/A01demort/comfyui_controlnet_aux.git || echo '⚠️ controlnet_aux 실패'
git clone https://github.com/A01demort/ComfyUI_LayerStyle.git || echo '⚠️ ComfyUI_LayerStyle 실패(12)'
git clone https://github.com/A01demort/ComfyUI-Frame-Interpolation.git || echo '⚠️ Frame-Interpolation 실패'
git clone https://github.com/A01demort/ComfyUI-Impact-Pack.git || echo '⚠️ Impact-Pack 실패(13)'
)

############################################
# � 커스텀 노드 의존성 설치
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
        # torch/torchvision/torchaudio는 버전 보호를 위해 제외
        if grep -v -E '^(torch|torchvision|torchaudio)([><=[:space:]]|$)' "$req_file" \
            | pip install -r /dev/stdin; then
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
