/// 练了么 · **大字号全屏扫描**（VI 计划 §7 E 组"`xxxLarge` 下不许溢出"的整屏版）
///
/// **为什么要有它**：计划里那条判据只盯了"主按钮的高度"，而 2026-10-10 收尾时
/// 我在 **2.0×** 下抓到训练屏真溢出 17px ——「本次 · N 组」+「长按某一行可撤销」
/// 那一行合计 388pt > 屏宽 371pt。**一件事只有被整屏扫过，才知道它到底通不通**：
/// 零散地测某一屏某一处，正是这类缺陷活下来的方式。
///
/// 覆盖范围：能便宜地构造出来的**主要屏**（见 [kScreens]）。
/// ⚠️ 没覆盖的（需要更重的依赖，如实记在下面，不当成通过）：
/// 身体数据页（要 `BodyMetricRepository` + 健康桥）、数据与备份（要 profile/backup/账号）、
/// 通知详情、分享卡预览（要导出器）、引导页（要 consent 流程）。
///
/// 判据：每一屏 × {1.5×, 2.0×} 下 `pump` 之后
/// **不许有 `RenderFlex overflowed`（`tester.takeException()` 必须为 null）**。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide SetRecord, Workout, Exercise, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/notification_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/billing/entitlement.dart';
import 'package:lianleme/billing/paywall_copy.dart';
import 'package:lianleme/billing/paywall_screen.dart';
import 'package:lianleme/data/entitlement_repository.dart';
import 'package:lianleme/features/exercise/exercise_picker_screen.dart';
import 'package:lianleme/health/health_bridge.dart';
import 'package:lianleme/features/notifications/notification_center_screen.dart';
import 'package:lianleme/features/notifications/notification_detail_screen.dart';
import 'package:lianleme/features/backup/cloud_backup_screen.dart';
import 'package:lianleme/features/profile/privacy_about_screen.dart';
import 'package:lianleme/features/onboarding/intro_carousel_screen.dart';
import 'package:lianleme/features/profile/settings_home_screen.dart';
import 'package:lianleme/data/body_metric_repository.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/features/body/body_metric_screen.dart';
import 'package:lianleme/features/profile/data_tools_screen.dart';
import 'package:lianleme/features/summary/share_card_preview_screen.dart';
import 'package:lianleme/features/progress/achievements_screen.dart';
import 'package:lianleme/features/progress/all_data_screen.dart';
import 'package:lianleme/features/progress/progress_screen.dart';
import 'package:lianleme/features/routine/plan_screen.dart';
import 'package:lianleme/features/summary/workout_summary.dart';
import 'package:lianleme/features/summary/workout_summary_screen.dart';
import 'package:lianleme/features/today/today_screen.dart';
import 'package:lianleme/features/workout/workout_controller.dart';
import 'package:lianleme/features/workout/workout_screen.dart';
import 'package:lianleme/features/workout/workout_session.dart';

/// 常见安卓机的逻辑尺寸（411×914）—— 比测试默认的 800×600 窄得多，
/// 而"溢出"几乎都是**窄屏 + 大字号**一起才出现。
const Size kPhone = Size(411, 914);
const double kPhoneDpr = 3.0;

/// 一次训练记录（总结页/全部数据页要有东西可显示才谈得上"展示态溢出"）。
/// 训练开始时间：组记录的第一组。
final int _startMs = DateTime(2026, 10, 10, 19).millisecondsSinceEpoch;

List<SetRecord> _sets() => <SetRecord>[
      for (int i = 0; i < 3; i++)
        SetRecord(
          id: 's$i',
          workoutId: 'w1',
          exerciseId: 'ex_bb_bench_press',
          setIndex: i + 1,
          reps: 10,
          weightKg: 65,
          completedAtMs: _startMs + i * 60000,
        ),
    ];

/// 假健康桥：`isAvailable=true`、读数返回空，**而且不挂 Timer**
/// （真身那个 5 秒超时见 `MethodChannelHealthBridge._probeTimeout`）。
class _FakeHealthBridge implements HealthBridge {
  const _FakeHealthBridge();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<List<HealthSample>> readBodyComposition({int days = 180}) async =>
      const <HealthSample>[];
}

void main() {
  /// 训练屏那个控制器要留个引用：点完大按钮会起**休息倒计时**（periodic Timer），
  /// 不掐掉测试结束时会报 "Pending timers"。
  WorkoutController? workoutController;

  late AppDatabase db;
  late DriftLocalStore store;
  late ExerciseRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
    repo = ExerciseRepository(db);
    await repo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
    // 总结页与分享卡预览要有**一条真记录**才谈得上"展示态溢出"
    // ⚠️ 起始时间必须是**真实的那天**：早先写 `startedAtMs: 0`（1970），
    // 而组记录在 2026-10-10 —— 于是摘要时长算出来是「295131 小时 47 分」，
    // 分享卡的「时长」一栏被这串假数据顶出 20px 溢出。
    // 那是**测试自己的假数据**造出来的溢出，不是产品的：修种子，不改版式
    // （把值改成 `Flexible` + 省略号反而是错的 —— 分享卡上的数字不能被截断）。
    await store.saveWorkout(
        Workout(id: 'w1', startedAtMs: _startMs));
    for (final SetRecord r in _sets()) {
      await store.saveSet(r);
    }
  });

  tearDown(() => db.close());

  /// 一屏怎么造。`label` 只用于报错信息。
  final Map<String, Future<Widget> Function()> screens =
      <String, Future<Widget> Function()>{
    '首页': () async => TodayScreen(onStart: () {}, onOpenLibrary: () {}),
    '进步页': () async => ProgressScreen(
          store: store,
          repository: repo,
          onOpenToday: () {},
          now: DateTime(2026, 10, 10),
        ),
    '全部数据页': () async => AllDataScreen(
          store: store,
          repository: repo,
          now: DateTime(2026, 10, 10),
        ),
    '动作库': () async => ExercisePickerScreen(repository: repo),
    '通知中心': () async => NotificationCenterScreen(repository: NotificationRepository(db)),
    '计划页': () async => PlanScreen(
          repository: RoutineRepository(db),
          exercises: repo,
          store: store,
          onBack: () {},
          now: DateTime(2026, 10, 10),
        ),
    '成就册': () async => AchievementsScreen(sets: _sets()),
    '设置页': () async => SettingsHomeScreen(
          store: store,
          repository: repo,
          profile: ProfileRepository(db),
        ),
    '总结页': () async => WorkoutSummaryScreen(
          service: SummaryService(store: store, repository: repo),
          workoutId: 'w1',
        ),
    // ⚠️ 健康桥**必须注入**：真身 `MethodChannelHealthBridge.isAvailable()`
    // 挂了一个 5 秒超时 Timer 等平台回话，widget 测试里平台不会回话，测试结束
    // 就报 "A Timer is still pending" —— 那和"溢出不溢出"没有关系，却把这一屏
    // 一直染成红的。两条路径都要扫：没有健康库（真机上的安卓/旧包）与有入口。
    '身体数据页': () async => BodyMetricScreen(
          repository: BodyMetricRepository(db),
          clock: () => DateTime(2026, 10, 10, 8),
          healthBridge: const NoopHealthBridge(),
        ),
    '身体数据页（有健康入口）': () async => BodyMetricScreen(
          repository: BodyMetricRepository(db),
          clock: () => DateTime(2026, 10, 10, 8),
          healthBridge: const _FakeHealthBridge(),
        ),
    '数据与备份': () async => DataToolsScreen(
          store: store,
          repository: repo,
          profile: ProfileRepository(db),
        ),
    // 收尾补的四屏：都是"能到、但原来没人扫过大字号"的二级页。
    // 通知详情是最窄的一屏（ProfileSubPage + 图标 + 长正文）；
    // 「隐私与关于」那几段撤回说明是**全 App 最长的正文**；
    // 云备份页有一行状态 + 一个主按钮；引导轮播是首启动第一眼。
    '通知详情': () async => NotificationDetailScreen(
          notification: AppNotificationData(
            id: 'n1',
            kind: 'achievement',
            title: '解锁了新徽章',
            body: '你解锁了「连续 7 天」——这个提示本身也会很长，'
                '长到在大字号下必须能换行而不是把右边顶出去。',
            createdAtMs: DateTime(2026, 10, 10, 9).millisecondsSinceEpoch,
          ),
        ),
    '云备份': () async => CloudBackupScreen(
          store: store,
          repository: repo,
          profile: ProfileRepository(db),
        ),
    '隐私与关于': () async => PrivacyAboutScreen(profile: ProfileRepository(db)),
    '引导轮播': () async => IntroCarouselScreen(
          onSkip: () {},
          onStartFirst: () {},
        ),
    // 会员页（M1，2026-10-10）：它有"三档商品 + 说明块 + 三个入口"，
    // 是大字号下最容易挤的一屏之一（价格数字用了 tabular，但仍要扫）。
    '会员页': () async => PaywallScreen(
          repository: EntitlementRepository(db),
          catalog: const _SweepCatalog(),
          now: () => DateTime(2026, 10, 10, 12),
        ),
    '分享卡预览': () async => ShareCardPreviewScreen(
          summary: (await SummaryService(store: store, repository: repo)
              .build('w1', unit: WeightUnit.kg))!,
          analytics: RecordingAnalytics(),
        ),
    '训练屏（记过一组）': () async {
      final WorkoutController c = WorkoutController(
        exercise: const ExerciseSpec(
          id: 'ex_bb_bench_press',
          name: '杠铃卧推',
          weightIncrement: 2.5,
          defaultWeightKg: 40,
          defaultRestSec: 60,
        ),
        plan: const PlanTarget(targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10),
        analytics: RecordingAnalytics(),
        store: InMemoryLocalStore(),
        syncQueue: InMemorySyncQueue(),
        clock: () => 1000000,
      );
      workoutController = c;
      final Widget screen = WorkoutScreen(session: WorkoutSession.single(c));
      // 记一组（休息条 + 已完成行都出现）—— 那正是溢出被藏起来的地方
      // 调用方会在 pump 之后点一次大按钮（见下面的 `tapBigButton`）。
      return screen;
    },
  };

  for (final double scale in <double>[1.5, 2.0]) {
    for (final MapEntry<String, Future<Widget> Function()> e in screens.entries) {
      testWidgets('${e.key}：${scale}× 下不溢出', (WidgetTester tester) async {
        tester.view.physicalSize = kPhone * kPhoneDpr;
        tester.view.devicePixelRatio = kPhoneDpr;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final List<String> overflowing = <String>[];

        /// 扫一遍横向 `RenderFlex`，把"子宽度之和 > 自身宽度"的那些记下来。
        ///
        /// ⚠️ **每一帧之后都要扫**：溢出可能只出现在中间某一帧（加载态 / 弹层刚出现时），
        /// 到最后一帧已经恢复正常 —— 只在最后扫一次会漏掉它（第一版就是这么漏的）。
        void scanOverflow() {
          for (final Element el in tester.allElements) {
            final RenderObject? ro = el.renderObject;
            if (ro is! RenderFlex || ro.direction != Axis.horizontal) continue;
            double sum = 0;
            RenderBox? child = ro.firstChild;
            while (child != null) {
              sum += child.size.width;
              child = ro.childAfter(child);
            }
            if (sum > ro.size.width + 0.5) {
              final List<String> bits = <String>[];
              void collect(Element e2) {
                final Widget w = e2.widget;
                if (w is Text && w.data != null && bits.length < 6) bits.add(w.data!);
                e2.visitChildren(collect);
              }
              el.visitChildren(collect);
              final String line = '${ro.size.width} ← 子 $sum ｜ 内容：${bits.join(' / ')}';
              if (!overflowing.contains(line)) overflowing.add(line);
            }
          }
        }

        // ⚠️ **接住 FlutterErrorDetails**：`takeException()` 只给一个 FlutterError，
        // 而"是哪一行"要的是 details 里那份完整诊断（含 `The relevant error-causing widget`）。
        final List<FlutterErrorDetails> caught = <FlutterErrorDetails>[];
        final void Function(FlutterErrorDetails)? prevOnError = FlutterError.onError;
        FlutterError.onError = caught.add;

        final Widget home = await e.value();
        await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: home));
        scanOverflow(); // ← 第一帧也要扫（有些溢出只出现在加载态那一帧）
        // 推进固定时长而不是 pumpAndSettle：这些屏里有不确定进度的转圈圈/常驻计时器
        for (int i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 120));
          scanOverflow();
        }
        final Object? first = tester.takeException();

        // 训练屏：再点一次大按钮，把"接上休息条 + 已完成行"那个状态也过一遍
        if (e.key.startsWith('训练屏') &&
            find.byKey(const Key('big-log-button')).evaluate().isNotEmpty) {
          await tester.tap(find.byKey(const Key('big-log-button')));
          for (int i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
        }
        final Object? second = tester.takeException();
        // 掐掉休息倒计时（否则 "Pending timers"）
        workoutController?.skipRest();
        workoutController?.dispose();
        workoutController = null;

        FlutterError.onError = prevOnError;
        // ⚠️ **接住之后必须再喂回原来的处理器**（2026-10-10 自己踩的坑）：
        // `FlutterError.onError = caught.add` 会把异常**吞掉** —— 测试框架那个
        // 处理器收不到，`takeException()` 于是永远是 null，**真的溢出被判成通过**。
        // 第一版就是这么写的：补进「通知详情」这一屏后，它明明报了
        // "A RenderFlex overflowed by 63 pixels"，测试却打的是 All tests passed。
        // 所以：留一份给自己看（下面那行 SWEEP-DETAIL），再原样转发给原处理器。
        for (final FlutterErrorDetails d in caught) {
          prevOnError?.call(d);
        }
        if (caught.isNotEmpty) {
          // ignore: avoid_print
          print('SWEEP-DETAIL>>> ${e.key} ${scale}× :: '
              '${caught.first.toString().split('\n').take(14).join(' ~ ')}');
        }
        final Object? err = first ?? second;
        if (err is FlutterError) {
          // ignore: avoid_print
          print('SWEEP-ERR>>> ${e.key} ${scale}× :: '
              '${err.diagnostics.map((DiagnosticsNode d) => d.toStringDeep()).join(' | ')}');
        }
        expect(err, isNull,
            reason: '${e.key} 在 ${scale}× 下溢出了 —— 大字号是 40+ 用户会开的档位，'
                '而溢出意味着**有内容被裁掉**（不是"看着挤"）。'
                '${overflowing.isEmpty ? '' : '溢出的行：${overflowing.join(' ／ ')}'}');
      });
    }
  }
}

/// 大字号扫描用的商品目录：三档齐全（含推荐档），与真机上的形状一致。
class _SweepCatalog implements PaywallCatalog {
  const _SweepCatalog();

  @override
  Future<List<UltraProductView>> load() async => const <UltraProductView>[
        UltraProductView(
          id: 'ultra.monthly',
          product: UltraProduct.monthly,
          title: 'Ultra 月订阅',
          duration: '每月',
          priceLabel: r'¥18.00',
        ),
        UltraProductView(
          id: 'ultra.yearly',
          product: UltraProduct.yearly,
          title: 'Ultra 年订阅',
          duration: '1 年',
          priceLabel: r'¥98.00',
          trialDays: 7,
          recommended: true,
        ),
        UltraProductView(
          id: 'ultra.lifetime',
          product: UltraProduct.lifetime,
          title: 'Ultra 终身',
          duration: '一次性买断',
          priceLabel: r'¥198.00',
        ),
      ];
}
