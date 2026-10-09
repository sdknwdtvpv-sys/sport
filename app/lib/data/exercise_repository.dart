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
// 只借一个常量（`kLocalUserId`）——单行表的 id 只该有一处定义
import 'profile_repository.dart' show ProfileRepository;

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
  /// [category] 按类别过滤（strength / warmup / stretch）。传 `'strength'` 就是
  /// **"只挑能当训练的动作"** —— 「今天练什么」必须传它，否则会把拉伸排进今天的计划里。
  /// 注：曾经有个 `plannable` 参数（把距离类动作挡在推荐之外）——
  /// 2026-09-29 距离处方做出来之后它就多余了，删掉。
  /// **留着它反而危险**：以后有人加距离动作时会照着旧注释把自己挡在推荐外。
  /// [subTag] 按**细分标签**过滤（上胸 / 中缝 / 后束…，10.9 清单第 7 条）。
  /// 存的是 JSON 文本，所以用 LIKE 匹配 `"上胸"`（带引号，避免"胸"匹配到"上胸"以外的词 —
  /// 标签都是短词且带引号写法唯一，这里够用；要精确匹配就得上关联表，见 `db.dart` 那一列的理由）。
  Future<List<ExerciseData>> search({
    String query = '',
    String? muscleGroup,
    String? equipment,
    /// **一组**器械（"在哪儿练"那种场景筛，2026-10-09 第二份 docx 第 4 条）。
    /// 与 [equipment] 的关系：那个是"只看这一个器械"，这个是"这几个器械都算" ——
    /// 两个都给时取交集（调用方不会那么干，但语义要说得清）。
    Set<String>? equipmentIn,
    String? category,
    String? subTag,
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
      if (equipmentIn != null && equipmentIn.isNotEmpty) {
        cond = cond & t.equipment.isIn(equipmentIn.toList());
      }
      if (category != null) {
        cond = cond & t.category.equals(category);
      }
      if (subTag != null && subTag.isNotEmpty) {
        cond = cond & t.subTags.like('%"$subTag"%');
      }
      if (q.isNotEmpty) {
        // 名字 / 别名 / **细分标签**都参与搜索（10.9 清单第 7 条）：
        // 用户打「上胸」时，他要的是"哪些动作是练上胸的"，而不是"名字里带'上胸'三个字"。
        cond = cond &
            (t.name.like('%$q%') |
                t.aliases.like('%$q%') |
                t.subTags.like('%$q%'));
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

  // ── 加重步进（2026-10-09，10.9 清单第 8a 条）──────────────────────────────
  //
  // 步进本来是**种子数据**的一部分（哑铃 2、器械 5、杠铃 2.5…），用户改不动 ——
  // 而有些健身房的片子只有 5 kg 一档，那种地方每个动作都要能用同一个步进。

  /// 用户设的**库级默认步进**（kg）。null = 没设过（各动作用自己的）。
  ///
  /// ⚠️ 这一列长在 `userProfile` 表上（它是"人的偏好"，写入口在
  /// `ProfileRepository.setDefaultWeightIncrement`），但**用它的地方全在动作这一层**
  /// —— 新建自定义动作要按它开场。与其把 `ProfileRepository` 一路透传到
  /// 动作选择器（那条链上有 5 个构造点，多带一个参数就是多 5 处可能传漏），
  /// 不如在这里开一个**只读**的口：同一个库、同一列，来源仍然只有一个。
  Future<double?> profileDefaultIncrement() async {
    final UserProfileData? row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(ProfileRepository.kLocalUserId)))
        .getSingleOrNull();
    return row?.defaultWeightIncrement;
  }

  /// 改**某一个动作**的加重步进（kg）。`0` 表示自重动作（界面不会给自重动作开这个入口）。
  ///
  /// ⚠️ 只动这一列：动作名、部位、说明都不碰 —— 它是"用户自己的偏好"，
  /// 不是"编辑这个动作"（那两个入口在动作库里）。
  Future<void> setWeightIncrement(String exerciseId, double kg, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.exercise)..where((t) => t.id.equals(exerciseId)))
        .write(ExerciseCompanion(
      weightIncrement: Value<double>(kg),
      updatedAt: Value<int>(now),
    ));
  }

  /// 把步进**铺到所有动作**上（设置页那个"应用到所有动作"）。
  ///
  /// ⚠️ 自重动作（`weight_increment == 0`）**跳过**：它们的 0 是"没有重量"的标记
  /// （`ExerciseSpec.isBodyweight` 就认它），铺上 5 会把引体向上变成"能加 5 kg"的动作。
  /// ⚠️ 已删除的也跳过：那是回收站里的东西。
  Future<int> setAllWeightIncrements(double kg, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return (_db.update(_db.exercise)
          ..where((t) =>
              t.deletedAt.isNull() & t.weightIncrement.isBiggerThanValue(0)))
        .write(ExerciseCompanion(
      weightIncrement: Value<double>(kg),
      updatedAt: Value<int>(now),
    ));
  }

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
        category: e.category,
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
      subTags: jsonEncode(const <String>[]),
      equipment: equipment,
      // 用户自建的动作一律算力量动作：他想记的是一个训练动作。
      // （要建"我自己的一套拉伸"，那是另一个功能，不是这里。）
      category: 'strength',
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

  /// 跨库恢复时**按备份里的 id 补建**一个动作（用户点头要的行为，2026-09-30）。
  ///
  /// **它解决的问题**：备份里有一张 `exercise_names`（id → 名字）。恢复到的库如果**没有**这个动作
  /// （用户自建的、或这个版本的动作库里没有），记录虽然不丢，但**动作名会退化成 `ex_xxxxxxxx`** ——
  /// 换手机的人看到的是一串 id。补建之后，历史里显示的还是他自己的动作名。
  ///
  /// 三条刻意的选择：
  ///   * **按原 id 建**（不是 `createCustom` 那种新生成 id）—— 否则记录里的 `exercise_id`
  ///     依然指不到它，等于白建；
  ///   * **已存在就什么都不做**（幂等）：用户可能改过名字/部位，不能拿备份里的旧名字盖回去；
  ///   * **部位与器械写 `unspecified`（未分类）**、步长 2.5kg（起始 20kg）：备份里**没有**这两样信息，
  ///     与其瞎猜一个部位（那会是假话），不如明说"未分类"——它不会落进任何部位筛选，只在「全部」里出现。
  ///
  /// 返回 true 表示这次真的建了；false 表示本来就有（或名字是空的，没建）。
  Future<bool> restoreFromBackup({
    required String id,
    required String name,
    int? nowMs,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    if (await byId(id) != null) return false;

    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.exercise).insertOnConflictUpdate(ExerciseData(
          id: id,
          name: trimmed,
          nameEn: null,
          aliases: jsonEncode(const <String>[]),
          muscleGroup: 'unspecified',
          secondaryMuscles: jsonEncode(const <String>[]),
          subTags: jsonEncode(const <String>[]),
          equipment: 'unspecified',
          category: 'strength',
          trackType: 'weight_reps',
          defaultRestSec: 90,
          // 步长 > 0 就必须有起始重量（见 createCustom 里那条不变量），20kg 是保守起步值
          defaultWeightKg: 20,
          weightIncrement: 2.5,
          isBuiltin: false,
          popularity: 0,
          createdAt: now,
          updatedAt: now,
        ));
    return true;
  }

  /// ⚠️ 这里的必填字段是照 db.g.dart 里的 ExerciseData 构造签名核对的。
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
        // 缺省 strength：老种子文件里没有这个字段（2026-09-29 之前），
        // 而那时库里没有一个热身/拉伸动作 —— 缺省值就是对的。
        category: (e['category'] as String?) ?? 'strength',
        trackType: (e['track_type'] as String?) ?? 'weight_reps',
        defaultRestSec: (e['default_rest_sec'] as num?)?.toInt() ?? 90,
        defaultWeightKg: (e['default_weight_kg'] as num?)?.toDouble(),
        defaultTargetDistanceM:
            (e['default_target_distance_m'] as num?)?.toDouble(),
        instructions: e['instructions'] as String?,
        // 细分标签：老种子文件里没有这个字段（2026-10-09 之前）→ 空数组
        subTags: jsonEncode(e['sub_tags'] ?? const <String>[]),
        weightIncrement: (e['weight_increment'] as num?)?.toDouble() ?? 0,
        isBuiltin: ((e['is_builtin'] as num?)?.toInt() ?? 1) == 1,
        popularity: (e['popularity'] as num?)?.toInt() ?? 0,
        createdAt: _seedTs,
        updatedAt: _seedTs,
      );

  /// 与 seed/build.mjs 里的 SEED_TS 一致（固定值，保证种子可复现）
  static const int _seedTs = 1767225600000;
}
