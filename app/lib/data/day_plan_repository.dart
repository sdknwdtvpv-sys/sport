/// 练了么 · 「今天的安排」落库（2026-10-09，10.9 清单第 6 条）
///
/// ## 为什么要有这一层
///
/// 那份安排原来是 `TodayPlanner.planToday()` **每次冷启动现算**的 ——
/// 首页显示的就是它，大按钮开练用的也是它。看上去没问题，直到用户说
/// 「今天的安排」要能长按拖动 / 删除 / 替换：**改了没地方存**。
/// 而且即使不改，"隔一小时再打开又换了一批动作"本身就是一件怪事。
///
/// 所以当天这份**落库**：生成一次 → 之后以库里那份为准 → 用户的拖动 / 删除 /
/// 替换都写在这里。第二天是新的 `date`，重新按分化生成。
///
/// ## 两条刻意的取舍
///
///   1. **只存"用户能改的东西"**（动作 + 处方 + 顺序）。引擎算出来的
///      `Suggestion` / `LastSession` **不存** —— 那是"每次打开现算"的东西，
///      存下来就会与历史脱节（今天练完再看，上面还写着昨天的建议）。
///   2. **"排过"这件事与"排了哪几个"分开记**（`day_plan_day` 那张表）：
///      用户可以把今天的动作全删光，而"我删光了"必须存得住 ——
///      否则下次冷启动那 6 个动作又回来了，他会以为删除按钮是坏的。
library;

import 'package:drift/drift.dart';

import '../domain/models.dart' show PlanTarget;
import '../features/today/today_planner.dart' show RoutineEntry;
import 'db.dart';

/// 本地日（`YYYY-MM-DD`）—— 与 `body_metric.date` / `streak_protection.date`
/// 是同一种写法，排障时能被人肉读出来。
///
/// ⚠️ 用**本地**年月日，不用 `toIso8601String()`：后者带时分秒，而且 UTC 下
/// 晚上 8 点之后就算成第二天了（中国时区 UTC+8，那会差 8 小时）。
String dayPlanKey(DateTime day) => '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

class DayPlanRepository {
  DayPlanRepository(this._db);

  final AppDatabase _db;

  /// 这一天排过没有（**哪怕用户把它删空了**）。
  Future<bool> hasPlan(String date) async {
    final row = await (_db.select(_db.dayPlanDay)
          ..where((t) => t.date.equals(date)))
        .getSingleOrNull();
    return row != null;
  }

  /// 这一天排的是哪几个动作，**按用户看到的顺序**。
  ///
  /// 没排过 → 空列表（调用方据此决定"现算一份并落库"）。
  Future<List<RoutineEntry>> load(String date) async {
    final List<DayPlanItemData> rows = await (_db.select(_db.dayPlanItem)
          ..where((t) => t.date.equals(date))
          ..orderBy(<OrderingTerm Function(DayPlanItem)>[
            (DayPlanItem t) => OrderingTerm.asc(t.position),
          ]))
        .get();
    return <RoutineEntry>[
      for (final DayPlanItemData r in rows)
        RoutineEntry(
          exerciseId: r.exerciseId,
          plan: PlanTarget(
            targetSets: r.targetSets,
            targetRepsLow: r.targetRepsLow,
            targetRepsHigh: r.targetRepsHigh,
          ),
        ),
    ];
  }

  /// 覆盖写入这一天（先删后插，一个事务里做完）。
  ///
  /// **空列表也是合法的**：那表示"用户把今天的动作全删了"，标记行照样写，
  /// 于是下次打开不会又冒出一批动作来。
  Future<void> save(String date, List<RoutineEntry> items, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await (_db.delete(_db.dayPlanItem)..where((t) => t.date.equals(date))).go();
      for (int i = 0; i < items.length; i++) {
        final RoutineEntry e = items[i];
        await _db.into(_db.dayPlanItem).insert(DayPlanItemData(
              date: date,
              position: i,
              exerciseId: e.exerciseId,
              targetSets: e.plan.targetSets,
              targetRepsLow: e.plan.targetRepsLow,
              targetRepsHigh: e.plan.targetRepsHigh,
              updatedAt: now,
            ));
      }
      await _db.into(_db.dayPlanDay).insertOnConflictUpdate(
            DayPlanDayData(date: date, generatedAt: now),
          );
    });
  }

  /// 只删这一天的**内容**（标记也一起删 = "当没排过"）——
  /// 给"删除全部数据"与测试用；用户界面上的删除走 [save]（空列表）。
  Future<void> forget(String date) async {
    await _db.transaction(() async {
      await (_db.delete(_db.dayPlanItem)..where((t) => t.date.equals(date))).go();
      await (_db.delete(_db.dayPlanDay)..where((t) => t.date.equals(date))).go();
    });
  }

  /// 清掉 [before] **之前**的那些天（不含当天）。返回清掉的天数。
  ///
  /// 为什么需要：这是一张每天都会长一行（动作多时 6 行）的表，而**只有当天那份有用**。
  /// 不清的话，一年就是两千多行死数据；而"留着历史"也没有任何用处 ——
  /// 真正该留下的历史是**练了什么**（`set_record`），不是"当初打算练什么"。
  Future<int> pruneBefore(String before, {int keepDays = 30}) async {
    final DateTime cutoff = DateTime.parse(before)
        .subtract(Duration(days: keepDays < 0 ? 0 : keepDays));
    final String key = dayPlanKey(cutoff);
    final int items = await (_db.delete(_db.dayPlanItem)
          ..where((t) => t.date.isSmallerThanValue(key)))
        .go();
    await (_db.delete(_db.dayPlanDay)
          ..where((t) => t.date.isSmallerThanValue(key)))
        .go();
    return items;
  }
}
