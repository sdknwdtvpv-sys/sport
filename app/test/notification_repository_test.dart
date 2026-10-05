/// 站内消息（通知中心）数据层的契约。
///
/// 最要紧的一条是**去重**：同一件事只能发一条。它不是靠调用方"记得先查一次"
/// （那种记得迟早会漏），而是靠数据库层的 partial unique index ——
/// 所以这里要**真的插两次**，看第二次是不是被挡掉。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/notification_repository.dart';

void main() {
  late AppDatabase db;
  late NotificationRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = NotificationRepository(db);
  });
  tearDown(() => db.close());

  test('写一条能读回来，且默认是未读', () async {
    final bool ok = await repo.add(
      kind: NotificationKind.achievement,
      title: '解锁「首训」',
      body: '完成第 1 次训练',
      nowMs: 1000,
    );
    expect(ok, isTrue);
    final List<AppNotificationData> rows = await repo.list();
    expect(rows.length, 1);
    expect(rows.first.title, '解锁「首训」');
    expect(rows.first.readAtMs, isNull);
    expect(await repo.unreadCount(), 1);
  });

  test('去重：同一 kind + refKey 插两次只留一条（靠唯一索引，不靠调用方自觉）', () async {
    Future<bool> put() => repo.add(
          kind: NotificationKind.achievement,
          title: '解锁「一周不断」',
          body: '连续打卡 7 天',
          refKey: 'week_streak',
          nowMs: 2000,
        );
    expect(await put(), isTrue, reason: '第一次该写进去');
    expect(await put(), isFalse, reason: '第二次要被唯一索引挡掉（静默丢掉，不抛异常）');
    expect((await repo.list()).length, 1);
  });

  test('不同 kind 用同一个 refKey 不算重复（两件事各发一条）', () async {
    await repo.add(
        kind: NotificationKind.achievement, title: 'A', body: 'a', refKey: 'x', nowMs: 1);
    await repo.add(kind: NotificationKind.backup, title: 'B', body: 'b', refKey: 'x', nowMs: 2);
    expect((await repo.list()).length, 2);
  });

  test('refKey 为 null 的消息**不参与去重**（同一句话可以出现多次）', () async {
    await repo.add(kind: NotificationKind.reminder, title: '提醒', body: '今天还没练', nowMs: 1);
    await repo.add(kind: NotificationKind.reminder, title: '提醒', body: '今天还没练', nowMs: 2);
    expect((await repo.list()).length, 2);
  });

  test('列表按时间倒序（新的在前）', () async {
    await repo.add(kind: NotificationKind.backup, title: '旧', body: '', nowMs: 100);
    await repo.add(kind: NotificationKind.backup, title: '新', body: '', nowMs: 300);
    await repo.add(kind: NotificationKind.backup, title: '中', body: '', nowMs: 200);
    final List<AppNotificationData> rows = await repo.list();
    expect(rows.map((AppNotificationData r) => r.title).toList(), <String>['新', '中', '旧']);
  });

  test('按类筛（通知中心那排 chip）', () async {
    await repo.add(kind: NotificationKind.achievement, title: '徽章', body: '', nowMs: 1);
    await repo.add(kind: NotificationKind.reminder, title: '提醒', body: '', nowMs: 2);
    expect((await repo.listOf(NotificationKind.achievement)).length, 1);
    expect((await repo.listOf(NotificationKind.achievement)).first.title, '徽章');
    expect((await repo.listOf(null)).length, 2, reason: 'null = 全部');
  });

  test('全部已读：未读数归零，且**只改未读的那些**', () async {
    await repo.add(kind: NotificationKind.achievement, title: 'A', body: '', nowMs: 1);
    await repo.add(kind: NotificationKind.achievement, title: 'B', body: '', nowMs: 2);
    expect(await repo.unreadCount(), 2);
    await repo.markAllRead(nowMs: 5000);
    expect(await repo.unreadCount(), 0);
    final List<AppNotificationData> rows = await repo.list();
    expect(rows.every((AppNotificationData r) => r.readAtMs == 5000), isTrue);
  });

  test('三类 kind 与界面上的筛选一一对应（只有三种）', () {
    expect(NotificationKind.all.length, 3);
    expect(NotificationKind.label(NotificationKind.achievement), '成就');
    expect(NotificationKind.label(NotificationKind.reminder), '训练');
    expect(NotificationKind.label(NotificationKind.backup), '系统');
  });
}
