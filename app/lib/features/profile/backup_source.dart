/// 练了么 · 「把数据装进备份 / 把备份写回库里」这两件小事
///
/// 抽出来的理由很实际：**这两段逻辑现在有两条调用路径** ——
/// 「我」页的导出/粘贴导入，与云备份的上传/恢复。
/// 各写一遍的下场是"导出的能导回、云端的导不回"这种最难查的偏差，
/// 而备份恰恰是最后一道防线（`PRODUCT.md` §10.5：数据丢失是工具类死刑）。
///
/// 这一层刻意不认识"云"：它只负责「库 ↔ 一份 JSON 字符串」。
/// 加密与上传是 `lib/backup/` 的事，两边互不知道对方存在。
library;

import '../../data/db.dart' show ExerciseData;
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../domain/models.dart';
import 'backup.dart';

/// 一份攒好的备份：JSON 本身 + 两个用来跟用户交代的数字
class BackupBundle {
  const BackupBundle({required this.json, required this.workouts, required this.sets});

  /// 可直接导出 / 上传（加密前）的备份正文
  final String json;

  /// 里面有几次训练、多少组 —— 用来显示"已导出 3 次训练 / 21 组"
  final int workouts;
  final int sets;
}

/// 从库里攒出一份可导回的备份。
///
/// `allSets()` 只给正式组，正好用来枚举"练过哪些训练"；再按训练把**整份**记录
/// （含热身组）读回来。
Future<BackupBundle> collectBackup({
  required LocalStore store,
  required ExerciseRepository repository,
  int? nowMs,
}) async {
  final List<SetRecord> normal = await store.allSets();
  final List<String> ids = <String>[];
  for (final SetRecord s in normal) {
    if (!ids.contains(s.workoutId)) ids.add(s.workoutId);
  }

  final List<Workout> workouts = <Workout>[];
  for (final String id in ids) {
    final List<SetRecord> sets = await store.setsFor(id);
    if (sets.isEmpty) continue;
    // 训练行只用来拿起止时间，**不作为数据来源**：项目里真发生过
    // "只写了 set_record、没写 workout 行"的缺陷，那时 loadWorkout 返回 null ——
    // 如果备份依赖它，那一整次训练就会被静默丢掉。备份是最后一道防线，
    // 所以缺训练行时用最早那一组的完成时间兜底，宁可时间粗一点也不丢数据。
    final Workout? loaded = await store.loadWorkout(id);
    final Workout w = Workout(
      id: id,
      startedAtMs: loaded?.startedAtMs ?? sets.first.completedAtMs,
      endedAtMs: loaded?.endedAtMs,
    );
    w.sets.addAll(sets);
    workouts.add(w);
  }

  final List<ExerciseData> rows = await repository.search(limit: 500);
  final Map<String, String> names = <String, String>{
    for (final ExerciseData r in rows) r.id: r.name,
  };

  final String json = encodeBackup(
    workouts: workouts,
    exerciseNames: names,
    nowMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
  );
  return BackupBundle(
    json: json,
    workouts: workouts.length,
    sets: workouts.fold<int>(0, (int a, Workout w) => a + w.sets.length),
  );
}

/// 一次导入的结果
class BackupApplyResult {
  const BackupApplyResult({
    required this.workouts,
    required this.sets,
    required this.skippedSets,
  });

  /// 写进库的训练次数
  final int workouts;

  /// 写进库的组数
  final int sets;

  /// 解析时就没认出来、被跳过的组数
  final int skippedSets;

  /// 给人看的一句话
  String get summary {
    final String skipped =
        skippedSets > 0 ? '，跳过 $skippedSets 条没认出来的' : '';
    return '已导入 $workouts 次训练 / $sets 组$skipped';
  }
}

/// 把一份**已经解析好**的备份写进库。
///
/// 幂等：组与训练都按 id 落库（`saveSet` / `saveWorkout` 都是 upsert），
/// 所以同一份备份导两遍不会翻倍 —— 这一点在"云端恢复了、又手动粘一遍"时很重要。
Future<BackupApplyResult> applyBackup(
  LocalStore store,
  BackupParse parsed,
) async {
  for (final Workout w in parsed.workouts) {
    for (final SetRecord s in w.sets) {
      await store.saveSet(s);
    }
    // 训练行本身也要写：时长要用 started_at / ended_at
    await store.saveWorkout(w);
  }
  return BackupApplyResult(
    workouts: parsed.workoutCount,
    sets: parsed.setCount,
    skippedSets: parsed.skippedSets,
  );
}
