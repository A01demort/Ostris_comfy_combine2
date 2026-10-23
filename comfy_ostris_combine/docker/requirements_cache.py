import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import time
from importlib.metadata import version
from pathlib import Path


def environment_key():
    import torch
    capabilities = []
    try:
        capabilities = [torch.cuda.get_device_capability(i) for i in range(torch.cuda.device_count())]
    except Exception:
        pass
    if not capabilities:
        stamp = Path('/tmp/.a1_node_env_id')
        capabilities = [stamp.read_text() if stamp.exists() else str(time.time_ns())]
    data = [sys.version, platform.machine(), platform.libc_ver(), version('torch'), torch.version.cuda, capabilities,
            {key: os.environ.get(key, '') for key in ('TORCH_CUDA_ARCH_LIST', 'CC', 'CXX', 'CFLAGS', 'CXXFLAGS',
                                                      'LDFLAGS', 'CUDA_HOME', 'SAM2_BUILD_CUDA', 'SAM2_BUILD_ALLOW_ERRORS')}]
    for command in (['nvcc', '--version'], ['c++', '--version']):
        try:
            data.append(subprocess.check_output(command, timeout=60).decode())
        except (OSError, subprocess.SubprocessError):
            data.append(None)
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()[:24]


def prepare(source, target, exclude):
    lines = Path(source).read_text(encoding='utf-8').splitlines()
    result = []
    for line in lines:
        if re.match(exclude, line):
            continue
        if line.strip() == 'git+https://github.com/facebookresearch/sam2':
            output = subprocess.check_output(
                ['git', 'ls-remote', 'https://github.com/facebookresearch/sam2', 'HEAD'], timeout=int(os.environ.get('A1_GIT_REF_TIMEOUT', '120')))
            commit = output.decode().split()[0]
            if not re.fullmatch(r'[0-9a-f]{40,64}', commit):
                raise ValueError('SAM2 commit unavailable')
            line = line.strip() + '@' + commit
        result.append(line)
    Path(target).write_text('\n'.join(result) + '\n', encoding='utf-8')


if __name__ == '__main__':
    try:
        if sys.argv[1:] == ['--environment']:
            print(environment_key())
        else:
            prepare(*sys.argv[1:])
    except Exception as error:
        print('❌ 의존성 목록 준비 실패: ' + type(error).__name__, file=sys.stderr)
        sys.exit(1)
