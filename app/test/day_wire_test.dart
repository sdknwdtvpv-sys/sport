/// 今日安排标题与动作同源（v2.0.0，schema v33）
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/day_plan_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/today/today_planner.dart';

void main() {
  test('存下肢 → 现算 nextTrainingDay 返回上肢 → 恢复标题仍是下肢', () async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final DayPlanRepository repo = DayPlanRepository(db);
    await repo.save('2026-11-07', <RoutineEntry>[
      const RoutineEntry(
        exerciseId: 'ex_bb_squat',
        plan: PlanTarget(targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10),
      ),
    ], dayWire: 'lower');
    expect(await repo.loadDayWire('2026-11-07'), 'lower');
    // 恢复时的回退参数故意给"现算的上肢"——库里的 wire 必须胜出。
    expect(resolveStoredDay(await repo.loadDayWire('2026-11-07'), TrainingDay.upper),
        TrainingDay.lower);
    // 老库没有 wire（null）→ 回退到现算值（同旧行为，不崩）
    await repo.save('2026-11-08', const <RoutineEntry>[]);
    expect(await repo.loadDayWire('2026-11-08'), isNull);
    expect(resolveStoredDay(null, TrainingDay.upper), TrainingDay.upper);
  });
}
