FROM nvidia/cuda:12.6.3-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# ================================
# 1단계: 시스템 패키지 설치
# ================================
RUN apt-get update && apt-get install --no-install-recommends -y \
    git \
    curl \
    wget \
    build-essential \
    cmake \
    ffmpeg \
    libgl1 \
    python3.12 \
    python3-pip \
    python3-dev \
    python3-setuptools \
    python3-wheel \
    python3-venv \
    python3-opencv \
    tmux \
    htop \
    nvtop \
    openssh-client \
    openssh-server \
    openssl \
    rsync \
    unzip \
    locales \
    sudo \
    tzdata \
    nano \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Python 심볼릭 링크 설정
RUN if [ ! -f /usr/bin/python ]; then ln -s /usr/bin/python3 /usr/bin/python; fi

# ================================
# 2단계: Node.js 23.x 설치
# ================================
RUN curl -sL https://deb.nodesource.com/setup_23.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* nodesource_setup.sh

# ================================
# 3단계: PyTorch 설치 (CUDA 12.6)
# ================================
RUN pip install --no-cache-dir \
    torch==2.6.0 \
    torchvision==0.21.0 \
    torchaudio==2.6.0 \
    --index-url https://download.pytorch.org/whl/cu126

# ================================
# 4단계: ComfyUI 설치
# ================================
WORKDIR /workspace
RUN git clone https://github.com/A01demort/ComfyUI.git /workspace/ComfyUI

WORKDIR /workspace/ComfyUI

# ComfyUI 의존성 설치
# torch/torchvision/torchaudio/transformers 버전 보호를 위해 제외 후 설치
RUN grep -v -E '^(torch|torchvision|torchaudio|transformers)([><=\s]|$)' requirements.txt \
    | pip install --no-cache-dir -r /dev/stdin && \
    pip install --no-cache-dir transformers==4.57.3

# JupyterLab 설치
RUN pip install --no-cache-dir jupyterlab==4.3.5 jupyter-server==2.15.0

# Jupyter 설정
RUN mkdir -p /root/.jupyter && \
    printf "c.ServerApp.allow_origin = '*'\nc.ServerApp.ip = '0.0.0.0'\nc.ServerApp.open_browser = False\nc.ServerApp.token = ''\nc.ServerApp.password = ''\nc.ServerApp.root_dir = '/workspace'\n" \
    > /root/.jupyter/jupyter_server_config.py

# ================================
# 5단계: 스크립트 복사 (A1 폴더)
# ================================
RUN mkdir -p /workspace/A1
COPY comfy_ostris_combine/init_or_check_nodes.sh /workspace/A1/init_or_check_nodes.sh
COPY comfy_ostris_combine/Startup+banner.sh      /workspace/A1/Startup+banner.sh
COPY comfy_ostris_combine/Wan2.1_Vace_a1.sh      /workspace/A1/Wan2.1_Vace_a1.sh
COPY comfy_ostris_combine/SCAIL_down_a1.sh       /workspace/A1/SCAIL_down_a1.sh
RUN chmod +x \
    /workspace/A1/init_or_check_nodes.sh \
    /workspace/A1/Startup+banner.sh \
    /workspace/A1/Wan2.1_Vace_a1.sh \
    /workspace/A1/SCAIL_down_a1.sh

# ================================
# 6단계: OSTRIS (ai-toolkit) 설치
# ================================
COPY comfy_ostris_combine/ /workspace/ostris/
RUN cd /workspace/ostris && \
    chmod +x docker/install.sh && \
    ./docker/install.sh

# OSTRIS 시작 스크립트
COPY comfy_ostris_combine/docker/start.sh /workspace/ostris/start.sh
RUN chmod +x /workspace/ostris/start.sh

# ================================
# 7단계: 최종 정리
# ================================
RUN rm -rf /root/.cache/pip /tmp/*

# 볼륨 / 포트 설정
VOLUME ["/workspace"]
EXPOSE 8188
EXPOSE 8888
EXPOSE 8675

CMD bash -c "\
echo '🌀 A1(AI는 에이원) : https://www.youtube.com/@A01demort' && \
/workspace/A1/init_or_check_nodes.sh && \
echo '✅ 의존성 확인 완료 - 서비스 시작' && \
( \
  jupyter lab --ip=0.0.0.0 --port=8888 --allow-root \
    --ServerApp.root_dir=/workspace \
    --ServerApp.token='' --ServerApp.password='' & \
  python -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port=8188 \
    --front-end-version Comfy-Org/ComfyUI_frontend@1.37.2 & \
  cd /workspace/ostris/ui && npm run start & \
  /workspace/A1/Startup+banner.sh & \
  wait \
)"
