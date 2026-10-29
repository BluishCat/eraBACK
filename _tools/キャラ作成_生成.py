# -*- coding: utf-8 -*-
"""キャラ作成.html を作る。

使い方（開発フォルダで）:  python _tools/キャラ作成_生成.py
  _tools/キャラ作成_雛形.html の /*DATA*/ の所に、素質（CSV/Talent.csv）・衣装と衣類の台帳（CSV/台帳）・
  口上テンプレートを埋めて、開発フォルダ直下の キャラ作成.html に書く。
  素質や台帳を足したら、もう一度走らせる（build_dist.py の前に）。
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def rows(rel):
    """; で始まる行と空行を除いて、カンマで割った行を返す。"""
    out = []
    with open(os.path.join(ROOT, *rel.split('/')), encoding='utf-8-sig') as f:
        for line in f:
            line = line.rstrip('\r\n')
            if not line.strip() or line.lstrip().startswith(';'):
                continue
            out.append(line.split(','))
    return out


def main():
    talents = [{'id': int(r[0]), 'name': r[1]} for r in rows('CSV/Talent.csv')]

    # 衣装の組：名前と、組ごとの性別（同じ名前で女と男の行がある）
    sets = []
    for r in rows('CSV/台帳/衣装.csv'):
        if r[0] not in sets:
            sets.append(r[0])

    # 衣類：枠ごとの名前
    wear = {}
    for r in rows('CSV/台帳/衣類.csv'):
        if len(r) < 2:
            continue
        wear.setdefault(r[1], [])
        if r[0] not in wear[r[1]]:
            wear[r[1]].append(r[0])

    # 口上テンプレート（100_なまえ の中身）
    tdir = os.path.join(ROOT, '口上テンプレート', '100_なまえ')
    tmpl = {}
    for n in sorted(os.listdir(tdir)):
        if n.upper().endswith('.ERB'):
            with open(os.path.join(tdir, n), encoding='utf-8-sig', newline='') as f:
                tmpl[n] = f.read()

    data = {'talents': talents, 'sets': sets, 'wear': wear, 'kojo': tmpl}
    src = os.path.join(ROOT, '_tools', 'キャラ作成_雛形.html')
    with open(src, encoding='utf-8') as f:
        html = f.read()
    if '/*DATA*/' not in html:
        raise SystemExit('雛形に /*DATA*/ が無い')
    js = json.dumps(data, ensure_ascii=False).replace('</', '<\\/')
    html = html.replace('/*DATA*/null', js)
    dst = os.path.join(ROOT, 'キャラ作成.html')
    with open(dst, 'w', encoding='utf-8', newline='\n') as f:
        f.write(html)
    print('書いた:', dst, '素質', len(talents), '衣装', len(sets), '衣類の枠', len(wear))


if __name__ == '__main__':
    main()
