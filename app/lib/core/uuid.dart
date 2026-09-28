/// 练了么 · 主键生成
///
/// `docs/data-model.md` 的全局约定是「**客户端生成 UUID 主键**」——
/// 多端同步时不能靠自增，也不能靠时间戳：两台设备在同一毫秒建记录会撞主键。
///
/// 这里手写 UUID v4 而不引 `uuid` 包：项目 pubspec 写着「依赖保持最小」，
/// 而生成 16 个随机字节并摆好版本位，不值得为它加一个依赖。
library;

import 'dart:math';

final Random _secureRandom = Random.secure();

/// 生成一个 UUID v4 字符串（如 `3f2b1c04-9a7e-4d21-b0f5-8c6e1a2d3b4c`）。
String newUuid() {
  final List<int> b = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // 版本 4
  b[8] = (b[8] & 0x3f) | 0x80; // 变体 10xx
  final String hex =
      b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// 带前缀的 UUID，方便在日志与调试里一眼看出这是哪种实体。
String newPrefixedId(String prefix) => '${prefix}_${newUuid()}';
