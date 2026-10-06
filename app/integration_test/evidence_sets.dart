/// 练了么 · **证据图共用的那份固定训练记录**（2026-10-06）
///
/// 抽出来是因为现在有两个证据脚本要用同一份数据：
///   * `badge_redesign_evidence_test.dart` —— A2「离你最近的一枚」/ A5 段位 / A4 折叠；
///   * `part2_evidence_test.dart` —— 第二部分那几条（周报 / 部位平衡 / 回归激励 / 我的页）。
///
/// ⚠️ 这份数据**不许为了图好看去改**：它的用途是"给每一枚徽章、每一条提示一个
/// **可见的中间态**"，改了之后图里那些"还差 N"就变成编出来的。
/// 里面每个动作 id 都取自 `assets/exercises.json`（写错了不报错、图里也看不出来）。
library;

import 'package:lianleme/domain/models.dart';

/// **一份固定的训练记录**：约 6 周、每周 3 练、每次 4 个动作 × 3 组。
///
/// 覆盖率是**刻意**的 —— 四类徽章都要有东西可看，而且要有"在跑、但还没到"的进度：
/// * 连续打卡：首训已拿、7 天连续没拿（数据里刻意**不连续**，跨周断）；
/// * 力量突破：单次 5 吨拿到、百公斤俱乐部差一点（最大单组 90 kg）、累计 10 吨在跑；
/// * 探索发现：练过 8 个动作（差 12 个）、早鸟拿到（有几组 6:30 记的）、夜猫没拿；
/// * 里程碑：练满 10 次在跑、单次 20 组没拿（每次 12 组）。
///
/// ⚠️ 这份数据**不许**随徽章扩容而改：它的用途是"给这几枚徽章一个可见的中间态"，
/// 一旦有人为了截图好看去调数字，图上那些"还差 N"就变成了编出来的。
List<SetRecord> evidenceSets() {
  // id 一律取自 `assets/exercises.json`（写错了不会报错，图里也看不出来 —— 所以逐个核过）
  const List<String> exercises = <String>[
    'ex_bb_bench_press',
    'ex_bb_squat',
    'ex_deadlift',
    'ex_bb_row',
    'ex_lat_pulldown',
    'ex_db_shoulder_press',
    'ex_leg_press',
    'ex_bb_curl',
  ];
  // 起始日期固定：截图可复现（不跟"今天"走，否则同一份脚本每周出的图都不一样）
  final DateTime start = DateTime(2026, 9, 1, 19, 30);
  final List<SetRecord> out = <SetRecord>[];
  int n = 0;
  for (int week = 0; week < 6; week++) {
    // 每周三练：周二 / 周四 / 周六（刻意留出断点 → "连续 7 天"拿不到，进度在跑）
    for (final int day in <int>[1, 3, 5]) {
      final DateTime at = start.add(Duration(days: week * 7 + day));
      // 第一周周四那一练刻意记在 6:30（早鸟的证据），其余按 19:30
      final bool early = week == 0 && day == 3;
      final int hour = early ? 6 : 19;
      final int minute = early ? 30 : 30;
      for (int i = 0; i < 4; i++) {
        final String exerciseId = exercises[(week * 4 + i) % exercises.length];
        for (int s = 0; s < 3; s++) {
          final DateTime t = DateTime(at.year, at.month, at.day, hour, minute)
              .add(Duration(minutes: i * 4 + s * 1));
          // 重量按"动作序号"给：没有一枚徽章靠随机数，都是这张表里能复算的
          final double w = i == 0 ? 90 : (i == 1 ? 80 : (i == 2 ? 70 : 60));
          n++;
          out.add(SetRecord(
            id: 'ev-$n',
            workoutId: 'ev-w${week * 3 + day}',
            exerciseId: exerciseId,
            setIndex: s + 1,
            reps: 10,
            weightKg: w,
            completedAtMs: t.millisecondsSinceEpoch,
          ));
        }
      }
    }
  }

  // ── 再补四场"另类"训练：让四类徽章都有近处的进度可看，而不是清一色"差很多" ──
  //
  // 每一场都对应一枚**明确**的徽章（图上那些数字要能当场复算出来）：
  //   * 破晓场：凌晨 4:40 记的一组 → 「破晓」（隐藏）解锁；
  //   * 跨零点场：1:20 记的一组 → 「跨零点」（隐藏）解锁；
  //   * 自重场：15 组、一组重量都没有 → 「只用自重」（隐藏）解锁；
  //   * 有氧场：跑步机 3 组 × 2000 m → 「一次五公里」差一点点。
  void add(DateTime at, String exerciseId, int sets, double? weight) {
    final String wid = 'ev-x${at.millisecondsSinceEpoch}';
    for (int s = 0; s < sets; s++) {
      n++;
      out.add(SetRecord(
        id: 'ev-$n',
        workoutId: wid,
        exerciseId: exerciseId,
        setIndex: s + 1,
        reps: 10,
        weightKg: weight,
        completedAtMs: at.add(Duration(minutes: s)).millisecondsSinceEpoch,
      ));
    }
  }

  add(DateTime(2026, 10, 2, 4, 40), 'ex_bb_squat', 2, 70); // 破晓
  add(DateTime(2026, 10, 3, 1, 20), 'ex_bb_curl', 1, 20); // 跨零点
  {
    // 只用自重：一整场 15 组不碰重量
    final DateTime at = DateTime(2026, 10, 4, 19, 30);
    for (int s = 0; s < 15; s++) {
      n++;
      out.add(SetRecord(
        id: 'ev-$n',
        workoutId: 'ev-bw',
        exerciseId: 'ex_push_up',
        setIndex: s + 1,
        reps: 15,
        completedAtMs: at.add(Duration(minutes: s)).millisecondsSinceEpoch,
      ));
    }
  }
  {
    // 有氧：距离动作的 reps 存的是秒，距离单独一列
    final DateTime at = DateTime(2026, 9, 30, 19);
    for (int s = 0; s < 3; s++) {
      n++;
      out.add(SetRecord(
        id: 'ev-$n',
        workoutId: 'ev-cardio',
        exerciseId: 'ex_running',
        setIndex: s + 1,
        reps: 1200,
        distanceM: 2000,
        completedAtMs: at.add(Duration(minutes: s * 2)).millisecondsSinceEpoch,
      ));
    }
  }
  return out;
}
