/// 练了么 · **消息的种类长什么样**（图标 / 颜色）
///
/// 抽出来是因为它现在有**两个渲染点**：通知中心列表里那一排小方块，与消息详情页顶部
/// 那一格。2026-10-07 之前这两处是各写一份的（详情页那会儿是弹层里的一份私有函数）——
/// 同一件事有两份实现，早晚会出现"列表里是奖杯、详情里变成云"这种漂移。
///
/// ⚠️ 颜色**只说种类**，不说"好坏"：备份失败也是这个颜色（失败那条看正文就够了，
/// 把失败画成红色会让整列消息都在喊）。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/notification_repository.dart';

/// 这一类消息的图标。
IconData iconForKind(String kind) => switch (kind) {
      NotificationKind.achievement => Icons.emoji_events_outlined,
      NotificationKind.reminder => Icons.alarm,
      _ => Icons.cloud_outlined,
    };

/// 这一类消息的图标颜色。
Color colorForKind(String kind) => switch (kind) {
      NotificationKind.achievement => Tokens.pr,
      NotificationKind.reminder => Tokens.accent,
      _ => Tokens.success,
    };
