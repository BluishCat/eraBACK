# -*- coding: utf-8 -*-
"""配布用の zip を作る。

使い方（開発フォルダで）:  python _tools/build_dist.py
  version.txt の版で _build/eraBACK/ に配布の中身を組み、_build/eraBACK_<版>.zip に固める。
  zip の中は eraBACK/ の下に配布物（更新プログラムが読む manifest.txt・version.txt つき）。
  配布物に入れるもの：ゲーム本体（EmueraEX.exe・CSV・ERB・口上テンプレート・エンジン・README・setting.json）と
  更新プログラム（更新.bat・_update/update.ps1）。emuera.config は _tools/配布用/ の配布用のもの（開発用とは窓の大きさが違う）。
  入れないもの：sav・profile・ログ・debug・_tools・開発文書（設計メモ・進捗.md・画面イメージ・コマンド一覧・memo.md）。
"""
import hashlib
import os
import shutil
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, '_build')
TOP = 'eraBACK'

# (開発フォルダでの相対パス, 配布物での相対パス)。フォルダは中を丸ごと
INCLUDE = [
    ('EmueraEX.exe', 'EmueraEX.exe'),
    ('README.txt', 'README.txt'),
    ('setting.json', 'setting.json'),
    ('_tools/配布用/emuera.config', 'emuera.config'),
    ('更新.bat', '更新.bat'),
    ('_update/update.ps1', '_update/update.ps1'),
    ('CSV', 'CSV'),
    ('ERB', 'ERB'),
    ('口上テンプレート', '口上テンプレート'),
    ('キャラ作成.html', 'キャラ作成.html'),
    ('キャラ作成.bat', 'キャラ作成.bat'),
    ('_chara_tool', '_chara_tool'),
    ('エンジン', 'エンジン'),
]
SKIP_NAMES = {'.git', '.gitignore', 'Thumbs.db', 'desktop.ini', '.DS_Store'}


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    version = open(os.path.join(ROOT, 'version.txt'), encoding='utf-8').read().strip()
    stage = os.path.join(BUILD, TOP)
    if os.path.exists(stage):
        shutil.rmtree(stage)
    os.makedirs(stage)

    for src, dst in INCLUDE:
        s = os.path.join(ROOT, *src.split('/'))
        d = os.path.join(stage, *dst.split('/'))
        if not os.path.exists(s):
            sys.exit('無い: ' + src)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        if os.path.isdir(s):
            shutil.copytree(s, d, ignore=shutil.ignore_patterns(*SKIP_NAMES))
        else:
            shutil.copy2(s, d)

    with open(os.path.join(stage, 'version.txt'), 'w', encoding='utf-8', newline='') as f:
        f.write(version)

    files = []
    for base, dirs, names in os.walk(stage):
        dirs.sort()
        for n in sorted(names):
            p = os.path.join(base, n)
            rel = os.path.relpath(p, stage).replace(os.sep, '/')
            if rel == 'manifest.txt':
                continue
            files.append((rel, p))
    files.sort()
    with open(os.path.join(stage, 'manifest.txt'), 'w', encoding='utf-8', newline='') as f:
        for rel, p in files:
            f.write('%s  %s\n' % (sha256(p), rel))

    out = os.path.join(BUILD, 'eraBACK_%s.zip' % version)
    if os.path.exists(out):
        os.remove(out)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for base, dirs, names in os.walk(stage):
            dirs.sort()
            for n in sorted(names):
                p = os.path.join(base, n)
                z.write(p, TOP + '/' + os.path.relpath(p, stage).replace(os.sep, '/'))
    print('版', version, ' ファイル', len(files) + 1, ' zip', out, os.path.getsize(out), 'bytes')
    print('zip の sha256:', sha256(out))


if __name__ == '__main__':
    main()
