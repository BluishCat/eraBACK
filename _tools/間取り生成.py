# 間取り図を生成する。手で描くと幅がずれ、絵と隣接表が食い違うので必ずこれを使う。
#   python _tools/間取り生成.py
# マスの割り当て（G）とドアの一覧（D）を直して走らせ、出た図を AA_*.ERB に貼る。
# 検証：①定義したドアが壁を共有しているか ②入口から全部屋に行けるか
import unicodedata
W = lambda t: sum(2 if unicodedata.east_asian_width(c) in 'WFA' else 1 for c in t)

# 部屋の広さは畳数をマス数に割る（1マス≒2畳）
# トイレ1 風呂2 玄関2 階段2 キッチン4 客間6 リビング16 私室8 空き部屋6
# EXITS: 外へ出るドア {部屋: 外の番号}。最下行に面している部屋だけ置ける
PLANS = {
    '自宅1F': (
        [['03','03','05','05','05','05'],
         ['02','01','05','05','05','05'],
         ['06','01','07','07','04','04']],
        {('01','02'),('01','03'),('01','06'),('01','07'),('01','05'),('05','04')},
        '01', {'01':'09'}),
    # 2Fは階段ホール08を中央の帯にして、そこから各部屋へ。部屋を通り抜けさせない
    # 店1F：裏方が上段、カウンターが境、ホールが中央、玄関まわりが下段
    #   BX＝ボックス席の区画（中の番号は ERB 側で建てた数だけ並べる）
    '店1F': (
        [['16','16','16','16','16','16'],
         ['05','06','06','07','14','14'],
         ['02','02','02','02','02','02'],
         ['03','04','04','03','03','03'],
         ['03','03','03','03','03','03'],
         ['BX','BX','BX','08','10','11']],
        # 16＝裏の廊下。裏方の部屋どうしはここでつながる
        # 厨房だけカウンターと直結（注文→調理→配膳を短くするため）
        {('16','05'),('16','06'),('16','07'),('16','14'),
         ('02','06'),('02','03'),
         ('03','04'),('03','BX'),('03','08'),('03','10'),('03','11')},
        '03', {'08':'09'}),
    '自宅2F': (
        [['10','10','11','11'],
         ['08','08','08','08'],
         ['12','12','13','13']],
        {('08','10'),('08','11'),('08','12'),('08','13')},
        '08', {}),
}

def check(G, doors, entry):
    rows, cols = len(G), len(G[0])
    walls = set()
    for r in range(rows):
        for c in range(cols):
            for dr, dc in ((0,1),(1,0)):
                r2, c2 = r+dr, c+dc
                if r2 < rows and c2 < cols and G[r][c] != G[r2][c2]:
                    walls.add(frozenset((G[r][c], G[r2][c2])))
    bad = [d for d in doors if frozenset(d) not in walls]
    adj = {}
    for a, b in doors:
        adj.setdefault(a, set()).add(b)
        adj.setdefault(b, set()).add(a)
    seen, stack = {entry}, [entry]
    while stack:
        for n in adj.get(stack.pop(), ()):
            if n not in seen:
                seen.add(n); stack.append(n)
    return bad, sorted({c for row in G for c in row} - seen)

def render(G, doors, exits=None):
    rows, cols = len(G), len(G[0])
    exits = exits or {}
    pair = lambda a, b: (a,b) in doors or (b,a) in doors
    # ドアは接している境界のうち1マスだけ開ける。全マス開けると壁が消える
    seen = set()
    door_v, door_h = set(), set()     # 縦境界(r,c)＝列cと列c+1の間／横境界(r,c)＝行rと行r+1の間
    for r in range(rows):
        for c in range(cols):
            if c+1 < cols:
                a, b = G[r][c], G[r][c+1]
                if a != b and pair(a,b) and frozenset((a,b)) not in seen:
                    seen.add(frozenset((a,b))); door_v.add((r,c))
            if r+1 < rows:
                a, b = G[r][c], G[r+1][c]
                if a != b and pair(a,b) and frozenset((a,b)) not in seen:
                    seen.add(frozenset((a,b))); door_h.add((r,c))
    # 外へ出るドアの位置（最下行の列）
    exit_col = {}
    for c in range(cols):
        v = exits.get(G[rows-1][c])
        if v and v not in exit_col.values():
            exit_col[c] = v
    label = {}
    for name in {c for row in G for c in row}:
        cells = [(r,c) for r in range(rows) for c in range(cols) if G[r][c] == name]
        label[name] = cells[len(cells)//2]
    CORNER = {(0,1,0,1):'┌',(0,1,1,0):'┐',(1,0,0,1):'└',(1,0,1,0):'┘',
              (1,1,0,1):'├',(1,1,1,0):'┤',(0,1,1,1):'┬',(1,0,1,1):'┴',
              (1,1,1,1):'┼',(0,0,1,1):'─',(1,1,0,0):'│',
              (1,0,0,0):'│',(0,1,0,0):'│',(0,0,1,0):'─',(0,0,0,1):'─',
              (0,0,0,0):'　'}
    out = []
    for r in range(rows+1):
        line = ''
        for c in range(cols+1):
            al = G[r-1][c-1] if r>0 and c>0 else None
            ar = G[r-1][c]   if r>0 and c<cols else None
            bl = G[r][c-1]   if r<rows and c>0 else None
            br = G[r][c]     if r<rows and c<cols else None
            up    = (al is not None and ar is not None and al!=ar) or (r>0 and (c==0 or c==cols))
            down  = (bl is not None and br is not None and bl!=br) or (r<rows and (c==0 or c==cols))
            left  = (al is not None and bl is not None and al!=bl) or (c>0 and (r==0 or r==rows))
            right = (ar is not None and br is not None and ar!=br) or (c<cols and (r==0 or r==rows))
            line += CORNER[(int(up),int(down),int(left),int(right))]
            if c < cols:
                a = G[r-1][c] if r>0 else None
                b = G[r][c]   if r<rows else None
                if a is not None and b is not None and a == b:        line += '　'*3
                elif (r-1, c) in door_h:                              line += '─　─'
                elif r == rows and c in exit_col:                     line += '─　─'
                else:                                                 line += '─'*3
        out.append(line)
        if r < rows:
            line = ''
            for c in range(cols+1):
                l  = G[r][c-1] if c>0 else None
                rr = G[r][c]   if c<cols else None
                if l is None or rr is None:      line += '│'
                elif l == rr:                    line += '　'
                elif (r, c-1) in door_v:         line += '　'
                else:                            line += '│'
                if c < cols:
                    line += f'　{G[r][c]}　' if label[G[r][c]] == (r,c) else '　'*3
            out.append(line)
    if exit_col:
        line = ''
        for c in range(cols):
            line += '　' + (exit_col[c] if c in exit_col else '　　') + '　'
        out.append(line.rstrip('　') + '　')
    return out

def pad(t, width):
    while W(t) < width:
        t += '　'
    return t

def side_by_side(left, right, gap=4):
    """2つの図を左右に並べる。短い方は空行で埋める"""
    lw = max(W(l) for l in left)
    h = max(len(left), len(right))
    out = []
    for i in range(h):
        l = left[i]  if i < len(left)  else ''
        r = right[i] if i < len(right) else ''
        out.append(pad(pad(l, lw), lw + gap) + r)
    return out

rendered = {}
for name, (G, D, entry, EX) in PLANS.items():
    bad, unreach = check(G, D, entry)
    print(f'--- {name}')
    if bad:     print(f'  [NG] 壁を共有しないドア: {bad}')
    if unreach: print(f'  [NG] {entry} から行けない部屋: {unreach}')
    if not bad and not unreach: print('  検証OK')
    rendered[name] = render(G, D, EX)

# 左に1F、右に上の階を並べる
print('--- 自宅（横並び）')
for l in side_by_side(['一階'] + rendered['自宅1F'], ['二階'] + rendered['自宅2F']):
    print(f'{W(l):3d} |{l}|')

print('--- 店1F（単体）')
for l in rendered['店1F']:
    print(f'{W(l):3d} |{l}|')
