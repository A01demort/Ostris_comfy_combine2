#!/bin/bash
A1_DOWNLOAD_ATTEMPT=${A1_DOWNLOAD_ATTEMPT:-1}
if ! [[ "$A1_DOWNLOAD_ATTEMPT" =~ ^[1-3]$ ]]; then
    printf '❌ 다운로드 재실행은 최대 3회입니다.\n' >&2
    exit 1
fi

# ====================================
# 🧳 Hugging Face API 키 설정
# ====================================
# ✅ RunPod 환경변수(Huggingface_API_key)에서 자동으로 읽어옵니다.
# ❌ 환경변수가 없을 경우 아래 직접 입력란을 사용하세요:
#    (JupyterLab에서 /workspace/A1/ZIT_down_a1.sh 열고 수정 후 실행)
HUGGINGFACE_TOKEN="${Huggingface_API_key:-Huggingface_Token_key}"

# ====================================
# 🛠️ 사용자 설정값
# ====================================
MAX_PARALLEL=8

# ====================================
# 📂 파일 설정
# ====================================
INPUT_FILE="aria2_downloads.txt"
LOG_FILE="aria2_log.txt"
RESULT_FILE="aria2_result.txt"

# ====================================
# ⏱️ 타이머 시작
# ====================================
start_time=$(date +%s)

# ====================================
# 📦 Aria2 설치 확인
# ====================================
if ! command -v aria2c &> /dev/null; then
    echo "📦 aria2c가 설치되지 않았습니다. 설치를 시작합니다..."
    timeout --signal=TERM --kill-after=30s 600s sudo bash -c 'apt update && apt install -y aria2'
    if [ $? -ne 0 ]; then
        echo "❌ aria2 설치 실패. 수동 설치 필요."
        exit 1
    fi
else
    echo "✅ aria2c 설치 확인 완료."
fi

# ====================================
# 🔐 Hugging Face API 키 유효성 검사
# whoami-v2 API: 유효 토큰만 200 반환
# (공개 파일 URL은 토큰 없이도 200이라 의미 없음)
# ====================================
echo "🔍 Hugging Face API 키 유효성 검사 중..."

test_response=$(curl --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 5 --retry-max-time 100 -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $HUGGINGFACE_TOKEN" \
    "https://huggingface.co/api/whoami-v2")

if [[ "$test_response" != "200" ]]; then
    echo -e "\n\033[0;31m🚫 오류: Hugging Face API 키가 유효하지 않습니다! (HTTP $test_response)\033[0m"
    echo "🚫 다운로드를 중단합니다."
    exit 1
fi

echo "✅ Hugging Face API 키 인증 성공 (HTTP $test_response)"

# ====================================
# 📌 다운로드 리스트 (6개 파일)
# ====================================
downloads=(

  # 1. Z_image_turbo- 모델 (bf16)
  "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors|/workspace/ComfyUI/models/diffusion_models/z_image_turbo_bf16.safetensors"

  # 2. Z_image_turbo- Distill (LORA)
  "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/loras/z_image_turbo_distill_patch_lora_bf16.safetensors|/workspace/ComfyUI/models/loras/z_image_turbo_distill_patch_lora_bf16.safetensors"

  # 3. VAE (FLUX버전과 같음)
  "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors|/workspace/ComfyUI/models/vae/FLUX_VAE.safetensors"

  # 4. TEXT ENCODER모델 (Qwen3_4b)
  "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors|/workspace/ComfyUI/models/text_encoders/qwen_3_4b.safetensors"

  # 5. Z-image-Union-Controlnet file- 업글버전 (2.1 Version)
  "https://huggingface.co/alibaba-pai/Z-Image-Turbo-Fun-Controlnet-Union-2.1/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union-2.1-2601-8steps.safetensors|/workspace/ComfyUI/models/model_patches/Z-Image-Turbo-Fun-Controlnet-Union-2.1-2601-8steps.safetensors"

  # 6. Z-image-Union-Controlnet file- tile버전 (2.1 Version)
  "https://huggingface.co/alibaba-pai/Z-Image-Turbo-Fun-Controlnet-Union-2.1/resolve/main/Z-Image-Turbo-Fun-Controlnet-Tile-2.1-2601-8steps.safetensors|/workspace/ComfyUI/models/model_patches/Z-Image-Turbo-Fun-Controlnet-Tile-2.1-2601-8steps.safetensors"

  # 7. SeedVR2 - EMA VAE (fp16)
  "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors|/workspace/ComfyUI/models/SEEDVR2/ema_vae_fp16.safetensors"

  # 8. SeedVR2 - EMA 7B (fp8_e4m3fn mixed block35 fp16)
  "https://huggingface.co/AInVFX/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_fp8_e4m3fn_mixed_block35_fp16.safetensors|/workspace/ComfyUI/models/SEEDVR2/seedvr2_ema_7b_fp8_e4m3fn_mixed_block35_fp16.safetensors"

)

# ====================================
# 🧹 초기화
# ====================================
rm -f "$INPUT_FILE" "$LOG_FILE" "$RESULT_FILE"

# ====================================
# 📋 리스트 생성
# ====================================
for item in "${downloads[@]}"; do
  IFS="|" read -r url path <<< "$item"
  if [ -s "$path" ] && [ ! -f "$path.aria2" ]; then
    echo "[완료] 이미 존재: $path" | tee -a "$RESULT_FILE"
  else
    mkdir -p "$(dirname "$path")"
    echo "$url" >> "$INPUT_FILE"
    echo "  dir=$(dirname "$path")" >> "$INPUT_FILE"
    echo "  out=$(basename "$path")" >> "$INPUT_FILE"
  fi
done

# ====================================
# 🚀 다운로드 시작
# ====================================
A1_DOWNLOAD_RC=0
if [ -s "$INPUT_FILE" ]; then
  echo -e "\n🚀 다운로드 시작...\n"
  timeout --signal=TERM --kill-after=30s 1800s aria2c --max-tries=3 --retry-wait=5 --connect-timeout=10 --timeout=60 -x 8 -j "$MAX_PARALLEL" -i "$INPUT_FILE" \
         --console-log-level=notice --summary-interval=1 \
         --header="Authorization: Bearer $HUGGINGFACE_TOKEN" \
         | tee -a "$LOG_FILE"
  A1_DOWNLOAD_STATUS=("${PIPESTATUS[@]}")
  if [ "${A1_DOWNLOAD_STATUS[0]}" -ne 0 ] || [ "${A1_DOWNLOAD_STATUS[1]}" -ne 0 ]; then A1_DOWNLOAD_RC=1; fi
else
  echo "📂 다운로드할 항목이 없습니다."
fi

# ====================================
# ✅ 결과 반영
# ====================================
total=${#downloads[@]}
success=0
failures=()

for item in "${downloads[@]}"; do
  IFS="|" read -r url path <<< "$item"
  if [ -s "$path" ] && [ ! -f "$path.aria2" ]; then
    echo "[완료] $path" | tee -a "$RESULT_FILE"
    ((success++))
  else
    echo "[실패] $path" | tee -a "$RESULT_FILE"
    failures+=("$path")
  fi
done

# ====================================
# ⏱️ 소요 시간
# ====================================
end_time=$(date +%s)
duration=$((end_time - start_time))
minutes=$((duration / 60))
seconds=$((duration % 60))

echo -e "\n🕒 총 소요 시간: ${minutes}분 ${seconds}초\n" | tee -a "$RESULT_FILE"

# ====================================
# 📊 요약
# ====================================
if [ "$success" -eq "$total" ]; then
  echo "✅ $success/$total 모든 파일 정상!" | tee -a "$RESULT_FILE"
else
  echo "❌ $success/$total 완료, ${#failures[@]} 실패" | tee -a "$RESULT_FILE"
  echo "🔹 실패 파일 목록:" | tee -a "$RESULT_FILE"
  for fail in "${failures[@]}"; do
    echo " - $fail" | tee -a "$RESULT_FILE"
  done
fi

# ====================================
# ❌ 손상/중단 파일 검사 및 재시도
# ====================================
echo -e "\n🔍 다중 실패(또는 중단) 파일 검사..."
broken_files=()

for item in "${downloads[@]}"; do
  IFS="|" read -r url path <<< "$item"
  if [[ ! -s "$path" ]] || [[ -f "$path.aria2" ]]; then
    broken_files+=("$path")
  fi
done

if [ "${#broken_files[@]}" -gt 0 ]; then
  echo -e "\n🚨 ${#broken_files[@]}개의 중단/잘못된 파일 발견됨:"
  for bf in "${broken_files[@]}"; do
    echo " - $bf"
  done

  echo -e "\n❓ 자동 삭제 후 재다운로드 하시겠습니까? (Y/N): \c"
  confirm_retry=N
  if [ -t 0 ]; then read -r -t 60 confirm_retry || confirm_retry=N; fi

  if [[ "$confirm_retry" == "Y" || "$confirm_retry" == "y" ]]; then
    if [ "$A1_DOWNLOAD_ATTEMPT" -ge 3 ]; then
      printf '❌ 다운로드 최대 3회 시도 후 중단\n' >&2
      exit 1
    fi
    echo "🗑️ 삭제 중..."
    for bf in "${broken_files[@]}"; do
      rm -f "$bf" "$bf.aria2"
      echo "삭제됨: $bf"
    done
    echo "♻️ 다시 실행합니다..."
    A1_DOWNLOAD_ATTEMPT=$((A1_DOWNLOAD_ATTEMPT + 1)) bash "$0"
    exit $?
  else
    echo "⛔ 수동 처리 위해 종료합니다."
    exit 1
  fi
else
  if [ "$A1_DOWNLOAD_RC" -ne 0 ]; then
    printf '❌ 다운로드 명령 실패. 다운로드 로그를 확인하세요.\n' >&2
    exit 1
  fi
  echo "✅ 모든 파일이 정상적으로 다운되었습니다. (All good)"
   # ====================================
  # 🎓 AI 교육 & 커뮤니티 안내 (Community & EDU)
  # ====================================
  echo -e "\n====🎓 AI 교육 & 커뮤니티 안내====\n"
  echo -e "1. Youtube : https://www.youtube.com/@A01demort"
  echo "2. 교육 문의 : https://a01demort.com"
  echo "3. CLASSU 강의 : https://classu.co.kr/me/19375"
  echo "4. Stable AI KOREA : https://cafe.naver.com/sdfkorea"
  echo "5. 카카오톡 오픈채팅방 : https://open.kakao.com/o/gxvpv2Mf"
  echo "6. CIVITAI : https://civitai.com/user/a01demort"
  echo -e "\n==================================="
fi
