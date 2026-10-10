/// 练了么 · **图标规格**（2026-10-10，VI 计划 T1-3；方案见 `docs/vi-proposal-c-brand-2026-10-10.md` §3.1）
///
/// **它为什么存在**：改这一条之前，全仓 **112 个互不相同的字形、12 个尺寸值**，
/// 同一个火焰在 6 个地方指 6 件事，同一个"换"在 3 屏用了 `refresh` / `swap_horiz` / `shuffle`
/// 三个隐喻 —— **图标不是装饰，是动词的缩写**：用户第二次看到火焰时如果它指的是"首训徽章"、
/// 第三次指"连续 2 天"，那它第 N 次就什么都不指了。
///
/// 这个文件立两条规矩：
///
/// 1. **尺寸只有 4 档**（[IconSpec]）：`s 16 / m 20 / l 24 / xl 40`。
///    原来那 12 个值（11/14/15/16/18/19/20/22/23/26/30/42）里有 4 组只差 1pt ——
///    那不是设计，那是每次现场决定的产物。
/// 2. **语义只有这张表**（[kIconSemantics]）：一个语义一个**规范图形**，
///    两台（Material / SF Symbol）**成对**写在同一条记录里。
///
/// ⚠️ **与方案文档的两处出入（都在这里说清）**：
///   * 方案要的是 `kIconSemantics` + 另一个独立的 `kSfSymbolPairs` 两份常量数组，
///     然后断言"两者长度相等"。**两份数组正是漂移的来源**（加了一台忘另一台，
///     长度还不等就会崩）—— 所以这里**只有一份表**，SF Symbol 那一份由
///     [kSfSymbols] 派生。判据更强：长度天然相等，且每条都必须**两台都有**。
///   * 方案点名的 `Icons.exercise`（今天/开练）与 `Icons.trophy`（破纪录）
///     在 Flutter 的 Material 图标集里**不存在**（本机 Flutter 实测）。
///     所以：今天/开练用 `fitness_center`（哑铃，与 SF `dumbbell.fill` 同形），
///     破纪录用 `workspace_premium`（与「我」页的段位同族，但语义不同屏）。
library;

import 'package:flutter/material.dart';

/// **图标尺寸只有 4 档**。
///
/// | 档 | 值 | 什么时候用 |
/// |---|---|---|
/// | [s] | 16 | 与文字同排的行内小图标（单位、提示、行尾） |
/// | [m] | 20 | **默认**：列表行、按钮、顶栏两枚动作 |
/// | [l] | 24 | 底栏那一格、需要强调的图标 |
/// | [xl] | 40 | 英雄位：完成页那颗勾、引导页的主图形 |
abstract final class IconSpec {
  static const double s = 16;
  static const double m = 20;
  static const double l = 24;
  static const double xl = 40;

  /// 四档的**全部取值**（守卫测试按它扫全仓）。
  static const List<double> values = <double>[s, m, l, xl];
}

/// 一条语义：**一个名字、两台配对**。
typedef IconSemantic = ({String name, IconData material, String sf});

/// **语义映射表**：一个语义一个规范图形。
///
/// 加一条时要同时给 Material 与 SF —— 少给一台编译不过（这也是"成对"的意思）。
/// ⚠️ 这张表是**规范**，不是"全部图标"：装饰性/一次性的图形不必进来，
/// 但**凡是同一个动作出现在两屏以上，就必须收敛到同一条**。
const List<IconSemantic> kIconSemantics = <IconSemantic>[
  // ── 三格底栏（也是三个一级页的名字）────────────────────────────────
  (name: 'today', material: Icons.fitness_center, sf: 'dumbbell.fill'),
  (name: 'progress', material: Icons.trending_up, sf: 'chart.line.uptrend.xyaxis'),
  (name: 'profile', material: Icons.person, sf: 'person'),
  // ── 激励（`badges.dart` 的分区、进步页、分享卡）────────────────────
  (name: 'streak', material: Icons.local_fire_department, sf: 'flame'),
  (name: 'volume', material: Icons.bolt, sf: 'bolt'),
  (name: 'milestone', material: Icons.emoji_events, sf: 'trophy'),
  (name: 'explore', material: Icons.explore, sf: 'safari'),
  (name: 'pr', material: Icons.workspace_premium, sf: 'trophy.fill'),
  // ── 动作（"给我别的"只有一个符号：`refresh`）──────────────────────
  (name: 'swap', material: Icons.refresh, sf: 'arrow.clockwise'),
  (name: 'swapExercise', material: Icons.swap_horiz, sf: 'arrow.left.arrow.right'),
  (name: 'back', material: Icons.chevron_left, sf: 'chevron.left'),
  (name: 'more', material: Icons.chevron_right, sf: 'chevron.right'),
  (name: 'next', material: Icons.arrow_forward, sf: 'arrow.right'),
  // ── 状态与工具 ────────────────────────────────────────────────────
  (name: 'check', material: Icons.check, sf: 'checkmark'),
  (name: 'close', material: Icons.close, sf: 'xmark'),
  (name: 'rest', material: Icons.timer, sf: 'timer'),
  (name: 'bell', material: Icons.notifications, sf: 'bell'),
  (name: 'settings', material: Icons.settings, sf: 'gearshape'),
  (name: 'search', material: Icons.search, sf: 'magnifyingglass'),
  (name: 'searchEmpty', material: Icons.search_off, sf: 'magnifyingglass'),
  (name: 'weight', material: Icons.monitor_weight, sf: 'scalemass'),
  (name: 'pin', material: Icons.push_pin, sf: 'pin'),
  (name: 'edit', material: Icons.edit, sf: 'pencil'),
  (name: 'share', material: Icons.ios_share, sf: 'square.and.arrow.up'),
  (name: 'trash', material: Icons.delete_outline, sf: 'trash'),
  (name: 'info', material: Icons.info_outline, sf: 'info.circle'),
  (name: 'plan', material: Icons.event_note, sf: 'calendar'),
  (name: 'library', material: Icons.menu_book, sf: 'books.vertical'),
  (name: 'light', material: Icons.timer_outlined, sf: 'timer'),
  (name: 'history', material: Icons.history, sf: 'clock.arrow.circlepath'),
  (name: 'undo', material: Icons.undo, sf: 'arrow.uturn.backward'),
];

/// 按名字取规范图形。**名字写错要当场炸**（不许静默给一个默认图标 ——
/// 那会让"图标指错事"这类 bug 一路溜到用户面前）。
IconData iconOf(String name) {
  for (final IconSemantic s in kIconSemantics) {
    if (s.name == name) return s.material;
  }
  throw ArgumentError('图标语义表里没有「$name」—— 请先在 icon_spec.dart 里登记它');
}

/// 按名字取 SF Symbol（iOS 原生底栏用）。
String sfSymbolOf(String name) {
  for (final IconSemantic s in kIconSemantics) {
    if (s.name == name) return s.sf;
  }
  throw ArgumentError('图标语义表里没有「$name」—— 请先在 icon_spec.dart 里登记它');
}

/// **派生**出来的 SF Symbol 列表（顺序与 [kIconSemantics] 一致）。
///
/// ⚠️ 不另外维护一份：两份数组长度不同会崩、**语义错位没有任何东西会发现**。
List<String> get kSfSymbols =>
    <String>[for (final IconSemantic s in kIconSemantics) s.sf];

/// Material 侧的列表（同样派生，供需要"两串一一对应"的地方用）。
List<IconData> get kMaterialIcons =>
    <IconData>[for (final IconSemantic s in kIconSemantics) s.material];
