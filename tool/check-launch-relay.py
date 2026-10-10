#!/usr/bin/env python3
"""练了么 · **启动接力对位**（VI 计划 T3-6 判据 3）

**它要回答的问题**：冷启动那一刻，屏幕上有两枚"同一枚品牌环" ——
先是原生的 `LaunchImage@1x/2x/3x.png`（UIKit 画的），再是 Flutter 第一帧的
`SplashOverlay`（`BrandMark` 画的）。**两枚对不上，接力那一刻就会看到一次跳变**
（环跳一下、或者大小变一点）。这件事眼睛在生产设备上很难看清，但**量得出来**。

它核四件事：
  1. **环心是透明的**（alpha < 8）—— 否则原生启动图渲出来是"白饼 + 橙环"；
  2. **环的几何**：外径换算成 pt 之后，与 Flutter 那一侧的 `BrandMark` 同尺寸外径
     相差 ≤ 2pt（比例从 `app/lib/core/brand_mark.dart` 里读，画布从 `splash_overlay.dart` 里读 ——
     不在这里再抄一份数）；
  3. **环在画布正中**（偏移 ≤ 0.5pt）：偏了的话两枚环的圆心会错开；
  4. 三档（1x / 2x / 3x）彼此一致（同一枚环的三个分辨率）。

用法：
    python3 tool/check-launch-relay.py            # 核仓库里的启动图
    python3 tool/check-launch-relay.py --selftest # 自检（造几张假的，验它抓得住）

退出码：任何一项不符 → 1。
"""

import re
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
LAUNCH = ROOT / 'app/ios/Runner/Assets.xcassets/LaunchImage.imageset'
BRAND = ROOT / 'app/lib/core/brand_mark.dart'
SPLASH = ROOT / 'app/lib/features/onboarding/splash_overlay.dart'

TOL_PT = 2.0        # 判据给的对位容差
TOL_CENTER_PT = 0.5  # 圆心偏移容差


def flutter_side():
    """从 Dart 源码里读"Flutter 这一侧"的两个数：外径比例与画布边长。"""
    ratio = re.search(r'outerRatio\s*=\s*([0-9.]+)', BRAND.read_text(encoding='utf-8'))
    canvas = re.search(r'canvas\s*=\s*([0-9.]+)', SPLASH.read_text(encoding='utf-8'))
    if not ratio or not canvas:
        raise SystemExit('✗ 读不到 brand_mark.dart 的 outerRatio 或 splash_overlay.dart 的 canvas')
    return float(ratio.group(1)), float(canvas.group(1))


def measure(path):
    """量一张启动图：中心 alpha、环外径（pt）、圆心偏移（pt）。"""
    im = Image.open(path).convert('RGBA')
    px, W, H = im.load(), *im.size
    scale = round(W / 96)  # 画布 96pt 的 @1x/@2x/@3x
    cx, cy = W / 2 - 0.5, H / 2 - 0.5
    center_alpha = max(px[int(cx) + dx, int(cy) + dy][3] for dx in (-1, 0, 1) for dy in (-1, 0, 1))

    # 过中心横扫一行，取 alpha>200 的第一段与最后一段 → 环带
    segs, start = [], None
    for x in range(W):
        solid = px[x, int(cy)][3] > 200
        if solid and start is None:
            start = x
        elif not solid and start is not None:
            segs.append((start, x - 1))
            start = None
    if start is not None:
        segs.append((start, W - 1))
    if len(segs) < 2:
        return None
    outer_px = segs[-1][1] - segs[0][0] + 1
    center_px = (segs[0][0] + segs[-1][1]) / 2
    return {
        'scale': scale,
        'center_alpha': center_alpha,
        'outer_pt': outer_px / scale,
        'offset_pt': abs(center_px - (W - 1) / 2) / scale,
        'size': im.size,
    }


def check(launch_dir):
    ratio, canvas = flutter_side()
    want = ratio * canvas  # Flutter 那一侧的环外径（pt）
    problems, facts = [], []
    outs = []
    for p in sorted(launch_dir.glob('LaunchImage*.png')):
        m = measure(p)
        if m is None:
            problems.append(f'{p.name}：过中心那一行找不到两段实心 —— 这不像一枚环')
            continue
        outs.append((p.name, m['outer_pt']))
        if m['center_alpha'] >= 8:
            problems.append(f'{p.name}：环心 alpha = {m["center_alpha"]}（要 < 8）—— '
                            '原生启动图会渲成"白饼 + 橙环"')
        if abs(m['outer_pt'] - want) > TOL_PT:
            problems.append(f'{p.name}：环外径 {m["outer_pt"]:.2f}pt，Flutter 那一侧是 {want:.2f}pt'
                            f'（差 {abs(m["outer_pt"] - want):.2f}pt > {TOL_PT}）')
        if m['offset_pt'] > TOL_CENTER_PT:
            problems.append(f'{p.name}：环心偏了 {m["offset_pt"]:.2f}pt（> {TOL_CENTER_PT}）')
        facts.append(f'{p.name}: 外径 {m["outer_pt"]:.2f}pt · 环心 alpha {m["center_alpha"]} · '
                     f'偏移 {m["offset_pt"]:.2f}pt')
    if len(outs) >= 2:
        lo, hi = min(o for _, o in outs), max(o for _, o in outs)
        if hi - lo > TOL_PT:
            problems.append(f'三档彼此不一致：外径从 {lo:.2f}pt 到 {hi:.2f}pt')
    return problems, facts, want


def selftest():
    tmp = Path(tempfile.mkdtemp())
    problems = []

    def fake(name, size, ring_pt, center_alpha=0, hole=True, offset=0):
        """造一张假启动图：画布 96pt 的 @(size/96)x，环外径 ring_pt。"""
        im = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        s = size / 96
        r = ring_pt * s / 2
        c = size / 2 + offset * s
        d.ellipse([c - r, c - r, c + r, c + r], fill=(255, 92, 38, 255))
        if hole:
            hr = r * 0.6
            d.ellipse([c - hr, c - hr, c + hr, c + hr], fill=(0, 0, 0, 0))
        if center_alpha:
            d.point((int(c), int(c)), fill=(255, 255, 255, center_alpha))
        im.save(tmp / name)

    # ① 正常的一档：外径 42.9pt（= 0.447 × 96）、环心透明
    fake('LaunchImage.png', 96, 42.9)
    p, _, want = check(tmp)
    if p:
        problems.append(f'正常的启动图被判红：{p}')
    if abs(want - 42.9) > 0.05:
        problems.append(f'从 Dart 源码读出来的外径 {want:.3f} 不是 42.9')

    # ② 环心不透明（白饼）
    for f in tmp.iterdir():
        f.unlink()
    fake('LaunchImage.png', 96, 42.9, center_alpha=255)
    p, _, _ = check(tmp)
    if not any('环心 alpha' in x for x in p):
        problems.append('环心不透明没被抓出来')

    # ③ 环太小（对不上）
    for f in tmp.iterdir():
        f.unlink()
    fake('LaunchImage.png', 96, 30.0)
    p, _, _ = check(tmp)
    if not any('环外径' in x for x in p):
        problems.append('环外径对不上没被抓出来')

    # ④ 环心偏了
    for f in tmp.iterdir():
        f.unlink()
    fake('LaunchImage.png', 96, 42.9, offset=4)
    p, _, _ = check(tmp)
    if not any('偏了' in x for x in p):
        problems.append('环心偏移没被抓出来')

    # ⑤ 三档彼此不一致（1x 对、3x 小一圈）
    for f in tmp.iterdir():
        f.unlink()
    fake('LaunchImage.png', 96, 42.9)
    fake('LaunchImage@3x.png', 288, 36.0)
    p, _, _ = check(tmp)
    if not any('三档' in x for x in p):
        problems.append('三档不一致没被抓出来')

    for f in tmp.iterdir():
        f.unlink()
    tmp.rmdir()

    if problems:
        print('✗ 自检失败：')
        for x in problems:
            print(f'  - {x}')
        return 1
    print('✓ 自检通过 5 条：正常 / 环心不透明 / 环太小 / 环心偏移 / 三档不一致 都判对了')
    return 0


def main():
    if '--selftest' in sys.argv:
        return selftest()
    ratio, canvas = flutter_side()
    problems, facts, want = check(LAUNCH)
    for f in facts:
        print(f'  {f}')
    if problems:
        print('')
        for x in problems:
            print(f'✗ {x}')
        print(f'\n✗ 启动图与 Flutter 那一侧的环对不上（容差 {TOL_PT}pt）—— '
              '冷启动接力那一刻会看到跳变')
        return 1
    print(f'✓ 三档启动图与 Flutter 那一侧的环对得上：'
          f'外径 {want:.2f}pt（{ratio} × {canvas}pt），环心透明、居中')
    return 0


if __name__ == '__main__':
    sys.exit(main())
