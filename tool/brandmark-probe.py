#!/usr/bin/env python3
"""练了么 · 从证据图上**量**那枚环（VI 计划 T3-1）

为什么要它：`BrandMark` 的几何全是比例（外径 0.447 / 环带 0.1985 / 洞 0.603），
而"比例对不对"这件事**必须在像素上验一次** —— 组件里的常量只能证明代码自洽，
证明不了画出来的就是那枚环（描边位置、抗锯齿、`size` 传错都会让它跑掉）。

用法：
    python3 tool/brandmark-probe.py <证据图.png> [组件边长逻辑像素]

它取图上**最大**的那枚环（证据图里是 320 那一档），过中心横扫一行，
按"明显橙"的连续区段量出外径 / 环带 / 洞径，然后和 `brand_mark.dart` 里的三个比例比对。
"""

import sys

from PIL import Image


def is_orange(c):
    r, g, b = c
    return r > 150 and g < r * 0.75


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    size = float(sys.argv[2]) if len(sys.argv) > 2 else 320.0
    scale = 3.0  # iPhone 证据图是 @3x

    im = Image.open(path).convert("RGB")
    px = im.load()
    w, h = im.size

    # 每一行上有多少橙像素 → 橙最多的那一段连续行就是最大的环
    counts = [sum(1 for x in range(0, w, 2) if is_orange(px[x, y])) for y in range(h)]
    peak = max(range(h), key=lambda y: counts[y])
    y0 = peak
    while y0 > 0 and counts[y0 - 1] > 0:
        y0 -= 1
    y1 = peak
    while y1 < h - 1 and counts[y1 + 1] > 0:
        y1 += 1
    cy = (y0 + y1) // 2

    segs, start = [], None
    for x in range(w):
        if is_orange(px[x, cy]):
            if start is None:
                start = x
        elif start is not None:
            segs.append((start, x - 1))
            start = None
    if start is not None:
        segs.append((start, w - 1))
    if len(segs) < 2:
        raise SystemExit(f"过中心那一行只找到 {len(segs)} 段橙色 —— 这不像一枚环")

    a, b = segs[0]
    c, d = segs[-1]
    outer = d - a + 1
    band = b - a + 1
    hole = c - b - 1

    print(f"最大环：y {y0}..{y1}（{outer}px 外径 @{scale:.0f}x）")
    print(f"  外径/组件边长 = {outer / scale / size:.3f}   （目标 0.447）")
    print(f"  环带/外径     = {band / outer:.3f}   （目标 0.1985）")
    print(f"  洞径/外径     = {hole / outer:.3f}   （目标 0.603）")

    ok = (abs(outer / scale / size - 0.447) < 0.006
          and abs(band / outer - 0.1985) < 0.006
          and abs(hole / outer - 0.603) < 0.006)
    print("✓ 画出来的就是那枚环" if ok else "✗ 与 brand_mark.dart 的比例对不上")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
