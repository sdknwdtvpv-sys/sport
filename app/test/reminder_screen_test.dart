/// 练了么 · 设置页里的「训练提醒」（开关 + 时间）
///
/// 这里守的是**交互上的诚实**：权限被拒时开关必须弹回去并说明原因，
/// 而不是"打开了但什么都不响"——那种状态用户查不出来，也怪不到系统头上。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/glass_switch.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/features/profile/reminder.dart';
import 'package:lianleme/features/profile/settings_screen.dart';

/// 有状态的宿主：模拟 main.dart —— 改完 setState 重建，新值再传回页面。
class _ReminderHost extends StatefulWidget {
  const _ReminderHost({
    required this.profile,
    required this.initial,
    this.hint,
    required this.onChanged,
  });

  final ProfileRepository profile;
  final ReminderSettings initial;
  final String? hint;
  final Future<bool> Function(ReminderSettings) onChanged;

  @override
  State<_ReminderHost> createState() => _ReminderHostState();
}

class _ReminderHostState extends State<_ReminderHost> {
  late ReminderSettings _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return PreferencesScreen(
      profile: widget.profile,
      unit: WeightUnit.kg,
      reminder: _value,
      reminderHint: widget.hint,
      onReminderChanged: (ReminderSettings next) async {
        final bool ok = await widget.onChanged(next);
        if (ok && mounted) setState(() => _value = next);
        return ok;
      },
    );
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// 「训练提醒」那一节在偏好设置页的**折叠线以下**：列表是懒构建的，
  /// 不滚过去它在树里根本不存在（`find` 找不到）。与 rest_preference_test 同一招。
  Future<void> reveal(WidgetTester tester, Key key) async {
    await tester.dragUntilVisible(
      find.byKey(key),
      find.byType(ListView),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pump(
    WidgetTester tester, {
    required Future<bool> Function(ReminderSettings) onChanged,
    ReminderSettings initial = ReminderSettings.off,
    String? hint,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      // 与真实 App 一致的中文本地化：少了它，时间选择器的按钮是 OK/Cancel ——
      // 而"中文 App 里夹着英文按钮"正是这个项目在意的细节。
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const <Locale>[Locale('zh', 'CN')],
      home: _ReminderHost(
        profile: ProfileRepository(db),
        initial: initial,
        hint: hint,
        onChanged: onChanged,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('默认：开关是关的，也没有「提醒时间」那一行', (WidgetTester tester) async {
    await pump(tester, onChanged: (_) async => true);
    await reveal(tester, const Key('reminder-switch'));

    final AppSwitchTile sw =
        tester.widget<AppSwitchTile>(find.byKey(const Key('reminder-switch')));
    expect(sw.value, isFalse);
    expect(find.byKey(const Key('reminder-time')), findsNothing);
    // 文案审计（2026-10-04）：原来断言的是「默认关闭」——那是**复述开关的状态**
    // （开关就摆在眼前），已删。留下的是真正有信息量的那句：数据去向。
    expect(find.textContaining('不上传任何东西'), findsOneWidget,
        reason: '关闭态要如实说清「在本机提醒、不上传」，这是隐私承诺，不能悄悄丢掉');
  });

  testWidgets('★ 打开（系统给了权限）→ 开关亮、出现时间行、回调收到 enabled=true',
      (WidgetTester tester) async {
    final List<ReminderSettings> seen = <ReminderSettings>[];
    await pump(tester, onChanged: (ReminderSettings s) async {
      seen.add(s);
      return true;
    });

    await reveal(tester, const Key('reminder-switch'));
    await tester.tap(find.byKey(const Key('reminder-switch')));
    await tester.pumpAndSettle();

    expect(seen.single.enabled, isTrue);
    final AppSwitchTile sw =
        tester.widget<AppSwitchTile>(find.byKey(const Key('reminder-switch')));
    expect(sw.value, isTrue);
    expect(find.byKey(const Key('reminder-time')), findsOneWidget);
    expect(find.byKey(const Key('reminder-time-label')), findsOneWidget);
  });

  testWidgets('★ 权限被拒 → 开关**弹回去**，并如实说清怎么办', (WidgetTester tester) async {
    await pump(tester, onChanged: (_) async => false);

    await reveal(tester, const Key('reminder-switch'));
    await tester.tap(find.byKey(const Key('reminder-switch')));
    await tester.pumpAndSettle();

    final AppSwitchTile sw =
        tester.widget<AppSwitchTile>(find.byKey(const Key('reminder-switch')));
    expect(sw.value, isFalse, reason: '没拿到权限就不该显示成"已开启"');
    expect(find.textContaining('系统没有给通知权限'), findsOneWidget);
    expect(find.byKey(const Key('reminder-time')), findsNothing);
  });

  testWidgets('开着的时候显示「下次提醒：…」（真机上缺这一行才被误解成"没响"）',
      (WidgetTester tester) async {
    await pump(
      tester,
      initial: const ReminderSettings(enabled: true, minutesOfDay: 20 * 60),
      hint: '下次提醒：明天 20:00（今天已经练过了，不打扰）',
      onChanged: (_) async => true,
    );
    await reveal(tester, const Key('reminder-next'));

    expect(find.byKey(const Key('reminder-next')), findsOneWidget);
    expect(find.textContaining('明天 20:00'), findsOneWidget);
  });

  testWidgets('没开提醒时不显示那一行', (WidgetTester tester) async {
    await pump(tester, onChanged: (_) async => true);
    await reveal(tester, const Key('reminder-switch'));
    expect(find.byKey(const Key('reminder-next')), findsNothing);
  });

  testWidgets('开着的时候点「提醒时间」会打开**滚轮**（不是 Material 表盘）',
      (WidgetTester tester) async {
    await pump(
      tester,
      initial: const ReminderSettings(enabled: true, minutesOfDay: 20 * 60),
      onChanged: (_) async => true,
    );
    await reveal(tester, const Key('reminder-time'));

    await tester.tap(find.byKey(const Key('reminder-time')));
    await tester.pumpAndSettle();

    // 闹钟式双滚轮（不是 Material 的表盘）：小时 + 分钟两个 picker，
    // 而且**不再有 TimePickerDialog**（那正是真机上难用的那个）。
    expect(find.byKey(const Key('time-wheel-hour')), findsOneWidget);
    expect(find.byKey(const Key('time-wheel-minute')), findsOneWidget);
    expect(find.byType(TimePickerDialog), findsNothing);
  });

  testWidgets('拨滚轮到 07:30 → 回调收到那个分钟数', (WidgetTester tester) async {
    final List<ReminderSettings> seen = <ReminderSettings>[];
    await pump(
      tester,
      initial: const ReminderSettings(enabled: true, minutesOfDay: 20 * 60),
      onChanged: (ReminderSettings s) async {
        seen.add(s);
        return true;
      },
    );

    await reveal(tester, const Key('reminder-time'));
    await tester.tap(find.byKey(const Key('reminder-time')));
    await tester.pumpAndSettle();

    // 两个滚轮各拨到 07 / 30：`dragUntilVisible` 对 picker 不适用，
    // 直接按 itemExtent(44) 算距离更稳（这就是滚轮的确定之处 —— 表盘得按坐标猜）。
    // 从初始的 20 时**往上拨 11 格** → 索引 20+11 = 31 → 生产代码取模后是 07。
    // （looping picker 的 selectedItem 不取模 —— 生产代码里的 `% 24` 就是被这条钉住的）
    await tester.drag(find.byKey(const Key('time-wheel-hour')), const Offset(0, -44 * 11));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('time-wheel-minute')), const Offset(0, -44 * 30));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('time-wheel-done')));
    await tester.pumpAndSettle();

    expect(seen, isNotEmpty, reason: '拨完必须通知上层（存库 + 重排都由上层做）');
    expect(seen.last.minutesOfDay, 7 * 60 + 30);
    expect(find.text('07:30'), findsOneWidget);
  });

  _trainingTimeSuggestionUiTests();
}

// ── 固定训练时段建议（第二部分第 6 条，2026-10-06）──────────────────

void _trainingTimeSuggestionUiTests() {
  testWidgets('★ 有建议时那一行出现；点它**打开开关并把时间改成建议的点**',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ProfileRepository profile = ProfileRepository(db);
    ReminderSettings? applied;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: PreferencesScreen(
          profile: profile,
          unit: WeightUnit.kg,
          reminder: const ReminderSettings(enabled: false, minutesOfDay: 20 * 60),
          onReminderChanged: (ReminderSettings next) async {
            applied = next;
            return true;
          },
          trainingTimeSuggestion: '你多数在 19:00 前后开始练（8 次）—— 要不要把提醒定在这个点？',
          suggestedReminderMinutes: 19 * 60,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final Finder tile = find.byKey(const Key('reminder-suggestion'));
    await tester.dragUntilVisible(
        tile, find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(tile, findsOneWidget);
    expect(find.textContaining('19:00'), findsWidgets);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(applied, isNotNull, reason: '点了要真的把设置交出去');
    expect(applied!.enabled, isTrue, reason: '采纳建议 = 打开提醒');
    expect(applied!.minutesOfDay, 19 * 60, reason: '时间要变成建议的那个点');
  });

  testWidgets('★ 没有建议时那一行**完全不出现**（数据不够就不许瞎建议）',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: PreferencesScreen(
          profile: ProfileRepository(db),
          unit: WeightUnit.kg,
          reminder: const ReminderSettings(enabled: false, minutesOfDay: 20 * 60),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reminder-suggestion')), findsNothing);
  });
}
