#!/bin/bash
set -euo pipefail

SEED=/opt/a1-template
WORKSPACE=/workspace

if [ ! -f "$SEED/init_or_check_nodes.sh" ]; then
    echo "ERROR: Missing image startup files: $SEED" >&2
    exit 1
fi

mkdir -p "$WORKSPACE/A1" "$WORKSPACE/ostris" \
    "$WORKSPACE/lora_training/output" "$WORKSPACE/lora_training/datasets"
python3 - "$SEED" "$WORKSPACE" <<'PY'
import json
import runpy
import shutil
import sys
from pathlib import Path

seed = Path(sys.argv[1])
workspace = Path(sys.argv[2])

def copy_missing(source, target):
    if not target.exists() and not target.is_symlink():
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

for source in seed.rglob('*'):
    target = workspace / 'ostris' / source.relative_to(seed)
    if source.is_dir():
        target.mkdir(parents=True, exist_ok=True)
    else:
        copy_missing(source, target)
for source in seed.glob('*.sh'):
    copy_missing(source, workspace / 'A1' / source.name)
copy_missing(seed / 'runtime-constraints-v1.0.31.txt', workspace / 'A1' / 'runtime-constraints-v1.0.31.txt')
copy_missing(seed / 'Move_LoRA_a1.sh', workspace / 'Move_LoRA_a1.sh')
copy_missing(seed / 'docker/start.sh', workspace / 'ostris/start.sh')

replacements = json.loads('[["jupyter-server==1.23.6", "jupyter-server==2.21.1"], ["if [ -f \\"$marker_file\\" ]; then", "if [ -f \\"$marker_file\\" ] && [ \\"$(cat \\"$marker_file\\")\\" = \\"$A1_NODE_ENV_ID\\" ]; then"], ["touch \\"$marker_file\\"", "printf \'%s\\\\n\' \\"$A1_NODE_ENV_ID\\" > \\"$marker_file\\""]]')
prelude = 'export PIP_CONSTRAINT=/workspace/A1/runtime-constraints-v1.0.31.txt\nif [ -f /tmp/.a1_sys_pkg_checked ] && ! python3 -c \'from importlib.metadata import version; assert version("jupyter-server") == "2.21.1"\' >/dev/null 2>&1; then\n    rm -f /tmp/.a1_sys_pkg_checked\nfi\n\n'
node_env = "if [ ! -f /tmp/.a1_node_env_id ]; then\n    python3 -c 'import uuid; print(uuid.uuid4())' > /tmp/.a1_node_env_id || exit 1\nfi\nA1_NODE_ENV_ID=$(cat /tmp/.a1_node_env_id)\n\n"
impact_build = '        A1_NODE_BUILD_ARGS=()\n        if [ "$d" = "ComfyUI-Impact-Pack/" ]; then\n            A1_NODE_BUILD_ARGS=(--no-build-isolation)\n        fi\n\n'
for relative in ('A1/init_or_check_nodes.sh', 'ostris/init_or_check_nodes.sh'):
    path = workspace / relative
    original = path.read_bytes()
    text = original.decode('utf-8')
    newline = '\r\n' if '\r\n' in text else '\n'
    text = text.replace('\r\n', '\n')
    for before, after in replacements:
        text = text.replace(before, after)
    if 'runtime-constraints-v1.0.31.txt' not in text:
        text = text.replace('#!/bin/bash\n', '#!/bin/bash\n' + prelude, 1)
    if 'A1_NODE_ENV_ID=' not in text:
        text = text.replace('for d in */; do\n', node_env + 'for d in */; do\n', 1)
    if 'A1_NODE_BUILD_ARGS=()' not in text:
        text = text.replace('        echo "📦 $d 의존성 설치 중..."\n', impact_build + '        echo "📦 $d 의존성 설치 중..."\n', 1)
    text = text.replace('| pip install -r /dev/stdin --break-system-packages; then', '| pip install "${A1_NODE_BUILD_ARGS[@]}" -r /dev/stdin --break-system-packages; then', 1)
    updated = text.replace('\n', newline).encode('utf-8')
    if updated != original:
        backup = workspace / 'A1' / '.compat-backup-v1.0.31' / relative
        if not backup.exists():
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup)
        path.write_bytes(updated)
runpy.run_path(str(seed / 'docker/startup_upgrade.py'))['migrate'](workspace)
runpy.run_path(str(seed / 'docker/uv_upgrade.py'))['migrate'](workspace)
runpy.run_path(str(seed / 'docker/timeout_upgrade.py'))['migrate'](workspace)
PY

chmod +x "$WORKSPACE"/A1/*.sh "$WORKSPACE/Move_LoRA_a1.sh" \
    "$WORKSPACE/ostris/start.sh" "$WORKSPACE/ostris/docker/install.sh"
