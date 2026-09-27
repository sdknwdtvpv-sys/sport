/// 练了么 · 动作库仓库测试
///
/// 直接读 `assets/exercises.json`（而不是走 rootBundle），
/// 这样测试不依赖 asset bundle 的装配，跑起来更快也更好定位问题。
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/exercise_repository.dart';

Future<String> _readAsset() => File('assets/exercises.json').readAsString();

void main() {
  late AppDatabase db;
  late ExerciseRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExerciseRepository(db);
  });

  tearDown(() => db.close());

  test('导入种子后动作数为 165', () async {
    final int n = await repo.importSeed(loadJson: _readAsset);
    expect(n, 165);
    expect(await repo.builtinCount(), 165);
  });

  test('重复导入是幂等的（冷启动每次都调也不会翻倍）', () async {
    await repo.importSeed(loadJson: _readAsset);
    await repo.importSeed(loadJson: _readAsset);
    await repo.importSeed(loadJson: _readAsset);

    expect(await repo.builtinCount(), 165);
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
}
