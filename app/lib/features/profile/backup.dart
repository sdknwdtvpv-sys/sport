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
const int kBackupFormat = 2;

/// 备份里的应用标识。粘错东西时要能一眼认出来，所以不只看 JSON 能不能解析。
const String kBackupApp = 'lianleme';

/// 文件名（不含目录）。带日期，用户存多份也分得清。
String backupFileName(int nowMs) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(nowMs);
  String two(int n) => n.toString().padLeft(2, '0');
  return '练了么-备份-${t.year}-${two(t.month)}-${two(t.day)}.json';
}

/// 把训练数据编码成备份文本。
///
/// [exerciseNames] 只是**给人看的**（id → 名称）—— 导入时不依赖它，
/// 因为它可能过期（动作被改名/删除）。真正的关联永远是 id。
String encodeBackup({
  required List<Workout> workouts,
  required Map<String, String> exerciseNames,
  int? nowMs,
}) {
  final Map<String, Object?> root = <String, Object?>{
    'app': kBackupApp,
    'format': kBackupFormat,
    'exported_at': nowMs ?? DateTime.now().millisecondsSinceEpoch,
    'unit': 'kg', // 数值一律 kg；写出来是为了让人看懂，不是给程序读的
    'exercise_names': exerciseNames,
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
    this.skippedSets = 0,
    this.error,
  });

  final List<Workout> workouts;

  /// 因为缺字段/类型不对被跳过的组数。> 0 时界面必须如实说出来。
  final int skippedSets;

  /// 非 null 表示整份文件不可用（不是 JSON / 不是本应用的备份）。
  final String? error;

  bool get ok => error == null;

  int get setCount =>
      workouts.fold<int>(0, (int a, Workout w) => a + w.sets.length);

  int get workoutCount => workouts.length;
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

  return BackupParse(workouts: out, skippedSets: skipped);
}
