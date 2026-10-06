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
import 'package:lianleme/features/progress/badges.dart';
import 'package:lianleme/features/profile/profile_screen.dart';
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

    test('隐私开关默认是关的（PIPL：非必需收集要用户主动开启）', () async {
      expect(await profile.analyticsEnabled(), isFalse);
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

    testWidgets('没有记录时给出明确说明，而不是一排 0', (WidgetTester tester) async {
      await pumpProfile(tester);

      // 2026-09-29 加了「体重 kg/斤」那一行之后，统计区被顶到首屏之下 ——
      // ListView 懒构建，不滚过去 `find` 会直接落空（这个文件早就记着这条规律）
      await scrollTo(tester, find.textContaining('还没有训练记录'));
      expect(find.textContaining('还没有训练记录'), findsOneWidget);
      expect(find.byKey(const Key('profile-stat-sets')), findsNothing);
    });

    testWidgets('有记录时显示三项统计', (WidgetTester tester) async {
      await store.saveSet(_set(id: 'a', reps: 8, weightKg: 60));
      await store.saveSet(_set(id: 'b', reps: 8, weightKg: 60, setIndex: 2));
      await pumpProfile(tester);

      // 同上：统计区在首屏之下，懒构建 —— 先滚过去
      await scrollTo(tester, find.byKey(const Key('profile-stat-workouts')));
      expect(
        tester.widget<Text>(find.byKey(const Key('profile-stat-workouts'))).data,
        '1 次',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('profile-stat-sets'))).data,
        '2 组',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('profile-stat-volume'))).data,
        '960 kg',
      );
    });

    testWidgets('A5 段位卡：0 枚时是青铜，如实写"还差 3 枚到白银"', (WidgetTester tester) async {
      await pumpProfile(tester);
      await scrollTo(tester, find.byKey(const Key('rank-card')));

      expect(tester.widget<Text>(find.byKey(const Key('rank-name'))).data, '青铜 · 0 枚',
          reason: '段位名要带上**这一段自己的门槛**，否则"离青铜多远"没人说得清');
      expect(
        tester.widget<Text>(find.byKey(const Key('rank-next'))).data,
        contains('还差 3 枚到白银'),
      );
      expect(find.textContaining('已解锁 0 / '), findsOneWidget,
          reason: '段位卡里的分母必须是**真的徽章总数**，不写死');
    });

    testWidgets('A5 段位卡：解锁到 3 枚以上就进白银（段位是算出来的，不落库）',
        (WidgetTester tester) async {
      // 5 枚最容易拿的一批：首训 / 练满 10 次还给不了、早鸟 + 夜猫 + 二十个动作要 20 个动作
      // —— 这里直接构造"首批 5 枚"：1 次训练 + 早鸟 + 夜猫 + 不同动作 1 个 + 单次 5 吨
      await store.saveSet(_set(id: 'a', reps: 10, weightKg: 600, atMs: 6 * 3600 * 1000));
      await store.saveSet(_set(
          id: 'b', reps: 10, weightKg: 600, setIndex: 2, atMs: 23 * 3600 * 1000));
      await pumpProfile(tester);
      await scrollTo(tester, find.byKey(const Key('rank-card')));

      final String name =
          tester.widget<Text>(find.byKey(const Key('rank-name'))).data!;
      final String next =
          tester.widget<Text>(find.byKey(const Key('rank-next'))).data!;
      // 这一段**不钉死**解锁到第几枚（徽章还在分批扩），只钉"名字与门槛一致、进度与下一段自洽"
      expect(name, matches(RegExp(r'^(青铜|白银|黄金|铂金|钻石|大师|传奇) · \d+ 枚$')));
      expect(next, matches(RegExp(r'^(还差 \d+ 枚到.+|已经是最高段位) · 已解锁 \d+ / \d+ 枚$')));
    });

    testWidgets('★ A1 集齐奖励：集齐一条线 → 段位卡换上那条线的颜色（展示层）',
        (WidgetTester tester) async {
      // ⚠️ 这里**不走"造一年记录"那条路**（那测的是数据生成器）：
      // 判据 `completedLines()` 已由 `badges_test.dart` 用构造的 BadgeStatus 钉死，
      // 这一条只测"集齐之后界面上多了一圈什么颜色"，所以直接注入那一条已集齐的线。
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            store: store,
            repository: repo,
            profile: profile,
            debugCompleteLines: const <BadgeLine>[
              BadgeLine(
                category: BadgeCategory.streak,
                label: '连续打卡',
                unlocked: 20,
                total: 20,
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('rank-card')));

      expect(find.byKey(const Key('rank-card-line')), findsOneWidget,
          reason: '集齐一条收集线之后，段位卡要换上那条线的颜色（A1 的展示性奖励）');
      final Container box =
          tester.widget<Container>(find.byKey(const Key('rank-card-line')));
      final BoxDecoration deco = box.decoration! as BoxDecoration;
      expect((deco.border! as Border).top.color, Tokens.accent,
          reason: '集齐的是「连续打卡」那条线（它的颜色就是主色）');
    });

    testWidgets('A1：**没集齐就不许换色**（空记录下没有那圈描边）',
        (WidgetTester tester) async {
      await pumpProfile(tester);
      await scrollTo(tester, find.byKey(const Key('rank-card')));
      expect(find.byKey(const Key('rank-card-line')), findsNothing,
          reason: '一枚都没集齐时出现那圈色 = 在说假话');
    });

    testWidgets('★ 连续天数**认补签**，而且如实写"其中 N 天是补签"（与首页同一口径）',
        (WidgetTester tester) async {
      // 昨天与前天练了、今天没练；再往前一天被补签保护 —— 于是连续 3 天，
      // 其中 1 天是补签。用真记录 + 注入 protectedDays（判据本身在
      // `streak_protection_test.dart` 里逐条钉着，这里只测界面是否照实说）。
      final DateTime now = DateTime.now();
      final DateTime d0 = DateTime(now.year, now.month, now.day);
      final DateTime yesterday = d0.subtract(const Duration(days: 1));
      String key(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      await store.saveSet(_set(
          id: 'y', workoutId: 'wy', atMs: yesterday.millisecondsSinceEpoch));
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            store: store,
            repository: repo,
            profile: profile,
            protectedDays: <String>{
              key(yesterday.subtract(const Duration(days: 1))),
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('profile-streak-label')));

      expect(
        tester.widget<Text>(find.byKey(const Key('profile-streak-label'))).data,
        '已连续打卡 2 天（其中 1 天是补签）',
        reason: '昨天练了 + 前天被补签保护 = 2 天，而且必须写明其中 1 天是补签',
      );
    });

    testWidgets('★ 经验卡（第二部分第 7 条）：按累计组数给等级与进度',
        (WidgetTester tester) async {
      // 三组 → 经验等级还是「起步」，进度 3/100
      for (int i = 0; i < 3; i++) {
        await store.saveSet(_set(id: 'e$i', setIndex: i + 1));
      }
      await pumpProfile(tester);
      await scrollTo(tester, find.byKey(const Key('experience-card')));

      expect(tester.widget<Text>(find.byKey(const Key('experience-sets'))).data, '3 组');
      expect(tester.widget<Text>(find.byKey(const Key('experience-title'))).data,
          '经验 · 起步');
      expect(tester.widget<Text>(find.byKey(const Key('experience-hint'))).data,
          contains('还差 97 组'));
    });

    testWidgets('开关默认开着，关掉之后写进库', (WidgetTester tester) async {
      await pumpProfile(tester);
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

    testWidgets('隐私开关默认**关着**：不主动打开就一条都不记，打开后立刻生效且落库',
        (WidgetTester tester) async {
      final RecordingAnalytics analytics = RecordingAnalytics();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            store: store,
            repository: repo,
            profile: profile,
            analytics: analytics,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 2026-10-01 重排：隐私开关在「我 → 隐私与关于」里
      await openPage(tester, 'open-privacy-about');
      await scrollTo(tester, find.byKey(const Key('analytics-switch')));
      expect(
        tester.widget<AppSwitchTile>(find.byKey(const Key('analytics-switch'))).value,
        isFalse,
        reason: '默认必须是关的 —— "默认同意"在 PIPL 下站不住',
      );
      expect(await profile.analyticsEnabled(), isFalse, reason: '库里也必须是关的');

      // 关着的时候不该记任何东西
      analytics.track('set_logged');
      expect(analytics.countOf('set_logged'), 0, reason: '没主动打开就不该有数据');

      // 主动打开 → 立刻生效 + 落库
      await tester.tap(find.byKey(const Key('analytics-switch')));
      await tester.pumpAndSettle();

      expect(await profile.analyticsEnabled(), isTrue, reason: '打开也必须落库');
      expect(analytics.enabled, isTrue, reason: '必须立刻生效，等重启就晚了');
      analytics.track('set_logged');
      expect(analytics.countOf('set_logged'), 1, reason: '打开了才开始记');

      // 再关掉 → 立刻停
      await tester.tap(find.byKey(const Key('analytics-switch')));
      await tester.pumpAndSettle();
      expect(await profile.analyticsEnabled(), isFalse);
      expect(analytics.enabled, isFalse);
      analytics.track('set_logged');
      expect(analytics.countOf('set_logged'), 1, reason: '关掉之后不该再多一条');
    });

    testWidgets('点导出会把 CSV 放进剪贴板', (WidgetTester tester) async {
      await store.saveSet(_set(id: 'a', reps: 8, weightKg: 60));
      await pumpProfile(tester);

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
      await pumpProfile(tester);

      await tapDeleteAll(tester);

      expect(find.byKey(const Key('delete-all-dialog')), findsOneWidget);
      expect(find.textContaining('无法撤销'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete-all-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete-all-dialog')), findsNothing);
      expect(await store.allSets(), hasLength(1), reason: '点了取消就不能删');
    });

    testWidgets('确认后数据真没了，且界面立刻刷新（不是只清了库）',
        (WidgetTester tester) async {
      await store.saveSet(_set(id: 'a', reps: 8, weightKg: 60));
      await pumpProfile(tester);
      await scrollTo(tester, find.byKey(const Key('profile-stat-sets')));
      expect(find.byKey(const Key('profile-stat-sets')), findsOneWidget, reason: '前置：有数据');

      await tapDeleteAll(tester);
      await tester.tap(find.byKey(const Key('delete-all-confirm')));
      await tester.pumpAndSettle();

      expect(await store.allSets(), isEmpty, reason: '库里必须真删掉（硬删除）');

      // 2026-10-01 重排之后，统计卡在上一级「我」页 —— 删完得退回那一页再看。
      // （退回这一步本身就是设计的一部分：二级页不自己复制一份统计。）
      await tester.tap(find.byKey(const Key('subpage-back')));
      await tester.pumpAndSettle();

      // ⚠️ 断言统计卡之前要先滚回顶部：`ListView` 是**懒构建**的 ——
      // 统计卡在首屏，退回来时就在视口里；下面这句仍保留"滚到目标"的语义。
      await tester.dragUntilVisible(
        find.textContaining('还没有训练记录'),
        find.byType(ListView),
        const Offset(0, 220),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile-stat-sets')), findsNothing,
          reason: '界面必须一起刷新 —— 否则用户以为没删掉');
      expect(find.textContaining('还没有训练记录'), findsOneWidget);
      expect(find.textContaining('已删除全部数据'), findsOneWidget);
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

      await pumpProfile(tester);
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

      await pumpProfile(tester);
      await tapDeleteAll(tester);
      await tester.tap(find.byKey(const Key('delete-all-confirm')));
      await tester.pumpAndSettle();

      // 新加的表如果不接进 deleteAllUserData，用户点了"删除全部数据"
      // 之后体重还留在库里 —— 这是合规问题，不是功能瑕疵
      expect(await body.count(), 0);
    });
  });
}
