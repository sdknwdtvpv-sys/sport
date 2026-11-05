/// 练了么 · 周期化计划 v1 纯函数 + 仓储（Ultra 权益 10）
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/period_plan_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/domain/periodization.dart';

SetRecord _set({
  required String id,
  required String exerciseId,
  required int atMs,
  int reps = 8,
  double? weightKg = 60,
  SetType setType = SetType.normal,
}) =>
    SetRecord(
      id: id,
      workoutId: 'w_$id',
      exerciseId: exerciseId,
      setIndex: 1,
      reps: reps,
      completedAtMs: atMs,
      weightKg: weightKg,
      setType: setType,
    );

PeriodSessionSpec _spec(int day, int position, String exerciseId, {double? weight = 60, int week = 1}) =>
    PeriodSessionSpec(
      week: week,
      day: day,
      position: position,
      exerciseId: exerciseId,
      targetSets: 3,
      repsLow: 8,
      repsHigh: 10,
      targetWeightKg: weight,
    );

void main() {
  group('加重 / deload', () {
    test('普通周 +2.5%（2.5kg 步进）；第 4 周 deload -10%；之后回到正常线', () {
      expect(targetWeightForWeek(100, 1), 100);
      expect(targetWeightForWeek(100, 2), closeTo(102.5, 0.001));
      expect(targetWeightForWeek(100, 3), closeTo(105, 0.001));
      // 正常线到 W4 是 107.5；deload 显示 107.5 × 0.9 = 96.75 → 97.5
      expect(targetWeightForWeek(100, 4), closeTo(97.5, 0.001));
      // W5 回到正常线 110（不是从 97.5 往上爬）
      expect(targetWeightForWeek(100, 5), closeTo(110, 0.001));
      expect(targetWeightForWeek(100, 8), closeTo(105, 0.001)); // W8 deload
    });

    test('小重量也至少 +2.5kg；自重/按时长永远是 null（不编重量）', () {
      expect(targetWeightForWeek(5, 2), closeTo(7.5, 0.001));
      expect(targetWeightForWeek(null, 5), isNull);
      expect(targetWeightForWeek(0, 3), isNull);
      expect(isDeloadWeek(4), isTrue);
      expect(isDeloadWeek(8), isTrue);
      expect(isDeloadWeek(6), isFalse);
    });

    test('第 1 周模板展开：组数/次数不变、目标重量按周重算', () {
      final PeriodPlanSnapshot plan = PeriodPlanSnapshot(
        id: 'p1',
        name: 'x',
        weeks: 4,
        daysPerWeek: 3,
        startDate: DateTime(2026, 11, 2),
        currentWeek: 1,
        status: PeriodPlanStatus.active,
        sessions: <PeriodSessionSpec>[_spec(1, 0, 'bench', weight: 100)],
      );
      final List<PeriodSessionSpec> w4 = sessionsForWeek(plan, 4);
      expect(w4.single.targetSets, 3);
      expect(w4.single.repsLow, 8);
      expect(w4.single.targetWeightKg, closeTo(97.5, 0.001));
    });
  });

  group('周窗与完成判定', () {
    PeriodPlanSnapshot plan({DateTime? start, int weeks = 4}) => PeriodPlanSnapshot(
          id: 'p1',
          name: 'x',
          weeks: weeks,
          daysPerWeek: 3,
          startDate: start ?? DateTime(2026, 11, 2),
          currentWeek: 1,
          status: PeriodPlanStatus.active,
          sessions: <PeriodSessionSpec>[
            for (int w = 1; w <= weeks; w += 1)
              for (int d = 1; d <= 3; d += 1)
                for (int p = 0; p < 6; p += 1) _spec(d, p, 'ex_${d}_$p', week: w),
          ],
        );

    test('周窗按本地日期左闭右开；跨年连续、闰年 2-29 计入', () {
      final ({DateTime start, DateTime end}) w1 =
          periodWeekWindow(DateTime(2025, 12, 29), 1);
      expect(w1.start, DateTime(2025, 12, 29));
      expect(w1.end, DateTime(2026, 1, 5));
      final ({DateTime start, DateTime end}) w2 =
          periodWeekWindow(DateTime(2025, 12, 29), 2);
      expect(w2.start, DateTime(2026, 1, 5));
      // 闰年：2024-02-26 那周包含 2-29
      final ({DateTime start, DateTime end}) leap =
          periodWeekWindow(DateTime(2024, 2, 26), 1);
      expect(leap.start, DateTime(2024, 2, 26));
      expect(leap.end, DateTime(2024, 3, 4));
    });

    test('80% 阈值（向上取整）：18 项要 15 项；24 项要 20 项', () {
      final PeriodPlanSnapshot p = plan();
      final int start =
          DateTime(2026, 11, 2, 10).millisecondsSinceEpoch;
      // 14 项 → 不够
      final List<SetRecord> fourteen = <SetRecord>[
        for (int i = 0; i < 14; i += 1)
          _set(id: 's$i', exerciseId: 'ex_${i ~/ 6 + 1}_${i % 6}', atMs: start),
      ];
      expect(evaluateWeekCompletion(plan: p, week: 1, sets: fourteen).isComplete, isFalse);
      expect(evaluateWeekCompletion(plan: p, week: 1, sets: fourteen).required, 15);
      // 15 项 → 达标
      final List<SetRecord> fifteen = <SetRecord>[
        for (int i = 0; i < 15; i += 1)
          _set(id: 't$i', exerciseId: 'ex_${i ~/ 6 + 1}_${i % 6}', atMs: start),
      ];
      expect(evaluateWeekCompletion(plan: p, week: 1, sets: fifteen).isComplete, isTrue);
    });

    test('同一动作多组只算一项；热身组不算；下周的组不算本周', () {
      final PeriodPlanSnapshot p = plan();
      final List<SetRecord> sets = <SetRecord>[
        _set(id: 'a', exerciseId: 'ex_1_0', atMs: DateTime(2026, 11, 2, 10).millisecondsSinceEpoch),
        _set(id: 'b', exerciseId: 'ex_1_0', atMs: DateTime(2026, 11, 2, 11).millisecondsSinceEpoch),
        _set(id: 'w', exerciseId: 'ex_1_1', atMs: DateTime(2026, 11, 2, 9).millisecondsSinceEpoch, setType: SetType.warmup),
        _set(id: 'next', exerciseId: 'ex_1_2', atMs: DateTime(2026, 11, 9, 9).millisecondsSinceEpoch),
      ];
      final PeriodWeekCompletion c = evaluateWeekCompletion(plan: p, week: 1, sets: sets);
      expect(c.done, 1);
    });

    test('练满 → 进下一周；最后一周练满 → completed；没练满 → 原地不动', () {
      final PeriodPlanSnapshot p = plan(weeks: 2);
      final CompleterSets all = CompleterSets();
      final List<SetRecord> complete = all.week(p, 1);
      final PeriodAdvanceResult r = advanceAfterWeek(plan: p, sets: complete);
      expect(r.advanced, isTrue);
      expect(r.currentWeek, 2);
      expect(r.status, PeriodPlanStatus.active);

      final PeriodPlanSnapshot last = p.copyWith(currentWeek: 2);
      final PeriodAdvanceResult done = advanceAfterWeek(plan: last, sets: all.week(last, 2));
      expect(done.status, PeriodPlanStatus.completed);
      expect(done.currentWeek, 2);

      final PeriodAdvanceResult stay = advanceAfterWeek(plan: p, sets: const <SetRecord>[]);
      expect(stay.advanced, isFalse);
      expect(stay.currentWeek, 1);
    });
  });

  group('计划 JSON', () {
    PeriodPlanSnapshot sample() => PeriodPlanSnapshot(
          id: 'p1',
          name: '4 周入门',
          weeks: 4,
          daysPerWeek: 3,
          startDate: DateTime(2026, 11, 9),
          currentWeek: 2,
          status: PeriodPlanStatus.active,
          sessions: <PeriodSessionSpec>[
            _spec(1, 0, 'bench', weight: 60),
            const PeriodSessionSpec(
              week: 1, day: 1, position: 1, exerciseId: 'pull', targetWeightKg: null,
            ),
          ],
        );

    test('roundtrip：字段与 null 重量原样回来', () {
      final String json = encodePeriodPlanJson(sample());
      final PeriodPlanParseResult r = parsePeriodPlanJson(json);
      expect(r.ok, isTrue, reason: r.error);
      final PeriodPlanSnapshot p = r.plan!;
      expect(p.name, '4 周入门');
      expect(p.weeks, 4);
      expect(p.daysPerWeek, 3);
      expect(p.currentWeek, 2);
      expect(p.status, PeriodPlanStatus.active);
      expect(p.startDate, DateTime(2026, 11, 9));
      expect(p.sessions.length, 2);
      expect(p.sessions[0].targetWeightKg, 60);
      expect(p.sessions[1].targetWeightKg, isNull);
    });

    test('未知字段/版本不符/坏日期/重复位置/缺字段：都给可读原因', () {
      final Map<String, Object?> base =
          (jsonDecode(encodePeriodPlanJson(sample())) as Map<String, Object?>);
      Map<String, Object?> copy() => jsonDecode(jsonEncode(base)) as Map<String, Object?>;

      final Map<String, Object?> unknownTop = copy()..['foo'] = 1;
      expect(parsePeriodPlanJson(jsonEncode(unknownTop)).error, contains('拒绝未知字段'));

      final Map<String, Object?> unknownPlan = copy();
      (unknownPlan['plan'] as Map<String, Object?>)['bar'] = 1;
      expect(parsePeriodPlanJson(jsonEncode(unknownPlan)).error, contains('拒绝未知字段'));

      final Map<String, Object?> unknownSession = copy();
      ((unknownSession['plan'] as Map<String, Object?>)['sessions'] as List<Object?>)
          .add(<String, Object?>{'week': 1, 'day': 2, 'position': 0, 'exercise_id': 'x',
            'target_sets': 3, 'reps_low': 8, 'reps_high': 10, 'target_weight_kg': null, 'zzz': 1});
      expect(parsePeriodPlanJson(jsonEncode(unknownSession)).error, contains('拒绝未知字段'));

      final Map<String, Object?> badVersion = copy()..['version'] = 2;
      expect(parsePeriodPlanJson(jsonEncode(badVersion)).error, contains('更新版本'));

      final Map<String, Object?> badName = copy();
      (badName['plan'] as Map<String, Object?>).remove('name');
      expect(parsePeriodPlanJson(jsonEncode(badName)).error, contains('缺少字段'));

      final Map<String, Object?> badDate = copy();
      (badDate['plan'] as Map<String, Object?>)['start_date'] = '2026-02-30';
      expect(parsePeriodPlanJson(jsonEncode(badDate)).error, contains('YYYY-MM-DD'));

      final Map<String, Object?> dup = copy();
      final List<Object?> sessions =
          (dup['plan'] as Map<String, Object?>)['sessions'] as List<Object?>;
      ((sessions[1] as Map<String, Object?>))['position'] = 0; // 与第 0 条同 (1,1,0)
      ((sessions[1] as Map<String, Object?>))['exercise_id'] = 'bench';
      expect(parsePeriodPlanJson(jsonEncode(dup)).error, contains('重复'));

      expect(parsePeriodPlanJson('not json').error, contains('JSON'));
    });
  });

  group('仓储', () {
    late AppDatabase db;
    late PeriodPlanRepository repo;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = PeriodPlanRepository(db);
    });
    tearDown(() async => db.close());

    test('createPlan 展开所有周、归档上一份；refreshProgress 按完成度推进', () async {
      final PeriodPlanSnapshot a = await repo.createPlan(
        name: 'A',
        weeks: 4,
        daysPerWeek: 3,
        startDate: DateTime(2026, 11, 2),
        baseSessions: <PeriodSessionSpec>[_spec(1, 0, 'bench', weight: 100)],
        nowMs: 1000,
      );
      expect(a.sessions.length, 4);
      expect(a.sessions.first.targetWeightKg, 100);
      expect(a.sessions[3].targetWeightKg, closeTo(97.5, 0.001), reason: 'W4 deload');

      // 第 1 周只有 1 项，80% → 1 项就达标
      final List<SetRecord> done = <SetRecord>[
        _set(id: 's', exerciseId: 'bench', atMs: DateTime(2026, 11, 2, 10).millisecondsSinceEpoch),
      ];
      final PeriodPlanSnapshot advanced = await repo.refreshProgress(a, done);
      expect(advanced.currentWeek, 2);

      final PeriodPlanSnapshot b = await repo.createPlan(
        name: 'B',
        weeks: 4,
        daysPerWeek: 3,
        startDate: DateTime(2026, 12, 1),
        baseSessions: <PeriodSessionSpec>[_spec(1, 0, 'bench', weight: 50)],
        nowMs: 2000,
      );
      expect((await repo.activePlan())!.name, 'B');
      expect((await repo.byId(a.id))!.status, PeriodPlanStatus.archived);
      expect(b.name, 'B');
    });
  });
}

/// 造"这一周全部练满"的组（供推进测试用）。
class CompleterSets {
  List<SetRecord> week(PeriodPlanSnapshot plan, int week) {
    final ({DateTime start, DateTime end}) w = periodWeekWindow(plan.startDate, week);
    final List<SetRecord> out = <SetRecord>[];
    int i = 0;
    for (final PeriodSessionSpec s in plan.sessionsOfWeek(week)) {
      out.add(_set(id: 'c${i++}', exerciseId: s.exerciseId, atMs: w.start.millisecondsSinceEpoch + 1000));
    }
    return out;
  }
}
