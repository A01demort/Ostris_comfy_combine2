#!/bin/bash
set -e

# ================================================
# OSTRIS ai-toolkit 설치 스크립트
# 환경: CUDA 12.6 + Ubuntu 22.04 + Python 3.12
# (Dockerfile에서 이미 설치된 항목은 스킵)
# ================================================

# OSTRIS 추가 시스템 의존성 설치
# (git, curl, wget, ffmpeg, build-essential 등은 Dockerfile에서 이미 설치됨)
echo "Installing additional system dependencies for OSTRIS..."
apt-get update && apt-get install --no-install-recommends -y \
    cmake \
    tmux \
    htop \
    nvtop \
    openssh-client \
    openssh-server \
    openssl \
    rsync \
    unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Python / pip / Node.js 는 Dockerfile에서 이미 설치됨 (스킵)
# - Python 3.12 (apt)
# - Node.js 23.x
# - pip

# PyTorch 설치 (CUDA 12.6 호환 버전)
echo "Installing PyTorch (CUDA 12.6 compatible)..."
pip install --no-cache-dir \
    torch==2.6.0 \
    torchvision==0.21.0 \
    torchaudio==2.6.0 \
    --index-url https://download.pytorch.org/whl/cu126

# OSTRIS Python 의존성 설치
echo "Installing OSTRIS Python dependencies..."
cd /workspace/ostris
pip install --no-cache-dir -r requirements.txt

# UI 빌드
echo "Building OSTRIS UI..."
cd /workspace/ostris/ui
npm install && \
    npm run build && \
    npm run update_db

# 최종 정리
echo "Cleaning up..."
npm cache clean --force
rm -rf /root/.cache/pip
rm -rf /tmp/*
