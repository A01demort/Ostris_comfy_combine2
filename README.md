# OSTRIS AI Toolkit + ComfyUI for RunPod

RunPod의 클라우드 GPU 환경에서 **OSTRIS AI Toolkit과 ComfyUI를 동시에 사용할 수 있도록 구성한 Docker 프로젝트**입니다.

로컬 GPU의 성능이나 VRAM 한계로 AI 모델 학습과 이미지 생성이 어려운 사용자가 RunPod에서 제공하는 다양한 클라우드 GPU를 활용할 수 있도록 제작했습니다.

[![RunPod에서 실행](https://img.shields.io/badge/RunPod-바로%20실행-673DE6?style=for-the-badge)](https://console.runpod.io/deploy?template=i58iivqmwa&ref=zsh71wg9)

## 프로젝트 소개

기존에는 OSTRIS AI Toolkit과 ComfyUI를 각각 설치하고 서로 다른 방식으로 실행해야 했습니다.

이 Docker 환경을 사용하면 RunPod Pod를 시작할 때 다음 서비스가 함께 실행됩니다.

- **OSTRIS AI Toolkit**: 데이터셋 관리 및 AI 모델·LoRA 학습
- **ComfyUI**: 노드 기반 AI 이미지·영상 생성
- **JupyterLab**: 파일 관리 및 터미널 작업

OSTRIS AI Toolkit에서 LoRA를 학습한 뒤 같은 Pod의 ComfyUI에서 바로 불러와 테스트할 수 있어 설치와 실행 과정이 간단해집니다.

## 주요 특징

- OSTRIS AI Toolkit과 ComfyUI 동시 실행
- RunPod의 다양한 클라우드 GPU 사용 가능
- 하나의 Pod에서 LoRA 학습부터 이미지 생성까지 진행
- JupyterLab을 통한 파일 및 터미널 관리
- ComfyUI 주요 커스텀 노드 자동 설치
- `/workspace`를 중심으로 작업 파일과 결과물 관리
- 학습된 LoRA 파일을 ComfyUI 모델 폴더로 간편하게 이동

## RunPod에서 사용하기

별도의 로컬 설치 없이 아래 링크에서 템플릿을 배포하여 사용할 수 있습니다.

### [RunPod 템플릿으로 바로 배포하기](https://console.runpod.io/deploy?template=i58iivqmwa&ref=zsh71wg9)

1. 위 링크에 접속합니다.
2. 사용할 RunPod GPU를 선택합니다.
3. Pod를 배포합니다.
4. 초기 설치와 서비스 실행이 완료될 때까지 기다립니다.
5. RunPod의 **Connect** 메뉴에서 원하는 서비스에 접속합니다.

> 첫 실행에서는 필요한 패키지와 ComfyUI 커스텀 노드를 설치하므로 시간이 다소 걸릴 수 있습니다.

## 서비스 포트

| 서비스 | 포트 | 용도 |
|---|---:|---|
| ComfyUI | `8188` | 이미지 및 영상 생성 워크플로 |
| OSTRIS AI Toolkit | `8675` | 데이터셋 관리 및 AI 모델·LoRA 학습 |
| JupyterLab | `8888` | 파일 관리 및 터미널 사용 |

## 기본 저장 경로

| 항목 | 경로 |
|---|---|
| ComfyUI | `/workspace/ComfyUI` |
| OSTRIS AI Toolkit | `/workspace/ostris` |
| 학습 데이터셋 | `/workspace/lora_training/datasets` |
| 학습 결과 | `/workspace/lora_training/output` |
| ComfyUI LoRA 모델 | `/workspace/ComfyUI/models/loras` |

## 학습한 LoRA를 ComfyUI로 이동하기

OSTRIS AI Toolkit에서 생성된 `.safetensors` 파일은 JupyterLab 터미널에서 다음 명령으로 ComfyUI의 LoRA 폴더로 이동할 수 있습니다.

```bash
move
```

이 명령은 `/workspace/lora_training/output`의 LoRA 파일을 `/workspace/ComfyUI/models/loras`로 이동합니다.

## Hugging Face 토큰 설정

일부 모델을 자동으로 다운로드하려면 RunPod 환경 변수에 Hugging Face 토큰을 등록합니다.

```text
Huggingface_API_key=YOUR_HUGGINGFACE_TOKEN
```

토큰을 등록하지 않아도 ComfyUI와 OSTRIS AI Toolkit은 실행할 수 있지만, 인증이 필요한 모델의 자동 다운로드는 건너뜁니다.

## 이런 분들에게 유용합니다

- 로컬 GPU 성능이나 VRAM이 부족한 사용자
- 고성능 GPU를 필요한 시간만 빌려 사용하고 싶은 사용자
- OSTRIS AI Toolkit으로 LoRA를 학습하려는 사용자
- 학습 결과를 ComfyUI에서 바로 테스트하고 싶은 사용자
- AI Toolkit과 ComfyUI를 각각 설치하고 실행하는 과정이 번거로운 사용자

## 주의사항

- RunPod는 선택한 GPU와 Pod 실행 시간에 따라 비용이 발생합니다.
- 작업이 끝난 후에는 불필요한 요금이 발생하지 않도록 Pod를 반드시 중지하거나 삭제하세요.
- GPU 종류와 VRAM 용량에 따라 실행 가능한 모델과 학습 설정이 달라질 수 있습니다.
- 각 프로그램과 모델의 라이선스 및 사용 조건은 해당 원본 프로젝트의 정책을 따릅니다.

## License

이 프로젝트는 [MIT License](https://opensource.org/licenses/MIT)로 배포됩니다.

