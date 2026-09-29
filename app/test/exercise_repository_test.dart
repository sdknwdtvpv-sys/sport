/// 练了么 · 动作库仓库测试
///
/// 直接读 `assets/exercises.json`（而不是走 rootBundle），
/// 这样测试不依赖 asset bundle 的装配，跑起来更快也更好定位问题。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/exercise_repository.dart';
// db.dart（drift）与 models.dart 都定义了 Workout / SetRecord ——
// 这里只需要 isDistanceTrack，所以用 as 带前缀（verify.sh 有检查守这条）
import 'package:lianleme/domain/models.dart' as domain;

Future<String> _readAsset() => File('assets/exercises.json').readAsString();

/// 种子里到底有多少个动作 —— **从资产文件本身数出来，不写死**。
///
/// 踩过的坑：这里原先写死 `165`，2026-09-29 从上游补库到 318 个之后，
/// 6 条测试一起红。写死数字的问题不是"要改"，而是**改的时候很容易顺手改成新数字
/// 而不去想它在守什么**。真正该守的是"导入一个不少、重复导入不翻倍"，
/// 所以基准值从资产里数；另外 `种子规模` 那条测试专门守"库不该悄悄缩水"。
Future<int> _seedCount() async {
  final Map<String, dynamic> json =
      jsonDecode(await _readAsset()) as Map<String, dynamic>;
  return (json['exercises'] as List<dynamic>).length;
}

void main() {
  late AppDatabase db;
  late ExerciseRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExerciseRepository(db);
  });

  tearDown(() => db.close());

  test('种子规模：351 个动作（库不该悄悄缩水；改种子时这个数字要一起改）', () async {
    // 这一条是"故意的写死"：它是**人对当前库规模的一次背书**。
    // 加动作 / 减动作都会让它红，逼着改动的人确认"是我干的、且我认这个数字"。
    // 351 = 165（手工维护的 01/02/03）+ 186（2026-09-29 从上游补的库：
    //        153 力量 + 11 热身 + 13 有氧 + 9 拉伸）。
    expect(await _seedCount(), 351);
  });

  test('动作类别：318 力量 / 11 热身 / 13 有氧 / 9 拉伸（类别决定会不会被推荐）', () async {
    await repo.importSeed(loadJson: _readAsset);

    expect((await repo.search(category: 'strength', limit: 500)).length, 318);
    expect((await repo.search(category: 'warmup', limit: 500)).length, 11);
    expect((await repo.search(category: 'cardio', limit: 500)).length, 13);
    expect((await repo.search(category: 'stretch', limit: 500)).length, 9);

    // 13 个有氧 = 4 个按秒记的（跳绳/椭圆机/爬楼机/战绳）
    //          + 9 个按距离记的（跑步机/划船机/游泳…）
    final List<ExerciseData> cardio =
        await repo.search(category: 'cardio', limit: 500);
    for (final String id in <String>[
      'ex_jump_rope', 'ex_elliptical', 'ex_stair_climber', 'ex_battle_ropes',
      'ex_running', 'ex_rowing', 'ex_swimming', 'ex_treadmill_incline_walk',
    ]) {
      expect(cardio.map((ExerciseData e) => e.id), contains(id), reason: id);
    }

    // 四类加起来必须等于总量 —— 免得将来加类别时漏掉一条
    final List<ExerciseData> all = await repo.search(limit: 500);
    expect(all.length, 351);
  });

  test('距离类动作的 track_type 是 distance_time（有氧 + 农夫行走）', () async {
    await repo.importSeed(loadJson: _readAsset);

    final List<ExerciseData> distance = (await repo.search(limit: 500))
        .where((ExerciseData e) => domain.isDistanceTrack(e.trackType))
        .toList();

    // 9 个有氧机 + 农夫行走（它本来是 weight_reps —— 农夫行走不是"8–10 次"）
    expect(distance.length, 10);
    expect(distance.map((ExerciseData e) => e.id), contains('ex_farmer_walk'));
  });

  test('不传 category 时行为与以前完全一致（全都要，包含热身与拉伸）', () async {
    await repo.importSeed(loadJson: _readAsset);

    final List<ExerciseData> all = await repo.search(limit: 500);
    expect(all.length, await _seedCount());
    expect(all.any((ExerciseData e) => e.category == 'stretch'), isTrue,
        reason: '不筛类别就该看得到拉伸 —— 否则用户没法找到它');
  });

  test('类别与部位/器械可以叠加筛（"腿部的拉伸"要能查出来）', () async {
    await repo.importSeed(loadJson: _readAsset);

    final List<ExerciseData> legStretch =
        await repo.search(muscleGroup: 'legs', category: 'stretch', limit: 100);
    expect(legStretch, isNotEmpty);
    expect(
      legStretch.every((ExerciseData e) =>
          e.muscleGroup == 'legs' && e.category == 'stretch'),
      isTrue,
    );
  });

  test('导入种子后动作数与资产一致（一个不少）', () async {
    final int seeded = await _seedCount();
    final int n = await repo.importSeed(loadJson: _readAsset);
    expect(n, seeded);
    expect(await repo.builtinCount(), seeded);
  });

  test('重复导入是幂等的（冷启动每次都调也不会翻倍）', () async {
    await repo.importSeed(loadJson: _readAsset);
    await repo.importSeed(loadJson: _readAsset);
    await repo.importSeed(loadJson: _readAsset);

    expect(await repo.builtinCount(), await _seedCount());
  });

  test('全文检索：名称与别名都参与匹配', () async {
    await repo.importSeed(loadJson: _readAsset);

    final rows = await repo.search(query: '卧推');
    final ids = rows.map((ExerciseData r) => r.id).toList();

    // 名称命中
    expect(ids, contains('ex_bb_bench_press'));
    // ⚠️ 别名命中：仰卧臂屈伸的名字里没有「卧推」，它的别名是「法式卧推」。
    //    它就该被搜出来 —— 这正是别名检索存在的理由。
    //    （这条断言原先被我写成"每条的 name 都含卧推"，是错的。）
    expect(ids, contains('ex_skull_crusher'));

    // 真正该保证的是：每条至少在一个字段里命中
    expect(
      rows.every((ExerciseData r) =>
          r.name.contains('卧推') || r.aliases.contains('卧推')),
      isTrue,
    );
  });

  test('全文检索：按别名（引擎的搜索要靠这个）', () async {
    await repo.importSeed(loadJson: _readAsset);

    final bp = await repo.search(query: 'bp');
    expect(bp.map((ExerciseData r) => r.id), contains('ex_bb_bench_press'));

    final rdl = await repo.search(query: 'rdl');
    expect(rdl.map((ExerciseData r) => r.id), contains('ex_rdl'));
  });

  test('按部位筛选', () async {
    await repo.importSeed(loadJson: _readAsset);

    final chest = await repo.search(muscleGroup: 'chest', limit: 100);
    expect(chest, isNotEmpty);
    expect(chest.every((ExerciseData r) => r.muscleGroup == 'chest'), isTrue);
  });

  test('结果按 popularity 降序（常用动作排在前面）', () async {
    await repo.importSeed(loadJson: _readAsset);

    final rows = await repo.search(limit: 20);
    for (int i = 1; i < rows.length; i++) {
      expect(
        rows[i].popularity <= rows[i - 1].popularity,
        isTrue,
        reason: '第 $i 条的 popularity 比前一条大',
      );
    }
    expect(rows.first.popularity, 100, reason: '最高的应是 100');
  });

  test('limit 生效', () async {
    await repo.importSeed(loadJson: _readAsset);
    expect((await repo.search(limit: 5)).length, 5);
  });

  test('软删除的动作不出现在结果里', () async {
    await repo.importSeed(loadJson: _readAsset);

    final before = await repo.search(query: '卧推');
    expect(before, isNotEmpty);

    await (db.update(db.exercise)..where((t) => t.id.equals(before.first.id)))
        .write(ExerciseCompanion(
      deletedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));

    final after = await repo.search(query: '卧推');
    expect(after.map((ExerciseData r) => r.id), isNot(contains(before.first.id)));
  });

  test('specOf 把行转成引擎输入，字段对得上', () async {
    await repo.importSeed(loadJson: _readAsset);

    final rows = await repo.search(query: 'bp');
    final bench = rows.firstWhere((ExerciseData r) => r.id == 'ex_bb_bench_press');
    final spec = repo.specOf(bench);

    expect(spec.id, 'ex_bb_bench_press');
    expect(spec.name, '杠铃卧推');
    expect(spec.weightIncrement, 2.5);
    expect(spec.defaultWeightKg, 40);
    expect(spec.defaultRestSec, 120);
    expect(spec.isBodyweight, isFalse);
  });

  test('自重动作导入后 increment 为 0、起始重量为 null', () async {
    await repo.importSeed(loadJson: _readAsset);

    final rows = await repo.search(query: '引体');
    final pull = rows.firstWhere((ExerciseData r) => r.id == 'ex_pull_up');
    final spec = repo.specOf(pull);

    expect(spec.weightIncrement, 0);
    expect(spec.defaultWeightKg, isNull);
    expect(spec.isBodyweight, isTrue,
        reason: '这条不变量若破了，引擎会给出加重量而不是加次数的错误建议');
  });

  // ---------- 新建自定义动作 ----------

  test('新建的自定义动作立刻能被搜到，且 isBuiltin 为 false', () async {
    await repo.importSeed(loadJson: _readAsset);

    final ExerciseData created = await repo.createCustom(
      name: '坐姿划船机',
      muscleGroup: 'back',
      equipment: 'machine',
      weightIncrement: 5,
      nowMs: 1770000000000,
    );

    expect(created.isBuiltin, isFalse);
    expect(created.popularity, 0, reason: '不该挤掉内置动作在「常用」区的位置');
    expect(await repo.builtinCount(), await _seedCount(),
        reason: '内置动作数不受影响');

    // search 不按 isBuiltin 过滤，所以建完就该能搜到
    final List<ExerciseData> found = await repo.search(query: '坐姿划船机');
    expect(found.map((ExerciseData e) => e.id), contains(created.id));
  });

  test('重新导入种子不会冲掉自定义动作（upsert 只动种子那几个 id）', () async {
    final ExerciseData created = await repo.createCustom(
      name: '我的动作',
      muscleGroup: 'core',
      equipment: 'bodyweight',
      weightIncrement: 0,
      nowMs: 1770000000001,
    );

    await repo.importSeed(loadJson: _readAsset);

    expect(await repo.byId(created.id), isNotNull);
    expect(await repo.builtinCount(), await _seedCount());
  });

  test('步长 > 0 的自定义动作一定有起始重量（否则会被当成自重动作）', () async {
    // 两个 isBodyweight 的判据不一致：
    //   ExerciseSpec.isBodyweight => weightIncrement == 0
    //   Suggestion.isBodyweight   => weightKg == null
    // 所以步长 > 0 却没有起始重量时，引擎会给出 weightKg = null 的建议，
    // 这个有重量的动作就被当成自重动作 —— 用户再也输入不了重量。
    final ExerciseData barbell = await repo.createCustom(
      name: '自定义杠铃动作',
      muscleGroup: 'legs',
      equipment: 'barbell',
      weightIncrement: 2.5,
      nowMs: 1770000000002,
    );
    expect(barbell.defaultWeightKg, isNotNull);
    expect(repo.specOf(barbell).isBodyweight, isFalse);
  });

  test('步长为 0 的自定义动作起始重量必须是 null（走加次数推进）', () async {
    final ExerciseData bw = await repo.createCustom(
      name: '自定义自重动作',
      muscleGroup: 'chest',
      equipment: 'bodyweight',
      weightIncrement: 0,
      nowMs: 1770000000003,
    );
    expect(bw.defaultWeightKg, isNull);
    expect(repo.specOf(bw).isBodyweight, isTrue);
  });

  group('按器械过滤（居家 / 女性人群的第一道门）', () {
    setUp(() => repo.importSeed(loadJson: _readAsset));

    test('只返回该器械的动作', () async {
      final List<ExerciseData> dumb =
          await repo.search(equipment: 'dumbbell', limit: 500);
      expect(dumb, isNotEmpty);
      expect(dumb.every((ExerciseData e) => e.equipment == 'dumbbell'), isTrue);
    });

    test('自重筛选里能拿到平板支撑，且拿不到杠铃动作', () async {
      final List<ExerciseData> body =
          await repo.search(equipment: 'bodyweight', limit: 500);
      expect(body.map((ExerciseData e) => e.id), contains('ex_plank'));
      expect(body.map((ExerciseData e) => e.id), isNot(contains('ex_bb_bench_press')));
    });

    test('器械 + 部位可以叠加', () async {
      final List<ExerciseData> rows = await repo.search(
          equipment: 'dumbbell', muscleGroup: 'chest', limit: 500);

      expect(rows, isNotEmpty);
      expect(
        rows.every((ExerciseData e) =>
            e.equipment == 'dumbbell' && e.muscleGroup == 'chest'),
        isTrue,
      );
    });

    test('不传 equipment 时行为与以前完全一致（全都要）', () async {
      final List<ExerciseData> all = await repo.search(limit: 500);
      expect(all.length, await _seedCount());
    });
  });
}
