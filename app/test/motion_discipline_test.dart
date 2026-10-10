/// 练了么 · **动效值的纪律**（VI 计划 T1-4）
///
/// **为什么要有它**：动效最容易变成"每个页面自己写一个 220ms 和一条随手挑的曲线"——
/// 而这个仓库已经有实况：全仓 `AnimationController` 0 个、`Curves.` 2 处、
/// 真 UI 时长只有 `220` 与 `260 + 90 × 距离`（一个规格外的算式）。
/// 所以：**所有时长与曲线只许来自 `Motion.*`**，例外按文件名写进 [exempt]。
///
/// ⚠️ 判据是"**扫描器 + 白名单 + 反向验过**"（与 `tool/check-user-text.mjs` 同一思路）：
/// 白名单里的文件允许出现字面量（它们不是动效），其余一律红。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **允许出现时长/曲线字面量的文件**（都不是"动效"）。每条都要写清理由 ——
/// 不然下一个人只会往里加一行。
const Map<String, String> exempt = <String, String>{
  'lib/features/workout/haptics.dart': '触觉的两次震动之间那个 120ms 间隔（节奏，不是动画）',
  'lib/domain/models.dart': '时长算术（end - startedAtMs，把毫秒数包成 Duration）',
  'lib/analytics/flusher.dart': '上报失败后的指数退避（网络策略，不是 UI）',
  // 令牌与开关自己就是定义处
  'lib/core/motion.dart': '动效令牌的定义处',
  'lib/core/reduced_motion.dart': '降级开关的定义处',
};

/// 一行里有没有"动效字面量"。
///
/// ⚠️ **先去掉行注释**：这个仓库的注释习惯是"把改之前的写法写进注释"
/// （我这一轮自己就这么写的），所以注释里出现 `Curves.easeOutCubic` 是**正常的**，
/// 不该被判红 —— 判的是**活代码**。
bool _hasMotionLiteral(String line) {
  final int i = line.indexOf('//');
  final String code = i < 0 ? line : line.substring(0, i);
  return code.contains('Duration(milliseconds:') || code.contains('Curves.');
}

/// 扫一份源码：返回命中行。**抽成纯函数是为了能反向验它**（见下面那条自检）。
List<String> scanMotionLiterals(Map<String, String> sources) {
  final List<String> out = <String>[];
  sources.forEach((String path, String src) {
    if (exempt.containsKey(path)) return;
    final List<String> lines = src.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (_hasMotionLiteral(lines[i])) out.add('$path:${i + 1}: ${lines[i].trim()}');
    }
  });
  return out;
}

Map<String, String> _readLib() {
  final Map<String, String> out = <String, String>{};
  for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    out[e.path.replaceAll('\\', '/')] = e.readAsStringSync();
  }
  return out;
}

void main() {
  test('★ 动效时长与曲线只来自 `Motion`（豁免名单见本文件顶部）', () {
    final List<String> bad = scanMotionLiterals(_readLib());
    expect(bad, isEmpty,
        reason: '这些地方还在自己写时长/曲线，改用 `Motion.*`：\n${bad.join('\n')}');
  });

  test('★ 反向自检：扫描器真的抓得住（一个从来没红过的守卫不可信）', () {
    final List<String> hits = scanMotionLiterals(<String, String>{
      'lib/features/whatever.dart': 'AnimatedContainer(\n'
          '  duration: const Duration(milliseconds: 220),\n'
          '  curve: Curves.easeOut,\n'
          ');\n',
    });
    expect(hits, hasLength(2), reason: '时长与曲线各一行，都该被抓到');
  });

  test('★ 豁免名单里的理由都必须非空', () {
    // 一条"没写理由"的豁免就是下一个人的通行证。
    for (final MapEntry<String, String> e in exempt.entries) {
      expect(e.value.trim(), isNotEmpty, reason: '${e.key} 的豁免理由不能为空');
      expect(File(e.key).existsSync(), isTrue, reason: '${e.key} 不存在了 —— 名单要跟着清');
    }
  });
}
