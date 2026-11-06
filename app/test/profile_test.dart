/// 练了么 · S10「我」的测试（统计 / CSV / 设置 / 界面）
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/glass_switch.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/analytics/outbox.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/body_metric_repository.dart';
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/core/vi_cards.dart';
import 'package:lianleme/features/profile/profile_screen.dart';
import 'package:lianleme/features/profile/settings_home_screen.dart';
import 'package:lianleme/features/profile/training_stats.dart';

SetRecord _set({
  required String id,
  String workoutId = 'w1',
  String exerciseId = 'ex_bb_bench_press',
  int setIndex = 1,
  int reps = 8,
  double? weightKg = 60,
  int atMs = 1000,
  SetType setType = SetType.normal,
}) =>
    SetRecord(
      id: id,
      workoutId: workoutId,
      exerciseId: exerciseId,
      setIndex: setIndex,
      reps: reps,
      completedAtMs: atMs,
      weightKg: weightKg,
      setType: setType,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('训练统计', () {
    test('从记录里算出训练次数 / 组数 / 总容量', () {
      final TrainingStats s = TrainingStats.fromSets(<SetRecord>[
        _set(id: 'a', workoutId: 'w1', reps: 8, weightKg: 60), // 480
        _set(id: 'b', workoutId: 'w1', reps: 8, weightKg: 60), // 480
        _set(id: 'c', workoutId: 'w2', reps: 10, weightKg: 100), // 1000
      ]);

      expect(s.workoutCount, 2, reason: '两次训练');
      expect(s.setCount, 3);
      expect(s.totalVolumeKg, 480 + 480 + 1000);
    });

    test('没有记录时 isEmpty，容量显示「—」而不是 0 kg', () {
      final TrainingStats s = TrainingStats.fromSets(<SetRecord>[]);
      expect(s.isEmpty, isTrue);
      expect(s.volumeLabel, '—');
    });

    test('容量带千分位', () {
      final TrainingStats s = TrainingStats.fromSets(<SetRecord>[
        _set(id: 'a', reps: 10, weightKg: 1000), // 10000
      ]);
      expect(s.volumeLabel, '10,000 kg');

      final TrainingStats s2 = TrainingStats.fromSets(<SetRecord>[
        _set(id: 'a', reps: 8, weightKg: 60), // 480
      ]);
      expect(s2.volumeLabel, '480 kg');
    });
  });

  group('CSV 导出', () {
    final Map<String, String> names = <String, String>{
      'ex_bb_bench_press': '杠铃卧推',
      'ex_pull_up': '引体向上',
    };

    test('表头与行数正确', () {
      final String csv = buildSetsCsv(
        sets: <SetRecord>[_set(id: 'a'), _set(id: 'b', setIndex: 2)],
        exerciseNames: names,
      );
      final List<String> lines = csv.trim().split('\n');
      expect(lines.length, 3, reason: '1 行表头 + 2 行数据');
      expect(lines.first, '日期,动作,重量kg,次数,容量kg,组序,距离km');
      expect(lines[1], contains('杠铃卧推'));
    });

    test('自重动作的重量留空，而不是 0', () {
      final String csv = buildSetsCsv(
        sets: <SetRecord>[
          _set(id: 'a', exerciseId: 'ex_pull_up', reps: 10, weightKg: null),
        ],
        exerciseNames: names,
      );
      final List<String> cells = csv.trim().split('\n')[1].split(',');
      expect(cells[1], '"引体向上"');
      expect(cells[2], '""', reason: '自重没有重量，留空比写 0 诚实');
    });

    test('动作名查不到时用 id 兜底，不丢行', () {
      final String csv = buildSetsCsv(
        sets: <SetRecord>[_set(id: 'a', exerciseId: 'ex_unknown')],
        exerciseNames: names,
      );
      expect(csv, contains('ex_unknown'));
    });

    test('名称里的逗号与引号被正确转义', () {
      final String csv = buildSetsCsv(
        sets: <SetRecord>[_set(id: 'a', exerciseId: 'weird')],
        exerciseNames: <String, String>{'weird': '哑铃"飞鸟", 上斜'},
      );
      // 引号翻倍，整体加引号 —— 贴进表格不会被拆成两列
      expect(csv, contains('"哑铃""飞鸟"", 上斜"'));
    });
  });

  group('渐进建议设置', () {
    late AppDatabase db;
    late ProfileRepository profile;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      profile = ProfileRepository(db);
    });
    tearDown(() => db.close());

    test('没设置过时返回引擎默认值', () async {
      expect(await profile.progressionMode(), ProgressionMode.doubleProgression);
    });

    test('关掉之后读回来是 off', () async {
      await profile.setProgressionMode(ProgressionMode.off, nowMs: 1000);
      expect(await profile.progressionMode(), ProgressionMode.off);
    });

    test('可以再打开', () async {
      await profile.setProgressionMode(ProgressionMode.off, nowMs: 1000);
      await profile.setProgressionMode(ProgressionMode.doubleProgression, nowMs: 2000);
      expect(await profile.progressionMode(), ProgressionMode.doubleProgression);
    });

    test('隐私开关默认是**开**的（2026-10-07 用户拍板；v1.28.0～v1.58.0 是关）', () async {
      expect(await profile.analyticsEnabled(), isTrue,
          reason: '这一格翻过两次，别再"顺手改回去"—— 每次都要有拍板与政策同步：'
              'docs/plan-ux-2026-10-07.md §三·9');
    });

    test('关掉隐私开关能落库，且不影响其他设置', () async {
      await profile.setProgressionMode(ProgressionMode.off, nowMs: 1000);
      await profile.setAnalyticsEnabled(false, nowMs: 2000);

      expect(await profile.analyticsEnabled(), isFalse);
      expect(await profile.progressionMode(), ProgressionMode.off,
          reason: '改一个设置不该把另一个抹了');

      final List<UserProfileData> rows = await db.select(db.userProfile).get();
      expect(rows.length, 1);
      expect(rows.single.createdAt, 1000, reason: '首次创建时间仍不该被改写');
    });

    test('只维护一行，且 createdAt 不被覆盖', () async {
      await profile.setProgressionMode(ProgressionMode.off, nowMs: 1000);
      await profile.setProgressionMode(ProgressionMode.doubleProgression, nowMs: 2000);

      final List<UserProfileData> rows = await db.select(db.userProfile).get();
      expect(rows.length, 1, reason: '应该是单行表');
      expect(rows.single.createdAt, 1000, reason: '首次创建时间不该被改写');
      expect(rows.single.updatedAt, 2000);
      expect(rows.single.progressionMode, 'double');
    });
  });

  group('界面', () {
    late AppDatabase db;
    late DriftLocalStore store;
    late ExerciseRepository repo;
    late ProfileRepository profile;
    String? copied;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftLocalStore(db);
      repo = ExerciseRepository(db);
      profile = ProfileRepository(db);
      copied = null;
      await repo.importSeed(
        loadJson: () => File('assets/exercises.json').readAsString(),
      );
      // 剪贴板是平台通道，测试里要自己接住
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      });
    });

    tearDown(() => db.close());

    Future<void> pumpProfile(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(store: store, repository: repo, profile: profile),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// 进「设置」总入口（2026-10-07 v1.60.0）：偏好设置 / 数据与备份 / 隐私与关于
    /// 三组**从「我」页搬进了独立的设置页**，入口是外壳顶栏右上角那枚齿轮。
    /// 所以凡是要进这三屏的测试，根 widget 换成 `SettingsHomeScreen`；
    /// 断言与 key 一个都没改（改的只是"从哪儿进去"）。
    Future<void> pumpSettings(WidgetTester tester, {Analytics? analytics}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SettingsHomeScreen(
            store: store,
            repository: repo,
            profile: profile,
            analytics: analytics,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// 「我」页现在有 5 个分区（单位 / 训练统计 / 渐进建议 / 隐私 / 数据），
    /// 800×600 的测试画布装不下。**ListView 是懒构建的**：没滚到的 widget
    /// 根本不存在，`find` 会直接落空 —— 所以必须 dragUntilVisible，
    /// 而不是 ensureVisible（后者要求 widget 已经被建出来）。
    Future<void> scrollTo(WidgetTester tester, Finder target) async {
      await tester.dragUntilVisible(
        target,
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
    }

    /// 进二级页（2026-10-01 重排：开关、导出、删除都收进去了）。
    ///
    /// 「我」页现在只剩统计 + 三个入口，所以这一步是**所有**二级页测试的公共前缀；
    /// 进去之后页面自己的内容还得用 [scrollTo] 滚过去（ListView 懒构建，老规矩）。
    Future<void> openPage(WidgetTester tester, String entryKey) async {
      final Finder row = find.byKey(Key(entryKey));
      await scrollTo(tester, row);
      await tester.tap(row);
      await tester.pumpAndSettle();
    }

    Future<void> tapDeleteAll(WidgetTester tester) async {
      await openPage(tester, 'open-data-tools');
      final Finder tile = find.byKey(const Key('delete-all'));
      await scrollTo(tester, tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

            testWidgets('A5 段位 / A1 换色：2026-10-10 起**都不在「我」里了**（搬进成就页）',
        (WidgetTester tester) async {
      // ⚠️ 这里原来有四条：段位是青铜/进白银、集齐一条收集线就换色、没集齐不许换色。
      // 用户 10.10 的设计评审之后「我」只留**一条进度**（等级）—— 段位本来是
      // "按已解锁枚数分档"，属于那本收藏册，所以它连同"集齐一条线的颜色奖励"
      // 一起搬进了成就页（`achievements_screen.dart` 的 `rank-name` / `rank-next`，
      // 断言在 `achievements_test.dart`）。这一条改成钉"确实搬走了、也没留下第二个入口"。
      await pumpProfile(tester);

      expect(find.byKey(const Key('rank-card')), findsNothing);
      expect(find.byKey(const Key('rank-name')), findsNothing);
      expect(find.byKey(const Key('rank-card-line')), findsNothing);
      expect(find.byKey(const Key('experience-title')), findsNothing,
          reason: '经验那一条也取消了 —— 等级与它都在说"练了多少"，两把尺子量一件事');
      expect(find.byKey(const Key('open-achievements')), findsOneWidget,
          reason: '收藏册仍然有一个入口（「成就」那一行）');
    });

            testWidgets('★ 经验（XP 称号）那一条**取消了** —— 全页只剩一条进度',
        (WidgetTester tester) async {
      // ⚠️ 原来这条钉的是「经验 · 起步 / 3 组 / 还差 97 组」。2026-10-10：等级与经验
      // 都在说"练了多少"（一个看次数、一个看组数），两把尺子量同一件事 —— 只留等级
      // （`docs/plan-ux-2026-10-10.md` §五-B）。`experience.dart` 那套纯函数还在
      // （有自己的单测），只是**界面上没有任何入口**了；要不要彻底删留给后续决定。
      for (int i = 0; i < 3; i++) {
        await store.saveSet(_set(id: 'e$i', setIndex: i + 1));
      }
      await pumpProfile(tester);

      expect(find.byKey(const Key('experience-title')), findsNothing);
      expect(find.byKey(const Key('experience-sets')), findsNothing);
      expect(find.byKey(const Key('experience-hint')), findsNothing);
      expect(find.byKey(const Key('profile-level-label')), findsOneWidget,
          reason: '留下的那一条是等级');
    });

    testWidgets('★ 「我的进度」现在**只有一条进度**（等级）+ 一行事实',
        (WidgetTester tester) async {
      // ⚠️ 原来这条钉的是"一张卡装下等级 / 段位 / 经验三行"。2026-10-10 改版：
      // 全 app 只留**一条进度条**（等级），连续天数与本周次数降级成**一行事实**
      // （没有进度条），段位搬去成就页、经验取消。见 `docs/plan-ux-2026-10-10.md` §五-B。
      await pumpProfile(tester);
      await scrollTo(tester, find.byKey(const Key('profile-level-label')));

      expect(find.text('我的进度'), findsOneWidget);
      expect(find.byKey(const Key('profile-level-label')), findsOneWidget);
      expect(find.byKey(const Key('profile-fact-line')), findsOneWidget,
          reason: '连续天数与本周次数是**一行事实**');
      expect(find.byKey(const Key('rank-name')), findsNothing);
      expect(find.byKey(const Key('experience-title')), findsNothing);

      // 这一屏**只有一条进度条**：等级那条（统计那两张卡是 `StatTile`，没有进度条）
      expect(find.byType(ViProgressBar), findsOneWidget,
          reason: '唯一的那条进度就是等级');
    });

    testWidgets('开关默认开着，关掉之后写进库', (WidgetTester tester) async {
      await pumpSettings(tester);
      await openPage(tester, 'open-preferences');
      await scrollTo(tester, find.byKey(const Key('progression-switch')));
      expect(tester.widget<AppSwitchTile>(find.byKey(const Key('progression-switch'))).value,
          isTrue);
      expect(await profile.progressionMode(), ProgressionMode.doubleProgression);

      await tester.tap(find.byKey(const Key('progression-switch')));
      await tester.pumpAndSettle();

      expect(await profile.progressionMode(), ProgressionMode.off,
          reason: '关掉必须真的落库，否则重启就白关了');
    });

    testWidgets('隐私开关默认**开着**：想关就关、关掉立刻停、再打开立刻生效（2026-10-07 拍板）',
        (WidgetTester tester) async {
      // ⚠️ 这条测试的**方向**在 2026-10-07 翻过一次（默认关 → 默认开，用户拍板，
      // 见 `docs/plan-ux-2026-10-07.md` §三·9）。它守的东西没变：
      // ① 开关显示的必须与库里一致；② 拨动必须**立刻**生效（等重启就晚了）；
      // ③ 关着的时候一条都不许记。
      final RecordingAnalytics analytics = RecordingAnalytics();
      await pumpSettings(tester, analytics: analytics);

      // 2026-10-01 重排：隐私开关在「我 → 隐私与关于」里
      await openPage(tester, 'open-privacy-about');
      await scrollTo(tester, find.byKey(const Key('analytics-switch')));
      expect(
        tester.widget<AppSwitchTile>(find.byKey(const Key('analytics-switch'))).value,
        isTrue,
        reason: '默认就是开着的；界面上显示的值必须与库里的值一致，不能各说一套',
      );
      expect(await profile.analyticsEnabled(), isTrue, reason: '库里也必须是开的');

      // 先关掉 → 立刻停（这是用户真正会做的动作）
      await tester.tap(find.byKey(const Key('analytics-switch')));
      await tester.pumpAndSettle();
      expect(await profile.analyticsEnabled(), isFalse, reason: '关掉也必须落库');
      expect(analytics.enabled, isFalse, reason: '必须立刻生效，等重启就晚了');
      analytics.track('set_logged');
      expect(analytics.countOf('set_logged'), 0, reason: '关掉之后一条都不该记');

      // 再打开 → 立刻开始记
      await tester.tap(find.byKey(const Key('analytics-switch')));
      await tester.pumpAndSettle();
      expect(await profile.analyticsEnabled(), isTrue);
      expect(analytics.enabled, isTrue);
      analytics.track('set_logged');
      expect(analytics.countOf('set_logged'), 1, reason: '打开了才开始记');
    });

    testWidgets('★ 身份块：昵称跟着库走；没登录就不显示 ID（10.7 清单第 7 条）',
        (WidgetTester tester) async {
      await profile.setNickname('李松', nowMs: 1000);
      await pumpProfile(tester);

      expect(find.byKey(const Key('profile-identity')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('profile-nickname'))).data, '李松');
      expect(tester.widget<Text>(find.byKey(const Key('profile-id-line'))).data,
          contains('还没登录'),
          reason: '没登录就不显示 ID —— 凭空编一个号就是假身份');
    });

    testWidgets('★ 没设过昵称 → 写"还没设昵称"（不编默认名）', (WidgetTester tester) async {
      await pumpProfile(tester);
      expect(tester.widget<Text>(find.byKey(const Key('profile-nickname'))).data,
          '还没设昵称');
    });

    testWidgets('点导出会把 CSV 放进剪贴板', (WidgetTester tester) async {
      await store.saveSet(_set(id: 'a', reps: 8, weightKg: 60));
      await pumpSettings(tester);

      await openPage(tester, 'open-data-tools');
      await scrollTo(tester, find.byKey(const Key('export-csv')));
      await tester.tap(find.byKey(const Key('export-csv')));
      await tester.pumpAndSettle();

      expect(copied, isNotNull);
      expect(copied, startsWith('日期,动作,重量kg,次数,容量kg,组序'));
      expect(copied, contains('杠铃卧推'));
      expect(find.textContaining('已复制 1 条记录'), findsOneWidget);
    });

    testWidgets('点「删除全部数据」先弹二次确认；点取消什么都不删',
        (WidgetTester tester) async {
      await store.saveSet(_set(id: 'a', reps: 8, weightKg: 60));
      await pumpSettings(tester);

      await tapDeleteAll(tester);

      expect(find.byKey(const Key('delete-all-dialog')), findsOneWidget);
      expect(find.textContaining('无法撤销'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete-all-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete-all-dialog')), findsNothing);
      expect(await store.allSets(), hasLength(1), reason: '点了取消就不能删');
    });

        testWidgets('删除全部数据会一并清掉还没上报的埋点事件', (WidgetTester tester) async {
      final AnalyticsOutboxStore outbox = AnalyticsOutboxStore(db);
      await outbox.enqueue(
        name: 'set_logged',
        props: <String, Object?>{'x': 1},
        priority: 0,
        nowMs: 1000,
      );
      expect(await outbox.pending(), 1, reason: '前置：outbox 里有待发事件');

      await pumpSettings(tester);
      await tapDeleteAll(tester);
      await tester.tap(find.byKey(const Key('delete-all-confirm')));
      await tester.pumpAndSettle();

      // 用户说"删掉我的数据"，之后还继续上报是合规上明确不允许的
      expect(await outbox.pending(), 0);
    });

    testWidgets('删除全部数据会一并清掉身体数据（加新表时最容易漏的一步）',
        (WidgetTester tester) async {
      final BodyMetricRepository body = BodyMetricRepository(db);
      await body.save(date: '2026-09-28', weightKg: 72.5, nowMs: 1000);
      expect(await body.count(), 1, reason: '前置：有一条体重');

      await pumpSettings(tester);
      await tapDeleteAll(tester);
      await tester.tap(find.byKey(const Key('delete-all-confirm')));
      await tester.pumpAndSettle();

      // 新加的表如果不接进 deleteAllUserData，用户点了"删除全部数据"
      // 之后体重还留在库里 —— 这是合规问题，不是功能瑕疵
      expect(await body.count(), 0);
    });
  });
}
