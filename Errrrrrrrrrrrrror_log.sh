#!/bin/bash
# =============================================================
# Errrrrrrrrrrrrror_log.sh
# 실행: bash /workspace/Errrrrrrrrrrrrror_log.sh
# 결과: /workspace/Errrrrrrrrrrrrror_log.txt
# =============================================================

LOG="/workspace/Errrrrrrrrrrrrror_log.txt"
> "$LOG"

sep() { echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$LOG"; }
h()   { sep; echo "[$1]" >> "$LOG"; }

h "TIMESTAMP"
date '+%Y-%m-%d %H:%M:%S %Z' >> "$LOG"

# ─── 1. 시스템 스펙 ──────────────────────────────────────────
h "OS"
cat /etc/os-release 2>/dev/null | grep -E '^(NAME|VERSION)=' >> "$LOG" || echo "N/A" >> "$LOG"

h "CUDA DRIVER"
nvidia-smi --query-gpu=driver_version,cuda_version --format=csv,noheader 2>/dev/null >> "$LOG" || echo "nvidia-smi 없음" >> "$LOG"

h "GPU"
nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader 2>/dev/null >> "$LOG" || echo "N/A" >> "$LOG"

h "CUDA TOOLKIT (nvcc)"
nvcc --version 2>/dev/null | grep "release" >> "$LOG" || echo "nvcc 없음 (런타임 이미지)" >> "$LOG"

h "CPU / RAM"
echo "CPU: $(nproc) cores" >> "$LOG"
free -h | awk '/Mem:/{print "RAM: "$2" total, "$7" available"}' >> "$LOG"

h "DISK"
df -h /workspace 2>/dev/null | tail -1 >> "$LOG"

# ─── 2. Python / Pip ─────────────────────────────────────────
h "PYTHON"
python --version 2>&1 >> "$LOG"
which python >> "$LOG"

h "PIP"
pip --version 2>&1 >> "$LOG"

# ─── 3. 핵심 패키지 버전 ─────────────────────────────────────
h "KEY PACKAGES (installed versions)"
pip show torch torchvision torchaudio torchao \
    transformers diffusers accelerate \
    xformers bitsandbytes \
    opencv-python opencv-python-headless \
    peft gradio safetensors \
    2>/dev/null | grep -E '^(Name|Version):' | paste - - >> "$LOG"

# ─── 4. PyTorch 상세 ─────────────────────────────────────────
h "PYTORCH DETAIL"
python -c "
import torch
print('torch:', torch.__version__)
print('CUDA available:', torch.cuda.is_available())
print('CUDA version (torch built):', torch.version.cuda)
print('cuDNN:', torch.backends.cudnn.version())
if torch.cuda.is_available():
    print('GPU:', torch.cuda.get_device_name(0))
    print('VRAM total:', round(torch.cuda.get_device_properties(0).total_memory/1024**3,1), 'GB')
" 2>&1 >> "$LOG"

# ─── 5. 호환성 충돌 검사 ─────────────────────────────────────
h "COMPATIBILITY CONFLICTS"

# torch vs torchaudio 충돌 검사
python -c "import torchaudio" 2>&1 | grep -i "error\|undefined\|symbol" >> "$LOG" && \
    echo "  ❌ torchaudio 버전 불일치 (torch와 다른 버전으로 빌드됨)" >> "$LOG" || \
    echo "  ✅ torchaudio OK" >> "$LOG"

# transformers vs torchao 충돌
python -c "from transformers import T5EncoderModel" 2>&1 | grep -i "error\|import" >> "$LOG" && \
    echo "  ❌ transformers T5EncoderModel import 실패 (torchao 버전 충돌 의심)" >> "$LOG" || \
    echo "  ✅ transformers T5EncoderModel OK" >> "$LOG"

# torchao API 검사
python -c "from torchao.quantization.quant_api import quantize_, Float8WeightOnlyConfig, UIntXWeightOnlyConfig; from torchao.dtypes import AffineQuantizedTensor" \
    2>&1 | grep -i "error\|import" >> "$LOG" && \
    echo "  ❌ torchao API 불일치" >> "$LOG" || \
    echo "  ✅ torchao API OK" >> "$LOG"

# xformers 충돌
python -c "import xformers.ops" 2>&1 | grep -i "error\|warning\|built for" >> "$LOG" && \
    echo "  ⚠️  xformers 충돌 (위 메시지 확인)" >> "$LOG" || \
    echo "  ✅ xformers OK (또는 미설치)" >> "$LOG"

# diffusers import
python -c "from diffusers import AutoencoderTiny" 2>&1 | grep -i "error\|failed" >> "$LOG" && \
    echo "  ❌ diffusers import 실패" >> "$LOG" || \
    echo "  ✅ diffusers OK" >> "$LOG"

# ─── 6. OSTRIS import 체인 검사 ──────────────────────────────
h "OSTRIS IMPORT CHAIN"
cd /workspace/ostris 2>/dev/null || { echo "OSTRIS 없음 (/workspace/ostris)" >> "$LOG"; }

python -c "
import sys
sys.path.insert(0, '/workspace/ostris')
tests = [
    ('torchaudio',                    'import torchaudio'),
    ('transformers.T5EncoderModel',   'from transformers import T5EncoderModel'),
    ('diffusers.AutoencoderTiny',     'from diffusers import AutoencoderTiny'),
    ('toolkit.train_tools',           'from toolkit.train_tools import addnet_hash_legacy'),
    ('jobs.BaseJob',                  'from jobs.BaseJob import BaseJob'),
    ('jobs.process.BaseProcess',      'from jobs.process import BaseProcess'),
]
for name, stmt in tests:
    try:
        exec(stmt)
        print(f'  ✅ {name}')
    except Exception as e:
        print(f'  ❌ {name}: {e}')
" 2>&1 >> "$LOG"

# ─── 7. ComfyUI import 검사 ──────────────────────────────────
h "COMFYUI IMPORT CHECK"
python -c "
import sys
sys.path.insert(0, '/workspace/ComfyUI')
tests = [
    ('transformers.CLIPTokenizer', 'from transformers import CLIPTokenizer'),
    ('transformers.T5TokenizerFast', 'from transformers import T5TokenizerFast'),
    ('sqlalchemy',                  'import sqlalchemy'),
    ('alembic',                     'import alembic'),
]
for name, stmt in tests:
    try:
        exec(stmt)
        print(f'  ✅ {name}')
    except Exception as e:
        print(f'  ❌ {name}: {e}')
" 2>&1 >> "$LOG"

# ─── 8. OSTRIS run.py 실제 실행 테스트 ───────────────────────
h "OSTRIS run.py IMPORT TEST (dry-run)"
cd /workspace/ostris 2>/dev/null
python -c "
import sys
sys.path.insert(0, '/workspace/ostris')
try:
    from toolkit.job import get_job
    print('  ✅ toolkit.job.get_job import 성공')
except Exception as e:
    print(f'  ❌ toolkit.job.get_job: {e}')
" 2>&1 >> "$LOG"

# ─── 9. 설치된 전체 패키지 (참고용) ─────────────────────────
h "ALL INSTALLED PACKAGES"
pip list 2>/dev/null >> "$LOG"

# ─── 완료 ────────────────────────────────────────────────────
sep
echo "LOG SAVED: $LOG"
echo "생성 완료 → $LOG"
cat "$LOG"
