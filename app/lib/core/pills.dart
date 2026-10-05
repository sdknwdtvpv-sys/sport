/// 练了么 · **胶囊选项**（全 App 唯一的"选中"语言）
///
/// 为什么放在 `core/` 而不是某个 feature 里：它被三处用着 ——
/// 偏好设置（休息时长、单位）、计划编辑（组数、次数区间）、新建动作（部位/器械/类别）。
/// **2026-10-04 之前它是三份拷贝**，于是同一个 bug 也复制了三份（见下）。
///
/// ⚠️ **不要在它内部用 `Container(alignment: ...)`**（这是真踩过的坑）：
/// 带 `alignment` 的 Container 会**撑满拿到的约束**，而 `Wrap` 给子项的是**有界宽度**
/// （`Row` / 横向 `ListView` 给的是无界）。表现就是：同一个胶囊在「单位」那行是紧凑的，
/// 在「休息时长」那个 `Wrap` 里却**每个占一整行**，半个屏幕没了 ——
/// 而且**两个平台都一样**、也不报任何错。
/// 正确写法是 `Center(widthFactor: 1)`：按内容宽度收缩、同时把字居中。
/// `app/test/pill_layout_test.dart` 钉着这条（它直接测组件本身，不依赖任何页面）。
library;

import 'package:flutter/material.dart';

import 'theme.dart';

Widget choicePill({
  required String label,
  required bool active,
  required VoidCallback onTap,
  Key? key,
}) =>
    GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
        height: 36,
        decoration: BoxDecoration(
          color: active ? Tokens.volt : Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.rPill),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: TextStyle(
              color: active ? Tokens.voltInk : Tokens.text2,
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
