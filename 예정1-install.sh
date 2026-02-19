#!/bin/bash
set -e

# Update and install system dependencies
echo "Installing system dependencies..."
apt-get update && apt-get install --no-install-recommends -y \
    git \
    curl \
    build-essential \
    cmake \
    wget \
    python3.12 \
    python3-pip \
    python3-dev \
    python3-setuptools \
    python3-wheel \
    python3-venv \
    ffmpeg \
    tmux \
    htop \
    nvtop \
    python3-opencv \
    openssh-client \
    openssh-server \
    openssl \
    rsync \
    unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install nodejs
echo "Installing Node.js..."
curl -sL https://deb.nodesource.com/setup_23.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh && \
    apt-get update && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
rm -f nodesource_setup.sh

# Set aliases for python
if [ ! -f /usr/bin/python ]; then
    ln -s /usr/bin/python3 /usr/bin/python
fi

# Install pytorch
echo "Installing PyTorch..."
pip install --no-cache-dir torch==2.9.1 torchvision==0.24.1 torchaudio==2.9.1 --index-url https://download.pytorch.org/whl/cu128 --break-system-packages

# Install Python dependencies
echo "Installing Python dependencies..."
cd /app
pip install --no-cache-dir --break-system-packages -r requirements.txt && \
    pip install setuptools==69.5.1 --no-cache-dir --break-system-packages

# Build UI
echo "Building UI..."
cd /app/ui
npm install && \
    npm run build && \
    npm run update_db

# Final cleanup
echo "Cleaning up..."
npm cache clean --force
rm -rf /root/.cache/pip
rm -rf /tmp/*
