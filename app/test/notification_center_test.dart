/// 消息通知（通知中心）的界面契约。
///
/// 三条要紧的：**没消息时要说人话**（不是一块空白）、**分类筛选真的筛**、
/// **「全部已读」只在有未读时出现且点了要生效**（未读点是"过期状态"最容易出问题的地方）。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/notification_repository.dart';
import 'package:lianleme/features/notifications/notification_center_screen.dart';

Future<void> _pump(WidgetTester tester, NotificationRepository repo) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: NotificationCenterScreen(repository: repo),
  ));
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late NotificationRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = NotificationRepository(db);
  });
  tearDown(() => db.close());

  testWidgets('一条消息都没有：给一句人话，而不是一块空白', (WidgetTester tester) async {
    await _pump(tester, repo);
    expect(find.byKey(const Key('notifications-empty')), findsOneWidget);
    expect(find.byKey(const Key('notifications-mark-all')), findsNothing,
        reason: '没有未读时那个按钮是个点不动的摆设');
  });

  testWidgets('列表按时间倒序，每条带标题、正文、分类与时间', (WidgetTester tester) async {
    await repo.add(
        kind: NotificationKind.achievement, title: '解锁「首训」', body: '完成第 1 次训练', nowMs: 1000);
    await repo.add(
        kind: NotificationKind.backup, title: '云备份已完成', body: '已加密上传', nowMs: 2000);
    await _pump(tester, repo);
    expect(find.text('云备份已完成'), findsOneWidget);
    expect(find.text('解锁「首训」'), findsOneWidget);
    expect(find.textContaining('成就 ·'), findsOneWidget);
    expect(find.textContaining('系统 ·'), findsOneWidget);
    // 倒序：新的在上面（用纵向位置判，别只看"在不在"）
    expect(tester.getCenter(find.text('云备份已完成')).dy,
        lessThan(tester.getCenter(find.text('解锁「首训」')).dy));
  });

  testWidgets('分类筛选真的筛（点「成就」只剩成就那类）', (WidgetTester tester) async {
    await repo.add(kind: NotificationKind.achievement, title: '徽章', body: '', nowMs: 1);
    await repo.add(kind: NotificationKind.reminder, title: '提醒', body: '', nowMs: 2);
    await _pump(tester, repo);
    expect(find.text('徽章'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);

    await tester.tap(find.byKey(const Key('notif-filter-成就')));
    await tester.pumpAndSettle();
    expect(find.text('徽章'), findsOneWidget);
    expect(find.text('提醒'), findsNothing);

    await tester.tap(find.byKey(const Key('notif-filter-全部')));
    await tester.pumpAndSettle();
    expect(find.text('提醒'), findsOneWidget);
  });

  testWidgets('未读点：有的消息带、已读的不带；「全部已读」点完点全消失',
      (WidgetTester tester) async {
    await repo.add(kind: NotificationKind.achievement, title: 'A', body: '', nowMs: 1);
    await repo.add(kind: NotificationKind.achievement, title: 'B', body: '', nowMs: 2);
    await _pump(tester, repo);
    expect(find.byKey(const Key('notifications-mark-all')), findsOneWidget);
    final Iterable<Element> dots = find
        .byWidgetPredicate((Widget w) => w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('unread-'))
        .evaluate();
    expect(dots.length, 2, reason: '两条都未读 → 两个点');

    await tester.tap(find.byKey(const Key('notifications-mark-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notifications-mark-all')), findsNothing,
        reason: '没有未读了 → 那个按钮也该消失');
    expect(
      find
          .byWidgetPredicate((Widget w) => w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('unread-'))
          .evaluate()
          .length,
      0,
    );
    expect(await repo.unreadCount(), 0);
  });

  test('相对时间：刚刚 / 分钟 / 小时 / 昨天 / N 天前 / 日期，且**未来时间不显示负数**', () {
    final DateTime now = DateTime(2026, 10, 5, 12);
    int ms(DateTime d) => d.millisecondsSinceEpoch;
    expect(relativeTime(ms(now.subtract(const Duration(seconds: 20))), now: now), '刚刚');
    expect(relativeTime(ms(now.subtract(const Duration(minutes: 3))), now: now), '3 分钟前');
    expect(relativeTime(ms(now.subtract(const Duration(hours: 5))), now: now), '5 小时前');
    expect(relativeTime(ms(now.subtract(const Duration(days: 1))), now: now), '昨天');
    expect(relativeTime(ms(now.subtract(const Duration(days: 3))), now: now), '3 天前');
    expect(relativeTime(ms(now.subtract(const Duration(days: 30))), now: now), '9月5日');
    expect(relativeTime(ms(now.add(const Duration(hours: 2))), now: now), '刚刚',
        reason: '时钟偏了也别显示"-2 小时前"');
  });
}
