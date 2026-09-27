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

    // 整个过程放进一个事务：165 条逐个 upsert，分开提交会慢一个数量级
    await _db.transaction(() async {
      for (final Map<String, dynamic> e in list) {
        await _db.into(_db.exercise).insertOnConflictUpdate(_toData(e));
      }
    });
    return list.length;
  }

  /// 查动作。别名与名称都参与匹配（"bp" 能搜到杠铃卧推）。
  Future<List<ExerciseData>> search({
    String query = '',
    String? muscleGroup,
    int limit = 50,
  }) {
    final String q = query.trim();
    final sel = _db.select(_db.exercise);
    sel.where((t) {
      Expression<bool> cond = t.deletedAt.isNull();
      if (muscleGroup != null) {
        cond = cond & t.muscleGroup.equals(muscleGroup);
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
  ExerciseSpec specOf(ExerciseData e) => ExerciseSpec(
        id: e.id,
        name: e.name,
        weightIncrement: e.weightIncrement,
        defaultWeightKg: e.defaultWeightKg,
        defaultRestSec: e.defaultRestSec,
      );

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
