#!/usr/bin/env python3
"""练了么 · 生成 Android 启动图标（一次性工具，产物入库）

为什么需要它：**2026-09-30 才发现 App 用的是 Flutter 默认图标**
（5 个密度的 ic_launcher.png 与 SDK 模板逐字节相同）。这既难看，也是商标问题
—— Flutter 的 logo 是 Google 的商标，不能拿来当自己的应用图标。
`tool/asset-check.mjs` 现在守着"不许再是默认图标"这条。

品牌 token 直接取自 `app/lib/core/theme.dart`，不另立一套：
    bg      #0B0B0D   应用底色
    volt    #D8FF47   强调色（App 里所有主按钮）
    voltInk #12180A   volt 上的字色

**两端一套配方**：Android（mipmap + 自适应 + 圆形 + 主题剪影）与
iOS（Assets.xcassets 里那 19 个尺寸 + 启动屏的 LaunchImage）都由这里生成，
免得两端各画一遍、慢慢长歪。

⚠️ iOS 图标**不能有透明通道**（App Store 会因此拒收），而且**不要自己切圆角**
（系统会自己裁）—— 所以 iOS 那套走的是"满幅不透明"的画法，和 Android 的圆角版不同。

方向 A（本工具默认）：volt 底 + 墨色「练」—— 启动器里最亮、最好认。
方向 B（`--alt`）：深底 + volt「练」—— 更像 App 内部，但小尺寸下发暗。

⚠️ **这是仓库里唯一需要第三方库的工具**（Pillow）。其余 tool/*.mjs 都是零依赖。
不用 Node 写是因为要渲染汉字：手写 PNG 编码器能做，字体光栅化不值得手写。
产物是入库的二进制资源，所以这个脚本**不进 verify.sh**，只在换图标时手动跑一次：

    python3 tool/gen-icons.py            # 方向 A
    python3 tool/gen-icons.py --alt      # 方向 B
    python3 tool/gen-icons.py --preview  # 只出预览图到 /tmp，不碰仓库
"""

import argparse
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'app/android/app/src/main/res')

BG = (11, 11, 13)          # Tokens.bg      #0B0B0D
VOLT = (216, 255, 71)      # Tokens.volt    #D8FF47
VOLT_INK = (18, 24, 10)    # Tokens.voltInk #12180A

FONT = '/System/Library/Fonts/STHeiti Medium.ttc'
GLYPH = '练'

# 传统图标：48dp 基准 × 密度倍数
LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
# 自适应图标：画布 108dp，安全区是中间 72dp（约 66%），超出会被各家启动器裁掉
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}

SS = 8  # 超采样倍数：先放大画再缩小，边缘才不会有锯齿


def glyph_layer(size, color, ratio):
    """透明底 + 居中汉字。ratio = 字高占画布的比例。"""
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    px = int(big * ratio)
    font = ImageFont.truetype(FONT, px, index=0)
    bb = d.textbbox((0, 0), GLYPH, font=font)
    # 用实际墨迹包围盒居中（汉字的字身框与墨迹不重合，按字身框居中也偏）
    x = (big - (bb[0] + bb[2])) / 2
    y = (big - (bb[1] + bb[3])) / 2
    d.text((x, y), GLYPH, font=font, fill=color)
    return img.resize((size, size), Image.LANCZOS)


def rounded_square(size, color, radius_ratio=0.22):
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, big - 1, big - 1], radius=int(big * radius_ratio), fill=color)
    return img.resize((size, size), Image.LANCZOS)


def legacy_icon(size, alt):
    """传统图标：圆角方底 + 字。Android 8 以下用这张。"""
    if alt:
        base, ink = rounded_square(size, BG), VOLT
    else:
        base, ink = rounded_square(size, VOLT), VOLT_INK
    base.alpha_composite(glyph_layer(size, ink, 0.58))
    return base


def adaptive_foreground(size, alt):
    """自适应前景：**透明底 + 字**，背景单独一层（见 ic_launcher_background.xml）。

    字只占 0.40 —— 安全区是 66%，但要留一圈余量：不同启动器裁的形状不一样
    （圆的、方的、水滴的），贴边写的字在圆的启动器上会被切掉一半。
    """
    return glyph_layer(size, VOLT if alt else VOLT_INK, 0.40)


def monochrome(size):
    """主题图标（Android 13+）：系统会自己上色，所以只给白色剪影。"""
    return glyph_layer(size, (255, 255, 255, 255), 0.40)


def round_icon(size, alt):
    """圆形版（`android:roundIcon`）：API 24/25 上有启动器会要这张。

    ⚠️ 必须在**每个传统密度**都出一张：只给 `mipmap-anydpi-v26/ic_launcher_round.xml`
    的话，API 24/25 上解析 `@mipmap/ic_launcher_round` 会找不到资源。
    （minSdk 是 24，所以这条不是假想问题。）
    """
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, big - 1, big - 1], fill=BG if alt else VOLT)
    base = img.resize((size, size), Image.LANCZOS)
    base.alpha_composite(glyph_layer(size, VOLT if alt else VOLT_INK, 0.50))
    return base


def launch_glyph(size, alt):
    """启动页中央的字形（透明底）。

    放在 `drawable-nodpi/`：1:1 像素、不随密度缩放 —— 启动图上字的大小
    不需要精确到 dp，一张够大的图在所有机型上都合适。
    """
    # 启动底色**永远是深的**（#0B0B0D），所以字永远用 volt —— 与图标方向无关
    return glyph_layer(size, VOLT, 0.86)


# iOS 需要的确切尺寸（名字与 Assets.xcassets/AppIcon.appiconset/Contents.json 对齐）
IOS_ICONS = [
    ('Icon-App-20x20@1x.png', 20), ('Icon-App-20x20@2x.png', 40),
    ('Icon-App-20x20@3x.png', 60),
    ('Icon-App-29x29@1x.png', 29), ('Icon-App-29x29@2x.png', 58),
    ('Icon-App-29x29@3x.png', 87),
    ('Icon-App-40x40@1x.png', 40), ('Icon-App-40x40@2x.png', 80),
    ('Icon-App-40x40@3x.png', 120),
    ('Icon-App-60x60@2x.png', 120), ('Icon-App-60x60@3x.png', 180),
    ('Icon-App-76x76@1x.png', 76), ('Icon-App-76x76@2x.png', 152),
    ('Icon-App-83.5x83.5@2x.png', 167),
    ('Icon-App-1024x1024@1x.png', 1024),
]


def ios_icon(size, alt):
    """iOS 图标：**满幅、不透明、不切圆角**（系统自己裁 + App Store 拒收带透明的图）。"""
    img = Image.new('RGB', (size, size), BG if alt else VOLT)
    img = img.convert('RGBA')
    img.alpha_composite(glyph_layer(size, VOLT if alt else VOLT_INK, 0.56))
    return img.convert('RGB')


def store_icon(size, alt):
    """应用商店要求：512×512、**不能有透明**、不能有圆角（商店自己加）。"""
    if alt:
        img, ink = Image.new('RGB', (size, size), BG), VOLT
    else:
        img, ink = Image.new('RGB', (size, size), VOLT), VOLT_INK
    img = img.convert('RGBA')
    img.alpha_composite(glyph_layer(size, ink, 0.56))
    return img.convert('RGB')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--alt', action='store_true', help='方向 B：深底 + volt 字')
    ap.add_argument('--preview', action='store_true', help='只出预览到 /tmp，不写仓库')
    args = ap.parse_args()

    if args.preview:
        out = '/tmp/icon-preview'
        os.makedirs(out, exist_ok=True)
        for tag, alt in (('A-volt', False), ('B-dark', True)):
            legacy_icon(192, alt).save(f'{out}/{tag}-192.png')
            legacy_icon(48, alt).save(f'{out}/{tag}-48.png')
            store_icon(512, alt).save(f'{out}/{tag}-512.png')
        print(f'预览写到 {out}/')
        return

    for d, size in LEGACY.items():
        p = os.path.join(RES, f'mipmap-{d}')
        os.makedirs(p, exist_ok=True)
        legacy_icon(size, args.alt).save(os.path.join(p, 'ic_launcher.png'))
        round_icon(size, args.alt).save(os.path.join(p, 'ic_launcher_round.png'))
        # ⚠️ 自适应图层**必须**用 ADAPTIVE 尺寸，不是传统图标的尺寸。
        # 系统把前景位图当作 108dp × 108dp 来缩放的：如果这里塞 48dp 的图，
        # 系统会放大 2.25 倍 —— 版式没错，但高密度屏上明显发虚。
        # （第一版就是这么写错的：定义了 ADAPTIVE 却没用上，自查时才发现。）
        a_size = ADAPTIVE[d]
        adaptive_foreground(a_size, args.alt).save(os.path.join(p, 'ic_launcher_foreground.png'))
        monochrome(a_size).save(os.path.join(p, 'ic_launcher_monochrome.png'))
        print(f'  mipmap-{d}: 传统 {size}px + 圆形 · 自适应前景 {a_size}px · 主题剪影 {a_size}px')

    # 自适应图标的描述文件（Android 8+ 走这条）
    anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, 'ic_launcher.xml'), 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<!-- 由 tool/gen-icons.py 生成，别手改 -->\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background" />\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
                '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
                '</adaptive-icon>\n')
    # 圆形图标：API 26+ 走这份自适应描述，API 24/25 走上面那些 ic_launcher_round.png
    with open(os.path.join(anydpi, 'ic_launcher_round.xml'), 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<!-- 由 tool/gen-icons.py 生成，别手改 -->\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background" />\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
                '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
                '</adaptive-icon>\n')

    colors = os.path.join(RES, 'values/ic_launcher_colors.xml')
    with open(colors, 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<!-- 由 tool/gen-icons.py 生成：自适应图标的背景层用纯色，不占体积 -->\n'
                '<resources>\n'
                f'    <color name="ic_launcher_background">#{VOLT[0]:02X}{VOLT[1]:02X}{VOLT[2]:02X}</color>\n'
                '</resources>\n')

    # ── iOS：19 个尺寸 + 启动屏的 LaunchImage ──
    ios_dir = os.path.join(ROOT, 'app/ios/Runner/Assets.xcassets/AppIcon.appiconset')
    if os.path.isdir(ios_dir):
        for name, size in IOS_ICONS:
            ios_icon(size, args.alt).save(os.path.join(ios_dir, name))
        print(f'  iOS AppIcon：{len(IOS_ICONS)} 个尺寸（满幅不透明，系统自己裁圆角）')

        # 启动屏：和 Android 一样，深底 + 居中的 volt「练」。
        # iOS 的 LaunchImage 是三张不同倍率的图，画布留白由 storyboard 的
        # contentMode=center 负责，所以这里给足四周留白。
        launch_dir = os.path.join(ROOT, 'app/ios/Runner/Assets.xcassets/LaunchImage.imageset')
        if os.path.isdir(launch_dir):
            for name, size in (('LaunchImage.png', 96), ('LaunchImage@2x.png', 192),
                               ('LaunchImage@3x.png', 288)):
                canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
                canvas.alpha_composite(glyph_layer(size, VOLT, 0.72))
                canvas.save(os.path.join(launch_dir, name))
            print('  iOS 启动图：LaunchImage @1x/@2x/@3x（透明底 + volt「练」）')

    nodpi = os.path.join(RES, 'drawable-nodpi')
    os.makedirs(nodpi, exist_ok=True)
    launch_glyph(288, args.alt).save(os.path.join(nodpi, 'launch_glyph.png'))
    print('  drawable-nodpi/launch_glyph.png（启动页中央的字）')

    # ⚠️ 写这里、**不是 dist/**：dist/ 是构建产物（gitignore），
    # 而商店图标是**要交给商店的交付物**，必须入库 —— 第一版写进 dist/，
    # clean 跑道上 asset-check 立刻红，才发现这个错。
    store = os.path.join(ROOT, 'store-assets')
    os.makedirs(store, exist_ok=True)
    store_icon(512, args.alt).save(os.path.join(store, 'icon-512.png'))
    store_icon(1024, args.alt).save(os.path.join(store, 'icon-1024.png'))
    print('  商店图标：store-assets/icon-512.png（512×512，无透明）+ icon-1024.png')
    print(f'方向：{"B（深底 + volt 字）" if args.alt else "A（volt 底 + 墨色字）"}')


if __name__ == '__main__':
    main()
