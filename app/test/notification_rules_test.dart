/// 三条消息生成规则的契约。
///
/// 这些规则决定"通知中心里会出现什么"，而它们**全在本地算** ——
/// 所以判据都是纯函数级的：给什么数据、出什么消息、会不会重复。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/notification_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/notifications/notification_rules.dart';
import 'package:lianleme/features/profile/reminder.dart';
import 'package:lianleme/features/progress/weekly_challenge.dart';

SetRecord _set(String workout, DateTime at) => SetRecord(
      id: '$workout-${at.millisecondsSinceEpoch}',
      workoutId: workout,
      exerciseId: 'ex_bb_bench_press',
      setIndex: 0,
      weightKg: 60,
      reps: 8,
      completedAtMs: at.millisecondsSinceEpoch,
    );

void main() {
  late AppDatabase db;
  late NotificationRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = NotificationRepository(db);
  });
  tearDown(() => db.close());

  final DateTime today = DateTime(2026, 10, 5, 21, 30);

  group('成就解锁', () {
    test('练过一次 → 至少发一条「首训」，而且**再跑一次不会重复发**', () async {
      final List<SetRecord> sets = <SetRecord>[_set('w1', DateTime(2026, 10, 5, 9))];
      final int first = await syncAchievementMessages(repo: repo, sets: sets, now: today);
      expect(first, greaterThan(0), reason: '至少"首训"该解锁');
      expect((await repo.list()).every((AppNotificationData r) => r.kind == NotificationKind.achievement), isTrue);

      final int second = await syncAchievementMessages(repo: repo, sets: sets, now: today);
      expect(second, 0, reason: '同一个徽章一辈子只发一条');
      expect((await repo.list()).length, first);
    });

    test('一条记录都没有 → 一条都不发（0 也不该解锁任何徽章）', () async {
      expect(await syncAchievementMessages(repo: repo, sets: <SetRecord>[], now: today), 0);
      expect(await repo.list(), isEmpty);
    });

    test('消息里带得上「怎么拿到」那句话（通知中心要显示它）', () async {
      await syncAchievementMessages(
          repo: repo, sets: <SetRecord>[_set('w1', DateTime(2026, 10, 5, 9))], now: today);
      final AppNotificationData first = (await repo.list()).first;
      expect(first.title, contains('解锁'));
      expect(first.body, isNotEmpty);
    });
  });

  group('A3 每周挑战完成（2026-10-06）', () {
    /// 把当前这一周的挑战做完（池子里每一条都做得到：一周四练那套覆盖了全部九枚）。
    List<SetRecord> doneWeekSets() => <SetRecord>[
          for (int d = 0; d < 4; d++) ...<SetRecord>[
            for (int i = 0; i < 6; i++)
              _set('w$d-am', DateTime(2026, 10, 5 + d, 9).add(Duration(minutes: i))),
            for (int i = 0; i < 10; i++)
              _set('w$d-pm', DateTime(2026, 10, 5 + d, 19).add(Duration(minutes: i))),
            SetRecord(
              id: 'run-$d',
              workoutId: 'w$d-pm',
              exerciseId: 'ex_running',
              setIndex: 0,
              reps: 1200,
              distanceM: 3000,
              completedAtMs: DateTime(2026, 10, 5 + d, 19, 30).millisecondsSinceEpoch,
            ),
            // 上午那场也塞一组上肢，保证"上肢 3 次"够（长课全是蹲）
            SetRecord(
              id: 'up-$d',
              workoutId: 'w$d-am',
              exerciseId: 'ex_bb_bench_press',
              setIndex: 0,
              reps: 8,
              weightKg: 60,
              completedAtMs: DateTime(2026, 10, 5 + d, 9, 30).millisecondsSinceEpoch,
            ),
          ],
        ];

    test('★ 本周做完了 → 发一条；同一周再跑不重复发', () async {
      final List<SetRecord> sets = doneWeekSets();
      expect(await maybeWeeklyChallengeDone(repo: repo, sets: sets, now: today), isTrue);
      expect(await maybeWeeklyChallengeDone(repo: repo, sets: sets, now: today), isFalse,
          reason: '同一周的挑战只该发一条');
      final List<AppNotificationData> all = await repo.list();
      expect(all.length, 1);
      expect(all.first.kind, NotificationKind.achievement,
          reason: '复用成就那一类，不新增枚举值');
      expect(all.first.title, contains('本周挑战完成'));
    });

    test('没做完 → 一条都不发（不许"参与即得"）', () async {
      expect(
        await maybeWeeklyChallengeDone(
            repo: repo,
            sets: <SetRecord>[_set('w1', DateTime(2026, 10, 5, 9))],
            now: today),
        isFalse,
      );
      expect(await repo.list(), isEmpty);
    });

    test('★ 轮到同一枚挑战的下一个周期 → **还能再发一条**（去重键必须带周序号）', () async {
      final List<SetRecord> sets = doneWeekSets();
      await maybeWeeklyChallengeDone(repo: repo, sets: sets, now: today);
      expect((await repo.list()).length, 1);

      // 找到"下一次拿到同一枚挑战"的那一周（池子 9 枚 → 9 周后轮回）
      final String firstId = weeklySpec(today).id;
      DateTime later = today.add(const Duration(days: 7));
      for (int i = 0; i < 12; i++) {
        if (weeklySpec(later).id == firstId) break;
        later = later.add(const Duration(days: 7));
      }
      expect(weeklySpec(later).id, firstId, reason: '池子应当会轮回');
      expect(later.isAfter(today), isTrue);

      // 把那份记录平移到 later 那一周再去发
      final int shift = weekBounds(later).start.difference(weekBounds(today).start).inDays;
      final List<SetRecord> shifted = <SetRecord>[
        for (final SetRecord s in sets)
          SetRecord(
            id: '${s.id}-x',
            workoutId: s.workoutId,
            exerciseId: s.exerciseId,
            setIndex: s.setIndex,
            reps: s.reps,
            weightKg: s.weightKg,
            distanceM: s.distanceM,
            completedAtMs: DateTime.fromMillisecondsSinceEpoch(s.completedAtMs)
                .add(Duration(days: shift))
                .millisecondsSinceEpoch,
          ),
      ];
      expect(await maybeWeeklyChallengeDone(repo: repo, sets: shifted, now: later), isTrue,
          reason: '下一轮拿到同一枚挑战时，完成了也要能发出来 —— 只用 id 做去重键就会漏掉这一条');
      expect((await repo.list()).length, 2);
    });
  });

  group('错过的训练提醒', () {
    const ReminderSettings on2000 =
        ReminderSettings(enabled: true, minutesOfDay: 20 * 60);

    test('开着 + 到点了 + 今天没练 → 发一条（refKey 是日期，一天一条）', () async {
      final bool sent = await maybeRemindMissed(
          repo: repo, settings: on2000, sets: <SetRecord>[], now: today);
      expect(sent, isTrue);
      final bool again = await maybeRemindMissed(
          repo: repo, settings: on2000, sets: <SetRecord>[], now: today);
      expect(again, isFalse, reason: '同一天只发一条');
    });

    test('今天练过了 → 不发（提醒的价值是"别断掉"，练过了就不该再提）', () async {
      final bool sent = await maybeRemindMissed(
        repo: repo,
        settings: on2000,
        sets: <SetRecord>[_set('w1', DateTime(2026, 10, 5, 9))],
        now: today,
      );
      expect(sent, isFalse);
      expect(await repo.list(), isEmpty);
    });

    test('还没到点 → 不发', () async {
      final bool sent = await maybeRemindMissed(
        repo: repo,
        settings: on2000,
        sets: <SetRecord>[],
        now: DateTime(2026, 10, 5, 19, 0),
      );
      expect(sent, isFalse);
    });

    test('提醒是关的 → 不发（用户主动关掉的事，不该在通知中心里替他记一笔）', () async {
      final bool sent = await maybeRemindMissed(
        repo: repo,
        settings: ReminderSettings.off,
        sets: <SetRecord>[],
        now: today,
      );
      expect(sent, isFalse);
    });
  });

  group('备份结果', () {
    test('成功与失败各一条，且同一时刻不会重复', () async {
      expect(await addBackupMessage(repo: repo, ok: true, now: today), isTrue);
      expect(await addBackupMessage(repo: repo, ok: true, now: today), isFalse,
          reason: '同一时刻的同一条不该发两次');
      expect(await addBackupMessage(repo: repo, ok: false, now: today), isTrue,
          reason: '失败是另一条消息');
      final List<AppNotificationData> rows = await repo.list();
      expect(rows.length, 2);
      expect(rows.map((AppNotificationData r) => r.title).toList(),
          containsAll(<String>['云备份已完成', '云备份没成功']));
    });
  });
}
