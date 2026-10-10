#!/usr/bin/env python3
"""练了么 · 把帧率探针的 JSON 画成一张图（VI 计划 T2-1 判据 3）

**为什么需要"画出来"**：`LIANLEME-FRAMES {...}` 那一行里是几百个数，肉眼看不出
"休息那 60 秒里到底发生了什么"。计划里那句话是"没有这张图，性能结论都只是推理"。

用法：
    python3 tool/frame-probe-plot.py <drive 日志> <输出 png> [副标题]

日志里找 `LIANLEME-FRAMES {json}` 那一行；JSON 结构见
`app/integration_test/frame_probe_test.dart`：
    {frames: [[build, raster, ts?], ...], marks: [{name, frame}], rests: [[from, to], ...],
     rest_frame_count, rest_worst_raster_ms, rest_worst_frame}

图：横轴 = 时间（ms，取自 `FrameTiming.timestampInMicroseconds`，缺列时退化成"帧号 × 16.67ms 并标注"），
纵轴 = 帧时长（ms，点 = raster、浅色 = build），一条 16ms 预算线，
三段（冷启动 / 连点 tab / 记 10 组）画成底部的色带，休息窗口另外填色。
"""

import json
import re
import sys

from PIL import Image, ImageDraw, ImageFont

W, H = 1680, 940
PAD_L, PAD_R, PAD_T, PAD_B = 110, 40, 120, 150
BG = (14, 12, 10)
GRID = (44, 40, 36)
TEXT = (245, 243, 241)
TEXT2 = (171, 164, 154)
TEXT3 = (138, 129, 118)
ACCENT = (255, 92, 38)
SUCCESS = (12, 172, 120)
BUDGET = (250, 200, 80)
RASTER = (255, 138, 92)
BUILD = (120, 112, 104)

FONT_CANDIDATES = [
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/Supplemental/Songti.ttc",
]


def font(size):
    for path in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def load(log_path):
    """把日志里那一行 `LIANLEME-FRAMES {json}` 捡出来。

    ⚠️ **它可能被折断成很多行**：`debugPrint` 对长行会按 ~800 字符换行，
    折行之后每一段前面还带着 `I/flutter (14967): ` 这样的日志前缀 ——
    所以这里要先把前缀剥掉、把小段接回去，再用"括号平衡"判断 JSON 到哪儿结束。
    （第一次就栽在这儿：`re.findall(r'\\{.*\\}')` 一行都匹配不到。）
    """
    raw = open(log_path, encoding="utf-8", errors="replace").read()
    # 探针按序号分段打印：`LIANLEME-FRAMES-PART i/n <chunk>`
    # ⚠️ **不要假设每一段都在**：logcat 会把长输出的尾巴吃掉（第一次跑丢的就是最后一段）。
    # 所以这里做两件事：① 小字段走单独一行 SUMMARY（短，几乎不会被截）；
    # ② 帧数据用正则从拼起来的文本里抠 —— 被截断的最后一帧自然匹配不上，丢掉就是。
    parts = {}
    for m in re.finditer(r"LIANLEME-FRAMES-PART (\d+)/(\d+) ([^\n]*)", raw):
        parts[int(m.group(1))] = m.group(3)
    if not parts:
        raise SystemExit("日志里没有 LIANLEME-FRAMES-PART（探针没跑到最后？）")
    total = max(int(m.group(2)) for m in re.finditer(r"LIANLEME-FRAMES-PART (\d+)/(\d+)", raw))
    payload = "".join(parts.get(i, "") for i in range(total))

    frames = [[float(a), float(b), float(c)] for a, b, c in
              re.findall(r"\[([0-9.]+),([0-9.]+),([0-9.]+)\]", payload)]
    if not frames:
        raise SystemExit("分段里没抠出帧数据（格式变了？）")

    data = {"frames": frames, "marks": [], "rests": [], "rest_frame_count": None,
            "rest_worst_raster_ms": None, "rest_worst_frame": None}
    # 分段里如果还留着 marks / rests 就用它（顺序：frames 在前，所以可能已经丢了）
    m = re.search(r'"marks":\[(.*?)\],\s*"rests":\[(.*?)\],?\s*(?:"rest_frame_count"|"frames")', payload)
    if m:
        try:
            data["marks"] = json.loads("[" + m.group(1) + "]")
            data["rests"] = json.loads("[" + m.group(2) + "]")
        except json.JSONDecodeError:
            pass
    # SUMMARY 那一行兜底（它总是排在长输出之前，因此最不容易丢）
    ms = re.search(r"LIANLEME-FRAMES-SUMMARY (\{[^\n]*\})", raw)
    if ms:
        try:
            summary = json.loads(ms.group(1))
            if not data["marks"]:
                data["marks"] = summary.get("marks", [])
            if not data["rests"]:
                data["rests"] = summary.get("rests", [])
            for k in ("rest_frame_count", "rest_worst_raster_ms", "rest_worst_frame",
                      "rest_build_max_ms"):
                data[k] = summary.get(k, data.get(k))
        except json.JSONDecodeError:
            pass
    data.setdefault("rest_build_max_ms", None)
    if data["rests"]:
        # 窗口是帧号区间，但帧可能被截断过 → 夹到现有长度
        data["rests"] = [[a, min(b, len(frames))] for a, b in data["rests"] if a < len(frames)]
    return data, raw


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    log_path, out_path = sys.argv[1], sys.argv[2]
    subtitle = sys.argv[3] if len(sys.argv) > 3 else ""
    note = sys.argv[4] if len(sys.argv) > 4 else ""
    data, raw = load(log_path)

    frames = data["frames"]
    marks = {m["name"]: m["frame"] for m in data.get("marks", [])}
    rests = data.get("rests", [])
    if not frames:
        raise SystemExit("探针一帧都没采到")

    # ── 时间轴 ────────────────────────────────────────────────────────────
    has_ts = len(frames[0]) >= 3
    t0 = frames[0][2] if has_ts else 0.0
    ts = [f[2] - t0 for f in frames] if has_ts else [i * (1000 / 60) for i in range(len(frames))]
    span = max(ts[-1], 1.0)
    rasters = [f[1] for f in frames]
    builds = [f[0] for f in frames]

    # 纵轴**故意收到 40ms**：这一条要回答的是"有没有越过 16ms 那条线"，
    # 让几个 200ms 的尖峰把 0–16ms 压成一条缝，图就白画了。
    # 超出的值夹在顶边（画成小三角），真实最大值写在右上角的统计里。
    y_max = 40.0
    x_of = lambda t: PAD_L + (W - PAD_L - PAD_R) * (t / span)
    y_of = lambda ms: H - PAD_B - (H - PAD_T - PAD_B) * (min(ms, y_max) / y_max)

    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    # 纵向网格（每 10 秒）
    step_ms = 10000
    t = 0
    while t <= span:
        x = x_of(t)
        d.line([(x, PAD_T), (x, H - PAD_B)], fill=GRID)
        d.text((x - 22, H - PAD_B + 8), f"{t/1000:.0f}s", font=font(20), fill=TEXT3)
        t += step_ms

    # 横向网格
    for ms in range(0, int(y_max) + 1, 8):
        y = y_of(ms)
        d.line([(PAD_L, y), (W - PAD_R, y)], fill=GRID)
        d.text((PAD_L - 62, y - 11), f"{ms}ms", font=font(18), fill=TEXT3)

    # 预算线
    yb = y_of(16)
    for x in range(PAD_L, W - PAD_R, 18):
        d.line([(x, yb), (x + 9, yb)], fill=BUDGET, width=2)
    d.text((W - PAD_R - 250, yb - 30), "16ms = 60Hz 一帧的预算", font=font(20), fill=BUDGET)

    # 休息窗口底色
    for i, (a, b) in enumerate(rests):
        if a >= len(frames) or b <= a:
            continue
        xa, xb = x_of(ts[a]), x_of(ts[min(b, len(frames) - 1)])
        d.rectangle([xa, PAD_T, max(xb, xa + 2), H - PAD_B], fill=(26, 34, 30))
        if xb - xa > 70:
            d.text((xa + 8, PAD_T + 10), f"休息 {i+1}", font=font(20), fill=SUCCESS)

    # 帧点
    for i, t in enumerate(ts):
        x = x_of(t)
        d.line([(x, y_of(builds[i])), (x, y_of(rasters[i]))], fill=BUILD, width=1)
        yr = y_of(rasters[i])
        if rasters[i] > y_max:  # 夹在顶边的那些：画一个小三角，别让人以为它是 40ms
            d.polygon([(x - 4, yr + 8), (x + 4, yr + 8), (x, yr)], fill=RASTER)
        else:
            d.ellipse([x - 1.6, yr - 1.6, x + 1.6, yr + 1.6], fill=RASTER)

    # 段标记
    seg_colors = {"cold_start_begin": ACCENT, "tab_taps_begin": BUDGET,
                  "workout_begin": SUCCESS}
    label_y = {}
    for name, frame in marks.items():
        if frame >= len(ts) or name not in seg_colors:
            continue
        x = x_of(ts[frame])
        d.line([(x, PAD_T), (x, H - PAD_B)], fill=seg_colors[name], width=2)
        # 标签竖着往下排（三段的起点挨得近，同一行会互相压住）
        slot = len(label_y)
        label_y[slot] = PAD_T + 8 + slot * 30
        d.text((x + 6, label_y[slot]), name.replace("_begin", ""), font=font(19),
               fill=seg_colors[name])

    # 标题与统计
    d.text((PAD_L, 22), "练了么 · 帧率探针", font=font(40), fill=TEXT)
    if subtitle:
        d.text((PAD_L, 74), subtitle, font=font(24), fill=TEXT2)

    srt = sorted(rasters)
    def pct(p):
        return srt[min(len(srt) - 1, int(len(srt) * p))]
    rest_worst = data.get("rest_worst_raster_ms")
    stats = [
        f"帧数 {len(frames)}    时长 {span/1000:.1f}s",
        f"raster  p50 {pct(0.5):.1f}ms   p95 {pct(0.95):.1f}ms   最大 {max(rasters):.1f}ms",
        f"build   p50 {sorted(builds)[len(builds)//2]:.1f}ms   最大 {max(builds):.1f}ms",
        f"休息窗口 {data.get('rest_frame_count')} 帧，最差 raster "
        f"{rest_worst:.1f}ms（帧号 {data.get('rest_worst_frame')}）" if rest_worst is not None
        else "休息窗口未采到",
    ]
    d.rectangle([W - PAD_R - 740, 92, W - PAD_R, 96 + len(stats) * 28 + 6], fill=BG)
    for i, line in enumerate(stats):
        d.text((W - PAD_R - 720, 100 + i * 28), line, font=font(21), fill=TEXT2)

    if note:
        d.text((PAD_L, H - 84), note, font=font(20), fill=TEXT2)
    d.text((PAD_L, H - 52),
           "横轴 = 时间（FrameTiming.timestampInMicroseconds）；点 = raster 时长，浅色竖线 = build 时长。"
           + ("" if has_ts else " ⚠️ 日志里没有时间戳列，横轴退化成帧号 × 16.67ms。"),
           font=font(19), fill=TEXT3)

    img.save(out_path)
    print(f"✓ {out_path}（{img.size[0]}×{img.size[1]}）")

    # 顺带把结论打到终端（门禁/报告里要引用这几个数）
    print(f"  帧数 {len(frames)}，raster p50 {pct(0.5):.2f}ms / p95 {pct(0.95):.2f}ms / max {max(rasters):.2f}ms")
    print(f"  休息窗口 {data.get('rest_frame_count')} 帧，最差 raster {rest_worst}ms")


if __name__ == "__main__":
    main()
