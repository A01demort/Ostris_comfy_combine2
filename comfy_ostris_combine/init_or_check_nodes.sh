#!/bin/bash
# set -e ❌ 제거 (중간 실패로 전체 중단 방지)

echo "🌀 RunPod 재시작 시 의존성 복구 시작"

############################################
# 📦 코어 파이썬 패키지 (ComfyUI 필수)
############################################
# 💨 빠른 실행을 위한 시스템 패키지 설치 확인 (휘발성 마커 사용)
if [ ! -f "/tmp/.a1_sys_pkg_checked" ]; then
    echo '📦 코어 파이썬 패키지 설치'

    # 🔥 [CRITICAL] Torch 버전 완전 재설치 (버전 불일치 방지)
    # 기존 버전 제거 (찌꺼기 방지)
    pip uninstall -y torch torchvision torchaudio

    # 최신 노드(WanVideo) 호환을 위해 Torch 2.4.1 + CUDA 12.1 조합으로 업그레이드
    # (이전 2.1.2는 너무 구버전이라 다른 패키지가 Torch만 몰래 업그레이드해서 깨짐)
    pip install torch==2.4.1 torchvision==0.19.1 torchaudio==2.4.1 --index-url https://download.pytorch.org/whl/cu121 || echo '⚠️ Torch 재설치 실패'

    # ComfyUI 필수 의존성 설치 (sqlalchemy, alembic 등)
    if [ -f /workspace/ComfyUI/requirements.txt ]; then
        pip install -r /workspace/ComfyUI/requirements.txt || echo '⚠️ ComfyUI requirements 설치 실패'
    fi

    # 필수 의존성 및 누락 패키지(pydantic-settings) 추가
    pip install torchsde av pydantic-settings || echo '⚠️ 초기 의존성 설치 실패'

    echo '📦 파이썬 패키지 설치'

    pip install --no-cache-dir \
        GitPython onnx onnxruntime opencv-python tqdm requests \
        scikit-image piexif packaging \
        protobuf pandas imageio[ffmpeg] pyzbar pillow numba \
        gguf insightface dill taichi pyloudnorm || echo '⚠️ 일부 pip 설치 실패'

    pip install timm || echo '⚠️ timm 실패'
    pip install ultralytics || echo '⚠️ ultralytics 실패'
    pip install ftfy || echo '⚠️ ftfy 실패'
    pip install bitsandbytes xformers || echo '⚠️ bitsandbytes 또는 xformers 설치 실패'
    pip install bitsandbytes xformers || echo '⚠️ bitsandbytes 또는 xformers 설치 실패'
    pip install sageattention || echo '⚠️ sageattention 설치 실패'
    
    # [중요] 모든 필수 패키지 설치 시도가 끝났을 때만 마커 생성
    # (실패 시 마커 안 생김 -> 수동 재실행 시 다시 시도 가능)
    touch "/tmp/.a1_sys_pkg_checked"
else
    echo "⏩ 시스템 패키지 설치 확인됨 (스킵)"
fi

############################################
# 📁 커스텀 노드 설치 (안 깨지게 서브셸로)
############################################
echo '📁 커스텀 노드 및 의존성 설치 시작'

mkdir -p /workspace/ComfyUI/custom_nodes

(
cd /workspace/ComfyUI/custom_nodes || exit 0

# Custom Nodes Git 주소 A01demort로 통일 (checkout 금지)
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
git clone https://github.com/A01demort/ComfyUI_LayerStyle.git || echo '⚠️ ComfyUI_LayerStyle 설치 실패(12)'
git clone https://github.com/A01demort/ComfyUI-Frame-Interpolation.git || echo '⚠️ Frame-Interpolation 실패'
git clone https://github.com/A01demort/ComfyUI-Impact-Pack.git || echo '⚠️ Impact-Pack 실패(13)'


)



############################################
# ⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇
# 👉 기존 init 구조 (그대로 유지)
############################################

cd /workspace/ComfyUI/custom_nodes || {
  echo "⚠️ custom_nodes 디렉토리 없음. ComfyUI 설치 전일 수 있음"
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
    if pip install -r "$req_file"; then
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

# /workspace/A1/Startup+banner.sh -> Dockerfile에서 병렬 실행으로 변경됨
