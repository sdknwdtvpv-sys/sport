#!/usr/bin/env python3
"""练了么 · 生成 Google Play「特征图片」（Feature Graphic，1024×500，一次性工具）

**为什么需要它**：Play 的商店条目里那张顶部横幅就是它 —— 规格是**精确 1024×500**，
JPEG 或 24 位 PNG（**不带透明**）。我们一直只有图标与截图，**这张是缺的**，
而它在 Play Console 里是必填项之一。

品牌 token 与 `tool/gen-icons.py` / `app/lib/core/theme.dart` 同源，不另立一套：
    bg      #0B0B0D   应用底色
    volt    #D8FF47   强调色（App 里所有主按钮）
    voltInk #12180A   volt 上的字色
    text2   #9A9AA5   次级文字色

画什么、不画什么（Play 有明确规矩）：
  * **不画界面**、不堆文字、不带号召语（"立即下载"这类会被判违规）；
  * 只放**品牌标记 + 一句话**：左边 volt 圆角方块里的「练」，右边产品名与一句话卖点；
  * 内容留足边距 —— Play 在推荐位会**裁切**这张图，靠边的字会被切掉。

产物入库：`store-assets/feature-graphic-1024x500.png`
（`tool/asset-check.mjs` 会核它的尺寸与"不带透明"。）

    python3 tool/gen-feature-graphic.py            # 写进仓库
    python3 tool/gen-feature-graphic.py --preview  # 只出到 /tmp 看看
"""

import argparse
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'store-assets/feature-graphic-1024x500.png')

W, H = 1024, 500
SS = 4  # 超采样：先放大画再缩小，汉字边缘才干净

BG = (11, 11, 13)          # Tokens.bg      #0B0B0D
VOLT = (216, 255, 71)      # Tokens.volt    #D8FF47
VOLT_INK = (18, 24, 10)    # Tokens.voltInk #12180A
TEXT2 = (154, 154, 165)    # Tokens.text2   #9A9AA5

FONT = '/System/Library/Fonts/STHeiti Medium.ttc'

NAME = '练了么'
GLYPH = '练'
TAGLINE = '一次点击记一组'


def font(px):
    return ImageFont.truetype(FONT, px, index=0)


def centered(draw, xy, text, f, fill):
    """按**墨迹包围盒**居中：汉字的字身框与墨迹不重合，按字身框居中是偏的。"""
    x, y = xy
    bb = draw.textbbox((0, 0), text, font=f)
    draw.text((x - (bb[0] + bb[2]) / 2, y - (bb[1] + bb[3]) / 2), text, font=f, fill=fill)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--preview', action='store_true', help='只出到 /tmp，不碰仓库')
    args = ap.parse_args()

    img = Image.new('RGB', (W * SS, H * SS), BG)
    d = ImageDraw.Draw(img)

    # 左边：volt 圆角方块 + 墨色「练」（与启动图标同一个标记，用户能对上）
    box, bx, by = 260, 92, (H - 260) // 2
    d.rounded_rectangle(
        [bx * SS, by * SS, (bx + box) * SS, (by + box) * SS],
        radius=int(box * 0.22) * SS,
        fill=VOLT,
    )
    centered(d, ((bx + box / 2) * SS, (by + box / 2) * SS), GLYPH,
             font(int(box * 0.62) * SS), VOLT_INK)

    # 右边：产品名 + 一句话（不写号召语，Play 会判违规）
    f_name, f_tag = font(104 * SS), font(44 * SS)
    tx = bx + box + 64
    right = W - 64                      # 右留白，和左边对称
    mid = (tx + right) / 2               # 文字块在"标记右侧到右留白"之间居中

    centered(d, (mid * SS, 198 * SS), NAME, f_name, (245, 245, 247))
    centered(d, (mid * SS, 300 * SS), TAGLINE, f_tag, TEXT2)

    # volt 小横杠**压在最后一行下面**：App 里的主按钮就是这个颜色，做一处呼应。
    # （第一版把它放在产品名左边，读起来像夹在"标记"和名字中间的一个怪符号。）
    bw, bh = 96, 8
    cy = 348
    d.rounded_rectangle(
        [(mid - bw / 2) * SS, cy * SS, (mid + bw / 2) * SS, (cy + bh) * SS],
        radius=(bh / 2) * SS, fill=VOLT)

    out = img.resize((W, H), Image.LANCZOS).convert('RGB')  # RGB = 一定不带 alpha

    path = '/tmp/feature-graphic-preview.png' if args.preview else OUT
    out.save(path, 'PNG', optimize=True)
    print(f'✓ {path}')
    print(f'  {out.size[0]}×{out.size[1]}　模式 {out.mode}（RGB = 无透明通道）')


if __name__ == '__main__':
    main()
