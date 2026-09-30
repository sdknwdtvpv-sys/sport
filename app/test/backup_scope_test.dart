/// 练了么 · 备份的**范围**（边界要写死，不能靠"没人注意"）
///
/// **为什么单独一组**：设计稿第四节的子决策 3 写的是「备份粒度 → **全都要（设置也备份）**」，
/// 而实现里 `collectBackup` 攒的只有**训练记录**（workouts + sets）加一张给人看的动作名表。
/// 于是实际边界是：
///
/// | 数据 | 在备份里吗 |
/// |---|---|
/// | 训练记录（动作/重量/次数/组序/热身/RPE/距离/完成时间） | ✅ |
/// | 动作 id → 中文名（只为人看，恢复时能显示名字） | ✅ |
/// | 身体数据（体重） | ❌ |
/// | 计划模板（routines） | ❌ |
/// | 个人设置（单位 / 渐进开关 / 休息时长 / 统计开关） | ❌ |
///
/// 也就是说：**换手机或从云端恢复之后，训练记录回来了，但那三样没有。**
/// 这不是 bug（代码行为一致），但它是**设计稿与实现不一致**，而且用户很容易以为
/// "我的数据都回来了"。所以这里把边界钉死：
///   * 谁想改这个范围，必须先改这里的断言 —— 而看到断言就会顺手去改政策与设计稿；
///   * 断言同时说明"现在为什么会丢"，免得下一个人把它当 bug 去"顺手修好"而没同步政策。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/body_metric_repository.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/backup.dart';
import 'package:lianleme/features/profile/backup_source.dart';

/// 造一台"有全部种类数据"的手机
Future<DriftLocalStore> seedRichDevice(AppDatabase db) async {
  final DriftLocalStore store = DriftLocalStore(db);
  await ExerciseRepository(db).importSeed(
    loadJson: () => File('assets/exercises.json').readAsString(),
  );
  await store.saveSet(SetRecord(
    id: 's1',
    workoutId: 'w1',
    exerciseId: 'ex_bb_bench_press',
    setIndex: 1,
    reps: 8,
    completedAtMs: 1000,
    weightKg: 40,
    setType: SetType.normal,
  ));
  await BodyMetricRepository(db).save(date: '2026-09-28', weightKg: 72.5, nowMs: 1000);
  final RoutineData r = await RoutineRepository(db).create('推日模板', nowMs: 1000);
  await RoutineRepository(db).addItem(r.id, 'ex_bb_bench_press', nowMs: 1000);
  final ProfileRepository profile = ProfileRepository(db);
  await profile.setUnit(WeightUnit.lb, nowMs: 1000);
  await profile.setProgressionMode(ProgressionMode.off, nowMs: 1000);
  await profile.setRestOverrideSec(180, nowMs: 1000);
  return store;
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('备份的顶层结构就是这几个键（多一个少一个都要来改这里）', () async {
    final DriftLocalStore store = await seedRichDevice(db);
    final BackupBundle bundle = await collectBackup(
      store: store,
      repository: ExerciseRepository(db),
      nowMs: 1000,
    );
    final Map<String, Object?> root =
        jsonDecode(bundle.json) as Map<String, Object?>;

    expect(root.keys.toSet(), <String>{
      'app',
      'format',
      'exported_at',
      'unit',
      'exercise_names',
      'workouts',
    }, reason: '备份的结构变了 —— 那就说明"备份范围"变了，'
        '请同时检查：docs/backend-design.md 第四节的子决策 3、隐私政策里的措辞、'
        '以及 docs/privacy-facts.json 的 cloudBackup 说明');

    // 数值一律 kg，与显示单位无关（显示单位是 lb，导出的还是 kg）
    expect(root['unit'], 'kg');
    expect(await ProfileRepository(db).unit(), WeightUnit.lb,
        reason: '前置：本机显示单位确实是 lb');
  });

  test('身体数据 / 计划模板 / 设置**不在**备份里（当前边界，故意的）', () async {
    final DriftLocalStore store = await seedRichDevice(db);
    final BackupBundle bundle = await collectBackup(
      store: store,
      repository: ExerciseRepository(db),
      nowMs: 1000,
    );

    // 这些值在本机确实存在……
    expect(await BodyMetricRepository(db).count(), 1);
    expect(await RoutineRepository(db).routines(), hasLength(1));
    // ……但它们不该出现在备份文本里
    expect(bundle.json.contains('72.5'), isFalse,
        reason: '体重进了备份 —— 要么把范围扩大并同步政策，要么这不是你想要的');
    expect(bundle.json.contains('推日模板'), isFalse,
        reason: '计划模板进了备份 —— 同上');
    expect(bundle.json.contains('rest_override'), isFalse);
  });

  test('换手机的真实后果：训练记录回来了，体重/计划/设置**没回来**', () async {
    final DriftLocalStore oldPhone = await seedRichDevice(db);
    final BackupBundle bundle = await collectBackup(
      store: oldPhone,
      repository: ExerciseRepository(db),
      nowMs: 1000,
    );

    // 新手机
    final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(db2.close);
    final DriftLocalStore newPhone = DriftLocalStore(db2);
    await ExerciseRepository(db2).importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
    final BackupParse parsed = parseBackup(bundle.json);
    expect(parsed.error, isNull, reason: '自己导出的备份必须能被自己读回来');
    await applyBackup(newPhone, parsed);

    expect(await newPhone.allSets(), hasLength(1), reason: '训练记录必须回来');
    expect(await BodyMetricRepository(db2).count(), 0,
        reason: '体重**不会**回来 —— 这是当前边界，不是意外');
    expect(await RoutineRepository(db2).routines(), isEmpty,
        reason: '计划模板**不会**回来');
    expect(await ProfileRepository(db2).unit(), WeightUnit.kg,
        reason: '设置回到默认值（不是原手机的 lb）');
  });

  test('备份里带了动作名，但导入时**不读它** —— 本机没有那个动作就只能显示 id', () async {
    // 老手机：建一个**自定义动作**，并记一组
    final DriftLocalStore oldPhone = await seedRichDevice(db);
    final ExerciseData custom = await ExerciseRepository(db).createCustom(
      name: '我的弹力带划船',
      muscleGroup: '背',
      equipment: 'band',
      weightIncrement: 2,
      nowMs: 1000,
    );
    await oldPhone.saveSet(SetRecord(
      id: 's9',
      workoutId: 'w9',
      exerciseId: custom.id,
      setIndex: 1,
      reps: 12,
      completedAtMs: 1000,
      setType: SetType.normal,
    ));

    final BackupBundle bundle = await collectBackup(
      store: oldPhone,
      repository: ExerciseRepository(db),
      nowMs: 1000,
    );
    final Map<String, Object?> root =
        jsonDecode(bundle.json) as Map<String, Object?>;
    final Map<String, Object?> names =
        (root['exercise_names'] as Map<Object?, Object?>).cast<String, Object?>();
    expect(names[custom.id], '我的弹力带划船',
        reason: '导出时确实把中文名写进了"动作名表"（那份是给人看的）');

    // 新手机：全新安装，动作库里**没有**那个自定义动作
    final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(db2.close);
    final DriftLocalStore newPhone = DriftLocalStore(db2);
    await ExerciseRepository(db2).importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
    final BackupParse parsed = parseBackup(bundle.json);
    expect(parsed.error, isNull);
    await applyBackup(newPhone, parsed);

    expect(await newPhone.allSets(), hasLength(2),
        reason: '记录本身不会丢（自定义动作那一组也在）');
    expect(await ExerciseRepository(db2).byId(custom.id), isNull,
        reason: '导入**不会**把缺失的动作补进本机库');

    // 界面上的名字是按 `names[id] ?? id` 取的（progress / training_stats / CSV 都是这个写法）
    final List<ExerciseData> rows = await ExerciseRepository(db2).search(limit: 500);
    final Map<String, String> names2 = <String, String>{
      for (final ExerciseData r in rows) r.id: r.name,
    };
    expect(names2[custom.id] ?? custom.id, custom.id,
        reason: '查不到就用 id 兜底 —— 所以恢复之后这个动作在界面上显示成 '
            '"${custom.id}" 而不是备份里那个中文名。「动作名表」目前是**只写不读**的，'
            '设计稿里"恢复时即使动作库变了也能显示中文名"这句**没有兑现**'
            '（要不要用起来见 docs/your-todo.md）');
  });

  test('动作库变了也能显示名字：备份里带了一份"动作 id → 中文名"', () async {
    // 这一条是设计上的**有意补偿**：动作名表让恢复后仍能显示中文，
    // 所以即使服务端/新版本的库里没有那个动作，用户也看得懂。
    final DriftLocalStore store = await seedRichDevice(db);
    final BackupBundle bundle = await collectBackup(
      store: store,
      repository: ExerciseRepository(db),
      nowMs: 1000,
    );
    final Map<String, Object?> root =
        jsonDecode(bundle.json) as Map<String, Object?>;
    final Map<String, Object?> names =
        (root['exercise_names'] as Map<Object?, Object?>).cast<String, Object?>();

    expect(names.keys, contains('ex_bb_bench_press'));
    expect(names['ex_bb_bench_press'], isA<String>());
    expect((names['ex_bb_bench_press']! as String).isNotEmpty, isTrue,
        reason: '名字是给人看的，空字符串等于没有');

    // ⚠️ 但动作**本身**不在备份里（自定义动作会丢）—— 这条也钉住
    expect(root.containsKey('exercises'), isFalse,
        reason: '如果哪天把动作库也塞进备份了，这条断言与上面的结构断言都要一起改');
  });
}
