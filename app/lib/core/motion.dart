/// 练了么 · **动效令牌**（2026-10-10，VI 计划 T1-4；方案见 `docs/vi-proposal-d-motion-2026-10-10.md` §二）
///
/// **它为什么存在**：全仓 `AnimationController` **0 个**、`Tween` **0 个**、`Curves.` **2 处**、
/// 真正的 UI 时长只有 2 个数字 —— 而 `docs/interaction-spec.md` §8 已经写了 5 条动效规格。
/// **规格书上的动效是写给一个不存在的实现的。** 这个文件把"档位"先立起来：
/// 时长五档 + 两个专用值、曲线四档 + 一个原生弹簧，**所有动效只许从这里取值**。
///
/// ## 两条纪律（写在这里，因为它们是这个文件存在的理由）
///
/// 1. **一个动效写不出它属于哪一档，就说明这个动效不该存在。**
/// 2. **有 `reduced_motion.dart` 那一个开关**：所有时长经过 [forContext] 短路。
///    不许任何页面自己写 `if (disableAnimations)` —— 那一定会漏掉某几处
///    （今天全仓 0 处，所以从 0 建规矩比从 137 处收口便宜得多）。
library;

import 'package:flutter/widgets.dart';

import 'reduced_motion.dart';

/// 动效的**所有**时长与曲线。
///
/// 与 `Tokens` 并列，是它的兄弟 —— `Tokens` 管"看起来什么样"，`Motion` 管"怎么动"。
abstract final class Motion {
  // ── 时长（5 档 + 2 个专用值）─────────────────────────────────────────

  /// **100ms** —— 按下态、触觉的视觉锚点、**颜色类变化**。
  ///
  /// ⚠️ 这一档**不要动**：60Hz 下 100ms ≈ 6 帧，是一只手能分辨"有反应"与"没反应"的下限，
  /// 它已经贴着感知阈值的上沿。98 或 104 都不必。
  static const Duration instant = Duration(milliseconds: 100);

  /// **180ms** —— 松手回弹、局部小元素（≤24pt）入场、未读点出现。
  static const Duration fast = Duration(milliseconds: 180);

  /// **260ms** —— **默认档**：同屏内的位移、弹层入场、卡片/横条入场、新行入场。
  static const Duration base = Duration(milliseconds: 260);

  /// **400ms** —— "到达"类（PR 徽章）、数字滚动、进度填充、面积图形变。
  static const Duration slow = Duration(milliseconds: 400);

  /// **600ms** —— **只给"训练完成那一刻"的数字计数**（一屏一次）。
  ///
  /// 它不是"第六档时长"，是**编排里的一个节拍**：600ms 是读一个 3–4 位数从 0 滚到终值、
  /// 眼睛来得及跟上的最长值；再长就变成"等它"。
  static const Duration celebrate = Duration(milliseconds: 600);

  /// **1000ms** —— 休息条那一根进度条的**线性补间**（见 [linear]）。
  ///
  /// 它不是"慢"，它是"把每秒一跳的离散值补成连续运动"：
  /// 倒计时的真源是 Timer（每秒一跳），视觉用这一档补上中间帧。
  static const Duration restTick = Duration(milliseconds: 1000);

  /// **300ms** —— 二级页的位移 + 淡入。
  ///
  /// 取值理由：iOS 系统 push 是 350ms、Material 是 300ms，**取 300 让两端都不觉得慢**；
  /// 而它必须与 `CupertinoPageTransitionsBuilder` 的返回手势共存
  /// （所以**不设** `pageTransitionsTheme`，见 `docs/plan-vi-2026-10-10.md` §8 问题 2 的裁决 B）。
  static const Duration pageTransition = Duration(milliseconds: 300);

  /// **1400ms** —— 完成页那条**时间轴**的总长（VI 计划 T2-3）。
  ///
  /// 为什么它是专用值而不是某一档：它是**一屏的叙事长度**（勾 420 → 标题 700 →
  /// 数字 1020 → 解锁 1200 → 完成键 1400），不是"某个元素动多久"。
  /// 五档管的是元素，它管的是**编排**；`Interval` 的切分点都按这个数算。
  static const Duration summaryTimeline = Duration(milliseconds: 1400);

  /// 上面那条时间轴的毫秒数（`Interval` 要的是 0..1 的切分点，用它算才不会两处写 1400）。
  static const int summaryTimelineMs = 1400;

  // ── 曲线（4 档 + 1 个 iOS 原生）──────────────────────────────────────

  /// **位置与尺寸的默认曲线** `(0.0, 0.55, 0.45, 1.0)`：无过冲、单调收敛。
  ///
  /// 比 `Curves.easeOutCubic` 前段更"给力"、比 `Curves.easeOutQuint` 尾段更"收得住"。
  /// `Curves` 里没有这一档，所以自己建一个。
  static const Cubic standard = Cubic(0.0, 0.55, 0.45, 1.0);

  /// **入场**（元素从无到有）`(0.16, 1.0, 0.30, 1.0)`：起点比 `easeOutQuint` 更缓 ——
  /// 于是"出现"看起来是**被放上去的**，不是"弹出来的"。
  static const Cubic enter = Cubic(0.16, 1.0, 0.30, 1.0);

  /// **出场**：与 `Curves.easeIn` 完全等价（它本来就是 `(0.42, 0, 1, 1)`）。
  ///
  /// 唯一纪律：**出场的时长必须是入场时长的 0.7 倍**（260 进 → 180 出）。
  /// 出场比入场慢 = 页面在"赖着不走"。
  static const Curve exit = Curves.easeIn;

  /// **"到达"类** `(0.34, 1.56, 0.64, 1.0)`：指示器落位、PR 徽章出现、新增组数字弹一下。
  /// 峰值过冲 **9.8%**（`motion_tokens_test.dart` 把这个数算出来钉住）。
  ///
  /// ⚠️ **只用于"到达"（元素已经在屏幕上、只是换位置/尺度），不用于"出现"** ——
  /// "从 0 放大到 1 并过冲"会在屏幕上留下一圈溢出的半透明边缘（`Transform.scale` 不裁剪）。
  static const Cubic arrival = Cubic(0.34, 1.56, 0.64, 1.0);

  /// **线性**：只给休息条那一条（见 [restTick]）。
  static const Curve linear = Curves.linear;

  /// **下压**（用户按住的那一下）：`Curves.easeOut`。
  static const Curve press = Curves.easeOut;

  // ── 降级 ────────────────────────────────────────────────────────────

  /// 把一档时长按"用户是否要求减弱动态效果"短路。
  ///
  /// **所有** `Duration` 都要过这一道：`Motion.forContext(context, Motion.base)`。
  /// 关掉动画之后拿到的是 [Duration.zero] —— 元素**直接出现在终态**，
  /// 而不是"消失"（降级拿走的是"运动"，不是"信息"）。
  static Duration forContext(BuildContext context, Duration d) =>
      reducedMotion(context) ? Duration.zero : d;
}
