import hashlib
import json
import os
import platform
import re
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
from pathlib import Path

MAX_ARCHIVE = 256 * 1024 * 1024
MAX_UNPACKED = 1280 * 1024 * 1024
GENERATED = ('node_modules', '.next', 'dist')


def file_hash(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def ui_fingerprint(root, source=None):
    source = Path(source or root)
    runtime = subprocess.check_output(
        ['node', '-p', 'JSON.stringify({versions:process.versions,arch:process.arch,platform:process.platform})'],
        cwd=root, timeout=30)
    digest = hashlib.sha256(b'a1-ui-cache-2\0' + runtime)
    digest.update(repr(platform.libc_ver()).encode())
    digest.update(str(root.resolve()).encode())
    keys = {'NODE_ENV', 'NODE_OPTIONS', 'AI_TOOLKIT_AUTH', 'TZ'}
    keys.update(key for key in os.environ if key.startswith('NEXT_PUBLIC_'))
    for directory, directories, filenames in os.walk(source):
        directories[:] = sorted(name for name in directories if name not in {*GENERATED, '.git', '.a1-build-cache'})
        for name in sorted(filenames):
            if name in {'next-env.d.ts', '.a1-ui-build.json', '.a1-ui-build.json.tmp'} or name.endswith('.tsbuildinfo'):
                continue
            path = Path(directory) / name
            content = path.read_bytes()
            digest.update(path.relative_to(source).as_posix().encode() + b'\0')
            digest.update(hashlib.sha256(content).digest())
            if path.suffix in {'.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs'}:
                keys.update(match.decode() for match in re.findall(rb'process\.env\.([A-Za-z_][A-Za-z_0-9]*)', content))
    for key in sorted(keys):
        digest.update(key.encode() + b'\0' + os.environ.get(key, '').encode() + b'\0')
    return digest.hexdigest()


def ui_artifacts(root):
    names = ('.next/BUILD_ID', '.next/build-manifest.json', '.next/required-server-files.json',
             'dist/cron/worker.js', 'node_modules/.package-lock.json', 'node_modules/next/package.json',
             'node_modules/@prisma/client/package.json', 'node_modules/sqlite3/package.json')
    return {name: file_hash(root / name) for name in names}


def ui_modules_ready(root):
    return subprocess.run(
        ['node', '-e', "require('next/package.json'); const {PrismaClient}=require('@prisma/client'); new PrismaClient(); require('sqlite3')"],
        cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30).returncode == 0


def ui_cache(mode, root, source=None):
    marker = root / '.a1-ui-build.json'
    try:
        current = {'source': ui_fingerprint(root, source), 'artifacts': ui_artifacts(root)}
        if not ui_modules_ready(root):
            return 1
        if mode == 'check':
            return 0 if json.loads(marker.read_text(encoding='utf-8')) == current else 1
        temporary = marker.with_suffix('.json.tmp')
        temporary.write_text(json.dumps(current, sort_keys=True), encoding='utf-8')
        temporary.replace(marker)
        return 0
    except (OSError, ValueError, subprocess.SubprocessError):
        return 1


def db_ready(root):
    database = root.parent / 'aitk_db.db'
    try:
        connection = sqlite3.connect(database.resolve().as_uri() + '?mode=ro', uri=True, timeout=3)
        try:
            tables = {row[0] for row in connection.execute('SELECT name FROM sqlite_master WHERE type="table"')}
            return {'Settings', 'Queue', 'Job'}.issubset(tables)
        finally:
            connection.close()
    except sqlite3.Error:
        return False


class NoOwnerTar(tarfile.TarFile):
    def chown(self, tarinfo, targetpath, numeric_owner):
        return


def restore_image_cache(root):
    archive = Path(os.environ.get('A1_UI_IMAGE_CACHE', '/opt/a1-ui-cache/ui.tar.gz'))
    descriptor = archive.with_suffix('.json')
    if any((root / name).exists() or (root / name).is_symlink() for name in GENERATED):
        return 1
    stage = None
    moved = []
    try:
        metadata = json.loads(descriptor.read_text(encoding='utf-8'))
        if archive.stat().st_size > MAX_ARCHIVE or metadata['sha256'] != file_hash(archive):
            return 1
        if metadata['source'] != ui_fingerprint(root):
            return 1
        stage = Path(tempfile.mkdtemp(prefix='.a1-ui-restore-', dir=root))
        with NoOwnerTar.open(archive, 'r:gz') as handle:
            members = handle.getmembers()
            if sum(member.size for member in members) > MAX_UNPACKED:
                return 1
            for member in members:
                name = Path(member.name)
                if not name.parts or name.is_absolute() or '..' in name.parts or name.parts[0] not in {*GENERATED, '.a1-ui-build.json'}:
                    return 1
                if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                    return 1
                if member.issym() or member.islnk():
                    base = stage / member.name
                    link = (base.parent / member.linkname).resolve() if member.issym() else (stage / member.linkname).resolve()
                    if stage.resolve() not in link.parents:
                        return 1
            handle.extractall(stage, members=members)
        for name in (*GENERATED, '.a1-ui-build.json'):
            (stage / name).replace(root / name)
            moved.append(name)
        if ui_cache('check', root):
            raise ValueError('cache incompatible')
        print('⏩ 이미지의 OSTRIS UI 빌드 캐시 적용 완료')
        return 0
    except (OSError, ValueError, KeyError, tarfile.TarError, subprocess.SubprocessError):
        for name in moved:
            target = root / name
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target)
            else:
                target.unlink(missing_ok=True)
        return 1
    finally:
        if stage is not None:
            shutil.rmtree(stage, ignore_errors=True)


def wait_services(seconds, ports=(8188, 8675, 8888)):
    deadline = time.monotonic() + seconds
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    while time.monotonic() < deadline:
        pending = []
        for port in ports:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            try:
                with opener.open(f'http://127.0.0.1:{port}/', timeout=min(5, remaining)) as response:
                    if response.status != 200:
                        pending.append(port)
            except Exception:
                pending.append(port)
        else:
            if not pending:
                return 0
        time.sleep(min(3, max(0, deadline - time.monotonic())))
    print('❌ 서비스 응답 대기 시간 초과 (8188 / 8675 / 8888). 서비스 로그를 확인하세요.', file=sys.stderr)
    return 1


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(2)
    mode, argument = sys.argv[1:]
    if mode == 'wait-services':
        sys.exit(wait_services(int(argument)))
    root = Path(argument)
    if mode in {'check', 'record'}:
        sys.exit(ui_cache(mode, root))
    if mode == 'restore':
        sys.exit(restore_image_cache(root))
    if mode == 'db-ready':
        sys.exit(0 if db_ready(root) else 1)
    sys.exit(2)
