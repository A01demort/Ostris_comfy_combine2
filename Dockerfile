FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# ================================
# 1단계: 최소 시스템 패키지만 설치 (빌드 경량화)
# Ubuntu 24.04 = Python 3.12 기본 내장
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
    util-linux \
    nano \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Python 심볼릭 링크
RUN ln -sf /usr/bin/python3 /usr/bin/python

COPY --from=ghcr.io/astral-sh/uv:0.13.5@sha256:a12ede1e6dc90d3b3e600d0901731e71f0ab0f4d72683ea097b76c19c43cc8df /uv /usr/local/bin/uv
RUN uv --version

# ================================
# bash 프롬프트(PS1) 및 터미널 환경 설정
# JupyterLab Terminal에서 경로가 제대로 표시되도록 .bashrc 구성
# ================================
RUN cat >> /root/.bashrc << 'BASHRC'

# ── 터미널 환경 ──────────────────────────────────────────
export TERM=xterm-256color
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# ── PS1 프롬프트: root@hostname:/현재경로# 형태로 표시 ──
export PS1='\[\e[01;32m\]\u@\h\[\e[00m\]:\[\e[01;34m\]\w\[\e[00m\]\$ '

# ── 기본 시작 경로: 시스템 루트(/)에서 열릴 때만 /workspace로 자동 이동 ──
# (하위 폴더에서 'Open Terminal' 클릭 시 해당 경로를 유지하기 위함)
if [ "$PWD" = "/" ]; then cd /workspace 2>/dev/null || true; fi

# ── 유용한 단축 명령어 ────────────────────────────────────
alias ll='ls -alF --color=auto'
alias ls='ls --color=auto'
alias la='ls -A --color=auto'
alias zit='bash /workspace/A1/ZIT_down_a1.sh'
alias comfy='cd /workspace/ComfyUI'
alias a1='cd /workspace/A1'
alias move='bash /workspace/Move_LoRA_a1.sh'

BASHRC

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
RUN mkdir -p /workspace/A1 /workspace/ostris /workspace/lora_training/output /workspace/lora_training/datasets

COPY comfy_ostris_combine/init_or_check_nodes.sh    /workspace/A1/init_or_check_nodes.sh
COPY comfy_ostris_combine/Startup+banner.sh         /workspace/A1/Startup+banner.sh
COPY comfy_ostris_combine/ZIT_down_a1.sh            /workspace/A1/ZIT_down_a1.sh
COPY comfy_ostris_combine/ZIT_no_key_banner.sh      /workspace/A1/ZIT_no_key_banner.sh
COPY comfy_ostris_combine/ZIT_tools_ready_banner.sh /workspace/A1/ZIT_tools_ready_banner.sh
COPY comfy_ostris_combine/start_services.sh         /workspace/A1/start_services.sh
COPY comfy_ostris_combine/Move_LoRA_a1.sh           /workspace/Move_LoRA_a1.sh

COPY comfy_ostris_combine/ /workspace/ostris/
COPY comfy_ostris_combine/docker/start.sh /workspace/ostris/start.sh

COPY comfy_ostris_combine/ /opt/a1-template/
COPY comfy_ostris_combine/docker/workspace_init.sh /usr/local/bin/a1-workspace-init.sh

RUN chmod +x \
    /opt/a1-template/docker/git-compat/git \
    /workspace/A1/init_or_check_nodes.sh \
    /workspace/A1/Startup+banner.sh \
    /workspace/A1/ZIT_down_a1.sh \
    /workspace/A1/ZIT_no_key_banner.sh \
    /workspace/A1/ZIT_tools_ready_banner.sh \
    /workspace/A1/start_services.sh \
    /workspace/Move_LoRA_a1.sh \
    /workspace/ostris/docker/install.sh \
    /workspace/ostris/start.sh

RUN --mount=type=tmpfs,target=/tmp/a1-uv-check,size=134217728 \
    timeout --signal=TERM --kill-after=10s 120s \
    python3 /opt/a1-template/docker/verify_python_installer.py

RUN --mount=type=tmpfs,target=/workspace/ostris/ui,size=2147483648 \
    timeout --signal=TERM --kill-after=30s 1800s \
    python3 /opt/a1-template/docker/build_ui_cache.py || \
    { rm -f /opt/a1-ui-cache/ui.tar.gz /opt/a1-ui-cache/ui.tar.json; \
      echo '⏩ UI 이미지 캐시 생략: 런타임 설치로 진행'; }

# 볼륨 / 포트
VOLUME ["/workspace"]
EXPOSE 8188
EXPOSE 8888
EXPOSE 8675

# ================================
# CMD: init 완료 후 exec 새 bash로 서비스 시작
# → PATH/pip 설치 경로가 완전히 반영된 환경에서 실행됨
# ================================
CMD ["/bin/bash", "-c", "\
echo '🌀 A1(AI는 에이원) : https://www.youtube.com/@A01demort' && \
/bin/bash /usr/local/bin/a1-workspace-init.sh && \
{ /workspace/A1/init_or_check_nodes.sh || { \
printf '❌ 설치 재시도 한도에 도달했습니다. /workspace/A1/logs를 확인한 후 수동 복구하세요. 컨테이너를 진단 대기 상태로 유지합니다.\n'; \
exec sleep infinity; }; } && \
echo '✅ 의존성 확인 완료 - 새 환경으로 서비스 시작' && \
exec /bin/bash /workspace/A1/start_services.sh"]
