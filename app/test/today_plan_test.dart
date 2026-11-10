/// 练了么 · 首页「今天的安排」+ 上下肢分化（2026-10-04）
///
/// 这一批改的是**北极星靶心那一屏**，两条投诉都来自真机：
///   1. 标题与按钮之间**空了一大块**（原来是一个 `Spacer()`），首屏很难看；
///   2. 默认只给 **3 个动作 = 9 组**，而 `PRODUCT.md` §9 的护栏是「单次 ≥ 12 组」
///      —— 默认计划**数学上就到不了**。证据与算账见 `TrainingDay` 的注释。
///
/// 所以这里守三条不变量：
///   * 首页中间那块**有内容**（不是空白），并且是**今天要练的那一份**；
///   * **大按钮开练的动作 = 首页列出来的那些**（显示了 A 却练 B 比不显示更糟）；
///   * 矮屏**不溢出**（加了卡片之后 Flutter 报过 RenderFlex overflowed by 72px）。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/labels.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/domain/models.dart' show PlanTarget;
import 'package:lianleme/core/app_tab_bar.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/features/today/today_planner.dart';
import 'package:lianleme/features/today/today_screen.dart';
import 'package:lianleme/main.dart';

void main() {
  late AppDatabase db;
  late String seedJson;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    seedJson = await File('assets/exercises.json').readAsString();
  });
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester) async {
    await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
    await tester.pumpWidget(LianLeMeApp(
      database: db,
      seedLoader: () async => seedJson,
    ));
    await tester.pumpAndSettle();
  }

  /// 卡片里所有文字（表头 + 每个动作名 + 建议值 + "换一批"）
  List<String> cardTexts(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(
        of: find.byKey(const Key('today-plan')),
        matching: find.byType(Text),
      ))
      .map((Text t) => t.data ?? '')
      .where((String s) => s.isNotEmpty)
      .toList();

  /// 卡片里列了几个动作 —— **按结构数**（每行一个 key），
  /// 不猜"文字里有没有 kg"：自重动作念「自重 × 8」，按 kg 数会漏掉它们。
  int rowCount(WidgetTester tester) => tester
      .widgetList(find.byWidgetPredicate((Widget w) {
        final Key? k = w.key;
        return k is ValueKey<String> && k.value.startsWith('today-plan-row-');
      }))
      .length;

  /// 必须销毁页面：外壳里有两个埋点定时器，不销毁 testWidgets 会因 pending timer 判失败
  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  group('首页「今天的安排」', () {
    testWidgets('中间那块不再是空白：有表头、有动作、有建议值',
        (WidgetTester tester) async {
      await pumpApp(tester);

      expect(find.byKey(const Key('today-plan')), findsOneWidget,
          reason: '首页中间现在该摆今天的安排（以前是一个 Spacer）');

      final List<String> texts = cardTexts(tester);
      // ⚠️ 2026-10-09（第二份 docx 第 4 条）起表头还带着**在哪儿练**：
      // 用户不看着"健身房/家里/徒手"这三个字，就会奇怪"我明明选了家里怎么还推这个"。
      expect(texts, contains('今日训练'));
      expect(texts.any((String s) => s.startsWith('上肢 · 健身房')), isTrue,
          reason: 'v2.2 卡片标题=22pt 的「部位 · 场景」，eyebrow 另起一行');
      expect(texts.any((String s) => s.contains('健身房')), isTrue,
          reason: '没选过场景 = 健身房（与这一版之前的行为一致）');
      expect(texts, contains('编辑'));
      // 上肢日第一个动作是常用度最高的胸部动作
      expect(texts, contains('杠铃卧推'));
      // 第一次练这个动作 → 建议值就是动作库起始重量（40kg × 8）
      expect(texts.any((String s) => s.contains('40 kg')), isTrue,
          reason: '重量列要带引擎算好的建议值，不能只给个名字：$texts');
      expect(texts.any((String s) => s.contains('×8–10次')), isTrue,
          reason: '组×次列要写清组数与次数区间：$texts');

      await teardown(tester);
    });

    testWidgets('★ 第一次只列 3 个动作（v2.3.0 首页减负）',
        (WidgetTester tester) async {
      await pumpApp(tester);

      final int rows = rowCount(tester);
      expect(rows, 3, reason: 'v2.3.0 首页只列 3 行（第 4+ 进编辑）');
      expect(find.byKey(const Key('home-plan-summary')), findsOneWidget);
      expect(find.textContaining('个动作'), findsWidgets,
          reason: '卡头副标题交代总数，不丢信息');

      await teardown(tester);
    });

    testWidgets('★ 大按钮开练的，就是首页列出来的那一个动作',
        (WidgetTester tester) async {
      await pumpApp(tester);

      final List<String> texts = cardTexts(tester);
      expect(texts, contains('杠铃卧推'));

      await tester.tap(find.byKey(const Key('start-workout')));
      await tester.pumpAndSettle();

      // 训练屏顶部那个动作名 —— 首页列的是杠铃卧推，那进去就该是它
      expect(find.text('杠铃卧推'), findsWidgets,
          reason: '首页显示的计划与真正开练的必须是同一份（显示了 A 却练 B 更糟）');
      expect(find.byKey(const Key('big-log-button')), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('「编辑」是显式入口（长按只是快捷方式，不是唯一路径）',
        (WidgetTester tester) async {
      await pumpApp(tester);
      expect(find.byKey(const Key('home-plan-edit')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-plan-edit')));
      await tester.pumpAndSettle();
      // 编辑器会打开（不依赖长按才发现）
      expect(find.byType(Dialog).evaluate().isNotEmpty ||
          find.byKey(const Key('home-plan-edit')).evaluate().isNotEmpty, isTrue);
      await teardown(tester);
    });

    testWidgets('★ 卡片整块可点：点它进建议卡（「我自己选 / 我的计划」在那儿）',
        (WidgetTester tester) async {
      await pumpApp(tester);

      // 那一行「看看今天练什么 ›」已经删掉（2026-10-04）—— 入口合并进卡片，
      // 所以这条测试要同时钉住"新入口在"与"旧的那一行不在了"。
      expect(find.byKey(const Key('see-plan')), findsNothing,
          reason: '同一件事不留两个入口');
      expect(find.byKey(const Key('open-plan')), findsOneWidget);

      await tester.tap(find.byKey(const Key('open-plan')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today-title')), findsOneWidget,
          reason: '点卡片该落到建议卡');
      expect(find.byKey(const Key('pick-myself')), findsOneWidget,
          reason: '「我自己选」只在建议卡里 —— 所以这个入口不能真删');
      expect(find.byKey(const Key('big-log-button')), findsNothing,
          reason: '点卡片只是"看看"，不是开练（开练永远是大按钮）');

      await teardown(tester);
    });

    testWidgets('计划还没算出来时，卡片照常在（入口不会因此消失）',
        (WidgetTester tester) async {
      // 只有 `todayPlan` 空、`onSeePlan` 非空 —— 这是"首页预览算失败"的样子。
      // 真源在 main.dart：`_loadTodayPlan()` 的 catch 是**吞掉异常**的，
      // 于是"预览空了"是可能发生的；如果这时卡片不显示，
      // 「我自己选 / 我的计划」就变得够不着了。
      bool opened = false;
      await tester.pumpWidget(MaterialApp(
        home: TodayScreen(
          onStart: () {},
          onSeePlan: () => opened = true,
          lastWeekSessions: 0,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today-plan')), findsOneWidget);
      expect(find.text('今天还没有安排'), findsOneWidget);

      // 2026-10-05：主按钮进了卡片（新 VI），而 `tester.tap` 点的是**中心**——
      // 现在中心是那颗按钮。所以要**点卡片的非按钮区域**（标题那行），
      // 并且顺手钉死一件事：**点按钮不能顺带把建议卡也打开**（两个目标是分开的）。
      await tester.tap(find.text('今天还没有安排'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);

      opened = false;
      await tester.tap(find.byKey(const Key('start-workout')));
      await tester.pumpAndSettle();
      expect(opened, isFalse, reason: '点主按钮不该同时打开建议卡');

      await teardown(tester);
    });

    testWidgets('卡片不可点时**不摆那个 ›**（点不动的箭头比没有更糟）',
        (WidgetTester tester) async {
      // 老调用方不传 onSeePlan，但**有**计划要显示（测试里的常见形状）。
      final ExerciseData ex = ExerciseData(
        id: 'ex_bench',
        name: '杠铃卧推',
        aliases: '[]',
        muscleGroup: 'chest',
        secondaryMuscles: '[]',
          subTags: '[]',
        equipment: 'barbell',
        category: 'strength',
        trackType: 'weight_reps',
        defaultRestSec: 90,
        weightIncrement: 2.5,
        isBuiltin: true,
        popularity: 100,
        createdAt: 0,
        updatedAt: 0,
      );
      await tester.pumpWidget(MaterialApp(
        home: TodayScreen(
          onStart: () {},
          lastWeekSessions: 0,
          todayPlan: <PlannedExercise>[
            PlannedExercise(
                exercise: ex,
                plan: const PlanTarget(
                    targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10)),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today-plan')), findsOneWidget);
      expect(find.byKey(const Key('open-plan')), findsNothing,
          reason: '没有 onOpen 就不该可点');
      expect(find.text('点这里看看怎么练 ›'), findsNothing);

      await teardown(tester);
    });

    testWidgets('★ 矮屏不溢出（加了卡片之后报过 overflowed 72px）',
        (WidgetTester tester) async {
      // 600 高 ≈ 很多手机横过来 / 大字体下的可用高度。
      // Flutter 在 RenderFlex 溢出时会直接让测试失败，所以这条不用额外断言什么 ——
      // 能跑完就是没溢出。
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpApp(tester);

      expect(find.byKey(const Key('today-plan')), findsOneWidget);
      expect(find.byKey(const Key('start-workout')), findsOneWidget,
          reason: '再挤也要看得见主按钮');
      expect(tester.takeException(), isNull);

      await teardown(tester);
    });

    testWidgets('★ 系统大字号 1.5× 也不溢出（40+ 用户会把字号调大）',
        (WidgetTester tester) async {
      // 为什么单独一条：全项目原先**没有任何一处**处理 textScaler，
      // 而首页是卡片叠卡片、最容易挤爆的一屏。
      // 设备按 411×914 逻辑像素（常见安卓机）+ 1.5 倍字体。
      tester.view.physicalSize = const Size(1233, 2742);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // 1.3× 与 1.5× 都跑一遍：1.3 是"调大一点"的常见档，1.5 是系统里最大的一档
      for (final double scale in <double>[1.3, 1.5]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await pumpApp(tester);

        // Flutter 在 RenderFlex 溢出时会直接让测试失败，能跑完就是没溢出
        expect(tester.takeException(), isNull, reason: '${scale}× 时首页溢出了');
        expect(find.byKey(const Key('start-workout')), findsOneWidget,
            reason: '${scale}× 时也要看得见主按钮');
        expect(find.byKey(const Key('open-notifications')), findsOneWidget,
            reason: '${scale}× 时铃铛不能被挤掉 —— 那是通知中心唯一的入口');
      }

      await teardown(tester);
    });
  });

    test('★ 手动换动作：与今天这场完全不协同时给一句人话（10.8 清单第 5 条）', () {
    // 用户原话："如果在同一天的计划里，我手动改了一个完全没有协同作用的肌群动作，
    // 能否进行提示"。判据只比**主肌群**（辅助肌群几乎人人都有两三个，
    // 拿它比这条提示就永远不会响）。
    const List<({String id, String muscle, List<String> secondary})> upper = <({String id, String muscle, List<String> secondary})>[
      (id: 'ex_bb_bench_press', muscle: 'chest', secondary: <String>['triceps', 'shoulders']),
      (id: 'ex_bb_row', muscle: 'back', secondary: <String>['biceps']),
    ];

    // 换进来一个练腿的 → 要提示，且句子是"事实 + 不协同在哪"
    final String? warn = muscleSynergyWarning(
      pickedId: 'ex_bb_squat',
      pickedMuscle: 'legs',
      session: upper,
      muscleNames: kMuscleLabels,
    );
    expect(warn, isNotNull);
    expect(warn, contains('腿'));
    expect(warn, contains('胸'));
    expect(warn, isNot(contains('!')), reason: '不说教、不带感叹号');

    // 换进来一个练胸的（同一肌群）→ 不提示
    expect(
      muscleSynergyWarning(
        pickedId: 'ex_db_fly',
        pickedMuscle: 'chest',
        session: upper,
        muscleNames: kMuscleLabels,
      ),
      isNull,
    );

    // 今天这场只有它自己（或空）→ 无可比，不提示（第一次选动作不该被拦）
    expect(
      muscleSynergyWarning(
        pickedId: 'ex_bb_squat',
        pickedMuscle: 'legs',
        session: <({String id, String muscle, List<String> secondary})>[
          (id: 'ex_bb_squat', muscle: 'legs', secondary: <String>[]),
        ],
      ),
      isNull,
    );
  });




      testWidgets('★ 回归激励：断 7 天以上才出现，且那条轻量入口跟着上来',
      (WidgetTester tester) async {
    int light = 0;
    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(
        onStart: () {},
        onLightWorkout: () => light++,
        comebackNudge: '已经 9 天没练了 —— 先做 5 分钟活动，也算一次。',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comeback-nudge')), findsOneWidget);
    expect(find.textContaining('9 天没练'), findsOneWidget);
    await tester.tap(find.byKey(const Key('comeback-light')));
    await tester.pumpAndSettle();
    expect(light, 1, reason: '卡里那颗按钮要真的能进 5 分钟活动');

    await tester.pumpWidget(MaterialApp(home: TodayScreen(onStart: () {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comeback-nudge')), findsNothing);
  });

  

  testWidgets('★ 高屏（≥900pt）首页有呼吸留白，不把内容全贴顶（审计 O1）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(440 * 3, 956 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TodayScreen(onStart: () {}))));
    await tester.pumpAndSettle();
    final ListView list = tester.widget<ListView>(find.byType(ListView).first);
    final EdgeInsets pad = list.padding! as EdgeInsets;
    expect(pad.top, greaterThan(Tokens.s4),
        reason: '高屏顶部加呼吸（24pt）');
    expect(pad.bottom, greaterThan(Tokens.s4 + AppTabBar.reservedSpaceFor(tester.element(find.byType(ListView)))),
        reason: '高屏底部多留 70pt，内容尾不贴底栏');
  });
}
