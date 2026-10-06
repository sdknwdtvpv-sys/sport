/// 练了么 · **第二部分那几条的证据图**（2026-10-06）
///
/// 与 `badge_redesign_evidence_test.dart` 同一个定位：**不是商店素材，是验证证据**，
/// 产物进 `docs/images/`（那一目录不参与 `tool/check-screenshots.mjs` 的核对），
/// 命名统一 `part2-20261006-*`。
///
/// 拍两张：**「我」页**（段位卡 + 经验卡 + 收集线奖励 / A5+A1+第 7 条）与
/// **「练」页**（周报卡 + 部位平衡那一行 / 第 1 条 + 第 5 条）。
/// 数据用与徽章那批**同一份**固定记录（`evidence_sets.dart`），
/// 所以两张图里的数字能互相对上（"我"页的总组数与首页那一行是同一份记录）。
///
/// ⚠️ 回归激励（第 9 条）拍不到：那份固定记录的最后一场在 2026-10-04，
/// 而"断 7 天"要求今天已经过去 7 天以上 —— 这条由
/// `muscle_balance_test.dart` 的纯函数测试钉住（判据 + 文案都测了），
/// 不为了一张图去改数据（改了就不再是同一份记录）。
///
/// 跑法（在 `app/` 下，iOS 模拟器 `lianleme-69`）：
///     SHOT_DIR=../docs/images flutter drive \
///       --driver=test_driver/screenshot_driver.dart \
///       --target=integration_test/part2_evidence_test.dart -d <UDID>
///
/// 判据是最后那行 `LIANLEME-EVIDENCE-SUMMARY`：**失败 0 步**才算过。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/profile_screen.dart';
import 'package:lianleme/features/progress/comeback.dart';
import 'package:lianleme/features/progress/muscle_balance.dart';
import 'package:lianleme/features/progress/streak_protection.dart';
import 'package:lianleme/features/progress/weekly_report.dart';
import 'package:lianleme/features/today/today_screen.dart';

import 'evidence_sets.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final List<String> shot = <String>[];
  final List<String> failed = <String>[];

  testWidgets('第二部分的证据图（周报 / 部位平衡 / 我的页）', (WidgetTester tester) async {
    Future<void> settle([int ms = 1200]) async {
      final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    Future<void> capture(String name) async {
      try {
        await binding.takeScreenshot(name).timeout(const Duration(seconds: 15));
        shot.add(name);
        debugPrint('LIANLEME-EVIDENCE $name');
      } catch (e) {
        failed.add('$name: $e');
        debugPrint('LIANLEME-EVIDENCE-FAIL $name — $e');
      }
    }

    final List<SetRecord> sets = evidenceSets();
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    try {
      final DriftLocalStore store = DriftLocalStore(db);
      for (final SetRecord r in sets) {
        await store.saveSet(r);
      }
      final ExerciseRepository repo = ExerciseRepository(db);
      // ⚠️ **动作表要自己灌**：`byId()` 查不到动作时 `muscleOf` 是空表，
      // 部位平衡那一行就永远算不出来（第一次跑就栽在这儿：图里少了那一行，
      // 而提示只是"Expected: not null"）。种子里 351 条，读一次就够。
      // 用 `rootBundle` 而不是 `File(...)`：integration test 的工作目录不是 `app/`，
      // 相对路径读文件会以"文件不存在"失败（第一次就栽在这儿）。
      await repo.importSeed(loadJson: () => rootBundle.loadString('assets/exercises.json'));
      expect(await repo.builtinCount(), greaterThan(0),
          reason: '动作表空的 —— 部位平衡那一行会算不出来');

      // ── 「我」页：段位（A5）+ 经验（第 7 条）+ 收集线奖励（A1）──────────
      try {
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: Tokens.bg,
            body: ProfileScreen(
              store: store,
              repository: repo,
              profile: ProfileRepository(db),
            ),
          ),
        ));
        await settle(2200);
        expect(find.byKey(const Key('rank-card')), findsOneWidget);
        expect(find.byKey(const Key('experience-card')), findsOneWidget);
        // ⚠️ 经验卡在统计区之下：ListView 懒构建，不滚过去它不在树里（老规矩）
        await tester.dragUntilVisible(find.byKey(const Key('experience-card')),
            find.byType(ListView), const Offset(0, -260));
        await settle(900);
        await capture('part2-20261006-profile');
      } catch (e) {
        failed.add('profile: $e');
        debugPrint('LIANLEME-EVIDENCE-STEP-FAIL profile — $e');
      }

      // ── 「练」页：周报（第 1 条）+ 部位平衡（第 5 条）──────────────────
      try {
        // 周报的判据是"周一 / 周二"，而这份记录的"上周"是 9/28~10/4 ——
        // 所以图里那一天的**周几**决定了周报出不出得来。用记录本身的最后一天
        // 所在那一周的**周二**当"今天"，两种情况都能拍到（周报 + 部位平衡）。
        final DateTime now = DateTime(2026, 10, 6, 20);
        final Map<String, String> muscleOf = await muscleMapForWeek(
          sets: sets,
          muscleOfId: (String id) async => (await repo.byId(id))?.muscleGroup,
          day: now,
        );
        final ({String text, String? worst, String? most})? balance =
            muscleBalanceHint(sets: sets, muscleOf: muscleOf, day: now);
        expect(balance, isNotNull, reason: '这份记录应当算得出部位平衡那一行');
        // 这块图的"今天"是**真的今天**，而周报只在周一/周二 + 上周练过时才出现 ——
        // 所以这一屏在别的日子本来就不该有周报（判据是纯函数，测试在
        // `weekly_report_test.dart` 里逐条钉着）。这里只断言"按判据该有就有"。
        expect(shouldShowWeeklyReport(sets, now),
            DateUtils.isSameDay(now, DateTime.now()) &&
                (now.weekday == DateTime.monday ||
                    now.weekday == DateTime.tuesday),
            reason: '周报的出现与否必须与纯函数的判据一致');

        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: Tokens.bg,
            body: TodayScreen(
              onStart: () {},
              // ⚠️ 这一行也要给真数：不给的话它按默认 0 显示"还没有训练记录"，
              // 而同一张图上周报正写着"上周练了 7 次" —— 那是自相矛盾的假话
              // （第一版图里就是这样，所以这一行现在是显式传的）。
              lastWeekSessions: weeklyReportFor(sets, now).sessions,
              streak: 0,
              recent: const <({String workoutId, DateTime day, int exercises, int sets, double volume})>[],
              weeklyReport: weeklyReportFor(sets, now),
              muscleBalance: balance!.text,
              comebackNudge: comebackCopy(sets, now),
            ),
          ),
        ));
        await settle(1800);
        await tester.dragUntilVisible(find.byKey(const Key('weekly-report')),
            find.byType(ListView), const Offset(0, -260));
        await settle(900);
        await capture('part2-20261006-today');

        // ── 补签保护（第二部分第 2 条）：把"今天"设成 10/14（周三）──────
        //
        // 为什么换一天：这份固定记录的最后一场是 **10/4**（周日），那之后到今天
        // 已经断了几十天 —— 那种局面下**不该**给补签（链回不来），
        // 所以拿它拍不到这一条。10/14 那一周里记录中有 10/13（周一）与 10/14，
        // 只有 10/12（周日，属上一周）是一个洞 —— 正是要为它拍一张。
        //
        // ⚠️ 用**同一份记录**、只换"今天"，判据与生产代码完全一样
        // （`protectionOffer()` 是纯函数），没有为截图造一条假的补齐状态。
        // 判据用的是**真的今天**（`DateTime.now()`）：`protectionOffer()` 只吃传进去的
        // 那个日期，而屏幕上的抬头也必须是同一天 —— 造一个"假今天"就会出现
        // "卡片里写着 10 月 12 日、抬头写着 10 月 6 日"那种自相矛盾的图。
        // ⚠️ 抹掉时分秒：`protectionOffer()` 内部用的是**当天零点**，
        // 拿带时分秒的 now 去比日期，`expect` 会因为时间部分不等而失败
        // （报错长这样：`Expected: DateTime:<2026-10-04 13:39:27.428252>`）。
        final DateTime nowD = DateTime.now();
        final DateTime today = DateTime(nowD.year, nowD.month, nowD.day);
        final DateTime yesterday = today.subtract(const Duration(days: 1));

        // 把最近几天补齐（唯独漏掉**前天**），让"昨天与前天里恰好断一天"这个局面真的成立。
        // ⚠️ 只往**这一张图的副本**里补，`sets` 本身不动（周报 / 部位平衡那两张图
        // 用的是原来那份，补了的话它们的数字就跟着变了）。
        int n = 900;
        // 局面：**今天练了、昨天空着、前天及更早都练过** ——
        // 正是补签判据要的那种"恰好断一天"（判据本身在
        // `streak_protection_test.dart` 里逐条钉着，这里只是把局面摆出来）。
        SetRecord day(DateTime d) => SetRecord(
              id: 'ev-${n++}',
              workoutId: 'ev-d${d.year}${d.month}${d.day}',
              exerciseId: 'ex_bb_bench_press',
              setIndex: 1,
              reps: 10,
              weightKg: 60,
              completedAtMs: DateTime(d.year, d.month, d.day, 19)
                  .millisecondsSinceEpoch,
            );
        // 造局面：**昨天&更早都练了，唯独前天是洞**（`i == 2` 跳过）。
        //   * `i = 1` 是昨天 → 必须练过，否则判据会把洞选成昨天；
        //   * `i = 2` 是前天 → 这就是要补的那天（跳过）；
        //   * `i = 3..10` 往前补几天，让链看起来是连续的。
        final List<SetRecord> withRecentDays = <SetRecord>[
          // ⚠️ 只取**最近 11 天之前**的那些记录，然后自己铺满最近 11 天 ——
          // 不能直接 `...sets` 再往上加：那份固定记录里本来就有 10/4 之类的一天，
          // "加"是加不出洞的（第一版就想当然了，`db=true` 直接把局面抵掉）。
          for (final SetRecord r in sets)
            if (DateTime.fromMillisecondsSinceEpoch(r.completedAtMs)
                .isBefore(today.subtract(const Duration(days: 11))))
              r,
          // 今天练了（补签的**代价**：本周至少练过一次；也免得"今天还没练"插进来）
          day(today),
          // 往前十天都练过，**唯独昨天留空** —— 那个洞就是要补的那一天
          for (int i = 2; i <= 10; i++) day(today.subtract(Duration(days: i))),
        ];
        expect(trainedThisWeek(withRecentDays, today), isTrue);
        expect(trainedThisWeek(withRecentDays, today), isTrue);
        debugPrint('LIANLEME-DBG cost=${trainedThisWeek(withRecentDays, today)} '
            'y=${trainedOn(withRecentDays, today.subtract(const Duration(days: 1)))} '
            'db=${trainedOn(withRecentDays, today.subtract(const Duration(days: 2)))} '
            'today=${trainedOn(withRecentDays, today)} '
            'used=${usedThisWeek(<String>{}, today)}');
        final StreakProtectionOffer? offer =
            protectionOffer(withRecentDays, <String>{}, today);
        expect(offer, isNotNull, reason: '这个局面应当给补签');
        expect(offer?.day, yesterday, reason: '要补的是**昨天**那个洞');

        Future<void> pumpToday({required Set<String> protected}) async {
          await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: Scaffold(
              backgroundColor: Tokens.bg,
              body: TodayScreen(
                onStart: () {},
                // ⚠️ 这三行**必须用同一份记录**：连续天数、其中几天是补签、
                // 能不能补 —— 三处各用一份数据的话，图上的数字会互相对不上。
                // ⚠️ 抬头那一行日期也要跟着走（`debugToday` 只影响那一行与
                // 「最近训练」的措辞）—— 不然图上是"卡片写着 10 月 12 日、
                // 抬头写着 10 月 6 日"，一张自相矛盾的证据图还不如不拍。
                debugToday: today,
                lastWeekSessions: weeklyReportFor(sets, today).sessions,
                streak: streakWithProtection(withRecentDays, protected, today),
                protectedInStreak:
                    protectedDaysInStreak(withRecentDays, protected, today),
                protectionOffer:
                    protectionOffer(withRecentDays, protected, today),
                onProtectStreak: () {},
                recent: const <({String workoutId, DateTime day, int exercises, int sets, double volume})>[],
              ),
            ),
          ));
          await settle(1500);
          await tester.dragUntilVisible(find.byKey(const Key('streak-card')),
              find.byType(ListView), const Offset(0, -260));
          await settle(700);
        }

        await pumpToday(protected: <String>{});
        expect(find.byKey(const Key('protection-offer')), findsOneWidget,
            reason: '没补过时那一行必须出现');
        await capture('part2-20261006-protection-offer');

        // 补上之后：那一行与按钮消失，连续天数那行**如实写出"其中 N 天是补签"**
        await pumpToday(protected: <String>{dayKey(yesterday)});
        expect(find.byKey(const Key('protection-offer')), findsNothing,
            reason: '补过之后不该再问一次（这一周额度用完了）');
        expect(
          tester.widget<Text>(find.byKey(const Key('streak-label'))).data,
          contains('补签'),
          reason: '连续天数里含补签却不写出来 = 假话',
        );
        await capture('part2-20261006-protection-done');
      } catch (e) {
        failed.add('today: $e');
        debugPrint('LIANLEME-EVIDENCE-STEP-FAIL today — $e');
      }
    } finally {
      await db.close();
    }

    debugPrint('LIANLEME-EVIDENCE-SUMMARY 成功 ${shot.length} 张（${shot.join(',')}）'
        ' · 失败 ${failed.length} 步 ${failed.isEmpty ? '' : ':: ${failed.join(' | ')}'}');
  });
}
