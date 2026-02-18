#!/bin/bash
set -e

# ================================================
# OSTRIS ai-toolkit 설치 스크립트
# 환경: CUDA 12.1 + Ubuntu 20.04 + Python 3.10.6
# (Dockerfile에서 이미 설치된 항목은 스킵)
# ================================================

# Update and install OSTRIS 추가 시스템 의존성
# (git, curl, wget, ffmpeg, build-essential 등은 Dockerfile에서 이미 설치됨)
echo "Installing additional system dependencies for OSTRIS..."
apt-get update && apt-get install --no-install-recommends -y \
    cmake \
    tmux \
    htop \
    openssh-client \
    openssh-server \
    openssl \
    rsync \
    unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Python / pip / Node.js 는 Dockerfile에서 이미 설치됨 (스킵)
# - Python 3.10.6 (소스 빌드)
# - Node.js 18
# - pip (python3.10 altinstall 포함)

# Install pytorch (CUDA 12.1 호환 버전)
echo "Installing PyTorch (CUDA 12.1 compatible)..."
pip install --no-cache-dir torch==2.4.1 torchvision==0.19.1 torchaudio==2.4.1 --index-url https://download.pytorch.org/whl/cu121

# Install Python dependencies
echo "Installing OSTRIS Python dependencies..."
cd /workspace/ostris
pip install --no-cache-dir -r requirements.txt && \
    pip install setuptools==69.5.1 --no-cache-dir

# Build UI
echo "Building OSTRIS UI..."
cd /workspace/ostris/ui
npm install && \
    npm run build && \
    npm run update_db

# Final cleanup
echo "Cleaning up..."
npm cache clean --force
rm -rf /root/.cache/pip
rm -rf /tmp/*
