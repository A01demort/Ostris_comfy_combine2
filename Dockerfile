FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# ================================
# 1단계: 최소 시스템 패키지만 설치 (빌드 경량화)
# Ubuntu 24.04 = Python 3.12 기본 내장 → python3.12 별도 설치 불필요
# 무거운 패키지(nvtop, cmake, openssh 등)는 런타임(init)에서 설치
# ================================
RUN apt-get update && apt-get install --no-install-recommends -y \
    git \
    curl \
    wget \
    build-essential \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    python3 \
    python3-pip \
    python3-dev \
    nano \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Python 심볼릭 링크
RUN ln -sf /usr/bin/python3 /usr/bin/python

# ================================
# 2단계: Node.js 23.x 설치 (OSTRIS UI 빌드에 필요)
# ================================
RUN curl -fsSL https://deb.nodesource.com/setup_23.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ================================
# 3단계: 스크립트 복사 (A1 폴더 & OSTRIS)
# 실제 무거운 설치는 모두 런타임(init_or_check_nodes.sh)에서 처리
# ================================
RUN mkdir -p /workspace/A1 /workspace/ostris

COPY comfy_ostris_combine/init_or_check_nodes.sh /workspace/A1/init_or_check_nodes.sh
COPY comfy_ostris_combine/Startup+banner.sh      /workspace/A1/Startup+banner.sh
COPY comfy_ostris_combine/Wan2.1_Vace_a1.sh      /workspace/A1/Wan2.1_Vace_a1.sh
COPY comfy_ostris_combine/SCAIL_down_a1.sh       /workspace/A1/SCAIL_down_a1.sh

COPY comfy_ostris_combine/ /workspace/ostris/
COPY comfy_ostris_combine/docker/start.sh /workspace/ostris/start.sh

RUN chmod +x \
    /workspace/A1/init_or_check_nodes.sh \
    /workspace/A1/Startup+banner.sh \
    /workspace/A1/Wan2.1_Vace_a1.sh \
    /workspace/A1/SCAIL_down_a1.sh \
    /workspace/ostris/docker/install.sh \
    /workspace/ostris/start.sh

# 볼륨 / 포트
VOLUME ["/workspace"]
EXPOSE 8188
EXPOSE 8888
EXPOSE 8675

# JSON 형식 CMD (OS signal 안전)
CMD ["/bin/bash", "-c", "\
echo '🌀 A1(AI는 에이원) : https://www.youtube.com/@A01demort' && \
/workspace/A1/init_or_check_nodes.sh && \
echo '✅ 의존성 확인 완료 - 서비스 시작' && \
jupyter lab --ip=0.0.0.0 --port=8888 --allow-root \
  --ServerApp.root_dir=/workspace \
  --ServerApp.token='' --ServerApp.password='' & \
python -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port=8188 \
  --front-end-version Comfy-Org/ComfyUI_frontend@1.37.2 & \
cd /workspace/ostris/ui && npm run start & \
/workspace/A1/Startup+banner.sh & \
wait"]
