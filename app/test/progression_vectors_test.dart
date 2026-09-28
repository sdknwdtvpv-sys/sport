/// 练了么 · Dart 引擎 vs 规范向量
///
/// **这份测试读的是仓库根目录的 `engine/vectors.json`，与 JS 端同一份文件，不复制。**
/// 这样"移植是否完成"就成了一个可判定的事实：本文件全绿 = Dart 与 JS 行为一致。
///
/// 移植时踩到的真实差异（说明共用向量是有意义的）：
///   Dart 打印 double 会输出 `2.0`，JS 输出 `2`，直接影响 reasonText 里的「+2kg」。
///   向量 `linear_progress_dumbbell` 恰好守着这一点。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/domain/progression.dart';

File _locateVectors() {
  const List<String> candidates = <String>[
    '../engine/vectors.json', // flutter test 的 CWD 是 app/
    'engine/vectors.json', // 万一从仓库根目录调用
  ];
  for (final String c in candidates) {
    final File f = File(c);
    if (f.existsSync()) return f;
  }
  fail('找不到 engine/vectors.json（当前目录 ${Directory.current.path}，找过 $candidates）');
}

class _Resolved {
  _Resolved(this.id, this.desc, this.suggestion, this.exercise);
  final String id;
  final String desc;
  final Suggestion? suggestion;
  final ExerciseSpec exercise;
}

void main() {
  final Map<String, dynamic> spec =
      jsonDecode(_locateVectors().readAsStringSync()) as Map<String, dynamic>;
  final Map<String, dynamic> fixtures = spec['fixtures'] as Map<String, dynamic>;
  final List<Map<String, dynamic>> vectors =
      (spec['vectors'] as List<dynamic>).cast<Map<String, dynamic>>();
  final List<Map<String, dynamic>> oneRmCases =
      (spec['oneRmCases'] as List<dynamic>).cast<Map<String, dynamic>>();

  // ⚠️ 这份映射与 tool/check_domain.dart 各有一份，加字段要两处同步（漏了会红）。
  ExerciseSpec exerciseOf(String key) {
    final Map<String, dynamic> f = fixtures[key] as Map<String, dynamic>;
    return ExerciseSpec(
      id: f['id'] as String,
      weightIncrement: (f['weight_increment'] as num).toDouble(),
      defaultWeightKg: (f['default_weight_kg'] as num?)?.toDouble(),
      // 缺省 weight_reps：没有这个字段的 fixture 行为完全不变
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

  _Resolved run(Map<String, dynamic> v) {
    final Map<String, dynamic> input = v['input'] as Map<String, dynamic>;
    final ExerciseSpec exercise = exerciseOf(input['exercise'] as String);
    final PlanTarget plan = planOf(input['plan'] as String);

    final Map<String, dynamic>? ls = input['lastSession'] as Map<String, dynamic>?;
    final LastSession? lastSession = ls == null
        ? null
        : LastSession(
            weightKg: (ls['weight_kg'] as num?)?.toDouble(),
            reps: (ls['reps'] as List<dynamic>)
                .map((dynamic e) => (e as num).toInt())
                .toList(),
            daysAgo: (ls['daysAgo'] as num?)?.toInt() ?? 0,
          );

    final Map<String, dynamic>? p = input['profile'] as Map<String, dynamic>?;
    final UserProfile profile =
        UserProfile(progressionMode: ProgressionMode.fromWire(p?['progression_mode'] as String?));

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
    return _Resolved(v['id'] as String, v['desc'] as String, s, exercise);
  }

  group('规范向量（与 JS 共用 engine/vectors.json）', () {
    for (final Map<String, dynamic> v in vectors) {
      test('${v['id']} —— ${v['desc']}', () {
        final _Resolved r = run(v);
        final Object? expected = v['expect'];

        if (expected == null) {
          expect(r.suggestion, isNull, reason: '该向量期望"不给建议"');
          return;
        }

        final Map<String, dynamic> e = expected as Map<String, dynamic>;
        final Suggestion s = r.suggestion!;

        expect(s.weightKg, (e['weight_kg'] as num?)?.toDouble(), reason: 'weight_kg');
        expect(s.reps, (e['reps'] as num).toInt(), reason: 'reps');
        expect(s.reasonCode.wire, e['reason_code'] as String, reason: 'reason_code');

        final String? includes = e['text_includes'] as String?;
        if (includes != null) {
          expect(s.reasonText, contains(includes), reason: 'reason_text 应包含「$includes」');
        }
        expect(s.reasonText.trim(), isNotEmpty, reason: '红线：建议必须能自我解释');
      });
    }
  });

  group('跨用例硬红线', () {
    test('任何非 null 的建议都必须带非空理由（解释不了的建议不许出现）', () {
      final List<String> mute = <String>[];
      for (final Map<String, dynamic> v in vectors) {
        final Suggestion? s = run(v).suggestion;
        if (s != null && s.reasonText.trim().isEmpty) mute.add(v['id'] as String);
      }
      expect(mute, isEmpty, reason: '这些向量给出了没有理由的建议：$mute');
    });

    test('自重动作永不 linear_progress，且重量恒为 null', () {
      final List<String> bad = <String>[];
      for (final Map<String, dynamic> v in vectors) {
        final _Resolved r = run(v);
        if (!r.exercise.isBodyweight || r.suggestion == null) continue;
        if (r.suggestion!.reasonCode == ReasonCode.linearProgress) {
          bad.add('${r.id}(linear_progress)');
        }
        if (r.suggestion!.weightKg != null) {
          bad.add('${r.id}(weight=${r.suggestion!.weightKg})');
        }
      }
      expect(bad, isEmpty, reason: '自重动作走了加重量路径：$bad');
    });
  });

  group('1RM 估算边界（用例同样来自 vectors.json）', () {
    for (final Map<String, dynamic> c in oneRmCases) {
      test('estimate1RM(${c['weight_kg']}, ${c['reps']}) —— ${c['desc']}', () {
        final double? got = estimate1RM(
          (c['weight_kg'] as num).toDouble(),
          (c['reps'] as num).toInt(),
        );
        expect(got, (c['expect'] as num?)?.toDouble());
      });
    }
  });
}
