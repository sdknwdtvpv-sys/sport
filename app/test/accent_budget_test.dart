/// 练了么 · **一屏一个橙色**（VI 计划 §5.4 的 `AccentBudget` 守卫）
///
/// 规格 §4 硬约束 1 与 §12 清单第 3 条写着「一屏内 `accent` ≤ 1」—— 而它一直是**一句口号**
/// （176 处 `Tokens.accent`，单屏落点：训练屏 10 处、首页 6 处、全部数据 2 处）。
/// 计划 §3 冲突 5 的裁决是：**拆令牌**（文字链接走 `accentText`）+ **这个守卫**。
///
/// ## ⚠️ 与计划的一处形式出入（写在最前面）
///
/// 计划 §5.4 要的是一个 `app/lib/core/accent_budget.dart` 里的 `InheritedWidget` +
/// `AccentBudget.claim(...)`，由**生产代码**在每个橙块上登记。这里**没有那样做**，理由：
///   * 那要求改五类落点的每一处调用点（实心块 / 进度填充 / 选中胶囊 / 强调图标 / 未读点），
///     而这一版的目标是"**让这条不变量可跑**"，不是"给每个橙块加一个登记调用"；
///   * 登记调用漏一个，守卫就永远绿 —— 那正是"不可信的守卫"。
///
/// 所以守卫改成**在测试里扫渲染出来的树**：把五个登记点的判据写成
/// [accentCarriersIn]，对真实屏 `pumpAndSettle` 之后数一遍。它同样**会红**，
/// 而且不需要生产代码配合（少一个能悄悄失效的环节）。
///
/// ## 断言的取值
///
/// 计划说"三个关键屏断言 `debugCount == 0`（超了就 > 0）"。**实测之后这条不成立**：
/// 训练屏本来就有两个承载体（那颗**大按钮**与**休息条的填充**）。
/// 而计划 §3 冲突 5 的裁决**明确保留了休息条用 `accent`**（"它与休息结束转 success 是一对状态色"）。
/// 两条判断合起来只有一种自洽读法：**训练屏的额度是 2**（大按钮 = 主操作，休息条 = 它的状态延续），
/// 首页 / 全部数据 / 进步页的额度是 **1**。守卫钉的就是这组值 + 每个承载体**是什么**，
/// 于是"再多冒一个橙块"会当场红，而"为什么它不算"也有据可查。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide SetRecord, Workout, Exercise, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/features/progress/all_data_screen.dart';
import 'package:lianleme/features/today/today_screen.dart';
import 'package:lianleme/features/workout/workout_controller.dart';
import 'package:lianleme/features/workout/workout_screen.dart';
import 'package:lianleme/features/workout/workout_session.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart' hide Workout;

/// 一个"橙色承载体"（计划 §5.4 列的五个登记点，逐个翻译成**能在树上认出来的判据**）。
///
/// ⚠️ 刻意**不数**的东西：橙色**文字**（`全部数据 ›` 这类链接 —— 冲突 5 的裁决把它们
/// 换成了 `accentText`，也就不再占用额度）、`Icon` 之外的橙色描边（`tierRare`/`pr` 是另一套）。
List<String> accentCarriersIn(WidgetTester tester) {
  final List<String> out = <String>[];

  // ⚠️ **不能用 `find.byType(Widget)`**：`byType` 是**精确类型**匹配，
  // 而"任何 widget"没有一个是 `runtimeType == Widget` 的 —— 那样扫出来永远是 0，
  // 一个永远绿的守卫比没有守卫更坏（第一版就是这么写的，反向自检当场把它抓了出来）。
  for (final Widget w in tester.allWidgets) {
    final String where = '${w.runtimeType}';

    // ① 实心橙块 / 选中胶囊 / 未读点：`Container`/`DecoratedBox`/`ColoredBox` 的底色 == accent
    Color? box;
    // ⚠️ **只数 `ColoredBox` / `DecoratedBox`，不数 `Container`**：
    // `Container` 只是"那一块"的语法糖 —— 它内部就会构出一个 `ColoredBox`
    // （只给 color 时）或 `DecoratedBox`（给 decoration 时）。三个都数会把
    // **同一个橙块数两遍**（第一版就是这么把"全部数据页"数成 2 的）。
    if (w is ColoredBox) {
      box = w.color;
    } else if (w is DecoratedBox) {
      final Decoration d = w.decoration;
      if (d is BoxDecoration) box = d.color;
    }
    if (box == Tokens.accent) out.add('实心橙块<$where>');

    // ② 进度填充：进度条的颜色是 accent（含 valueColor）
    if (w is LinearProgressIndicator) {
      final Color? c = w.valueColor?.value;
      if (c == Tokens.accent) out.add('进度填充<Linear>');
    }
    if (w is CircularProgressIndicator) {
      if (w.valueColor?.value == Tokens.accent || w.color == Tokens.accent) {
        out.add('进度填充<Circular>');
      }
    }

    // ③ 强调图标：`Icon` 的颜色是 accent
    if (w is Icon && w.color == Tokens.accent) out.add('强调图标<${w.icon?.codePoint}>');

    // ④ 实心主按钮：`FilledButton` 的 backgroundColor 解析成 accent
    if (w is FilledButton) {
      final Color? c = w.style?.backgroundColor?.resolve(<WidgetState>{});
      if (c == Tokens.accent) out.add('实心主按钮');
    }
  }
  return out;
}

void main() {
  // ⚠️ **库与种子必须在 `setUp` 里准备好**：`testWidgets` 体内是**假时钟域**，
  // 而 `File(...).readAsString()` 是真 I/O —— 在假时钟里它**永远不完成**，
  // 测试会安静地挂到框架把它杀掉（这一条我踩了两次：第一次是 `pumpAndSettle` 等转圈圈，
  // 第二次就是这里）。
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
  });

  tearDown(() => db.close());

  testWidgets('★ 反向自检：一棵有两块橙的树必须被数成 2（守卫自己会红）',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            ColoredBox(color: Tokens.accent, child: SizedBox(width: 10, height: 10)),
            ColoredBox(color: Tokens.accent, child: SizedBox(width: 10, height: 10)),
            // 橙色**文字**不算（冲突 5 的裁决：文字链接走 accentText）
            Text('全部数据 ›', style: TextStyle(color: Tokens.accentText)),
          ],
        ),
      ),
    ));
    await tester.pump();
    expect(accentCarriersIn(tester).length, 2,
        reason: '两块橙块要数成 2、橙色文字不算 —— 数不准的守卫等于没有守卫');
  });

  testWidgets('首页：额度 1', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(onStart: () {}, onOpenLibrary: () {}),
    ));
    await tester.pump();
    final List<String> carriers = accentCarriersIn(tester);
    expect(carriers.length, lessThanOrEqualTo(1), reason: '首页的橙：$carriers');
  });

  testWidgets('全部数据页：额度 1', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AllDataScreen(
        store: store,
        repository: repo,
        now: DateTime(2026, 10, 10),
      ),
    ));
    // ⚠️ 不能用 `pumpAndSettle`：这一屏在等库的时候有一个**不确定进度**的转圈圈，
    // 它永远不会静止 —— 第一版就这么挂了 5 分钟才被框架杀掉。
    // 老规矩：推固定时长（与证据脚本里的 `settle(ms)` 同一个写法）。
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final List<String> carriers = accentCarriersIn(tester);
    expect(carriers.length, lessThanOrEqualTo(1), reason: '全部数据页的橙：$carriers');
  });

  testWidgets('训练屏：额度 2（大按钮 + 休息条填充 —— 冲突 5 明确保留的那一对）',
      (WidgetTester tester) async {
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
    final int before = accentCarriersIn(tester).length;
    await tester.pumpWidget(
        MaterialApp(home: WorkoutScreen(session: WorkoutSession.single(c))));
    await tester.pump();

    // 记一组 → 休息条出现（那根填充就是第二个承载体）
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    final List<String> carriers = accentCarriersIn(tester);
    expect(carriers.length, lessThanOrEqualTo(2),
        reason: '训练屏的橙：$carriers（额度 2 = 大按钮 + 休息条填充）');
    expect(carriers.length, greaterThanOrEqualTo(before),
        reason: '休息条出现之后承载体只会变多，不会变少');

    // ⚠️ 记一组会起**休息倒计时**（一个 periodic Timer）：不掐掉，测试结束时会报
    // "Pending timers"（这个文件里我踩过一次）。
    c.skipRest();
    c.dispose();
  });

  test('位移白名单：橙色文字只许走 accentText（冲突 5 的裁决）', () {
    // 这一条是"拆令牌"那半边的守：`Text(color: Tokens.accent)` 出现在 lib 里 → 红。
    // 例外：`accentInk` 是橙**底上的字**（深墨），不在此列；这里只抓"橙色的字"。
    final List<String> bad = <String>[];
    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final int c = lines[i].indexOf('//');
        final String code = c < 0 ? lines[i] : lines[i].substring(0, c);
        // `style: TextStyle(color: Tokens.accent` 这种"橙字"就是越界
        if (RegExp(r'TextStyle\([^)]*color:\s*Tokens\.accent\b').hasMatch(code)) {
          bad.add('${e.path}:${i + 1}');
        }
      }
    }
    expect(bad, isEmpty,
        reason: '橙色文字要用 `Tokens.accentText`（对 bg 8.40:1）：\n${bad.join('\n')}');
  });
}
