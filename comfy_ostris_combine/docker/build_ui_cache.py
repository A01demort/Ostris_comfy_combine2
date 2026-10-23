import importlib.util
import json
import os
import shutil
import subprocess
import tarfile
from pathlib import Path

directory = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('a1_ui_cache', directory / 'deploy_optimizations.py')
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class BudgetExceeded(Exception):
    pass


class BudgetFile:
    def __init__(self, handle, maximum):
        self.handle = handle
        self.maximum = maximum

    def write(self, data):
        if self.handle.tell() + len(data) > self.maximum:
            raise BudgetExceeded()
        return self.handle.write(data)

    def __getattr__(self, name):
        return getattr(self.handle, name)


def pack_cache(root, output):
    total = 0

    def include(member):
        nonlocal total
        parts = Path(member.name).parts
        if parts[:2] == ('.next', 'cache') or '.cache' in parts or member.name == '.next/trace':
            return None
        total += member.size
        if total > cache.MAX_UNPACKED:
            raise BudgetExceeded()
        member.uid = member.gid = 0
        member.uname = member.gname = ''
        return member

    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        with output.open('wb') as raw:
            with tarfile.open(fileobj=BudgetFile(raw, cache.MAX_ARCHIVE), mode='w:gz', compresslevel=6) as archive:
                for name in (*cache.GENERATED, '.a1-ui-build.json'):
                    archive.add(root / name, arcname=name, filter=include)
        return total
    except Exception:
        output.unlink(missing_ok=True)
        raise


def main():
    seed = Path('/opt/a1-template/ui')
    root = Path('/workspace/ostris/ui')
    output = Path('/opt/a1-ui-cache/ui.tar.gz')
    if shutil.disk_usage(output.parent.parent).free < 512 * 1024 * 1024:
        print('⏩ UI 이미지 캐시 생략: 빌드 여유 공간 부족')
        return
    if not os.path.ismount(root):
        print('⏩ UI 이미지 캐시 생략: 임시 용량 제한 마운트 없음')
        return
    shutil.copytree(seed, root, dirs_exist_ok=True)
    environment = os.environ.copy()
    environment.update({'npm_config_cache': str(root / '.a1-build-cache/npm'),
                        'npm_config_devdir': str(root / '.a1-build-cache/node-gyp'),
                        'XDG_CACHE_HOME': str(root / '.a1-build-cache/xdg'),
                        'TMPDIR': str(root / '.a1-build-cache/tmp'),
                        'NEXT_TELEMETRY_DISABLED': '1'})
    Path(environment['TMPDIR']).mkdir(parents=True, exist_ok=True)
    try:
        for command, seconds in ((['npm', 'install', '--prefer-offline'], 600),
                                 (['npm', 'run', 'build'], 900)):
            subprocess.run(['timeout', '--signal=TERM', '--kill-after=30s', str(seconds), *command],
                           cwd=root, env=environment, check=True)
        if cache.ui_cache('record', root, source=seed):
            raise ValueError('UI cache not ready')
        unpacked = pack_cache(root, output)
        metadata = {'sha256': cache.file_hash(output), 'source': cache.ui_fingerprint(root, source=seed),
                    'compressed_bytes': output.stat().st_size, 'unpacked_bytes': unpacked}
        output.with_suffix('.json').write_text(json.dumps(metadata, sort_keys=True), encoding='utf-8')
        print(f'✅ UI 이미지 캐시 준비 완료: {output.stat().st_size} bytes (상한 {cache.MAX_ARCHIVE})')
    except Exception as error:
        output.unlink(missing_ok=True)
        output.with_suffix('.json').unlink(missing_ok=True)
        print('⏩ UI 이미지 캐시 생략: ' + type(error).__name__ + ' (런타임 설치로 진행)')


if __name__ == '__main__':
    main()
