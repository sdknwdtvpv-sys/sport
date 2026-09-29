/// 练了么 · 动作库仓库
///
/// 内置动作库的唯一真源是仓库根目录的 `seed/parts/*.json`，
/// 经 `node seed/build.mjs` 生成为 `app/assets/exercises.json`（提交进仓库），
/// 运行时由本文件**幂等**导入 `exercise` 表。
///
/// 幂等的意义：每次冷启动都可以安全地调一次 `importSeed()`，
/// 已导入的不会重复、用户自己改过的不会被覆盖（见下方 onConflict 说明）。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../domain/models.dart';
// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，
// 同时裸 import 两个库时，一用到同名类就 ambiguity_import。这里预先 hide 掉。
import 'db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;

class ExerciseRepository {
  ExerciseRepository(this._db);

  final AppDatabase _db;

  /// 与 `pubspec.yaml` 里声明的资源路径一致
  static const String assetPath = 'assets/exercises.json';

  /// 幂等导入内置动作库，返回导入条数。
  ///
  /// [loadJson] 可注入：测试直接读文件即可，不必依赖 asset bundle 的装配。
  Future<int> importSeed({Future<String> Function()? loadJson}) async {
    final String raw =
        await (loadJson ?? (() => rootBundle.loadString(assetPath)))();
    final Map<String, dynamic> decoded = jsonDecode(raw) as Map<String, dynamic>;
    final List<Map<String, dynamic>> list =
        (decoded['exercises'] as List<dynamic>).cast<Map<String, dynamic>>();

    // 整个过程放进一个事务：318 条逐个 upsert，分开提交会慢一个数量级
    await _db.transaction(() async {
      for (final Map<String, dynamic> e in list) {
        await _db.into(_db.exercise).insertOnConflictUpdate(_toData(e));
      }
    });
    return list.length;
  }

  /// 查动作。别名与名称都参与匹配（"bp" 能搜到杠铃卧推）。
  ///
  /// [equipment] 按器械过滤。**这不是锦上添花**：家里只有一对哑铃的人
  /// 不该被推荐杠铃卧推和腿举 —— 而这正是女性力量 / 居家训练那群人
  /// （乐刻报告：女性会员同比 +20.5%）进来的第一道门。
  Future<List<ExerciseData>> search({
    String query = '',
    String? muscleGroup,
    String? equipment,
    int limit = 50,
  }) {
    final String q = query.trim();
    final sel = _db.select(_db.exercise);
    sel.where((t) {
      Expression<bool> cond = t.deletedAt.isNull();
      if (muscleGroup != null) {
        cond = cond & t.muscleGroup.equals(muscleGroup);
      }
      if (equipment != null) {
        cond = cond & t.equipment.equals(equipment);
      }
      if (q.isNotEmpty) {
        cond = cond & (t.name.like('%$q%') | t.aliases.like('%$q%'));
      }
      return cond;
    });
    sel.orderBy([
      (t) => OrderingTerm.desc(t.popularity),
      (t) => OrderingTerm.asc(t.name),
    ]);
    // 注意：drift 的 where / orderBy / limit **全部返回 void**（就地修改语句），
    // 不能写成 sel.limit(n).get()。必须分两句。
    sel.limit(limit);
    return sel.get();
  }

  /// 按 id 取单个动作（部位轮转要靠它把动作 id 换成部位）
  Future<ExerciseData?> byId(String id) => (_db.select(_db.exercise)
        ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
      .getSingleOrNull();

  /// 已导入的内置动作数
  Future<int> builtinCount() async {
    final rows = await (_db.select(_db.exercise)
          ..where((t) => t.isBuiltin.equals(true) & t.deletedAt.isNull()))
        .get();
    return rows.length;
  }

  /// 把库里的行转成引擎要的输入
  ///
  /// `trackType` 必须带上：它决定引擎对平板支撑这类动作说的是"次"还是"秒"。
  /// （这个字段曾经躺在库里没人读 —— 当时 165 个动作全是 weight_reps，
  /// 于是平板支撑被开成「3 组 × 8–10 次」。）
  ExerciseSpec specOf(ExerciseData e) => ExerciseSpec(
        id: e.id,
        name: e.name,
        weightIncrement: e.weightIncrement,
        defaultWeightKg: e.defaultWeightKg,
        defaultRestSec: e.defaultRestSec,
        trackType: e.trackType,
      );

  /// 新建自定义动作。
  ///
  /// 自定义动作与内置动作存在**同一张表**里（靠 `isBuiltin` 区分），而 [search]
  /// 并不按 `isBuiltin` 过滤 —— 所以建完立刻就能被搜到、被选中、出现在「全部动作」区，
  /// 不需要任何额外接线。
  ///
  /// `popularity` 给 0：自定义动作不该挤掉内置动作在「常用」区的位置。
  /// 它会被「最近做过」接住 —— 练过一次之后自然浮上来。
  Future<ExerciseData> createCustom({
    required String name,
    required String muscleGroup,
    required String equipment,
    required double weightIncrement,
    double? defaultWeightKg,
    int defaultRestSec = 90,
    int? nowMs,
  }) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;

    // ⚠️ 不变量：步长 > 0 时**必须有**起始重量。
    //
    // 因为两个 isBodyweight 的判据不一致：
    //   ExerciseSpec.isBodyweight  => weightIncrement == 0
    //   Suggestion.isBodyweight    => weightKg == null
    // 一个有步长却没有起始重量的动作，会被引擎给出 weightKg = null 的建议，
    // 于是被当成自重动作 —— 用户再也输入不了重量。
    // 与其让链路自相矛盾，不如在这里兜一个保守的起步值（步长 × 8：
    // 杠铃 20kg、哑铃 16kg、器械 40kg），用户可以随时用步进按钮改。
    final double? startWeight =
        weightIncrement == 0 ? null : (defaultWeightKg ?? weightIncrement * 8);

    final ExerciseData row = ExerciseData(
      id: 'ex_custom_$now',
      name: name,
      nameEn: null,
      aliases: jsonEncode(const <String>[]),
      muscleGroup: muscleGroup,
      secondaryMuscles: jsonEncode(const <String>[]),
      equipment: equipment,
      trackType: 'weight_reps',
      defaultRestSec: defaultRestSec,
      defaultWeightKg: startWeight,
      weightIncrement: weightIncrement,
      isBuiltin: false,
      popularity: 0,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.exercise).insertOnConflictUpdate(row);
    return (await byId(row.id))!;
  }

  /// ⚠️ 这 13 个必填字段是照 db.g.dart 里的 ExerciseData 构造签名核对的。
  /// drift 的 withDefault() 只加 SQL 层 DEFAULT，Dart 数据类里这些字段仍是 required
  /// （踩过一次坑：SetRecordData 的 isPr）。
  ExerciseData _toData(Map<String, dynamic> e) => ExerciseData(
        id: e['id'] as String,
        name: e['name'] as String,
        nameEn: e['name_en'] as String?,
        aliases: jsonEncode(e['aliases'] ?? const <String>[]),
        muscleGroup: e['muscle_group'] as String,
        secondaryMuscles: jsonEncode(e['secondary_muscles'] ?? const <String>[]),
        equipment: e['equipment'] as String,
        trackType: (e['track_type'] as String?) ?? 'weight_reps',
        defaultRestSec: (e['default_rest_sec'] as num?)?.toInt() ?? 90,
        defaultWeightKg: (e['default_weight_kg'] as num?)?.toDouble(),
        weightIncrement: (e['weight_increment'] as num?)?.toDouble() ?? 0,
        isBuiltin: ((e['is_builtin'] as num?)?.toInt() ?? 1) == 1,
        popularity: (e['popularity'] as num?)?.toInt() ?? 0,
        createdAt: _seedTs,
        updatedAt: _seedTs,
      );

  /// 与 seed/build.mjs 里的 SEED_TS 一致（固定值，保证种子可复现）
  static const int _seedTs = 1767225600000;
}
