// 练了么 · 纯 Dart 领域校验器（零依赖，不需要 pub get）
//
//   用法（从仓库任意位置）：
//     dart app/tool/check_domain.dart
//     $HOME/development/flutter/bin/cache/dart-sdk/bin/dart app/tool/check_domain.dart
//
// 为什么需要这个文件：
//   `flutter test` 必须先跑通 `flutter pub get`，而 pub 在受限环境里会失败
//   （临时目录清理被拦、pub.dev 不可达）。但领域层是**纯 Dart、零 package 依赖**的，
//   所以可以用 SDK 自带的 dart 直接验证 —— 最关键的那条主张
//   （Dart 引擎与 JS 引擎行为一致）不必依赖 pub 就能被证实。
//
// 覆盖：
//   1. engine/vectors.json 的 28 条向量（与 JS 端同一份文件）
//   2. 3 条跨用例硬红线
//   3. 4 条 1RM 估算边界
//   4. 8 条 tap_count 边界（与 test/tap_meter_test.dart 同源）
//
// widget 测试无法在这里跑（需要 Flutter 测试框架），见 app/test/workout_flow_test.dart。

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import '../lib/domain/models.dart';
import '../lib/domain/progression.dart';
import '../lib/domain/tap_meter.dart';

const String _line = '────────────────────────────────────────────────────────────────────────';

int _passed = 0;
final List<String> _failures = <String>[];

void _check(String name, bool ok, [String? detail]) {
  if (ok) {
    _passed++;
  } else {
    _failures.add(detail == null ? name : '$name\n      $detail');
  }
}

bool _eqNum(num? a, num? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return (a.toDouble() - b.toDouble()).abs() < 1e-9;
}

File _vectorsFile() {
  final Directory scriptDir = File.fromUri(Platform.script).parent; // app/tool
  final String repoRoot = scriptDir.parent.parent.path; // 仓库根
  final List<File> candidates = <File>[
    File('$repoRoot/engine/vectors.json'),
    File('../engine/vectors.json'),
    File('engine/vectors.json'),
  ];
  for (final File f in candidates) {
    if (f.existsSync()) return f;
  }
  stderr.writeln('找不到 engine/vectors.json（找过 ${candidates.map((File f) => f.path).join(", ")}）');
  exit(2);
}

class _Outcome {
  _Outcome(this.id, this.suggestion, this.exercise);
  final String id;
  final Suggestion? suggestion;
  final ExerciseSpec exercise;
}

void main() {
  final Map<String, dynamic> spec =
      jsonDecode(_vectorsFile().readAsStringSync()) as Map<String, dynamic>;
  final Map<String, dynamic> fixtures = spec['fixtures'] as Map<String, dynamic>;
  final List<Map<String, dynamic>> vectors =
      (spec['vectors'] as List<dynamic>).cast<Map<String, dynamic>>();
  final List<Map<String, dynamic>> oneRmCases =
      (spec['oneRmCases'] as List<dynamic>).cast<Map<String, dynamic>>();

  // ⚠️ fixture → ExerciseSpec 的映射**这里和 test/progression_vectors_test.dart 各有一份**
  // （JS 那边直接读 fixture，不需要映射）。加了新字段要两处同步 ——
  // 漏了会以"向量失败"的形式立刻暴露，不会悄悄算错（这正是同一套向量存在的意义）。
  ExerciseSpec exerciseOf(String key) {
    final Map<String, dynamic> f = fixtures[key] as Map<String, dynamic>;
    return ExerciseSpec(
      id: f['id'] as String,
      weightIncrement: (f['weight_increment'] as num).toDouble(),
      defaultWeightKg: (f['default_weight_kg'] as num?)?.toDouble(),
      trackType: (f['track_type'] as String?) ?? 'weight_reps',
    );
  }

  PlanTarget planOf(String key) {
    final Map<String, dynamic> f = fixtures[key] as Map<String, dynamic>;
    return PlanTarget(
      targetSets: (f['target_sets'] as num).toInt(),
      targetRepsLow: (f['target_reps_low'] as num).toInt(),
      targetRepsHigh: (f['target_reps_high'] as num).toInt(),
    );
  }

  _Outcome run(Map<String, dynamic> v) {
    final Map<String, dynamic> input = v['input'] as Map<String, dynamic>;
    final ExerciseSpec exercise = exerciseOf(input['exercise'] as String);
    final PlanTarget plan = planOf(input['plan'] as String);

    final Map<String, dynamic>? ls = input['lastSession'] as Map<String, dynamic>?;
    final LastSession? lastSession = ls == null
        ? null
        : LastSession(
            weightKg: (ls['weight_kg'] as num?)?.toDouble(),
            reps: (ls['reps'] as List<dynamic>).map((dynamic e) => (e as num).toInt()).toList(),
            daysAgo: (ls['daysAgo'] as num?)?.toInt() ?? 0,
          );

    final Map<String, dynamic>? pf = input['profile'] as Map<String, dynamic>?;
    final UserProfile profile =
        UserProfile(progressionMode: ProgressionMode.fromWire(pf?['progression_mode'] as String?));

    final List<ManualOverride> overrides = ((input['overrides'] as List<dynamic>?) ?? <dynamic>[])
        .cast<Map<String, dynamic>>()
        .map((Map<String, dynamic> o) => ManualOverride(
              weightKg: (o['weight_kg'] as num).toDouble(),
              reps: (o['reps'] as num).toInt(),
            ))
        .toList();

    final Suggestion? s = suggestNext(
      exercise: exercise,
      plan: plan,
      lastSession: lastSession,
      profile: profile,
      overrides: overrides,
    );
    return _Outcome(v['id'] as String, s, exercise);
  }

  print(_line);
  print('Dart 领域校验：${vectors.length} 条向量 + 3 条红线 + ${oneRmCases.length} 条 1RM 边界 + 8 条 tap_count 边界');
  print(_line);

  // ── 1. 规范向量 ──────────────────────────────────────────────────────
  final List<_Outcome> outcomes = <_Outcome>[];
  for (final Map<String, dynamic> v in vectors) {
    final _Outcome r = run(v);
    outcomes.add(r);
    final Object? expected = v['expect'];
    final String id = v['id'] as String;

    if (expected == null) {
      _check(id, r.suggestion == null, '期望"不给建议"，实际 ${r.suggestion?.reasonText}');
      continue;
    }
    final Map<String, dynamic> e = expected as Map<String, dynamic>;
    final Suggestion? s = r.suggestion;
    if (s == null) {
      _check(id, false, '期望一条建议，实际 null');
      continue;
    }
    final List<String> problems = <String>[];
    if (!_eqNum(s.weightKg, e['weight_kg'] as num?)) {
      problems.add('weight_kg 期望 ${e['weight_kg']}，实际 ${s.weightKg}');
    }
    if (s.reps != (e['reps'] as num).toInt()) {
      problems.add('reps 期望 ${e['reps']}，实际 ${s.reps}');
    }
    if (s.reasonCode.wire != e['reason_code']) {
      problems.add('reason_code 期望 ${e['reason_code']}，实际 ${s.reasonCode.wire}');
    }
    final String? includes = e['text_includes'] as String?;
    if (includes != null && !s.reasonText.contains(includes)) {
      problems.add('reason_text 未包含「$includes」，实际「${s.reasonText}」');
    }
    if (s.reasonText.trim().isEmpty) {
      problems.add('reason_text 为空');
    }
    _check(id, problems.isEmpty, problems.join('\n      '));
  }

  // ── 2. 跨用例硬红线（与 JS 端 run-tests.mjs 的三条一一对应） ──────────
  final List<String> mute = <String>[];
  final List<String> bwLinear = <String>[];
  final List<String> bwWeight = <String>[];
  for (final _Outcome o in outcomes) {
    final Suggestion? s = o.suggestion;
    if (s == null) continue;
    if (s.reasonText.trim().isEmpty) mute.add(o.id);
    if (o.exercise.isBodyweight) {
      if (s.reasonCode == ReasonCode.linearProgress) bwLinear.add(o.id);
      if (s.weightKg != null) bwWeight.add('${o.id}(weight=${s.weightKg})');
    }
  }
  final bool okMute = mute.isEmpty;
  final bool okBwLinear = bwLinear.isEmpty;
  final bool okBwWeight = bwWeight.isEmpty;
  if (okMute) _passed++;
  if (okBwLinear) _passed++;
  if (okBwWeight) _passed++;

  // ── 3. 1RM 边界 ─────────────────────────────────────────────────────
  for (final Map<String, dynamic> c in oneRmCases) {
    final double? got = estimate1RM(
      (c['weight_kg'] as num).toDouble(),
      (c['reps'] as num).toInt(),
    );
    _check(
      'estimate1RM(${c['weight_kg']}, ${c['reps']})',
      _eqNum(got, c['expect'] as num?),
      '期望 ${c['expect']}，实际 $got —— ${c['desc']}',
    );
  }

  // ── 4. tap_count 边界（与 test/tap_meter_test.dart 同源） ─────────────
  {
    final TapMeter m = TapMeter()..begin();
    m.tap(TapKind.bigButton);
    _check('tap_count: 点一次 = 1', m.flush().count == 1);

    final TapMeter m2 = TapMeter()..begin();
    m2.tap(TapKind.longPress);
    m2.tap(TapKind.stepper);
    m2.tap(TapKind.sheetConfirm);
    m2.tap(TapKind.bigButton);
    final TapMeterReading r2 = m2.flush();
    _check('tap_count: 长按→步进→确定→记录 = 4', r2.count == 4, '实际 ${r2.count}');
    final String kindWires = r2.kinds.map((TapKind k) => k.wire).join(',');
    _check(
      'tap_count: kinds 顺序正确',
      kindWires == 'long_press,stepper,sheet_confirm,big_button',
      '实际 $kindWires',
    );

    final TapMeter m3 = TapMeter()..begin();
    m3.tap(TapKind.longPress);
    m3.tap(TapKind.sheetConfirm);
    m3.tap(TapKind.bigButton);
    _check('tap_count: 长按→确定→记录 = 3', m3.flush().count == 3);

    final TapMeter m4 = TapMeter();
    m4.begin();
    m4.tap(TapKind.bigButton);
    final int first = m4.flush().count;
    m4.begin();
    m4.tap(TapKind.bigButton);
    final int second = m4.flush().count;
    _check('tap_count: 连点两次各自为 1', first == 1 && second == 1, '实际 $first / $second');

    final TapMeter m5 = TapMeter()..begin();
    m5.tap(TapKind.bigButton);
    m5.flush();
    m5.tap(TapKind.stepper); // 周期外，必须被忽略
    _check('tap_count: 周期外点击被忽略', m5.pending == 0 && !m5.isActive);

    // 端到端口径的关键：控制器构造时用 ensure() 接住已有周期，**不能清零**。
    // 清零了，"开始训练 / 选动作"那几下导航点击就丢了 —— 第一组又会变回"只算大按钮"。
    // （这两条是变异测试抓出来的：把 ensure 的守卫去掉，上面 6 条一条都不会红。）
    final TapMeter m6 = TapMeter()..begin();
    m6.tap(TapKind.nav);
    m6.tap(TapKind.nav);
    m6.ensure(); // ← 控制器构造那一下
    m6.tap(TapKind.bigButton);
    final TapMeterReading r6 = m6.flush();
    _check('tap_count: ensure 不清零已有周期', r6.count == 3,
        '实际 ${r6.count}（应为 2 次导航 + 1 次大按钮）');

    final TapMeter m7 = TapMeter()..ensure(); // 没开周期时 ensure 要开一个
    m7.tap(TapKind.bigButton);
    _check('tap_count: 周期没开时 ensure 自己开一个', m7.flush().count == 1);
  }

  // ── 输出 ────────────────────────────────────────────────────────────
  if (_failures.isNotEmpty) {
    print('\n✗ ${_failures.length} 项失败：\n');
    for (final String f in _failures) {
      print('  ✗ $f');
    }
  } else {
    print('\n✓ ${vectors.length} 条向量全部通过\n');
  }

  final int suggestionCount = outcomes.where((_Outcome o) => o.suggestion != null).length;
  print('不变量检查：');
  print('  ${okMute ? "✓" : "✗"} every_suggestion_explains_itself —— '
      '${okMute ? "$suggestionCount 条建议全部带理由" : mute.join(", ")}');
  print('  ${okBwLinear ? "✓" : "✗"} bodyweight_never_linear_progress —— '
      '${okBwLinear ? "自重动作全部走加次数路径" : bwLinear.join(", ")}');
  print('  ${okBwWeight ? "✓" : "✗"} bodyweight_never_returns_weight —— '
      '${okBwWeight ? "自重动作重量恒为 null" : bwWeight.join(", ")}');

  final Map<String, int> byCode = <String, int>{};
  for (final _Outcome o in outcomes) {
    final String? c = o.suggestion?.reasonCode.wire;
    if (c != null) byCode[c] = (byCode[c] ?? 0) + 1;
  }
  print('\nreason_code 覆盖：${byCode.entries.map((MapEntry<String, int> e) => "${e.key} ${e.value}").join(" · ")}');

  // 分母必须跟上面实际跑的检查数一致 —— 加检查时忘了改这里，就会打印出
  // 「52/50」这种账对不上的结果（这个坑刚踩过一次，所以算式下面加了注释）。
  final int total = vectors.length + 3 + oneRmCases.length + 8; // 8 条 tap_count 边界
  final int failed = _failures.length + (okMute ? 0 : 1) + (okBwLinear ? 0 : 1) + (okBwWeight ? 0 : 1);
  print('\n$_line');
  print(failed == 0 ? '✓ 全部通过（$_passed/$total）' : '✗ 失败 $failed/$total（通过 $_passed）');
  print(_line);
  exit(failed == 0 ? 0 : 1);
}
