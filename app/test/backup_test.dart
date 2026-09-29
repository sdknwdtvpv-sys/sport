/// 练了么 · 备份（导出 / 导入 / 粘贴）
///
/// 这一批解决的是**数据安全**：对手（训记）评论里最集中的抱怨就是数据丢失，
/// 而 `PRODUCT.md` §10.5 自己写着"数据丢失是工具类死刑" ——
/// 在此之前我们**只有把 CSV 复制到剪贴板，一条导入路径都没有**。
///
/// 三条线都要锁住：
///   1. 编解码本身（纯函数）：导回来是同一批数据，坏行不能连累好行
///   2. 导回库里：7 天窗口、幂等
///   3. 界面：导出交出去的是备份（不是那份报表 CSV）、导入真的写库、错误留在弹层里
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/backup.dart';
import 'package:lianleme/features/profile/backup_exporter.dart';
import 'package:lianleme/features/profile/profile_screen.dart';
import 'package:lianleme/features/progress/progress_data.dart';

const int _day = Duration.millisecondsPerDay;

SetRecord _set({
  required String id,
  String workoutId = 'w1',
  String exerciseId = 'ex_bb_bench_press',
  int setIndex = 1,
  int reps = 8,
  double? weightKg = 60,
  int atMs = 1000,
  SetType setType = SetType.normal,
  double? rpe,
  double? distanceM,
}) =>
    SetRecord(
      id: id,
      distanceM: distanceM,
      workoutId: workoutId,
      exerciseId: exerciseId,
      setIndex: setIndex,
      reps: reps,
      completedAtMs: atMs,
      weightKg: weightKg,
      setType: setType,
      rpe: rpe,
    );

/// 记一次训练（含一组热身 + 两组正式），字段尽量都填上，好验证没有丢字段。
Workout _workout(String id, {int atMs = 1000}) {
  final Workout w = Workout(id: id, startedAtMs: atMs, endedAtMs: atMs + 3600000);
  w.sets.addAll(<SetRecord>[
    _set(id: '${id}_1', workoutId: id, setIndex: 1, reps: 15, weightKg: null,
        atMs: atMs, setType: SetType.warmup),
    _set(id: '${id}_2', workoutId: id, setIndex: 2, reps: 8, atMs: atMs + 60000,
        rpe: 8),
    _set(id: '${id}_3', workoutId: id, setIndex: 3, reps: 8, atMs: atMs + 120000),
  ]);
  return w;
}

/// 只接住分享调用的假实现 —— 插件调用验证不了，但"交出去了什么"可以。
class _FakeExporter implements BackupExporter {
  String? json;
  String? fileName;

  @override
  Future<void> shareBackup(String json, {required String fileName}) async {
    this.json = json;
    this.fileName = fileName;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('备份编解码（纯函数）', () {
    test('导出再导回来是同一批数据：热身标记、RPE、秒级时间、组序都不丢', () {
      final String json = encodeBackup(
        workouts: <Workout>[_workout('w1')],
        exerciseNames: <String, String>{'ex_bb_bench_press': '杠铃卧推'},
        nowMs: 1790612345678,
      );

      final BackupParse parsed = parseBackup(json);
      expect(parsed.ok, isTrue);
      expect(parsed.workoutCount, 1);
      expect(parsed.setCount, 3);

      final Workout w = parsed.workouts.single;
      expect(w.id, 'w1');
      expect(w.startedAtMs, 1000);
      expect(w.endedAtMs, 3601000, reason: '时长要用它，不能丢');

      expect(w.sets[0].setType, SetType.warmup, reason: '热身标记丢了会被算进计划进度');
      expect(w.sets[0].weightKg, isNull);
      expect(w.sets[1].rpe, 8);
      expect(w.sets[2].completedAtMs, 121000, reason: '秒级时间不能只剩分钟');
      expect(w.sets.map((SetRecord s) => s.setIndex).toList(), <int>[1, 2, 3]);
    });

    test('有氧的距离进得了备份、也回得来（format 2）', () {
      final Workout cardio = Workout(id: 'w_run', startedAtMs: 1000, endedAtMs: 1801000)
        ..sets.add(_set(
          id: 's_run_1',
          workoutId: 'w_run',
          exerciseId: 'ex_treadmill_incline_walk',
          reps: 1800,
          weightKg: null,
          distanceM: 5000,
        ));

      final String json = encodeBackup(
        workouts: <Workout>[cardio],
        exerciseNames: const <String, String>{'ex_treadmill_incline_walk': '跑步机爬坡走'},
        nowMs: 1790612345678,
      );
      final Map<String, dynamic> root = jsonDecode(json) as Map<String, dynamic>;
      expect(root['format'], 2, reason: '加了字段就要升版本，否则老备份的语义会漂');

      final BackupParse parsed = parseBackup(json);
      expect(parsed.ok, isTrue);
      final SetRecord back = parsed.workouts.single.sets.single;
      expect(back.distanceM, 5000);
      expect(back.reps, 1800);
      expect(back.weightKg, isNull);
    });

    test('format 1 的老备份照样能读 —— 距离是 null（没记过），不是 0', () {
      // 手写一份 v1 备份：那时还没有 distance_m 这个字段。
      // 兼容不是"能不能解析"，而是**语义对不对**：老备份里的组是"没记过距离"，
      // 导进来变成 0 公里就凭空多了一条"真的没动"的记录。
      const String v1 = '''
{
  "app": "lianleme", "format": 1, "unit": "kg",
  "exercise_names": {"ex_bb_bench_press": "杠铃卧推"},
  "workouts": [
    {"id": "w1", "started_at": 1000, "ended_at": 3601000,
     "sets": [{"id": "s1", "exercise_id": "ex_bb_bench_press", "set_index": 1,
               "reps": 8, "weight_kg": 60, "set_type": "normal",
               "rpe": 8, "completed_at": 1000}]}
  ]
}
''';
      final BackupParse parsed = parseBackup(v1);

      expect(parsed.ok, isTrue);
      expect(parsed.setCount, 1);
      final SetRecord s = parsed.workouts.single.sets.single;
      expect(s.weightKg, 60);
      expect(s.distanceM, isNull, reason: '老备份里没有距离这件事');
      expect(s.hasDistance, isFalse);
      expect(s.volume, 480, reason: '力量组的容量不受影响');
    });

    test('重量一律 kg —— 备份不跟显示单位走', () {
      final String json = encodeBackup(
        workouts: <Workout>[_workout('w1')],
        exerciseNames: const <String, String>{},
      );
      final Map<String, dynamic> root = jsonDecode(json) as Map<String, dynamic>;

      expect(root['unit'], 'kg');
      expect(json.contains('lb'), isFalse,
          reason: '一份 lb 备份导进 kg 手机上会静默变成另一组数字');
      // 60 写进去就是 60，不因为界面上显示 lb 而变成 132.3
      final BackupParse parsed = parseBackup(json);
      expect(parsed.workouts.single.sets[1].weightKg, 60);
    });

    test('粘错东西时给的是人话，不是 JSON 解析异常', () {
      expect(parseBackup('').error, contains('空'));
      expect(parseBackup('这是我今天的训练记录哈哈哈哈').error, contains('JSON'));
      expect(parseBackup('[1,2,3]').error, contains('顶层不是对象'));
      expect(parseBackup('{"app":"xunji","workouts":[]}').error,
          contains('不是练了么的'));
      expect(parseBackup('{"app":"lianleme"}').error, contains('workouts'));
    });

    test('坏行跳过并计数，好行照常进来（不因一行坏掉整份作废）', () {
      const String json = '''
{
  "app": "lianleme",
  "format": 1,
  "workouts": [
    {"id": "w1", "started_at": 1000, "ended_at": 2000, "sets": [
      {"id": "s1", "exercise_id": "ex_bb_bench_press", "set_index": 1,
       "reps": 8, "weight_kg": 60, "completed_at": 1000},
      {"id": "s2", "exercise_id": "ex_bb_bench_press", "set_index": 2},
      {"nope": true}
    ]},
    {"id": "w2"},
    "这不是个对象"
  ]
}''';
      final BackupParse parsed = parseBackup(json);

      expect(parsed.ok, isTrue);
      expect(parsed.setCount, 1, reason: '只有 s1 是完整的');
      expect(parsed.workoutCount, 1, reason: 'w2 一条组都没有，不写空训练');
      // 坏行：缺字段的 s2、不是对象的 {"nope":true}、缺 started_at 的 w2、
      // 以及 workouts 里那个字符串 —— 一共 4 条
      expect(parsed.skippedSets, 4, reason: '坏行必须如实计数，界面要说出来');
    });

    test('一份组全是坏行的备份：不崩、也不算成功导入', () {
      const String json =
          '{"app":"lianleme","workouts":[{"id":"w1","started_at":1,"sets":[{"id":"s"}]}]}';
      final BackupParse parsed = parseBackup(json);

      expect(parsed.ok, isTrue, reason: '格式没问题');
      expect(parsed.setCount, 0, reason: '但没东西可导 —— 界面据此提示"一条记录都没有"');
    });

    test('文件名带日期，存多份也分得清', () {
      final int ms = DateTime(2026, 9, 29, 10, 30).millisecondsSinceEpoch;
      expect(backupFileName(ms), '练了么-备份-2026-09-29.json');
    });
  });

  group('导回库里（"预置 6 周历史"靠的就是这条）', () {
    late AppDatabase db;
    late DriftLocalStore store;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftLocalStore(db);
    });
    tearDown(() => db.close());

    /// 导入 = 把解析出来的训练逐组写回去 + 写训练行本身。
    Future<void> importInto(DriftLocalStore s, BackupParse parsed) async {
      for (final Workout w in parsed.workouts) {
        for (final SetRecord r in w.sets) {
          await s.saveSet(r);
        }
        await s.saveWorkout(w);
      }
    }

    test('导入后 allSets 拿得到，7 天窗口只算最近的', () async {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final BackupParse parsed = parseBackup(encodeBackup(
        workouts: <Workout>[
          _workout('w_recent', atMs: now - 2 * _day),
          _workout('w_old', atMs: now - 40 * _day),
        ],
        exerciseNames: const <String, String>{},
      ));

      await importInto(store, parsed);

      final List<SetRecord> sets = await store.allSets();
      expect(sets.length, 4,
          reason: 'allSets 只给正式组：两次训练各 2 组（各有一组热身）');

      // 这就是可用性测试要的"预置 6 周历史"：库里有，但不会把首页"上周"数字顶起来
      expect(weekWorkoutCount(sets, DateTime.fromMillisecondsSinceEpoch(now)), 1);
    });

    test('同一份粘两次不会变成两份（幂等 —— id 是确定性的）', () async {
      final BackupParse parsed = parseBackup(encodeBackup(
        workouts: <Workout>[_workout('w1')],
        exerciseNames: const <String, String>{},
      ));

      await importInto(store, parsed);
      await importInto(store, parsed);

      expect((await store.allSets()).length, 2, reason: '正式组 2 条');
      expect((await store.setsFor('w1')).length, 3, reason: '含热身组一共 3 条');
    });

    test('导进来的历史能喂给引擎（不只是躺在那儿）', () async {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final BackupParse parsed = parseBackup(encodeBackup(
        // 各组完成时间都锚在"2 天前再往前 10 分钟"：不然最后一组是
        // "2 天差 2 分钟"，daysAgo 取整成 1（这个坑在契约测试里也踩过一次）
        workouts: <Workout>[_workout('w_prev', atMs: now - 2 * _day - 600000)],
        exerciseNames: const <String, String>{},
      ));
      await importInto(store, parsed);

      final LastSession? last = await store.lastSessionFor('ex_bb_bench_press');
      expect(last, isNotNull);
      expect(last!.reps, <int>[8, 8], reason: '只算正式组，热身不进引擎');
      expect(last.weightKg, 60);
      expect(last.daysAgo, 2);
    });
  });

  group('界面：导出与导入', () {
    late AppDatabase db;
    late DriftLocalStore store;
    late ExerciseRepository repo;
    late ProfileRepository profile;
    final _FakeExporter exporter = _FakeExporter();
    String? clipboard;
    int dataChanged = 0;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftLocalStore(db);
      repo = ExerciseRepository(db);
      profile = ProfileRepository(db);
      await repo.importSeed(
        loadJson: () => File('assets/exercises.json').readAsString(),
      );
      exporter.json = null;
      exporter.fileName = null;
      clipboard = null;
      dataChanged = 0;

      // 剪贴板是平台通道，测试里自己接住（读与写都要）
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform,
              (MethodCall call) async {
        // ⚠️ 不能无条件强转：SystemChannels.platform 上有些方法的参数是 String，
        // 强转会抛 PlatformException，把整批测试带崩（踩过一次）。
        final Object? raw = call.arguments;
        final Map<Object?, Object?> args =
            raw is Map ? raw.cast<Object?, Object?>() : <Object?, Object?>{};
        if (call.method == 'Clipboard.setData') {
          clipboard = args['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboard};
        }
        return null;
      });
    });

    tearDown(() => db.close());

    Future<void> pumpProfile(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            store: store,
            repository: repo,
            profile: profile,
            backupExporter: exporter,
            onDataChanged: () => dataChanged++,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// 800×600 装不下「我」页，ListView 又是懒构建的 —— 必须滚到才找得到。
    Future<void> scrollTo(WidgetTester tester, Finder target) async {
      await tester.dragUntilVisible(
        target,
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('「导出备份文件」交出去的就是能导回的备份', (WidgetTester tester) async {
      await store.saveSet(_set(id: 's1'));
      await pumpProfile(tester);

      await scrollTo(tester, find.byKey(const Key('export-backup')));
      await tester.tap(find.byKey(const Key('export-backup')));
      await tester.pumpAndSettle();

      expect(exporter.json, isNotNull, reason: '要真的交给系统分享面板');
      expect(exporter.fileName, endsWith('.json'));

      final BackupParse parsed = parseBackup(exporter.json!);
      expect(parsed.ok, isTrue);
      expect(parsed.setCount, 1);
      final Workout w = parsed.workouts.single;
      expect(w.sets.single.exerciseId, 'ex_bb_bench_press');
      // 这一组只有 set_record、**没有 workout 行**（saveSet 不建训练行）。
      // 备份是最后一道防线，所以这里必须仍然导得出来 ——
      // 时间用最早那一组兜底，宁可粗一点也不丢数据。
      expect(w.startedAtMs, 1000, reason: '缺训练行时用组的时间兜底');
      expect(w.id, 'w1');
    });

    testWidgets('粘贴 → 导入：库里真的多出来，并如实报条数', (WidgetTester tester) async {
      final String json = encodeBackup(
        workouts: <Workout>[_workout('w_imported')],
        exerciseNames: const <String, String>{},
      );
      await pumpProfile(tester);

      await scrollTo(tester, find.byKey(const Key('import-backup')));
      await tester.tap(find.byKey(const Key('import-backup')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('import-text')), json);
      await tester.tap(find.byKey(const Key('import-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-backup-dialog')), findsNothing,
          reason: '成功就关掉');
      expect((await store.allSets()).length, 2, reason: '3 组里有 1 组是热身');
      expect((await store.setsFor('w_imported')).length, 3, reason: '热身也算记录');
      expect(find.textContaining('已导入 1 次训练 / 3 组'), findsOneWidget);
      expect(dataChanged, 1, reason: '外壳要跟着刷新首页那个"我上周练了 N 次"');
    });

    testWidgets('粘进来的不是备份 → 弹层里报错、不关掉、库里不变',
        (WidgetTester tester) async {
      await pumpProfile(tester);

      await scrollTo(tester, find.byKey(const Key('import-backup')));
      await tester.tap(find.byKey(const Key('import-backup')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('import-text')), '今天练了卧推 60kg 8次');
      await tester.tap(find.byKey(const Key('import-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-error')), findsOneWidget,
          reason: '错误要留在弹层里 —— 关掉再弹 SnackBar 用户就得重新粘一遍');
      expect(find.byKey(const Key('import-backup-dialog')), findsOneWidget);
      expect(await store.allSets(), isEmpty);
    });

    testWidgets('「从剪贴板粘贴」把剪贴板内容填进输入框', (WidgetTester tester) async {
      clipboard = encodeBackup(
        workouts: <Workout>[_workout('w_clip')],
        exerciseNames: const <String, String>{},
      );
      await pumpProfile(tester);

      await scrollTo(tester, find.byKey(const Key('import-backup')));
      await tester.tap(find.byKey(const Key('import-backup')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import-paste')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-confirm')));
      await tester.pumpAndSettle();

      expect((await store.allSets()).length, 2);
    });

    testWidgets('导出用的是备份而不是那份报表 CSV（两者不能混）',
        (WidgetTester tester) async {
      await store.saveSet(_set(id: 's1'));
      await pumpProfile(tester);

      // 报表那条路仍然只往剪贴板写 CSV，不碰分享
      await scrollTo(tester, find.byKey(const Key('export-csv')));
      await tester.tap(find.byKey(const Key('export-csv')));
      await tester.pumpAndSettle();

      expect(clipboard, contains('日期,动作'));
      expect(exporter.json, isNull, reason: 'CSV 是报表，不是备份');
    });
  });
}
