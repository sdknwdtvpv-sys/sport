/// 练了么 · **输入框的共用外观**（2026-10-10，VI 计划 T0-2）
///
/// **它为什么存在**：全仓有 7 个 `TextField`（计划名 / 身体数据四个 / 导入备份 / 搜索动作），
/// 它们的 `InputDecoration` 是**七份拷贝**，而且七份都写着同一句话：
/// `filled: true, fillColor: Tokens.surface, border: BorderSide.none`。
/// 于是"输入框看不见边界"这件事也被复制了七份 —— 搜索框底对页面只有 **1.10:1**、
/// 没有边框；未选中胶囊骑在卡片上时对卡片 **1.00:1**。
///
/// 这正是 `vi_cards.dart` 开头那条教训的同一种形态（"三十个页面就会有三十份卡片样式"）：
/// **一处外观、多处使用**，改一次全站跟着变。
///
/// ## 口径（与 `theme.dart` 的 [Tokens.field] 一起看）
///   * **填充** `Tokens.field`：对 `bg` 1.39:1、对 `surface` 1.27:1 —— "可分辨"就够；
///   * **边界** `Tokens.lineStrong`：对 `bg` 3.18:1 —— WCAG 1.4.11 要的是**边界** 3:1。
///
/// ⚠️ **聚焦态刻意不换成强调色**：换上去会让"一屏 accent ≤ 1"在多输入框的屏（身体数据页）
/// 直接破功，而聚焦时键盘已经弹出、光标已经在闪 —— 那个状态不需要再喊一次。
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 一个输入框该长什么样。各调用点只需要给 [hint] 与 [fontSize]。
///
/// [fill] 默认 [Tokens.field]；**卡片内部**想要"下沉的井"时传 `Tokens.bg`
/// （身体数据页的体重那个大数字框就是这种），但边界仍走 [Tokens.lineStrong]。
InputDecoration appFieldDecoration({
  String? hint,
  double fontSize = 15,
  EdgeInsetsGeometry? contentPadding,
  double radius = Tokens.rCard,
  Color fill = Tokens.field,
}) {
  OutlineInputBorder border() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: Tokens.lineStrong),
      );
  return InputDecoration(
    hintText: hint,
    // hint 是「这里能干什么」的唯一提示 → text2（不是 text3，见 VI 计划 T0-3）
    hintStyle: TextStyle(color: Tokens.text2, fontSize: fontSize),
    filled: true,
    fillColor: fill,
    contentPadding: contentPadding ??
        const EdgeInsets.symmetric(horizontal: Tokens.s4, vertical: Tokens.s3),
    border: border(),
    enabledBorder: border(),
    focusedBorder: border(),
  );
}
