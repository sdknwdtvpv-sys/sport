/// 练了么 · 「把数据装进备份 / 把备份写回库里」这两件小事
///
/// 抽出来的理由很实际：**这两段逻辑现在有两条调用路径** ——
/// 「我」页的导出/粘贴导入，与云备份的上传/恢复。
/// 各写一遍的下场是"导出的能导回、云端的导不回"这种最难查的偏差，
/// 而备份恰恰是最后一道防线（`PRODUCT.md` §10.5：数据丢失是工具类死刑）。
///
/// 这一层刻意不认识"云"：它只负责「库 ↔ 一份 JSON 字符串」。
/// 加密与上传是 `lib/backup/` 的事，两边互不知道对方存在。
///
/// **2026-10-05：范围第二次扩大 —— 身体数据（身高 + 逐日的体重/体脂率/腰围/肌肉量/备注）。**
/// 与动作置顶那次不同的是，这一批数据属于**敏感个人信息**，本机记它之前先过了一道
/// **单独同意**（PIPL 第 29 条）。所以这一层多守两条：
///   1. **攒备份**：那道同意不在（从没同意过 / 已撤回）→ **一个数值都不放进去**
///      —— 否则"撤回同意"就等于空话（数据照样从云上走一圈）；
///   2. **写回库**：目标设备没有那道同意 → **一个数值都不写**，并在摘要里如实说
///      "有 N 条没进来"，而不是静默丢掉（用户会以为数据没恢复成功，而不知道是那道门）。
/// 两条都由 `app/test/backup_scope_test.dart` 钉着。
library;

import '../../data/body_metric_repository.dart';
import '../../data/db.dart' show ExerciseData, BodyMetricData;
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../data/profile_repository.dart';
import '../../domain/models.dart';
import 'backup.dart';

/// 一份攒好的备份：JSON 本身 + 几个用来跟用户交代的数字
class BackupBundle {
  const BackupBundle({
    required this.json,
    required this.workouts,
    required this.sets,
    this.pinned = 0,
    this.bodyMetrics = 0,
    this.hasBodyHeight = false,
    this.bodyHeldBack = 0,
    this.bodyHeightHeldBack = false,
  });

  /// 可直接导出 / 上传（加密前）的备份正文
  final String json;

  /// 里面有几次训练、多少组
  final int workouts;
  final int sets;

  /// 里面带了几个**动作置顶**（2026-10-04 起）。0 时界面上不提这一句。
  final int pinned;

  /// 里面带了几条**身体数据**（2026-10-05 起）。0 时界面上不提这一句。
  /// 注意 0 有两种可能：本机没有记录，或**那道单独同意不在**（撤回后就是这个样子）——
  /// 两种都不该在界面上编一句话解释，所以这里只说数字。
  final int bodyMetrics;

  /// 里面带没带身高（身高不是每日指标，所以不在 [bodyMetrics] 那个数字里）
  final bool hasBodyHeight;

  /// 本机**有**身体数据、但**没带上**的条数（> 0 只有一种原因：那道单独同意不在）。
  ///
  /// 为什么要单独说出来：用户换手机时看到"备份成功"，而身体数据悄悄没进去 ——
  /// 那正是这个功能最坏的失败方式。数字说出来，他才知道要去点那道门。
  final int bodyHeldBack;

  /// 同理，身高（它不在 [bodyHeldBack] 那个条数里）也没带上。
  final bool bodyHeightHeldBack;

  /// 「3 次训练 / 21 组 / 2 个置顶动作 / 12 条身体数据」——
  /// **一处拼好给两条路径用**（导出与云上传）：各拼一遍迟早会出现
  /// "导出说带了身体数据、云备份没说"这种不一致，而它恰好是用户判断
  /// "我要不要开云备份"的依据。
  String get summary {
    final String pin = pinned > 0 ? ' / $pinned 个置顶动作' : '';
    final String body = bodyMetrics > 0
        ? ' / $bodyMetrics 条身体数据${hasBodyHeight ? '（含身高）' : ''}'
        : (hasBodyHeight ? ' / 身高' : '');
    final String held = bodyHeldBack > 0
        ? '；身体数据 $bodyHeldBack 条没带上（那道单独同意不在）'
        : (bodyHeightHeldBack ? '；身高没带上（那道单独同意不在）' : '');
    return '$workouts 次训练 / $sets 组$pin$body$held';
  }
}

/// 从库里攒出一份可导回的备份。
///
/// `allSets()` 只给正式组，正好用来枚举"练过哪些训练"；再按训练把**整份**记录
/// （含热身组）读回来。
///
/// [profile] 是**必填**：身体数据要不要进备份，取决于"那道单独同意在不在"
/// （它存在 `user_profile` 里），而那个判断只在这个仓库手上。
/// [bodyMetrics] 可以为 null —— 那是"这条路径根本不碰身体数据"（截图脚本之类）；
/// 生产的两条路（「我」页导出、云备份上传）都必须传它。
///
/// ⚠️ 不管走哪条路，**本机有身体数据却没带上时，[BackupBundle.bodyHeldBack] 会说出来** ——
/// 让这件事在界面上有痕迹，而不是"备份成功、数据悄悄少了"。
Future<BackupBundle> collectBackup({
  required LocalStore store,
  required ExerciseRepository repository,
  required ProfileRepository profile,
  BodyMetricRepository? bodyMetrics,
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

  // ── 身体数据（v4，2026-10-05）──────────────────────────────────────────
  // 先看那道**单独同意**在不在：不在就**整块不写**（不是"写个空块"）——
  // 空块的意思是"这份备份明确说没有身体数据"，而我们现在要说的是
  // "这件事不在这次处理范围里"，那是两件事（见 backup.dart 的注释）。
  final bool bodyAllowed = await profile.bodyMetricConsentAtMs() != null;
  BackupBody? body;
  int bodyHeldBack = 0;
  bool bodyHeightHeldBack = false;
  if (bodyAllowed && bodyMetrics != null) {
    final List<BodyMetricData> metrics = await bodyMetrics.all();
    body = BackupBody(
      heightCm: await profile.heightCm(),
      metrics: <BackupBodyMetric>[
        for (final BodyMetricData m in metrics)
          BackupBodyMetric(
            date: m.date,
            weightKg: m.weightKg,
            bodyFatPct: m.bodyFatPct,
            waistCm: m.waistCm,
            muscleMassKg: m.muscleMassKg,
            note: m.note,
          ),
      ],
    );
  } else if (!bodyAllowed && bodyMetrics != null) {
    // 同意不在，但本机**确实有**身体数据 → 记住这个数字，界面上要说出来。
    // （只说条数，不把数值带进任何地方 —— 这一支连 `all()` 都不调。）
    bodyHeldBack = await bodyMetrics.count();
    bodyHeightHeldBack = await profile.heightCm() != null;
  }

  final List<String> pinnedIds = await store.pinnedExerciseIds();
  final String json = encodeBackup(
    workouts: workouts,
    exerciseNames: names,
    // 动作置顶（2026-10-04 起）
    pinnedExerciseIds: pinnedIds,
    // 身体数据（2026-10-05 起）—— 上面那道门没过时它是 null
    body: body,
    nowMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
  );
  return BackupBundle(
    json: json,
    workouts: workouts.length,
    sets: workouts.fold<int>(0, (int a, Workout w) => a + w.sets.length),
    pinned: pinnedIds.length,
    bodyMetrics: body?.metrics.length ?? 0,
    hasBodyHeight: body?.heightCm != null,
    bodyHeldBack: bodyHeldBack,
    bodyHeightHeldBack: bodyHeightHeldBack,
  );
}

/// 一次导入的结果
class BackupApplyResult {
  const BackupApplyResult({
    required this.workouts,
    required this.sets,
    required this.skippedSets,
    this.restoredExercises = 0,
    this.pinned,
    this.bodyMetrics = 0,
    this.bodySkipped = 0,
  });

  /// 写进库的训练次数
  final int workouts;

  /// 写进库的组数
  final int sets;

  /// 解析时就没认出来、被跳过的组数
  final int skippedSets;

  /// 这次导入**补建**了几个动作（备份里有名字、而本机没有的那些）。
  /// 0 表示不需要补（动作本来都在），界面就不提这一句。
  final int restoredExercises;

  /// 备份里带了几个**动作置顶**。**null = 这份备份没提置顶**（v1/v2），
  /// 那种情况下本机的置顶原样不动，摘要里也不提 —— 免得读成"置顶被清了"。
  final int? pinned;

  /// 这次真写进库的**身体数据条数**（v4 起）
  final int bodyMetrics;

  /// 备份里有、但**没写进来**的身体数据条数。> 0 只有一种原因：
  /// 这台设备还没过「身体数据」那道**单独同意**（换新手机后第一次恢复就是这种情形）。
  /// 界面上必须说出来，并告诉用户下一步怎么做 —— 静默丢掉会让人以为"恢复失败"。
  final int bodySkipped;

  /// 给人看的一句话
  String get summary {
    final String skipped =
        skippedSets > 0 ? '，跳过 $skippedSets 条没认出来的' : '';
    final String created =
        restoredExercises > 0 ? '，补建 $restoredExercises 个本机没有的动作' : '';
    final String pin = pinned == null ? '' : '，置顶 $pinned 个动作';
    final String body = bodyMetrics > 0 ? '，身体数据 $bodyMetrics 条' : '';
    final String bodyHeld = bodySkipped > 0
        ? '；另有 $bodySkipped 条身体数据没进来（先在「身体数据」页同意那次单独同意，再恢复一次就会进来）'
        : '';
    return '已导入 $workouts 次训练 / $sets 组$created$pin$body$skipped$bodyHeld';
  }
}

/// 把一份**已经解析好**的备份写进库。
///
/// 幂等：组与训练都按 id 落库（`saveSet` / `saveWorkout` 都是 upsert），
/// 身体数据按**日期**落库（同一天再写就是改那一条）—— 所以同一份备份导两遍
/// 不会翻倍 —— 这一点在"云端恢复了、又手动粘一遍"时很重要。
///
/// [bodyMetrics] / [profile] 不传表示"这条路径不负责身体数据"（例如截图脚本、
/// 或只关心训练记录的测试）：此时备份里若带着身体数据，会**如实计入
/// [BackupApplyResult.bodySkipped]**，不静默吞掉。
Future<BackupApplyResult> applyBackup(
  LocalStore store,
  BackupParse parsed, {
  ExerciseRepository? exercises,
  BodyMetricRepository? bodyMetrics,
  ProfileRepository? profile,
}) async {
  for (final Workout w in parsed.workouts) {
    for (final SetRecord s in w.sets) {
      await store.saveSet(s);
    }
    // 训练行本身也要写：时长要用 started_at / ended_at
    await store.saveWorkout(w);
  }

  // 记录写完了，再处理"本机缺的动作"（用户点头要的行为，2026-09-30）：
  // 只补**这次导入的记录里真的用到**、而本机又找不到的那些 ——
  // 备份里那张表可能列着几百个动作，全建一遍会往用户的动作库里塞一堆没碰过的东西。
  int created = 0;
  if (exercises != null) {
    final Set<String> used = <String>{
      for (final Workout w in parsed.workouts)
        for (final SetRecord s in w.sets) s.exerciseId,
    };
    for (final String id in used) {
      final String? name = parsed.exerciseNames[id];
      if (name == null) continue; // 备份里没留名字 → 只能维持原样（显示 id）
      if (await exercises.restoreFromBackup(id: id, name: name)) created += 1;
    }
  }

  // 动作置顶：**只有备份明确说了才动**（v1/v2 备份没有这个键 → 保持本机原样）。
  // 这一句是整个范围扩张里最容易被写错的地方：把"老备份不提"当成"备份说是空的"，
  // 就会在恢复时静默抹掉用户钉的那些动作。
  final List<String>? pinned = parsed.pinnedExerciseIds;
  if (pinned != null) {
    await store.setPinnedExerciseIds(pinned);
  }

  // 身体数据（v4）：**只在备份提过时才动** + **本机必须过过那道单独同意**。
  // 与置顶不同的是：身体数据**只增不减** —— 恢复绝不删掉本机已有的某一天
  // （用户在新手机上自己也记了几天，拿一份旧备份来恢复不该把它们抹掉）。
  int wroteBody = 0;
  int heldBody = 0;
  final BackupBody? body = parsed.body;
  if (body != null) {
    final bool allowed = bodyMetrics != null &&
        profile != null &&
        (await profile.bodyMetricConsentAtMs()) != null;
    if (!allowed) {
      heldBody = body.metrics.length;
    } else {
      for (final BackupBodyMetric m in body.metrics) {
        await bodyMetrics.save(
          date: m.date,
          weightKg: m.weightKg,
          bodyFatPct: m.bodyFatPct,
          waistCm: m.waistCm,
          muscleMassKg: m.muscleMassKg,
          note: m.note,
        );
        wroteBody += 1;
      }
      // 身高也只是"备份里有才写"：没有就保持本机原样（不是清空）
      final double? height = body.heightCm;
      if (height != null) await profile.setHeightCm(height);
    }
  }

  return BackupApplyResult(
    workouts: parsed.workoutCount,
    sets: parsed.setCount,
    skippedSets: parsed.skippedSets,
    restoredExercises: created,
    pinned: pinned?.length,
    bodyMetrics: wroteBody,
    bodySkipped: heldBody,
  );
}
