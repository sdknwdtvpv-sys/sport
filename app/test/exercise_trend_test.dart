/// 练了么 · **进阶分析**（Ultra 权益 7）的界面判据
///
/// 这一份盯三件事，都是"卖东西"这件事上的分寸：
///   1. **Ultra 用户**：动作列表出现、点得进趋势页、趋势页能切周/月/季；
///   2. **免费用户**：看到的是**预览态**（一行说明 + 一个按钮），
///      **已有的东西一个都没少**（红线 2：不许把原来能看的遮起来）；
///   3. **不许编数**：上一周期没有数据时**不显示百分比**，
///      数据不够时不写"0%"（那是编出来的趋势，用户会当真）。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/billing/entitlement.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide SetRecord, Workout, Exercise, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/entitlement_repository.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/features/progress/progress_screen.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/exercise_trend_screen.dart';

SetRecord _set(String exerciseId, DateTime at, {int reps = 10, double? weightKg = 60}) =>
    SetRecord(
      id: '$exerciseId-${at.millisecondsSinceEpoch}',
      workoutId: 'w',
      exerciseId: exerciseId,
      setIndex: 1,
      reps: reps,
      weightKg: weightKg,
      completedAtMs: at.millisecondsSinceEpoch,
    );

/// 三周的卧推：上周 500 kg、本周 600 kg（对比有数可说），另外还有深蹲与引体
final List<SetRecord> _sets = <SetRecord>[
  // 三个月前的起步组：没有它，"起步那 30 天"与"最近 30 天"会落在同一段里，
  // 变化率恒为 0%（第一版就是这么写的，测试当场说明白了）
  _set('bench', DateTime(2026, 7, 1), reps: 10, weightKg: 50),
  _set('bench', DateTime(2026, 9, 30), reps: 10, weightKg: 55),
  _set('bench', DateTime(2026, 10, 6), reps: 10, weightKg: 60),
  _set('bench', DateTime(2026, 10, 6), reps: 5, weightKg: 80),
  for (int i = 0; i < 4; i++) _set('squat', DateTime(2026, 10, 7), reps: 5, weightKg: 100),
  _set('pullup', DateTime(2026, 10, 7), reps: 8, weightKg: null),
  // 只在**本周**练过一次的负重动作：用来验"上一周期没有记录 ⇒ 不写百分比"
  // （负重才有容量；引体是自重，容量恒为 0，验不了这一条 —— 第一版就选错了动作）
  _set('row', DateTime(2026, 10, 7), reps: 10, weightKg: 60),
];

/// 三个文件级变量：`pumpProgress` 是**顶层函数**，看不到 `main()` 里的局部量。
/// （第一版就写成了局部 —— 编译直接报 `Undefined name 'store'`，这里记一笔。）
late AppDatabase db;
late DriftLocalStore store;
late ExerciseRepository repo;

void main() {
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
    repo = ExerciseRepository(db);
    // ⚠️ 种子放 `setUp`：`testWidgets` 的假时钟里做真实 IO（drift 写库）会挂住不返回
    // —— 仓库里为此踩过坑（`large_font_sweep_test.dart` 文件头记着这件事）。
    for (final SetRecord s in _sets) {
      await store.saveSet(s);
    }
  });
  tearDown(() => db.close());

  Future<void> pumpTrend(
    WidgetTester tester, {
    required String exerciseId,
    DateTime? now,
  }) async {
    tester.view.physicalSize = const Size(500, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: ExerciseTrendScreen(
        sets: _sets.where((SetRecord s) => s.exerciseId == exerciseId).toList(),
        exerciseId: exerciseId,
        exerciseName: exerciseId == 'bench' ? '杠铃卧推' : exerciseId,
        now: () => now ?? DateTime(2026, 10, 8, 12),
      ),
    ));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  group('动作趋势页', () {
    testWidgets('三块都在：周期切换、容量趋势、这一周期 vs 上一周期', (WidgetTester tester) async {
      await pumpTrend(tester, exerciseId: 'bench');
      expect(find.byKey(const Key('trend-range-week')), findsOneWidget);
      expect(find.byKey(const Key('trend-range-month')), findsOneWidget);
      expect(find.byKey(const Key('trend-range-quarter')), findsOneWidget);
      expect(find.byKey(const Key('trend-组数')), findsOneWidget);
      expect(find.byKey(const Key('trend-容量')), findsOneWidget);
      expect(find.byKey(const Key('trend-最重一组')), findsOneWidget);
      expect(find.byKey(const Key('trend-估算 1RM')), findsOneWidget);
      expect(find.byKey(const Key('trend-since-start')), findsOneWidget);
    });

    testWidgets('切到"月"之后，标题与轴标签跟着变（不是只换个高亮）', (WidgetTester tester) async {
      await pumpTrend(tester, exerciseId: 'bench');
      expect(find.text('每周容量'), findsOneWidget);
      await tester.tap(find.byKey(const Key('trend-range-month')));
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(find.text('每月容量'), findsOneWidget);
      expect(find.textContaining('这一月 vs 上一月'), findsOneWidget);
    });

    testWidgets('★ 上一周期没有数据 → **不显示百分比**（"从 0 到 600" 没有百分比可言）',
        (WidgetTester tester) async {
      await pumpTrend(tester, exerciseId: 'row'); // 只有本周一组（有重量的）
      // ⚠️ 只禁**百分比**：`组数 ↑ 1` 是事实（1 vs 0），而 `容量 ↑ 600%` 才是编出来的
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('没有记录'), findsWidgets,
          reason: '要说清「上周没有记录」，而不是写一个百分比');
    });

    testWidgets('★ 没有记录的动作：一句话说明，不画空图、不编数字', (WidgetTester tester) async {
      await pumpTrend(tester, exerciseId: 'never-trained');
      expect(find.byKey(const Key('trend-empty')), findsOneWidget);
      expect(find.byKey(const Key('trend-since-start')), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('起步 vs 现在：数据不足时**说不足**，不写 0%', (WidgetTester tester) async {
      await pumpTrend(tester, exerciseId: 'pullup');
      expect(find.textContaining('数据还不够'), findsOneWidget);
    });

    testWidgets('起步 vs 现在：两端都有数据时，把两个数与变化都写出来', (WidgetTester tester) async {
      await pumpTrend(tester, exerciseId: 'bench');
      // 起步那 30 天最重 50 kg；最近 30 天最重 80 kg → ↑ 60%
      expect(find.textContaining('起步那 30 天最重'), findsOneWidget);
      expect(find.textContaining('60%'), findsOneWidget);
    });
  });

  group('免费用户看到的是"预览态"，不是"被遮起来"', () {
    testWidgets('免费用户的进阶分析卡：一行说明 + 一个「看看 Ultra」按钮（点了会回调）',
        (WidgetTester tester) async {
      var opened = 0;
      await pumpProgress(
        tester,
        entitlements: EntitlementRepository(db),
        onOpenUltra: () => opened++,
      );
      expect(find.byKey(const Key('advanced-locked-note')), findsOneWidget);
      expect(find.byKey(const Key('advanced-try-ultra')), findsOneWidget);
      await tester.tap(find.byKey(const Key('advanced-try-ultra')));
      expect(opened, 1);
      // 免费版**已有**的东西一个都不能少（红线 2）
      expect(find.byKey(const Key('advanced-locked-note')), findsOneWidget);
    });

    testWidgets('Ultra 用户（权益在库里）：出现动作列表，且点得进趋势页', (WidgetTester tester) async {
      final EntitlementRepository ent = EntitlementRepository(db);
      await ent.upsert(UltraEntitlement(
        id: 'one',
        product: UltraProduct.yearly,
        source: UltraSource.apple,
        purchasedAtMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
        expiresAtMs: DateTime(2027, 10, 1).millisecondsSinceEpoch,
        lastVerifiedAtMs: DateTime(2026, 10, 8).millisecondsSinceEpoch,
      ));
      await pumpProgress(tester, entitlements: ent);
      expect(find.byKey(const Key('advanced-locked-note')), findsNothing,
          reason: 'Ultra 用户不该看到预览态');
      expect(find.byKey(const Key('advanced-exercise-bench')), findsOneWidget,
          reason: '最近 90 天练得最多的动作要排在前面');
    });
  });
}

/// 只挂进步页（省掉外壳与其它 tab）—— 这一条测的是"那张卡在两种权益下各长什么样"。
///
/// ⚠️ 用**真的** `ProgressScreen`（带真的 store/repo），不是复制一份它的卡片逻辑：
/// 复制出来的那份永远绿，而真页面早就变了。
Future<void> pumpProgress(
  WidgetTester tester, {
  required EntitlementRepository entitlements,
  VoidCallback? onOpenUltra,
}) async {
  tester.view.physicalSize = const Size(500, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      backgroundColor: Tokens.bg,
      body: ProgressScreen(
        store: store,
        repository: repo,
        // 同上：这一份测的是「进阶分析」这张卡本身，显式打开开关；
        // 首版（`kUltraReleased = false`）那张卡整块不出现，判据在 ultra_release_gate_test.dart
        showUltra: true,
        entitlements: entitlements,
        onOpenUltra: onOpenUltra,
        now: DateTime(2026, 10, 8, 12),
        onOpenToday: () {},
      ),
    ),
  ));
  // 老规矩：这一屏加载时有转圈，`pumpAndSettle` 等不到静止 → 推固定时长
  for (int i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}
