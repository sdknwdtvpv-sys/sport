/// 练了么 · 给原生桥用的 `#RRGGBB`（2026-10-09）
///
/// 为什么单独一个文件：**两个原生门面都要它**（底栏的 `native_tab_bar.dart`、
/// 分段控件的 `native_segmented.dart`），而它们是同一层的东西 ——
/// 谁 import 谁都不合适，所以抬到一个只装"颜色转字符串"的小文件里。
///
/// ⚠️ 原生的 `GlassBridge` / `NativeTabBarBridge` / `NativeSegmentedBridge` 里
/// 各有一份解析它的 `color(_:)`，那是**平台侧**的同一个约定（`#RRGGBBAA`）；
/// 这一份是 **Dart 侧**的编码端。改一处要想着对面三处。
library;

import 'package:flutter/material.dart';

/// `Color` → `#RRGGBB`（原生按这个解析）
String hexOfColor(Color c) {
  final int v = c.toARGB32();
  final String r = ((v >> 16) & 0xFF).toRadixString(16).padLeft(2, '0');
  final String g = ((v >> 8) & 0xFF).toRadixString(16).padLeft(2, '0');
  final String b = (v & 0xFF).toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}
