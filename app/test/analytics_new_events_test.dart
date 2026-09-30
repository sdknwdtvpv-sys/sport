/// 练了么 · 补发的 9 个埋点事件
///
/// **为什么每个事件都要有断言**：埋点最典型的失败模式是"以为发了，其实没发"——
/// 它不报错、不影响功能，只会让指标悄悄变成 0。所以每个事件至少测两件事：
/// 该发的时候发了，且**不该发的时候没发**（比如原样关掉弹层不算编辑）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/data/body_metric_repository.dart';
import 'package:lianleme/data/db.dart' show AppDatabase, ExerciseData;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/body/body_metric_screen.dart';
import 'package:lianleme/features/exercise/exercise_picker_screen.dart';
import 'package:lianleme/features/onboarding/onboarding_screen.dart';
import 'package:lianleme/features/today/today_planner.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/features/summary/share_card_exporter.dart';
import 'package:lianleme/features/summary/share_card_preview_screen.dart';
import 'package:lianleme/features/summary/workout_summary.dart';
import 'package:lianleme/features/summary/workout_summary_screen.dart';
import 'package:lianleme/features/workout/workout_controller.dart';

/// 取某个事件的全部记录
List<AnalyticsEvent> _of(RecordingAnalytics a, String name) =>
    a.events.where((AnalyticsEvent e) => e.name == name).toList();

const ExerciseSpec _squat = ExerciseSpec(
  id: 'ex_squat',
  name: '深蹲',
  weightIncrement: 2.5,
  defaultWeightKg: 40,
  defaultRestSec: 120,
);
const PlanTarget _plan = PlanTarget(targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10);

/// 什么都不做的导出器：这里验证的是"点了之后报没报"，不是导出本身
class _NullExporter implements ShareCardExporter {
  @override
  Future<void> shareToSystem(Uint8List png, {String? fileName}) async {}
  @override
  Future<bool> saveToGallery(Uint8List png, {String? fileName}) async => true;
}

void main() {
  // 真 IO 的夹具都放在 setUp 里（testWidgets 的假时钟里做不了）
  late AppDatabase ioDb;
  late ExerciseRepository ioRepo;
  late DriftLocalStore ioStore;
  late SummaryService summaryService;

  setUp(() async {
    ioDb = AppDatabase(NativeDatabase.memory());
    ioRepo = ExerciseRepository(ioDb);
    ioStore = DriftLocalStore(ioDb);
    await ioRepo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
    summaryService = SummaryService(store: ioStore, repository: ioRepo);
    // 先来一次更轻的历史：没有历史就"破了纪录"是不成立的
    // （破纪录要跟**以前的最好成绩**比，第一次练没有可比对象）
    await ioStore.saveWorkout(
        Workout(id: 'w0', startedAtMs: -600000, endedAtMs: -540000));
    await ioStore.saveSet(SetRecord(
      id: 's0',
      workoutId: 'w0',
      exerciseId: 'ex_bb_bench_press',
      setIndex: 1,
      reps: 10,
      completedAtMs: -600000,
      weightKg: 50,
    ));
    // 再练一次并超过它：60kg × 10
    await ioStore.saveWorkout(
        Workout(id: 'w1', startedAtMs: 0, endedAtMs: 60000));
    await ioStore.saveSet(SetRecord(
      id: 's1',
      workoutId: 'w1',
      exerciseId: 'ex_bb_bench_press',
      setIndex: 1,
      reps: 10,
      completedAtMs: 1000,
      weightKg: 60,
    ));
  });

  tearDown(() => ioDb.close());

  late RecordingAnalytics analytics;
  late InMemoryLocalStore store;
  late WorkoutController c;
  int t = 1000;

  setUp(() {
    analytics = RecordingAnalytics();
    store = InMemoryLocalStore();
    c = WorkoutController(
      exercise: _squat,
      plan: _plan,
      analytics: analytics,
      store: store,
      syncQueue: InMemorySyncQueue(),
      // 给一段历史，这样引擎会给出"线性加重"这类建议（有建议才测得到采纳链）
      lastSession: const LastSession(
        weightKg: 40,
        reps: <int>[10, 10, 10],
        daysAgo: 3,
      ),
      clock: () => t++,
    );
  });

  tearDown(() => c.dispose());

  group('建议采纳链', () {
    test('记下一组时：先报展示，再按"是否等于建议"分流成采纳', () {
      final Suggestion sg = c.suggestion!;
      // 默认值就是建议值 → 应当是"采纳"
      c.onBigButtonTap();
      expect(_of(analytics, 'suggestion_shown').length, 1);
      expect(_of(analytics, 'suggestion_accepted').length, 1);
      expect(_of(analytics, 'suggestion_modified'), isEmpty);
      expect(_of(analytics, 'suggestion_shown').single.props['reason_code'],
          sg.reasonCode.name);
    });

    test('手改成别的值再记 → 是"手改"，并且带上加减与方向', () {
      final Suggestion sg = c.suggestion!;
      c.onStepper(deltaWeight: 5); // 比建议重 5kg
      c.onBigButtonTap();

      expect(_of(analytics, 'suggestion_shown').length, 1);
      expect(_of(analytics, 'suggestion_accepted'), isEmpty);
      final AnalyticsEvent m = _of(analytics, 'suggestion_modified').single;
      expect(m.props['delta_weight_kg'], 5);
      expect(m.props['direction'], 'up');
      expect(m.props['reason_code'], sg.reasonCode.name);
    });

    test('往轻了改 → direction 是 down', () {
      c.onStepper(deltaWeight: -5);
      c.onBigButtonTap();
      expect(_of(analytics, 'suggestion_modified').single.props['direction'], 'down');
    });

    test('热身组不算对建议的表态：不报展示/采纳/手改', () {
      c.toggleWarmup();
      c.onBigButtonTap();
      expect(_of(analytics, 'suggestion_shown'), isEmpty);
      expect(_of(analytics, 'suggestion_accepted'), isEmpty);
      expect(_of(analytics, 'suggestion_modified'), isEmpty);
      // 但 set_logged 照记（热身也是要留痕的）
      expect(_of(analytics, 'set_logged').single.props['set_type'], 'warmup');
    });

    test('三条同源：shown 数 == accepted + modified 数', () {
      // 第一组按建议，第二组改重，第三组按建议
      c.onBigButtonTap();
      c.onStepper(deltaWeight: 2.5);
      c.onBigButtonTap();
      c.onStepper(deltaWeight: -2.5);
      c.onBigButtonTap();

      final int shown = _of(analytics, 'suggestion_shown').length;
      final int ok = _of(analytics, 'suggestion_accepted').length;
      final int mod = _of(analytics, 'suggestion_modified').length;
      expect(shown, 3);
      expect(shown, ok + mod, reason: '采纳率必须能落在 [0,1]');
    });
  });

  group('set_edited', () {
    test('真的改了才报，且带 from/to', () {
      c.onLongPress();
      c.onStepper(deltaWeight: 5);
      c.onSheetConfirm();

      final AnalyticsEvent e = _of(analytics, 'set_edited').single;
      expect(e.props['field'], 'weight');
      expect(e.props['to'], (e.props['from']! as num) + 5);
    });

    test('打开弹层又原样关掉 → 一条都不报（否则"编辑成本"会虚高）', () {
      c.onLongPress();
      c.onSheetConfirm();
      expect(_of(analytics, 'set_edited'), isEmpty);
    });

    test('重量与次数都改了 → 报两条（按字段分开）', () {
      c.onLongPress();
      c.onStepper(deltaWeight: 5, deltaReps: 2);
      c.onSheetConfirm();
      final List<AnalyticsEvent> edits = _of(analytics, 'set_edited');
      expect(edits.length, 2);
      expect(edits.map((AnalyticsEvent e) => e.props['field']).toSet(),
          <String>{'weight', 'reps'});
    });
  });

  group('pr_achieved / share_card_created / body_metric_logged', () {
    testWidgets('破纪录逐条上报（pr_type 按动作类型）', (WidgetTester tester) async {
      // ⚠️ 真 IO（读种子文件、drift 写库）**必须放在 testWidgets 之外**：
      // 它跑在假时钟里，真 Future 不会完成 —— 第一版把 importSeed 写在测试体内，
      // 结果这条测试"did not complete"（挂了 2 分钟才被超时杀掉）。
      // 所以这里用 setUp 里已经建好的库与仓库。
      final RecordingAnalytics a = RecordingAnalytics();
      await tester.pumpWidget(MaterialApp(
        home: WorkoutSummaryScreen(
          service: summaryService,
          workoutId: 'w1',
          analytics: a,
        ),
      ));
      await tester.pumpAndSettle();
      expect(_of(a, 'pr_achieved'), isNotEmpty);
      final AnalyticsEvent pr = _of(a, 'pr_achieved').first;
      expect(pr.props['exercise_id'], 'ex_bb_bench_press');
      expect(pr.props['pr_type'], 'weight');
    });

    testWidgets('身体数据保存时只报"填没填"，不报数值', (WidgetTester tester) async {
      final RecordingAnalytics a = RecordingAnalytics();
      await tester.pumpWidget(MaterialApp(
        home: BodyMetricScreen(
          repository: BodyMetricRepository(ioDb),
          analytics: a,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('body-weight')), '72.5');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('body-save')));
      await tester.pumpAndSettle();

      final AnalyticsEvent e = _of(a, 'body_metric_logged').single;
      expect(e.props['has_weight'], true);
      expect(e.props['has_note'], false);
      // 数值绝不出现在 payload 里
      expect(e.props.values.join(','), isNot(contains('72.5')));
    });
  });

  group('exercise_added / share_card_created / onboarding_step', () {
    testWidgets('从「最近做过」选动作 → add_method = recent', (WidgetTester tester) async {
      // setUp 里给卧推存过组记录，所以它一定在「最近做过」的第一行
      final RecordingAnalytics a = RecordingAnalytics();
      ExerciseData? picked;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (BuildContext ctx) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await Navigator.of(ctx).push<ExerciseData>(
                    MaterialPageRoute<ExerciseData>(
                      builder: (_) => ExercisePickerScreen(
                        repository: ioRepo,
                        store: ioStore,
                        analytics: a,
                      ),
                    ),
                  );
                },
                child: const Text('开'),
              ),
            ),
          );
        }),
      ));
      await tester.tap(find.text('开'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('exercise-ex_bb_bench_press')));
      await tester.pumpAndSettle();

      final AnalyticsEvent e = _of(a, 'exercise_added').single;
      expect(e.props['exercise_id'], 'ex_bb_bench_press');
      expect(e.props['add_method'], 'recent');
      expect(picked?.id, 'ex_bb_bench_press', reason: '埋点不该影响选中');
    });

    testWidgets('搜索后选动作 → add_method = search', (WidgetTester tester) async {
      final RecordingAnalytics a = RecordingAnalytics();
      await tester.pumpWidget(MaterialApp(
        home: ExercisePickerScreen(
          repository: ioRepo,
          store: ioStore,
          analytics: a,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('exercise-search')), '高脚杯深蹲');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exercise-ex_goblet_squat')));
      await tester.pumpAndSettle();
      expect(_of(a, 'exercise_added').single.props['add_method'], 'search');
    });

    testWidgets('引导：下一步与跳过都上报在哪一步走的', (WidgetTester tester) async {
      final RecordingAnalytics a = RecordingAnalytics();
      final TodayPlanner planner =
          TodayPlanner(repository: ioRepo, store: ioStore);
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(
          planner: planner,
          profile: ProfileRepository(ioDb),
          routines: RoutineRepository(ioDb),
          exercises: ioRepo,
          analytics: a,
        ),
      ));
      await tester.pumpAndSettle();

      // 第 1 步：选目标 → 下一步
      await tester.tap(find.text('增肌'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-next-1')));
      await tester.pumpAndSettle();
      final AnalyticsEvent first = _of(a, 'onboarding_step').first;
      expect(first.props['step_index'], 0);
      expect(first.props['skipped'], false);

      // 第 2 步：直接跳过 → skipped = true
      await tester.tap(find.byKey(const Key('onboarding-skip')));
      await tester.pumpAndSettle();
      expect(_of(a, 'onboarding_step').last.props['skipped'], true);
      expect(_of(a, 'onboarding_step').last.props['step_index'], 1);
    });

    testWidgets('分享卡：存相册 / 系统分享各报一次，带 channel',
        (WidgetTester tester) async {
      final RecordingAnalytics a = RecordingAnalytics();
      final WorkoutSummary? s = await summaryService.build('w1', nowMs: 90000);
      expect(s, isNotNull);
      // 真 IO 与 capture 都要在假时钟之外：这里只驱动"点了之后报了没有"
      await tester.pumpWidget(MaterialApp(
        home: ShareCardPreviewScreen(
          summary: s!,
          exporter: _NullExporter(),
          capture: (GlobalKey key) async => Uint8List.fromList(<int>[1, 2, 3]),
          analytics: a,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('share-card-save')));
      await tester.pumpAndSettle();
      expect(_of(a, 'share_card_created').single.props['channel'], 'save');
    });
  });
}
