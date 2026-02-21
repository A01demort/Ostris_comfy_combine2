#!/bin/bash

# ============================================================
# Move_LoRA_a1.sh
# OSTRIS 결과물(.safetensors)을 ComfyUI LoRA 폴더로 이동합니다.
# ============================================================

SOURCE_DIR="/workspace/lora_training/output"
DEST_DIR="/workspace/ComfyUI/models/loras"

# 대상 폴더가 없으면 생성
mkdir -p "$DEST_DIR"

echo "📂 LoRA 파일 이동 시작..."
echo "🔍 소스 경로: $SOURCE_DIR"
echo "🎯 대상 경로: $DEST_DIR"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ 소스 디렉토리가 존재하지 않습니다: $SOURCE_DIR"
    exit 1
fi

found_files=$(find "$SOURCE_DIR" -maxdepth 2 -name "*.safetensors" | wc -l)

if [ "$found_files" -eq 0 ]; then
    echo "ℹ️ 이동할 .safetensors 파일이 없습니다."
    exit 0
fi

# 파일 이동 실행
find "$SOURCE_DIR" -maxdepth 2 -name "*.safetensors" -exec mv -v {} "$DEST_DIR/" \;

echo "✅ 모든 LoRA 파일 이동 완료! ($found_files 개)"
