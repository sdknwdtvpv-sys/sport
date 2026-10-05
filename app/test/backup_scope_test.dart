/// 练了么 · 备份的**范围**（边界要写死，不能靠"没人注意"）
///
/// **为什么单独一组**：设计稿第四节的子决策 3 写的是「备份粒度 → **全都要（设置也备份）**」，
/// 而实现里 `collectBackup` 攒的只有**训练记录**（workouts + sets）加一张给人看的动作名表。
/// 于是实际边界是（**v4，2026-10-05**）：
///
/// | 数据 | 在备份里吗 |
/// |---|---|
/// | 训练记录（动作/重量/次数/组序/热身/RPE/距离/完成时间） | ✅ |
/// | 动作 id → 中文名（只为人看，恢复时能显示名字） | ✅ |
/// | **动作置顶（收藏）** | ✅ **2026-10-04 起** |
/// | **身体数据（体重/体脂率/腰围/肌肉量/备注 + 身高）** | ✅ **2026-10-05 起**（见下） |
/// | 计划模板（routines） | ❌ |
/// | 个人设置（单位 / 渐进开关 / 休息时长 / 统计开关） | ❌ |
///
/// **两次范围扩张，理由是同一条**：换手机时东西没了，用户会认为"我的数据没全回来"。
/// 第一次（2026-10-04）加的是**动作置顶**；第二次（2026-10-05）加的是**身体数据**。
///
/// ⚠️ 第二次比第一次多一道门：身体数据是**敏感个人信息**（PIPL 第 29 条），
/// 本机记它之前先过了一道**单独同意**。所以备份这边多两条硬规则（都有断言）：
///   1. **攒备份**：那道同意不在（从没给过 / 已撤回）→ **一个数值都不放进去**；
///   2. **写回库**：目标设备没有那道同意 → **一个数值都不写**，并在摘要里如实
///      说"有 N 条没进来"（换新手机第一次恢复就是这种情形）。
/// 撤回同意之后照样把数据从云上走一圈，"撤回"就成了空话 —— 这是这一组要守的东西。
///
/// **剩下没进备份的**（计划模板 / 其它设置）仍然不进：要动它们得再拍一次板，
/// 并同步 `privacy-facts.json` 的 `cloudBackup` 与 `docs/backend-design.md` 第四节的子决策 3。
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
  // 身体数据那道**单独同意**也过一下 —— 真实用户有身体数据就必然过过这道门
  // （不过门就进不了那一页）。身高同样属于这一组数据。
  await profile.setBodyMetricConsent(nowMs: 1000);
  await profile.setHeightCm(178, nowMs: 1000);
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
      profile: ProfileRepository(db),
      bodyMetrics: BodyMetricRepository(db),
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
      'pinned_exercises', // v3（2026-10-04）：动作置顶
      'body', // v4（2026-10-05）：身体数据（身高 + 逐日的体重/体脂率/腰围/肌肉量/备注）
      'workouts',
    }, reason: '备份的结构变了 —— 那就说明"备份范围"变了，'
        '请同时检查：docs/backend-design.md 第四节的子决策 3、隐私政策里的措辞、'
        '以及 docs/privacy-facts.json 的 cloudBackup 说明');
    expect(root['format'], 4, reason: 'v4 就是"多了身体数据"那一版');

    // 数值一律 kg，与显示单位无关（显示单位是 lb，导出的还是 kg）
    expect(root['unit'], 'kg');
    expect(await ProfileRepository(db).unit(), WeightUnit.lb,
        reason: '前置：本机显示单位确实是 lb');
  });

  test('计划模板 / 其它设置**仍然不在**备份里（剩下的那部分边界）', () async {
    final DriftLocalStore store = await seedRichDevice(db);
    final BackupBundle bundle = await collectBackup(
      store: store,
      repository: ExerciseRepository(db),
      profile: ProfileRepository(db),
      bodyMetrics: BodyMetricRepository(db),
      nowMs: 1000,
    );

    expect(await RoutineRepository(db).routines(), hasLength(1));
    expect(bundle.json.contains('推日模板'), isFalse,
        reason: '计划模板进了备份 —— 要动它得再拍一次板，并同步政策与事实表');
    expect(bundle.json.contains('rest_override'), isFalse,
        reason: '其它设置仍然不进备份（要动它同样得再拍一次板）');
  });

  test('换手机的真实后果：训练记录回来了；计划模板与设置**没回来**', () async {
    final DriftLocalStore oldPhone = await seedRichDevice(db);
    final BackupBundle bundle = await collectBackup(
      store: oldPhone,
      repository: ExerciseRepository(db),
      profile: ProfileRepository(db),
      bodyMetrics: BodyMetricRepository(db),
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
    expect(await RoutineRepository(db2).routines(), isEmpty,
        reason: '计划模板**不会**回来（仍在备份范围之外）');
    expect(await ProfileRepository(db2).unit(), WeightUnit.kg,
        reason: '设置回到默认值（不是原手机的 lb）');
  });

  test('★ 动作置顶：进备份、导回时**顺序一致**（2026-10-04 的范围扩张）', () async {
    final DriftLocalStore oldPhone = await seedRichDevice(db);
    await oldPhone.setPinnedExerciseIds(<String>['ex_bb_squat', 'ex_bb_bench_press']);

    final BackupBundle bundle = await collectBackup(
      store: oldPhone,
      repository: ExerciseRepository(db),
      profile: ProfileRepository(db),
      bodyMetrics: BodyMetricRepository(db),
      nowMs: 1000,
    );
    expect(bundle.pinned, 2, reason: '导出时要说清带了几个置顶');

    final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(db2.close);
    final DriftLocalStore newPhone = DriftLocalStore(db2);
    await applyBackup(
      newPhone,
      parseBackup(bundle.json),
      exercises: ExerciseRepository(db2),
    );

    expect(await newPhone.pinnedExerciseIds(),
        <String>['ex_bb_squat', 'ex_bb_bench_press'],
        reason: '顺序也要一致 —— 那是用户自己排的顺序');
  });

  test('★ 老备份（v2）里没有置顶那一项：**不许**拿它清掉本机的置顶', () async {
    // 这是这次范围扩张里最容易写错的一处：把"备份没提"当成"备份说是空的"，
    // 用户拿一份半年前的老备份恢复，收藏就被静默抹了。
    final DriftLocalStore store = DriftLocalStore(db);
    await store.setPinnedExerciseIds(<String>['ex_bb_squat']);

    final String legacy = jsonEncode(<String, Object?>{
      'app': 'lianleme',
      'format': 2, // v2：还没有 pinned_exercises 这个键
      'exported_at': 1000,
      'unit': 'kg',
      'exercise_names': <String, String>{},
      'workouts': <Object?>[],
    });
    final BackupParse parsed = parseBackup(legacy);
    expect(parsed.pinnedExerciseIds, isNull,
        reason: 'null（没提）与 []（明确说没有）必须是两件事');

    final BackupApplyResult applied = await applyBackup(store, parsed);
    expect(await store.pinnedExerciseIds(), <String>['ex_bb_squat'],
        reason: '老备份没提置顶，本机的置顶必须原样不动');
    expect(applied.pinned, isNull, reason: '摘要里也不该冒出"置顶 0 个"这种话');
  });

  test('v3 备份明确说"一个都没置顶"时，导入要真的清空（空列表是有意义的）',
      () async {
    final DriftLocalStore store = DriftLocalStore(db);
    await store.setPinnedExerciseIds(<String>['ex_bb_squat']);

    final String empty = jsonEncode(<String, Object?>{
      'app': 'lianleme',
      'format': 3,
      'exported_at': 1000,
      'unit': 'kg',
      'exercise_names': <String, String>{},
      'pinned_exercises': <String>[],
      'workouts': <Object?>[],
    });

    final BackupApplyResult applied = await applyBackup(store, parseBackup(empty));
    expect(await store.pinnedExerciseIds(), isEmpty);
    expect(applied.pinned, 0);
  });

  test('备份里带了动作名：导入时**按原 id 补建**本机缺的动作（2026-09-30 起）', () async {
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
      profile: ProfileRepository(db),
      bodyMetrics: BodyMetricRepository(db),
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
    // ⚠️ 2026-09-30 起行为变了（用户点头："动作名表**用起来**"）：
    // 导入时会用备份里的名字**按原 id 补建**本机缺的动作。
    final BackupApplyResult applied = await applyBackup(
      newPhone,
      parsed,
      exercises: ExerciseRepository(db2),
    );

    expect(await newPhone.allSets(), hasLength(2),
        reason: '记录本身不会丢（自定义动作那一组也在）');
    expect(applied.restoredExercises, 1, reason: '这一次导入应该补建 1 个动作');

    final ExerciseData? restored = await ExerciseRepository(db2).byId(custom.id);
    expect(restored, isNotNull,
        reason: '补齐之后，历史里显示的才是他自己的动作名，而不是一串 ex_xxxxxxxx');
    expect(restored!.name, custom.name, reason: '名字要来自备份里那张表');

    // 界面上的名字是按 `names[id] ?? id` 取的（progress / training_stats / CSV 都是这个写法）——
    // 补建之后这个兜底用不上了：查得到真名
    final List<ExerciseData> rows = await ExerciseRepository(db2).search(limit: 500);
    final Map<String, String> names2 = <String, String>{
      for (final ExerciseData r in rows) r.id: r.name,
    };
    expect(names2[custom.id] ?? custom.id, custom.name,
        reason: '恢复后界面上显示的是备份里的中文名（设计稿那句承诺现在兑现了）');
  });

  test('补建是**幂等**的：导两遍不会多出动作，也不会覆盖已有动作', () async {
    await seedRichDevice(db);
    final ExerciseData custom = await ExerciseRepository(db).createCustom(
      name: '我的壶铃摇摆', muscleGroup: 'legs', equipment: 'kettlebell',
      weightIncrement: 4,
    );
    await DriftLocalStore(db).saveSet(SetRecord(
      id: 's_custom', workoutId: 'w_custom', exerciseId: custom.id,
      setIndex: 1, weightKg: 24, reps: 12, completedAtMs: 1000,
    ));
    await DriftLocalStore(db).saveWorkout(Workout(
      id: 'w_custom', startedAtMs: 1000, endedAtMs: 2000,
    ));
    final BackupBundle bundle = await collectBackup(
      store: DriftLocalStore(db), repository: ExerciseRepository(db), 
      profile: ProfileRepository(db), bodyMetrics: BodyMetricRepository(db), nowMs: 1000,
    );

    // 新手机：先导入，再**把名字改掉**，然后再导一次同一份备份
    final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(db2.close);
    await ExerciseRepository(db2).importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
    final BackupParse parsed = parseBackup(bundle.json);
    final BackupApplyResult first = await applyBackup(
      DriftLocalStore(db2), parsed, exercises: ExerciseRepository(db2));
    expect(first.restoredExercises, 1);

    final ExerciseData? afterFirst = await ExerciseRepository(db2).byId(custom.id);
    expect(afterFirst!.name, custom.name);

    final BackupApplyResult second = await applyBackup(
      DriftLocalStore(db2), parsed, exercises: ExerciseRepository(db2));
    expect(second.restoredExercises, 0,
        reason: '第二次导入时动作已经在了 —— 不该重复建（幂等）');
  });

  // ──────────────────────────────────────────────────────────────────────
  // ★ 身体数据（v4，2026-10-05 的第二次范围扩张）
  //
  // 这一组比"动作置顶"那次多守一条：**那道单独同意**。
  // 同意不在时，一个数值都不许进备份、也不许写回库 —— 否则"撤回同意"就等于空话。
  // ──────────────────────────────────────────────────────────────────────

  test('★ 进备份：逐日的数值、备注与身高都在（过了那道单独同意）', () async {
    final DriftLocalStore store = await seedRichDevice(db);
    await BodyMetricRepository(db).save(
      date: '2026-10-01', weightKg: 71.2, bodyFatPct: 17.5,
      waistCm: 81, muscleMassKg: 31.4, note: '早上空腹', nowMs: 2000,
    );

    final BackupBundle bundle = await collectBackup(
      store: store,
      repository: ExerciseRepository(db),
      profile: ProfileRepository(db),
      bodyMetrics: BodyMetricRepository(db),
      nowMs: 3000,
    );

    expect(bundle.bodyMetrics, 2, reason: '两条记录都要带走');
    expect(bundle.hasBodyHeight, isTrue, reason: '身高也属于这一组数据');
    final Map<String, Object?> root =
        jsonDecode(bundle.json) as Map<String, Object?>;
    final Map<String, Object?> body =
        (root['body'] as Map<Object?, Object?>).cast<String, Object?>();
    expect(body['height_cm'], 178);
    final List<Object?> metrics = body['metrics']! as List<Object?>;
    expect(metrics, hasLength(2));
    final Map<String, Object?> first =
        (metrics.first as Map<Object?, Object?>).cast<String, Object?>();
    expect(first['date'], '2026-09-28',
        reason: '按日期升序写（老的在前面，与人翻记录的顺序一致）');
    expect((metrics.last as Map<Object?, Object?>)['note'], '早上空腹');
    // 汇总那句话也要对得上 —— 导出的 SnackBar 与云备份用的是同一句
    expect(bundle.summary, contains('2 条身体数据'));
    expect(bundle.summary, contains('含身高'));

    // 界面上不许出现 markdown 记号（SnackBar 的 Text 不渲染 markdown）
    expect(bundle.summary.contains('**'), isFalse);
  });

  test('★ 单独同意**撤回之后**：一个数值都不进备份，而且"没带上几条"要说得出来',
      () async {
    final DriftLocalStore store = await seedRichDevice(db);
    final ProfileRepository profile = ProfileRepository(db);
    await profile.clearBodyMetricConsent(nowMs: 2000); // 用户撤回

    final BackupBundle bundle = await collectBackup(
      store: store,
      repository: ExerciseRepository(db),
      profile: profile,
      bodyMetrics: BodyMetricRepository(db),
      nowMs: 3000,
    );

    expect(bundle.json.contains('72.5'), isFalse,
        reason: '撤回同意之后身体数据还在备份里 —— 那等于"撤回"是句空话');
    expect(bundle.json.contains('178'), isFalse, reason: '身高同理');
    expect(bundle.bodyMetrics, 0);
    // 但**不许静默**：用户看到的是"备份成功"，得让他知道身体数据没进去、为什么
    expect(bundle.bodyHeldBack, 1, reason: '本机有 1 条有效记录，要说出来');
    expect(bundle.bodyHeightHeldBack, isTrue);
    expect(bundle.summary, contains('没带上'));
    expect(bundle.summary, contains('单独同意'));
  });

  test('★ 写回库也要过那道门：新手机还没同意 → 一条都不写，摘要里如实说',
      () async {
    final DriftLocalStore oldPhone = await seedRichDevice(db);
    final BackupBundle bundle = await collectBackup(
      store: oldPhone,
      repository: ExerciseRepository(db),
      profile: ProfileRepository(db),
      bodyMetrics: BodyMetricRepository(db),
      nowMs: 1000,
    );

    // 新手机：全新安装，**还没过**「身体数据」那道单独同意
    final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(db2.close);
    await ExerciseRepository(db2).importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
    final BackupApplyResult r = await applyBackup(
      DriftLocalStore(db2),
      parseBackup(bundle.json),
      bodyMetrics: BodyMetricRepository(db2),
      profile: ProfileRepository(db2),
    );

    expect(await BodyMetricRepository(db2).count(), 0,
        reason: '没过同意就写身体数据 = 在用户没点头之前收集敏感个人信息');
    expect(await ProfileRepository(db2).heightCm(), isNull);
    expect(r.bodyMetrics, 0);
    expect(r.bodySkipped, 1, reason: '有一条没进来，必须报出来');
    expect(r.summary, contains('没进来'));
    expect(r.summary, contains('身体数据'));
  });

  test('★ 过了那道门 → 数值与身高都回来，而且**导两遍不会变成两条**', () async {
    final DriftLocalStore oldPhone = await seedRichDevice(db);
    final BackupBundle bundle = await collectBackup(
      store: oldPhone,
      repository: ExerciseRepository(db),
      profile: ProfileRepository(db),
      bodyMetrics: BodyMetricRepository(db),
      nowMs: 1000,
    );

    final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(db2.close);
    await ExerciseRepository(db2).importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
    final ProfileRepository profile2 = ProfileRepository(db2);
    await profile2.setBodyMetricConsent(nowMs: 1); // 新手机上他点了"同意并记录"

    final BackupParse parsed = parseBackup(bundle.json);
    final BackupApplyResult first = await applyBackup(
      DriftLocalStore(db2), parsed,
      bodyMetrics: BodyMetricRepository(db2), profile: profile2,
    );
    expect(first.bodyMetrics, 1);
    expect(first.bodySkipped, 0);

    final BodyMetricData? m = await BodyMetricRepository(db2).forDate('2026-09-28');
    expect(m, isNotNull);
    expect(m!.weightKg, 72.5, reason: '数值要原样回来');
    expect(m.deletedAt, isNull);
    expect(await profile2.heightCm(), 178, reason: '身高也回来了（BMI 才显示得出来）');

    // 再导一遍同一份：按**日期**落库，所以还是那一条
    await applyBackup(DriftLocalStore(db2), parsed,
        bodyMetrics: BodyMetricRepository(db2), profile: profile2);
    expect(await BodyMetricRepository(db2).count(), 1,
        reason: '导两遍不该变成两条（同一天是"改那条"）');
  });

  test('★ 恢复**只增不减**：新手机上自己记的那几天，不会被一份旧备份抹掉', () async {
    final DriftLocalStore oldPhone = await seedRichDevice(db);
    final BackupBundle bundle = await collectBackup(
      store: oldPhone,
      repository: ExerciseRepository(db),
      profile: ProfileRepository(db),
      bodyMetrics: BodyMetricRepository(db),
      nowMs: 1000,
    );

    final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(db2.close);
    await ExerciseRepository(db2).importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
    final ProfileRepository profile2 = ProfileRepository(db2);
    await profile2.setBodyMetricConsent(nowMs: 1);
    // 他在新手机上已经自己记了今天这条
    await BodyMetricRepository(db2).save(date: '2026-10-05', weightKg: 70.0, nowMs: 1);

    await applyBackup(DriftLocalStore(db2), parseBackup(bundle.json),
        bodyMetrics: BodyMetricRepository(db2), profile: profile2);

    expect(await BodyMetricRepository(db2).count(), 2,
        reason: '备份里的那条 + 他自己记的那条，两条都在（恢复绝不删本机数据）');
    expect((await BodyMetricRepository(db2).forDate('2026-10-05'))!.weightKg, 70.0);
  });

  test('★ 老备份（v3，没有 body 那一块）→ **不许**动本机的身体数据与身高', () async {
    final DriftLocalStore store = await seedRichDevice(db);
    final BackupBundle bundle = await collectBackup(
      store: store,
      repository: ExerciseRepository(db),
      profile: ProfileRepository(db),
      bodyMetrics: BodyMetricRepository(db),
      nowMs: 1000,
    );
    // 造一份"v3 老备份"：把 body 那一块删掉（老版本导出的就是这个形状）
    final Map<String, Object?> root =
        jsonDecode(bundle.json) as Map<String, Object?>;
    root.remove('body');
    root['format'] = 3;
    final BackupParse parsed = parseBackup(jsonEncode(root));
    expect(parsed.body, isNull, reason: '没有这一块 → null（"这份备份对这件事没有意见"）');

    final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(db2.close);
    await ExerciseRepository(db2).importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
    final ProfileRepository profile2 = ProfileRepository(db2);
    await profile2.setBodyMetricConsent(nowMs: 1);
    await BodyMetricRepository(db2).save(date: '2026-10-05', weightKg: 70.0, nowMs: 1);
    await profile2.setHeightCm(170, nowMs: 1);

    final BackupApplyResult r = await applyBackup(
      DriftLocalStore(db2), parsed,
      bodyMetrics: BodyMetricRepository(db2), profile: profile2,
    );

    expect(await BodyMetricRepository(db2).count(), 1, reason: '本机那条还在（没被清）');
    expect(await profile2.heightCm(), 170, reason: '身高保持本机原样（不是被清空）');
    expect(r.bodyMetrics, 0);
    expect(r.bodySkipped, 0, reason: '这份备份没提身体数据，就不该说"有 N 条没进来"');
  });

  test('身体数据里的坏行：跳过并计数，但**不影响**训练记录导入', () async {
    final DriftLocalStore store = await seedRichDevice(db);
    final BackupBundle bundle = await collectBackup(
      store: store,
      repository: ExerciseRepository(db),
      profile: ProfileRepository(db),
      bodyMetrics: BodyMetricRepository(db),
      nowMs: 1000,
    );
    final Map<String, Object?> root =
        jsonDecode(bundle.json) as Map<String, Object?>;
    (root['body']! as Map<String, Object?>)['metrics'] = <Object?>[
      <String, Object?>{'date': '2026-10-02', 'weight_kg': 70.5},
      <String, Object?>{'weight_kg': 71.0}, // 没有日期 → 跳过
      <String, Object?>{'date': '2026-10-03'}, // 只有日期、什么都没有 → 跳过
      'not-a-map', // 不是对象 → 跳过
    ];
    final BackupParse parsed = parseBackup(jsonEncode(root));
    expect(parsed.skippedBodyMetrics, 3);
    expect(parsed.bodyMetricCount, 1);

    final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(db2.close);
    await ExerciseRepository(db2).importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
    final ProfileRepository profile2 = ProfileRepository(db2);
    await profile2.setBodyMetricConsent(nowMs: 1);
    final BackupApplyResult r = await applyBackup(
      DriftLocalStore(db2), parsed,
      bodyMetrics: BodyMetricRepository(db2), profile: profile2,
    );
    expect(r.bodyMetrics, 1, reason: '认出来的那一条照样写进去');
    expect(await DriftLocalStore(db2).allSets(), hasLength(1),
        reason: '身体数据里的坏行**不许**连累训练记录');
  });

  test('动作库变了也能显示名字：备份里带了一份"动作 id → 中文名"', () async {
    // 这一条是设计上的**有意补偿**：动作名表让恢复后仍能显示中文，
    // 所以即使服务端/新版本的库里没有那个动作，用户也看得懂。
    final DriftLocalStore store = await seedRichDevice(db);
    final BackupBundle bundle = await collectBackup(
      store: store,
      repository: ExerciseRepository(db),
      profile: ProfileRepository(db),
      bodyMetrics: BodyMetricRepository(db),
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
