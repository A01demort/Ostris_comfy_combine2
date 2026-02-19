#!/bin/bash
# ================================================
# OSTRIS ai-toolkit install.sh (수동 실행용)
# 실제 Docker 런타임은 init_or_check_nodes.sh 에서 처리됨
#
# OSTRIS 공식 Docker 설치 순서:
#   pip install torch==2.9.1 torchvision==0.24.1 torchaudio==2.9.1
#          --index-url https://download.pytorch.org/whl/cu128
#   pip install -r requirements.txt
# ================================================
echo "ℹ️  OSTRIS install.sh: 수동 실행 모드"

# Step 1: PyTorch FIRST (OSTRIS 공식 Docker 기준)
pip install --no-cache-dir \
    torch==2.9.1 \
    torchvision==0.24.1 \
    torchaudio==2.9.1 \
    --index-url https://download.pytorch.org/whl/cu128 \
    --break-system-packages

# Step 2: OSTRIS requirements (torch 이후 설치 - 공식 순서)
cd /workspace/ostris
pip install --no-cache-dir -r requirements.txt --break-system-packages

# Step 3: OSTRIS UI 빌드
cd /workspace/ostris/ui
npm install && \
    npm run build && \
    npm run update_db

npm cache clean --force
rm -rf /root/.cache/pip /tmp/*
