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

方向 C（**本工具默认**，2026-10-05 起）：深底 #1A1A1A + 白色斜「练」+ 两侧 volt 哑铃头。
方向 A（`--logo classic`）：volt 底 + 墨色「练」—— 换图标前的旧版，留着对照。
方向 B（`--logo classic --alt`）：深底 + volt「练」—— 更像 App 内部，但小尺寸下发暗。

⚠️ **这是仓库里唯一需要第三方库的工具**（Pillow）。其余 tool/*.mjs 都是零依赖。
不用 Node 写是因为要渲染汉字：手写 PNG 编码器能做，字体光栅化不值得手写。
产物是入库的二进制资源，所以这个脚本**不进 verify.sh**，只在换图标时手动跑一次：

    python3 tool/gen-icons.py                  # 方向 C（当前线上配方）
    python3 tool/gen-icons.py --scheme ember   # 方向 C 的橙色备选（设计稿原样）
    python3 tool/gen-icons.py --logo classic   # 方向 A（换图标前那一版）
    python3 tool/gen-icons.py --preview        # 只出预览图到 /tmp，不碰仓库
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


# ─────────────────────────────────────────────────────────────────────────────
# 方向 C：**哑铃**（2026-10-05 用户给的设计稿）—— 现在这是默认方向
#
# 深底 + 白色粗斜「练」+ 两侧哑铃头。**几何不是肉眼估的**：哑铃两段的
# x/高比例是从设计稿逐像素量出来的（见下面 DB_GLYPH 那一节的注释）。
# 颜色有三条决定，都写在这儿：
#   * **底色用 #1A1A1A，不是 Tokens.bg 的 #0B0B0D** —— 设计稿就是 #1A1A1A，
#     而且在纯黑壁纸上，纯黑图标会"消失"，略亮一档才看得出边界；
#     ⚠️ 这是**图标专用色**：App 内部没有对应 token，别为了它去 theme.dart 加一个
#     没人用的 token（`asset-check` 只守尺寸/格式，颜色靠这段注释和配色表）；
#   * **哑铃用 volt（#D8FF47）而不是设计稿的橙** —— 用户 2026-10-05 定的：
#     图标和 App 内部主色是同一个绿，就不必再引第二个品牌色。
#     （橙色方案保留在 `--scheme ember` 里，想换回去是一条命令的事。）
#   * **字形用纯白 #FFFFFF**，不是 Tokens.text 的 #F5F5F7 —— 小尺寸下白得干脆一点。
#   * **字体用 Hiragino Sans GB W6 + 描边加粗**：本机没有 PingFang Heavy，
#     W6 是这里能拿到的最重黑体；再叠一点描边才接近设计稿那种"方块感"。
# ─────────────────────────────────────────────────────────────────────────────
DB_TILE = (26, 26, 26)       # #1A1A1A（图标专用）
DB_INK = (255, 255, 255)     # #FFFFFF（图标专用）
DB_EMBER = (255, 105, 46)    # #FF692E（未采用的备选配色）

# ── 配色方案（`--scheme`，默认 volt）─────────────────────────────────────────
# 设计稿给的是橙色（ember）。橙色好看，但**和 App 内部的 volt 不是一套**，
# 所以把"底色 / 字色 / 哑铃色"三件事都做成参数，四种方案能一次出图并排看：
#   volt    深底 + 白字 + volt 哑铃 ← **采用**
#   ember   深底 + 白字 + 橙哑铃   设计稿原样，辨识度最高，但引入第二个品牌色
#   allvolt 深底 + volt 字 + volt 哑铃 全绿，最"品牌"，但两色对比没了、小尺寸更糊
#   inverse volt 底 + 墨字 + 墨哑铃  方向 A 的延伸（绿底黑物），商店列表里最跳
DB_SCHEMES = {
    'ember':   {'tile': (26, 26, 26), 'ink': (255, 255, 255), 'accent': (255, 105, 46)},
    'volt':    {'tile': (26, 26, 26), 'ink': (255, 255, 255), 'accent': VOLT},
    'allvolt': {'tile': (26, 26, 26), 'ink': VOLT,             'accent': VOLT},
    'inverse': {'tile': VOLT,        'ink': VOLT_INK,         'accent': VOLT_INK},
}


def set_scheme(name):
    """切换配色：只改这三个全局量，画法一行都不用动。"""
    global DB_TILE, DB_INK, DB_EMBER
    s = DB_SCHEMES[name]
    DB_TILE, DB_INK, DB_EMBER = s['tile'], s['ink'], s['accent']
DB_FONT = '/System/Library/Fonts/Hiragino Sans GB.ttc'
DB_FONT_INDEX = 2            # W6（W3 太细、又比 Heiti Medium 重一档）
DB_SKEW = -0.16              # 负值 = 顶边右移（斜体感）
DB_STROKE = 0.013            # 额外描边宽度（占字高），把 W6 再喂粗一点
DB_GLYPH = 0.66              # 字形占比（设计稿量出来是 0.63，取 0.66 让启动器里更实一点）
#   ⚠️ 这个数不能大：字形一宽就把两侧的哑铃头压住了（第一版 0.80，预览一眼就发现
#   哑铃只剩两个角露在外面）—— 设计稿里两侧是**看得见**的，中间还留着一条缝。
#   ⚠️ 下面三组数字**不是估的**，是从设计稿逐像素量出来的（占画布宽度/高度的比例）：
#       内侧高杆  x 10.9%–15.9%（宽 5.0%）· 高 24.2%
#       外侧矮片  x  3.4%–10.6%（宽 7.2%）· 高 13.8%
#       字形      x 18.5%–81.5%（宽 63%）→ 与高杆之间留 2.6% 的缝
#   量出来的原因：第一版我按"看着差不多"调，两侧被字形压住、比例也不对；
#   量一遍之后一次就对了（而且换尺寸不会走形）。
DB_GLYPH_LAUNCH = 0.72       # 启动页中央
DB_SAFE = 0.72               # 自适应前景整体缩到画布的 72%（安全区 66% 之外再留余量）


def db_glyph(size, ratio):
    """透明底 + 居中「练」，**右倾**（设计稿里是斜体）。"""
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    px = int(big * ratio)
    font = ImageFont.truetype(DB_FONT, px, index=DB_FONT_INDEX)
    sw = max(1, int(px * DB_STROKE))
    bb = d.textbbox((0, 0), GLYPH, font=font, stroke_width=sw)
    x = (big - (bb[0] + bb[2])) / 2
    y = (big - (bb[1] + bb[3])) / 2
    d.text((x, y), GLYPH, font=font, fill=DB_INK, stroke_width=sw, stroke_fill=DB_INK)
    # 剪切：k<0 时顶边右移。c 取 -k*big/2 保证剪切后仍居中。
    img = img.transform((big, big), Image.AFFINE,
                        (1, DB_SKEW, -DB_SKEW * big / 2, 0, 1, 0), resample=Image.BICUBIC)
    return img.resize((size, size), Image.LANCZOS)


def db_ends(size):
    """两侧哑铃头：**两个竖向胶囊**（内高外矮），中间那根杆被字形挡住，不必画。

    几何取自设计稿的实测值（见上面那三行注释）——不是"看着差不多"调的。
    """
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cy = big / 2
    # (x0, x1, 高) 占画布的比例
    shapes = ((0.034, 0.106, 0.138),    # 外侧矮片
              (0.109, 0.159, 0.242))    # 内侧高杆
    for x0r, x1r, hr in shapes:
        w = (x1r - x0r) * big
        h = hr * big
        for side in (-1, 1):
            x0 = x0r * big if side < 0 else (1 - x1r) * big
            d.rounded_rectangle([x0, cy - h / 2, x0 + w, cy + h / 2],
                                radius=w / 2, fill=DB_EMBER)
    return img.resize((size, size), Image.LANCZOS)


# ─────────────────────────────────────────────────────────────────────────────
# 方向 D：**圆环**（2026-10-05 用户给的 `icon/AppIcon-1024x1024@1x.png`）—— 现在这是默认
#
# 和方向 C 的做法**不一样，故意不一样**：哑铃那版是"照着设计稿重画"（几何能量就量、能画就画），
# 这一版是**直接拿主图缩放**。原因：主图上有两样手画不出同等质感的东西 ——
# 环内的暖光晕、以及瓦片底色的细渐变。重画只会像"仿的"。
#
# 主图是"圆角瓦片 + 白底"（量出来：瓦片圆角 68px/1024，白底在四角），而两个平台要的东西不同：
#   * **iOS**：满幅方图、不许带 alpha、**不许自己切圆角**（系统自己裁）→ 白底那圈得补掉；
#   * **Android 传统图标**：要有 alpha 的圆角方块（我们的房子风格是 22% 圆角）；
#   * **Android 自适应**：背景是纯色、前景是图案（保持在 72% 安全区内）。
# 补角**不是拿一个平均色去糊**：沿水平方向从瓦片内部镜像取样，竖向渐变因此保住。
RING_MASTER = os.path.join(ROOT, 'icon/AppIcon-1024x1024@1x.png')
RING_CORNER = 68             # 瓦片自身的圆角（占 1024 的 6.6%，量出来的）
RING_TILE = (8, 12, 23)      # 瓦片边缘色（自适应图标的背景色，采样 px[10, 512]）
RING_OUTER = 0.4515          # 环外径占画布比例（量出来：包围盒 456/1024 ≈ 44.5%）
RING_INNER = 0.2580          # 环内径（内圈半径 132/512 = 25.8%）
_ring_cache = {}


def _ring_square():
    """主图 → **满幅方图**（白底角补成瓦片色）。缓存，因为每张图都要用。"""
    if 'square' in _ring_cache:
        return _ring_cache['square']

    img = Image.open(RING_MASTER).convert('RGB')
    px = img.load()
    W, H = img.size
    R = RING_CORNER

    def bright(p):
        return sum(p) > 600      # 白底

    # 四个角：沿水平方向找同一行里最靠内的"非白"像素，拿它的颜色往外填
    for cy0, cy1, cxs in ((0, R, range(R)), (H - R, H, range(R))):
        for y in range(cy0, cy1):
            for xs in (list(range(R - 1, -1, -1)), list(range(W - R, W))):
                inner = None
                for x in xs:
                    if not bright(px[x, y]):
                        inner = (x, px[x, y])
                        break
                if not inner:
                    continue
                ix, col = inner
                rng = range(ix - 1, -1, -1) if ix < W / 2 else range(ix + 1, W)
                for x in rng:
                    if not bright(px[x, y]):
                        break
                    px[x, y] = col

    _ring_cache['square'] = img
    return img


def _ring_layer(size, *, rounded=False, circle=False, scale=1.0):
    """满幅方图 → 指定尺寸；`rounded` 给传统图标切 22% 圆角，`circle` 给圆形图标切正圆。"""
    art = _ring_square()
    inner = int(size * scale)
    art = art.resize((inner, inner), Image.LANCZOS).convert('RGBA')
    if rounded:
        mask = rounded_square(inner, (255, 255, 255), 0.22).getchannel('A')
    elif circle:
        mask = Image.new('L', (inner, inner), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, inner - 1, inner - 1], fill=255)
    else:
        mask = Image.new('L', (inner, inner), 255)
    art.putalpha(mask)
    if inner == size:
        return art
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    off = (size - inner) // 2
    canvas.alpha_composite(art, (off, off))
    return canvas


def _ring_glyph(size):
    """启动页中央的图案：**把主图当自发光层抠出来**（暗底变全透明，环与光晕留住）。

    为什么不直接用那张方图：启动页底色是 App 的暖黑 `Tokens.bg`，而主图的瓦片是冷调深蓝 ——
    方图贴上去会看见一圈"另一个黑"。抠成自发光之后，环自己发光、底下就是启动页的底色。
    做法就是 `alpha = 亮度`、颜色照抄：对"亮物 + 近黑底"这种图，这一步等价于标准的 screen 合成。
    """
    big = size * SS
    src = _ring_square().resize((big, big), Image.LANCZOS).convert('RGB')
    px = src.load()
    out = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    op = out.load()
    half = big / 2
    for y in range(big):
        for x in range(big):
            r, g, b = px[x, y]
            lum = max(r, g, b)
            # ⚠️ 阈值 45 是量出来的、不是拍的：主图瓦片底色是 #080C15–#161A25
            # （亮度 21–37），而环内的光晕亮度 140+。阈值低于 37 就会在启动页上
            # 留下一块**看得见的方影子**（第一版阈值 6，预览里就是那个四方块）。
            if lum <= 45:
                continue
            a = min(255, int((lum - 45) * 255 / 105))
            # 再乘一圈**径向淡出**：主图的中心光晕是被瓦片"裁"住的，直接抠会留下一道
            # 方形的光边（第二版预览里就是它）。让它自己淡出去，边界就不存在了。
            dx, dy = (x + 0.5 - half) / half, (y + 0.5 - half) / half
            rr = (dx * dx + dy * dy) ** 0.5
            if rr >= 0.92:
                continue
            if rr > 0.70:
                a = int(a * (0.92 - rr) / 0.22)
            op[x, y] = (r, g, b, a)
    return out.resize((size, size), Image.LANCZOS)


def _ring_mono(size):
    """主题剪影（Android 13+ 单色图标）：系统自己上色，所以只留**白色圆环**的形状。

    形状由量出来的内外径决定 —— 直接拿主图做 alpha 是不行的：主图整块都不透明。
    """
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cy = big / 2
    r_out = big * RING_OUTER / 2
    r_in = big * RING_INNER
    d.ellipse([cy - r_out, cy - r_out, cy + r_out, cy + r_out], fill=(255, 255, 255, 255))
    d.ellipse([cy - r_in, cy - r_in, cy + r_in, cy + r_in], fill=(0, 0, 0, 0))
    return img.resize((size, size), Image.LANCZOS)


def db_logo(size, ratio=DB_GLYPH, rounded=False, tile=True, radius_ratio=0.22):
    """底色（可圆角、可透明）+ 哑铃头 + 白色斜「练」。字形画在最上面，压住横档。"""
    if tile:
        base = rounded_square(size, DB_TILE, radius_ratio) if rounded \
            else Image.new('RGBA', (size, size), DB_TILE + (255,))
    else:
        base = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    base.alpha_composite(db_ends(size))
    base.alpha_composite(db_glyph(size, ratio))
    return base


def db_silhouette(img):
    """主题剪影（Android 13+）：系统自己上色，所以只留**纯白形状**。"""
    out = Image.new('RGBA', img.size, (255, 255, 255, 255))
    out.putalpha(img.getchannel('A'))
    return out


def render(variant, size, alt, logo):
    """三个方向（classic / dumbbell / ring）× 七种用途，只有一个入口 —— 免得两套配方各长各的。"""
    if logo == 'ring':
        if variant == 'legacy':
            return _ring_layer(size, rounded=True)
        if variant == 'round':
            return _ring_layer(size, circle=True)
        if variant == 'adaptive':
            # 前景缩到安全区（同方向 C 的做法）；背景是纯色，由 ic_launcher_colors.xml 给
            return _ring_layer(size, scale=DB_SAFE)
        if variant == 'mono':
            inner = _ring_mono(int(size * DB_SAFE))
            canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
            off = (size - inner.size[0]) // 2
            canvas.alpha_composite(inner, (off, off))
            return canvas
        if variant == 'launch':
            return _ring_glyph(size)
        if variant in ('ios', 'store'):
            return _ring_square().resize((size, size), Image.LANCZOS).convert('RGB')
        raise SystemExit(f'不认识的 variant: {variant}')
    if logo == 'dumbbell':
        if variant == 'legacy':
            return db_logo(size, rounded=True)
        if variant == 'round':
            big = size * SS
            circ = Image.new('RGBA', (big, big), (0, 0, 0, 0))
            ImageDraw.Draw(circ).ellipse([0, 0, big - 1, big - 1], fill=DB_TILE)
            base = circ.resize((size, size), Image.LANCZOS)
            base.alpha_composite(db_ends(size))
            base.alpha_composite(db_glyph(size, 0.60))
            return base
        if variant == 'adaptive':
            inner = db_logo(int(size * DB_SAFE), ratio=DB_GLYPH, tile=False)
            canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
            off = (size - inner.size[0]) // 2
            canvas.alpha_composite(inner, (off, off))
            return canvas
        if variant == 'mono':
            inner = db_logo(int(size * DB_SAFE), ratio=DB_GLYPH, tile=False)
            canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
            off = (size - inner.size[0]) // 2
            canvas.alpha_composite(db_silhouette(inner), (off, off))
            return canvas
        if variant == 'launch':
            return db_logo(size, ratio=DB_GLYPH_LAUNCH, tile=False)
        if variant in ('ios', 'store'):
            return db_logo(size, ratio=DB_GLYPH).convert('RGB')
        raise SystemExit(f'不认识的 variant: {variant}')
    # ── classic（volt 方向）—— 原样保留 ──
    if variant == 'legacy':
        return legacy_icon(size, alt)
    if variant == 'round':
        return round_icon(size, alt)
    if variant == 'adaptive':
        return adaptive_foreground(size, alt)
    if variant == 'mono':
        return monochrome(size)
    if variant == 'launch':
        return launch_glyph(size, alt)
    if variant == 'ios':
        return ios_icon(size, alt)
    if variant == 'store':
        return store_icon(size, alt)
    raise SystemExit(f'不认识的 variant: {variant}')


def bg_color(logo):
    """自适应图标的背景层颜色（写进 ic_launcher_colors.xml）。"""
    if logo == 'ring':
        return RING_TILE
    return DB_TILE if logo == 'dumbbell' else VOLT


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--logo', choices=('classic', 'dumbbell', 'ring'), default='ring',
                    help='图标方向：ring（默认：用户给的橙色圆环主图）｜dumbbell（深底 + 「练」 + 哑铃）'
                         '｜classic（volt 底，最早那版）')
    ap.add_argument('--scheme', choices=tuple(DB_SCHEMES), default='volt',
                    help='dumbbell 的配色：volt（默认，品牌绿哑铃）｜ember（橙，设计稿）｜'
                         'allvolt（全绿）｜inverse（绿底墨物）')
    ap.add_argument('--alt', action='store_true', help='仅 classic：方向 B（深底 + volt 字）')
    ap.add_argument('--preview', action='store_true', help='只出预览到 /tmp，不写仓库')
    args = ap.parse_args()

    if args.preview:
        out = '/tmp/icon-preview'
        os.makedirs(out, exist_ok=True)
        # 参考项：A（现状）· B（classic 深底）
        for tag, logo, alt in (('A-volt', 'classic', False), ('B-dark', 'classic', True)):
            for size in (48, 192, 512):
                render('legacy', size, alt, logo).save(f'{out}/{tag}-{size}.png')
            render('store', 1024, alt, logo).save(f'{out}/{tag}-1024.png')
        # 圆环方向（当前默认）
        for size in (48, 192, 512):
            render('legacy', size, False, 'ring').save(f'{out}/D-ring-{size}.png')
        render('store', 1024, False, 'ring').save(f'{out}/D-ring-1024.png')
        # 哑铃方向的四种配色，同一套几何只换颜色
        for name in DB_SCHEMES:
            set_scheme(name)
            for size in (48, 192, 512):
                render('legacy', size, False, 'dumbbell').save(f'{out}/C-{name}-{size}.png')
            render('store', 1024, False, 'dumbbell').save(f'{out}/C-{name}-1024.png')
        set_scheme(args.scheme)
        print(f'预览写到 {out}/（classic 参考 2 版 + 哑铃 4 配色 × 48/192/512/1024）')
        return

    logo, alt = args.logo, args.alt
    if logo == 'dumbbell':
        set_scheme(args.scheme)

    for d, size in LEGACY.items():
        p = os.path.join(RES, f'mipmap-{d}')
        os.makedirs(p, exist_ok=True)
        render('legacy', size, alt, logo).save(os.path.join(p, 'ic_launcher.png'))
        render('round', size, alt, logo).save(os.path.join(p, 'ic_launcher_round.png'))
        a_size = ADAPTIVE[d]
        render('adaptive', a_size, alt, logo).save(os.path.join(p, 'ic_launcher_foreground.png'))
        render('mono', a_size, alt, logo).save(os.path.join(p, 'ic_launcher_monochrome.png'))
        print(f'  mipmap-{d}: 传统 {size}px + 圆形 · 自适应前景 {a_size}px · 主题剪影 {a_size}px')

    anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    for name in ('ic_launcher.xml', 'ic_launcher_round.xml'):
        with open(os.path.join(anydpi, name), 'w', encoding='utf-8') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                    '<!-- 由 tool/gen-icons.py 生成，别手改 -->\n'
                    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                    '    <background android:drawable="@color/ic_launcher_background" />\n'
                    '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
                    '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
                    '</adaptive-icon>\n')

    colors = os.path.join(RES, 'values/ic_launcher_colors.xml')
    c = bg_color(logo)
    with open(colors, 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<!-- 由 tool/gen-icons.py 生成：自适应图标的背景层用纯色，不占体积 -->\n'
                '<resources>\n'
                f'    <color name="ic_launcher_background">#{c[0]:02X}{c[1]:02X}{c[2]:02X}</color>\n'
                '</resources>\n')

    ios_dir = os.path.join(ROOT, 'app/ios/Runner/Assets.xcassets/AppIcon.appiconset')
    if os.path.isdir(ios_dir):
        for name, size in IOS_ICONS:
            render('ios', size, alt, logo).save(os.path.join(ios_dir, name))
        print(f'  iOS AppIcon：{len(IOS_ICONS)} 个尺寸（满幅不透明，系统自己裁圆角）')

        launch_dir = os.path.join(ROOT, 'app/ios/Runner/Assets.xcassets/LaunchImage.imageset')
        if os.path.isdir(launch_dir):
            for name, size in (('LaunchImage.png', 96), ('LaunchImage@2x.png', 192),
                               ('LaunchImage@3x.png', 288)):
                canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
                canvas.alpha_composite(render('launch', size, alt, logo))
                canvas.save(os.path.join(launch_dir, name))
            print('  iOS 启动图：LaunchImage @1x/@2x/@3x（透明底）')

    nodpi = os.path.join(RES, 'drawable-nodpi')
    os.makedirs(nodpi, exist_ok=True)
    render('launch', 288, alt, logo).save(os.path.join(nodpi, 'launch_glyph.png'))
    print('  drawable-nodpi/launch_glyph.png（启动页中央的图案）')

    store = os.path.join(ROOT, 'store-assets')
    os.makedirs(store, exist_ok=True)
    render('store', 512, alt, logo).save(os.path.join(store, 'icon-512.png'))
    render('store', 1024, alt, logo).save(os.path.join(store, 'icon-1024.png'))
    print('  商店图标：store-assets/icon-512.png（512×512，无透明）+ icon-1024.png')
    if logo == 'ring':
        print('方向：D（用户给的橙色圆环主图，直接缩放；白底角已按瓦片色补满）')
    else:
        print(f'方向：{"C（哑铃 · " + args.scheme + "）" if logo == "dumbbell" else ("B（深底 + volt 字）" if alt else "A（volt 底 + 墨色字）")}')


if __name__ == '__main__':
    main()
