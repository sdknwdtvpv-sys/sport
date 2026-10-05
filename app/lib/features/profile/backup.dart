/// 练了么 · 备份的编码与解码（纯函数，可单测）
///
/// **为什么备份不用 CSV**：`buildSetsCsv` 是**给人看的报表** ——
/// 日期精确到分钟、重量跟随显示单位、只有「日期/动作/重量/次数/容量/组序」六列。
/// 拿它当备份会把组 id、训练 id、热身标记、RPE、秒级时间全丢掉，
/// 导回来就是**另一份数据**。备份要的是能原样倒回去，所以用 JSON。
///
/// 两条设计约束：
///   1. **解析要能挨打**。用户粘进来的可能是任意东西（截图、聊天记录、半截 JSON），
///      所以每个字段都单独校验，坏行跳过并计数，绝不因为一行坏掉就整份作废。
///   2. **重量一律 kg**。备份是数据交换格式，不跟显示单位走 ——
///      否则一份 lb 备份导进 kg 手机上就会静默变成另一组数字。
library;

import 'dart:convert';

import '../../domain/models.dart';

/// 备份格式版本。加字段时靠它做兼容判断。
///
/// * **1** —— 最初那版：组里有 id / 动作 / 组序 / 次数 / 重量 / 类型 / RPE / 完成时间
/// * **2** —— 2026-09-29 加 `distance_m`（有氧记录）。**读的时候两个版本都认**：
///   v1 的组没有距离 → distanceM = null（"没记过距离"），不是 0。
///   写出去的一律是 v2（新格式带全字段，老 App 读不了新备份也没关系 ——
///   备份是给未来的自己用的，不是给旧版本用的）。
/// * **3** —— 2026-10-04 加 `pinned_exercises`（**动作置顶**）。
///   ⚠️ 这是本项目第一次**扩大备份范围**：原先只有训练记录（用户 2026-09-30 拍板
///   "范围就此定死"），2026-10-04 用户点头把"置顶"这一项也带上 ——
///   理由很直接：换手机时如果收藏没了，用户会觉得"我的数据没全回来"。
/// * **4** —— 2026-10-05 加 `body`（**身体数据**：身高 + 逐日的体重/体脂率/腰围/
///   肌肉量/备注）。第二次扩大范围，用户点头（同一条理由：换手机时那几样也得回来）。
///
/// ## 一条比"版本号"更要紧的纪律：**没提过的东西，不许动**
///
/// 读的时候 1–4 版全认。缺的键一律解析成 **null**，而 null 的语义是
/// **"这份备份对这件事没有意见"** —— 导入时**不许**拿它去清空本机已有的东西：
///   * v1/v2 没有 `pinned_exercises` → 不动本机的置顶（否则拿老备份恢复会清空收藏）；
///   * v1–v3 没有 `body` → 不动本机的身体数据与身高。
/// 反过来说，**空列表是有意义的**（"我一个都没置顶"）—— 两件事混成一件就是数据丢失。
///
/// ## 身体数据还多一道门（2026-10-05）
///
/// 体重那一类属于**敏感个人信息**（PIPL 第 29 条），本机记它之前先过了一道
/// **单独同意**。所以：
///   * **攒备份时**：那道同意不在（从没同意过、或已经撤回）→ **一个数值都不放进去**；
///   * **写回库时**：本机没有那道同意 → **一个数值都不写**（摘要里如实说有多少条没进来）。
/// 这条不是"多一层开关"，而是"同意范围到哪，处理就到哪"：撤回之后继续把它传出去，
/// 撤回就成了空话。判据在 `backup_source.dart`，测试在 `app/test/backup_scope_test.dart`。
const int kBackupFormat = 4;

/// 备份里的应用标识。粘错东西时要能一眼认出来，所以不只看 JSON 能不能解析。
const String kBackupApp = 'lianleme';

/// 文件名（不含目录）。带日期，用户存多份也分得清。
String backupFileName(int nowMs) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(nowMs);
  String two(int n) => n.toString().padLeft(2, '0');
  return '练了么-备份-${t.year}-${two(t.month)}-${two(t.day)}.json';
}

/// 备份里**一条身体数据**（一天一条，v4 起）。
///
/// 字段与 `body_metric` 表一一对应，但**故意不直接用 drift 的 `BodyMetricData`**：
/// 这一层是"格式与解析"，不该认识数据库（认识它的后果是"改一列 schema 就会
/// 悄悄改掉导出的形状"，而备份的形状是要长期稳定的）。
class BackupBodyMetric {
  const BackupBodyMetric({
    required this.date,
    this.weightKg,
    this.bodyFatPct,
    this.waistCm,
    this.muscleMassKg,
    this.note,
  });

  /// `YYYY-MM-DD`（本地日）—— 与库里的业务键同一个口径（`body_metric_repository.dart`）
  final String date;
  final double? weightKg;
  final double? bodyFatPct;
  final double? waistCm;
  final double? muscleMassKg;
  final String? note;

  /// 一条"有内容的"记录：至少要有一个值或一句备注。
  /// 只有日期的空壳不该被写回库里（那会造出一行什么都不表示的记录）。
  bool get hasContent =>
      weightKg != null ||
      bodyFatPct != null ||
      waistCm != null ||
      muscleMassKg != null ||
      (note != null && note!.trim().isNotEmpty);
}

/// 备份里的**身体数据整块**（v4 起）。
///
/// **`null`（整块没有）与"有块但一条都没有"是两件事**（见 `kBackupFormat` 的注释）：
/// v1–v3 的备份里没有这个键 → 解析成 null → 导入时**不动**本机的身体数据。
class BackupBody {
  const BackupBody({this.heightCm, this.metrics = const <BackupBodyMetric>[]});

  /// 身高（cm）。它不是每日指标，存在档案里、只用来算 BMI —— 不带上它，
  /// 恢复后 BMI 就一直空着（同一个功能"只回来一半"）。
  final double? heightCm;

  final List<BackupBodyMetric> metrics;
}

/// 把训练数据编码成备份文本。
///
/// [exerciseNames]（id → 名称）**导入时会用到**（2026-09-30 起，用户点头要的行为）：
/// 恢复到的库里如果缺某个动作，就用这里的名字**按原 id 补建**一个（见
/// `ExerciseRepository.restoreFromBackup`）—— 否则历史里的动作名会退化成 `ex_xxxxxxxx`。
///
/// ⚠️ 它的作用**仅限"补建缺失的动作"**：已有动作一律不动（用户可能改过名字），
/// 记录与动作的关联永远靠 id，不靠名字。
/// 它可能过期（动作被改名/删除）—— 所以名字只用于"新建一个"，不用于"改已有的"。
String encodeBackup({
  required List<Workout> workouts,
  required Map<String, String> exerciseNames,
  List<String> pinnedExerciseIds = const <String>[],
  BackupBody? body,
  int? nowMs,
}) {
  final Map<String, Object?> root = <String, Object?>{
    'app': kBackupApp,
    'format': kBackupFormat,
    'exported_at': nowMs ?? DateTime.now().millisecondsSinceEpoch,
    'unit': 'kg', // 数值一律 kg；写出来是为了让人看懂，不是给程序读的
    'exercise_names': exerciseNames,
    // **动作置顶**（v3 起）。按用户排的顺序写 —— 导回来时顺序要一样。
    'pinned_exercises': pinnedExerciseIds,
    // **身体数据**（v4 起）。攒它的人负责先过那道单独同意门（见 kBackupFormat 的注释）：
    // 传 null 就是"这份备份不带身体数据"，读的人会原样理解成"不动本机那些"。
    'body': body == null
        ? null
        : <String, Object?>{
            'height_cm': body.heightCm,
            'metrics': <Object?>[
              for (final BackupBodyMetric m in body.metrics)
                <String, Object?>{
                  'date': m.date,
                  'weight_kg': m.weightKg,
                  'body_fat_pct': m.bodyFatPct,
                  'waist_cm': m.waistCm,
                  'muscle_mass_kg': m.muscleMassKg,
                  'note': m.note,
                },
            ],
          },
    'workouts': <Object?>[
      for (final Workout w in workouts)
        <String, Object?>{
          'id': w.id,
          'started_at': w.startedAtMs,
          'ended_at': w.endedAtMs,
          'sets': <Object?>[
            for (final SetRecord s in w.sets)
              <String, Object?>{
                'id': s.id,
                'exercise_id': s.exerciseId,
                'set_index': s.setIndex,
                'reps': s.reps,
                'weight_kg': s.weightKg,
                // 距离（米）。null = 这个动作不记距离 / 老记录没这个字段。
                'distance_m': s.distanceM,
                'set_type': s.setType.wire,
                'rpe': s.rpe,
                'completed_at': s.completedAtMs,
              },
          ],
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(root);
}

/// 解析结果。**失败也不抛异常** —— 界面要把它当成一条消息显示出来。
class BackupParse {
  const BackupParse({
    this.workouts = const <Workout>[],
    this.exerciseNames = const <String, String>{},
    this.pinnedExerciseIds,
    this.body,
    this.skippedSets = 0,
    this.skippedBodyMetrics = 0,
    this.error,
  });

  final List<Workout> workouts;

  /// 备份里的 `exercise_names`（id → 名字）。**导入时用它补建本机缺的动作**：
  /// 只用名字建新行，绝不覆盖已有动作（名字可能过期）。
  final Map<String, String> exerciseNames;

  /// 备份里的**动作置顶**（v3 起）。**null 与空列表是两件事**：
  ///   * `null` —— 这份备份（v1/v2）根本没提置顶 → 导入时**不动**本机的置顶；
  ///   * `[]` —— v3 备份明确说"我一个都没置顶" → 导入时本机也不该有。
  /// 把这两件事混成一件的后果：拿一份老备份去恢复，会把用户的收藏静默清空。
  final List<String>? pinnedExerciseIds;

  /// 备份里的**身体数据**（v4 起）。**null 与"有块"是两件事**（同上）：
  /// `null` = v1–v3 没提过 → 导入时不动本机的身体数据与身高。
  final BackupBody? body;

  /// 因为缺字段/类型不对被跳过的组数。> 0 时界面必须如实说出来。
  final int skippedSets;

  /// 同理，被跳过的**身体数据条数**。整块 `body` 读不出来时也记 1 ——
  /// 粒度退化了，但**必须留痕**：静默丢掉一整个块，比这个数字不精确更坏。
  final int skippedBodyMetrics;

  /// 非 null 表示整份文件不可用（不是 JSON / 不是本应用的备份）。
  final String? error;

  bool get ok => error == null;

  int get setCount =>
      workouts.fold<int>(0, (int a, Workout w) => a + w.sets.length);

  int get workoutCount => workouts.length;

  /// 这份备份里带了几条身体数据（0 = 没带）
  int get bodyMetricCount => body?.metrics.length ?? 0;
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return null;
}

double? _asDouble(Object? v) {
  if (v is num) return v.toDouble();
  return null;
}

SetType _setType(String? wire) =>
    wire == SetType.warmup.wire ? SetType.warmup : SetType.normal;

/// 解析备份文本。
///
/// 坏行跳过并计数：**"42 条导进来、2 条没认出来"远好过"整份作废"** ——
/// 后者会让用户在数据最危险的时候失去唯一的恢复手段。
BackupParse parseBackup(String text) {
  final String raw = text.trim();
  if (raw.isEmpty) {
    return const BackupParse(error: '内容是空的');
  }

  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const BackupParse(error: '这不是有效的备份内容（读不出 JSON）');
  }
  if (decoded is! Map<String, dynamic>) {
    return const BackupParse(error: '这不是有效的备份内容（顶层不是对象）');
  }

  final Object? app = decoded['app'];
  if (app != null && app != kBackupApp) {
    return BackupParse(error: '这看起来是「$app」的备份，不是练了么的');
  }
  final Object? workoutsRaw = decoded['workouts'];
  if (workoutsRaw is! List) {
    return const BackupParse(error: '这不是有效的备份内容（没有 workouts 列表）');
  }

  // `exercise_names` 是**可选**的（老备份、或手抄的片段里可能没有）—— 缺了不影响导入，
  // 只是"本机缺的动作"没法补建，动作名会退化成 id（老行为）。
  final Map<String, String> names = <String, String>{};
  final Object? namesRaw = decoded['exercise_names'];
  if (namesRaw is Map) {
    for (final MapEntry<Object?, Object?> e in namesRaw.entries) {
      final Object? k = e.key;
      final Object? v = e.value;
      if (k is String && v is String && v.trim().isNotEmpty) names[k] = v;
    }
  }

  // 置顶列表也是**可选**的，且"没有这个键"≠"空列表"（见 pinnedExerciseIds 的注释）。
  List<String>? pinned;
  final Object? pinnedRaw = decoded['pinned_exercises'];
  if (pinnedRaw is List) {
    pinned = <String>[
      for (final Object? v in pinnedRaw)
        if (v is String && v.trim().isNotEmpty) v,
    ];
  }

  // 身体数据同样是**可选**的（v4 才有），规则与置顶完全一样：
  // 没有这个键 → null → 导入时不动本机的身体数据。
  int skippedBody = 0;
  BackupBody? body;
  final Object? bodyRaw = decoded['body'];
  if (bodyRaw is Map) {
    final List<BackupBodyMetric> metrics = <BackupBodyMetric>[];
    final Object? listRaw = bodyRaw['metrics'];
    if (listRaw is List) {
      for (final Object? mRaw in listRaw) {
        if (mRaw is! Map) {
          skippedBody++;
          continue;
        }
        final Object? dateRaw = mRaw['date'];
        if (dateRaw is! String || dateRaw.trim().isEmpty) {
          skippedBody++;
          continue;
        }
        final BackupBodyMetric m = BackupBodyMetric(
          date: dateRaw.trim(),
          weightKg: _asDouble(mRaw['weight_kg']),
          bodyFatPct: _asDouble(mRaw['body_fat_pct']),
          waistCm: _asDouble(mRaw['waist_cm']),
          muscleMassKg: _asDouble(mRaw['muscle_mass_kg']),
          note: (mRaw['note'] is String && (mRaw['note'] as String).trim().isNotEmpty)
              ? (mRaw['note'] as String).trim()
              : null,
        );
        // 只有日期的空壳不写回库（那会造出一行什么都不表示的记录）
        if (!m.hasContent) {
          skippedBody++;
          continue;
        }
        metrics.add(m);
      }
    } else if (listRaw != null) {
      skippedBody++; // 有 metrics 这一格但不是列表
    }
    body = BackupBody(
      heightCm: _asDouble(bodyRaw['height_cm']),
      metrics: metrics,
    );
  } else if (bodyRaw != null) {
    // 有 body 这一格但不是对象：**不当成"没有身体数据"**（那会静默地什么都不恢复），
    // 而是留痕：解析成 null（最安全的解释 = 不动本机），并记 1 处没认出来。
    skippedBody++;
  }

  final List<Workout> out = <Workout>[];
  int skipped = 0;

  for (final Object? wRaw in workoutsRaw) {
    if (wRaw is! Map<String, dynamic>) {
      skipped++;
      continue;
    }
    final String? id = wRaw['id'] as String?;
    final int? started = _asInt(wRaw['started_at']);
    if (id == null || started == null) {
      skipped++;
      continue;
    }
    final Workout w = Workout(
      id: id,
      startedAtMs: started,
      endedAtMs: _asInt(wRaw['ended_at']),
    );

    final Object? setsRaw = wRaw['sets'];
    if (setsRaw is! List) {
      skipped++;
      continue;
    }
    for (final Object? sRaw in setsRaw) {
      if (sRaw is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      final String? sid = sRaw['id'] as String?;
      final String? exId = sRaw['exercise_id'] as String?;
      final int? setIndex = _asInt(sRaw['set_index']);
      final int? reps = _asInt(sRaw['reps']);
      final int? completed = _asInt(sRaw['completed_at']);
      if (sid == null ||
          exId == null ||
          setIndex == null ||
          reps == null ||
          completed == null) {
        skipped++;
        continue;
      }
      w.sets.add(SetRecord(
        id: sid,
        workoutId: w.id,
        exerciseId: exId,
        setIndex: setIndex,
        reps: reps,
        weightKg: _asDouble(sRaw['weight_kg']),
        // v1 的备份没有这个字段 → null；v2 里没记距离的组也是 null。
        // 两种情况的含义一致：**没记过距离**（不是 0）。
        distanceM: _asDouble(sRaw['distance_m']),
        completedAtMs: completed,
        setType: _setType(sRaw['set_type'] as String?),
        rpe: _asDouble(sRaw['rpe']),
      ));
    }
    // 一条组都没解析出来的训练不写进去 —— 空训练行只会在总结页留下一个怪条目
    if (w.sets.isNotEmpty) out.add(w);
  }

  return BackupParse(
    workouts: out,
    exerciseNames: names,
    pinnedExerciseIds: pinned,
    body: body,
    skippedSets: skipped,
    skippedBodyMetrics: skippedBody,
  );
}
