/// 练了么 · **完成页的 1400ms 时间轴**（VI 计划 T2-3，2026-10-10）
///
/// 一个用户练完一场、最有分享欲的那一屏，在视觉上原来**是一个静止的绿圆**
/// （76×76 的实心圆 + 一个字形勾，`AnimationController` 全仓 0 命中）。
/// 这一条给它一条时间轴：勾 0→420 ｜ 标题 300→700 ｜ 三格数字 420→1020 ｜
/// 解锁横条 900→1200 ｜ 完成键 1100→1400（毫秒）。
///
/// 判据（与计划一致）：
///   1. 四个时刻（420 / 900 / 1100 / 1400ms）采到的值**各不相同且单调** ——
///      这一条只有在**一条**时间轴上才可能成立（五条各自计时的曲线凑出来的是"一起淡入"）；
///   2. 减弱动态效果下 t=0 就看到画满的勾与三个终值；
///   3. **1400ms 内点完成能立刻返回**（两个按钮从 t0 起就可点，不许 `IgnorePointer`）；
///   4. `workout_summary_screen.dart` 里没有 `Icons.check_rounded`（勾是自绘的）。
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/check_painter.dart';
import 'package:lianleme/core/theme.dart';
// db.dart（drift 表）与 models.dart（领域模型）都定义了 SetRecord / Workout，预先 hide。
import 'package:lianleme/data/db.dart' hide SetRecord, Workout;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/badges.dart';
import 'package:lianleme/features/summary/workout_summary.dart';
import 'package:lianleme/features/summary/workout_summary_screen.dart';

/// 时间轴上的四个采样时刻（毫秒）—— 与计划里的判据一字不差。
const List<int> kSampleMs = <int>[420, 900, 1100, 1400];

/// 一枚"刚解锁"的徽章（解锁横条只在真的有新解锁时出现）。
BadgeStatus _badge(String id, String name) => BadgeStatus(
      id: id,
      name: name,
      how: '练一次',
      tier: BadgeTier.common,
      category: BadgeCategory.streak,
      current: 1,
      target: 1,
      unlocked: true,
    );

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  late DriftLocalStore store;
  late ExerciseRepository repo;
  late SummaryService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
    repo = ExerciseRepository(db);
    service = SummaryService(store: store, repository: repo);
    await repo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
  });

  tearDown(() => db.close());

  /// 造一场"数字好看"的训练：容量是四位数、时长**超过一小时**、组数两位数 ——
  /// 三格都值得滚（组数 < 10 时按纪律**不滚**，那样这条测试就测了个寂寞）。
  Future<void> logWorkout(String id) async {
    await store.saveWorkout(Workout(id: id, startedAtMs: 0));
    for (int i = 0; i < 12; i++) {
      await store.saveSet(SetRecord(
        id: '$id|$i',
        workoutId: id,
        exerciseId: 'ex_bb_bench_press',
        setIndex: i + 1,
        reps: 10,
        weightKg: 65,
        // 每组间隔 6 分钟 → 整场约 66 分钟（跨过 1 小时，把"时长"那格的另一种写法也滚到）
        completedAtMs: i * 6 * 60 * 1000,
      ));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    String workoutId, {
    bool reduced = false,
    List<BadgeStatus> badges = const <BadgeStatus>[],
  }) async {
    final Widget screen = WorkoutSummaryScreen(
      service: service,
      workoutId: workoutId,
      newBadges: badges,
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: reduced
          ? MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: screen,
            )
          : screen,
    ));
    // ⚠️ 数据是异步读出来的（`_load`）：先让它在"没有动画也能推进"的帧里就绪。
    // 用 `pump()` 而不是 `pumpAndSettle()` —— 后者会把整条 1400ms 一口气跑完，
    // 那样就无从在四个时刻采样了。
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();
  }

  /// 采集当前帧的四个值：(勾的画满比例, 三格数字, 解锁横条 opacity, 完成键 opacity)
  List<String> sample(WidgetTester tester) {
    final CustomPaint paint = tester.widget<CustomPaint>(
      find.byKey(const Key('summary-check')),
    );
    final CheckPainter painter = paint.painter! as CheckPainter;
    final String numbers = <String>[
      tester.widget<Text>(find.byKey(const Key('summary-volume'))).data!,
      tester.widget<Text>(find.byKey(const Key('summary-duration'))).data!,
      tester.widget<Text>(find.byKey(const Key('summary-sets'))).data!,
    ].join(' | ');
    final Finder unlock = find.byKey(const Key('summary-unlock-opacity'));
    final String unlockOpacity = unlock.evaluate().isEmpty
        ? '—'
        : tester.widget<Opacity>(unlock).opacity.toStringAsFixed(3);
    final String doneOpacity = tester
        .widget<Opacity>(find.byKey(const Key('summary-done-opacity')))
        .opacity
        .toStringAsFixed(3);
    return <String>[
      painter.progress.toStringAsFixed(3),
      numbers,
      unlockOpacity,
      doneOpacity,
    ];
  }

  testWidgets('完成页时间轴在四个时刻的值各不相同且单调', (WidgetTester tester) async {
    await logWorkout('w1');
    await pump(tester, 'w1', badges: <BadgeStatus>[_badge('first', '首训')]);

    final List<List<String>> samples = <List<String>>[];
    int elapsed = 0;
    for (final int at in kSampleMs) {
      await tester.pump(Duration(milliseconds: at - elapsed));
      elapsed = at;
      samples.add(sample(tester));
    }

    // ① **各不相同**：四个时刻的元组两两不同（"一起淡入"会给出四个一样的值）
    for (int i = 0; i < samples.length; i++) {
      for (int j = i + 1; j < samples.length; j++) {
        expect(samples[i], isNot(samples[j]),
            reason: '第 ${kSampleMs[i]}ms 与 ${kSampleMs[j]}ms 采到的值一模一样：'
                '${samples[i]} —— 那不是时间轴，是一起淡入');
      }
    }

    // ② **单调**：勾越画越满、数字越滚越大、两条 opacity 只增不减
    double check(int i) => double.parse(samples[i][0]);
    for (int i = 1; i < samples.length; i++) {
      expect(check(i), greaterThanOrEqualTo(check(i - 1)), reason: '勾的画满比例必须单调');
    }
    expect(check(0), 1.0, reason: '420ms 时勾该写完了');
    expect(double.parse(samples[2][3]), lessThan(1.0), reason: '1100ms 时完成键还没到全亮');
    expect(double.parse(samples[3][3]), 1.0, reason: '1400ms 时完成键到全亮');
  });

  testWidgets('三格数字**同时**滚，不许错峰（同一段 420→1020ms）',
      (WidgetTester tester) async {
    await logWorkout('w1');
    await pump(tester, 'w1');

    await tester.pump(const Duration(milliseconds: 1600));
    // 终值必须与"不滚时应有的字符串"一字不差
    final WorkoutSummary s = (await service.build('w1'))!;
    expect(tester.widget<Text>(find.byKey(const Key('summary-volume'))).data,
        s.volumeLabel);
    expect(tester.widget<Text>(find.byKey(const Key('summary-duration'))).data,
        s.durationLabel);
    expect(tester.widget<Text>(find.byKey(const Key('summary-sets'))).data,
        '${s.totalSets}');
  });

  testWidgets('减弱动态效果下 t=0 就能看到画满的勾与三个终值',
      (WidgetTester tester) async {
    await logWorkout('w1');
    await pump(tester, 'w1', reduced: true);

    final WorkoutSummary s = (await service.build('w1'))!;
    final List<String> now = sample(tester);
    expect(double.parse(now[0]), 1.0, reason: '减弱动态效果 → 勾直接是画满的');
    expect(now[1], <String>[s.volumeLabel, s.durationLabel, '${s.totalSets}'].join(' | '));
    expect(double.parse(now[3]), 1.0, reason: '完成键也直接到位');
  });

  testWidgets('1400ms 内点完成能立刻返回（两个按钮从 t0 起就可点）',
      (WidgetTester tester) async {
    await logWorkout('w1');
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Builder(
        builder: (BuildContext ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      WorkoutSummaryScreen(service: service, workoutId: 'w1'),
                ),
              ),
              child: const Text('看总结'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('看总结'));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('训练完成！'), findsOneWidget);

    // **动画刚开始就点**（时间轴还在跑）
    await tester.tap(find.byKey(const Key('summary-done')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('训练完成！'), findsNothing,
        reason: '按钮在动画期间必须可点（不许 `IgnorePointer`）—— 手快的人不必等 1400ms');
    expect(find.text('看总结'), findsOneWidget);
  });

  test('反向自检：勾是自绘的（那一屏里没有现成的对勾字形）', () {
    final String src = File(
            'lib/features/summary/workout_summary_screen.dart')
        .readAsStringSync();
    expect(src.contains('Icons.check_rounded'), isFalse);
    expect(src.contains('CheckPainter'), isTrue,
        reason: '勾要走 `CheckPainter`（`PathMetric` 抽笔画），不是字形');
    // 时间轴是一条控制器 + Interval：五个 TweenAnimationBuilder 凑不出"四个时刻各不相同"
    expect(src.contains('AnimationController'), isTrue);
    expect(src.contains('Interval('), isTrue);
  });
}
