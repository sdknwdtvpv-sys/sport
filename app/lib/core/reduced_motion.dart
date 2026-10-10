/// 练了么 · **减弱动态效果**（`prefers-reduced-motion`）的唯一读取点
/// （2026-10-10，VI 计划 T1-4；方案见 `docs/vi-proposal-d-motion-2026-10-10.md` §五）
///
/// **它为什么存在**：`docs/interaction-spec.md` §12 的验收清单里挂着一条
/// 「`prefers-reduced-motion` 下无动效残留」，而全仓 `disableAnimations` **0 命中** ——
/// 那条验收从来没有对象（因为没有动效，也就无所谓残留）。
/// 批次 2 要把动效做起来，所以**先把这个开关建好**：一处读取、传到底。
///
/// ## 两条纪律
///
/// 1. **用 `MediaQuery.disableAnimationsOf(context)`**，不要用
///    `MediaQuery.of(context).disableAnimations` —— 前者是 Flutter 3.10+ 的正确 API
///    （含默认值处理），后者在测试里造数据时容易被写成"忘了给"。
/// 2. **不许任何页面自己写 `if (disableAnimations)`** —— 那一定会漏掉某几处。
///    页面只调 `Motion.forContext(context, Motion.base)`。
///
/// ## 降级拿走的是"运动"，不是"信息"
///
/// 一条判据可以判所有条目：**关掉动画之后，用户是否还能知道"发生了什么"？**
/// 答案是"不知道"的，那一条就不能全关。最典型的是训练屏与完成页：
///    * 训练屏：休息进度条的**宽度变化**要保留（改成每秒一格直接跳）、颜色切换瞬时完成、
///      **全部触觉保留** —— 训练屏是唯一"用户不看屏幕"的场景，
///      在减弱动态效果下把触觉也降掉，等于把这个产品对这类用户关掉；
///    * 完成页：**画满的勾、三个数字的终值、「✦ 新解锁」整块、全部触觉**一件都不能少 ——
///      减弱动态效果 ≠ 这次训练完成得没那么好。
library;

import 'package:flutter/widgets.dart';

/// 用户是否要求"减弱动态效果"。
///
/// ⚠️ 读的是 `MediaQuery.disableAnimationsOf`（iOS 的"减弱动态效果"、
/// Android 的"移除动画"、以及 Flutter 在 `accessibleNavigation` 下给同一套降级）。
bool reducedMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

/// 给不方便拿 `BuildContext` 的地方（纯函数、测试夹具）一个显式入口。
///
/// 页面里**不要**用它 —— 页面一律走 `Motion.forContext(context, …)`。
Duration reducedOr(bool reduce, Duration d) => reduce ? Duration.zero : d;
