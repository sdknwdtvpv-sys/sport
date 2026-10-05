/// 练了么 · 训练提醒（本地通知）
///
/// 这一组守四件事：
///   1. **什么时候该提醒** —— 规则是"到点了还没练才提醒"，而不是"每天准点响"；
///   2. **服务把三件事捏对了**：开关关着要撤、开着要排、练过了要顺延；
///   3. **训练结束那条预告**（2026-10-05 第 6 条）：练完当晚换成"明天该练X了"，
///      说不出来（没下次部位 / 那个点已经过了 / planner 挂了）就一字不改地退回通用那条，
///      而且**不许新增任何权限**；
///   4. **通道载荷**：Android/iOS 那两边按这些键取值。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/reminder_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/reminder.dart';
import 'package:lianleme/features/profile/reminder_bridge.dart';
import 'package:lianleme/features/profile/reminder_service.dart';

/// 记下"排了什么、撤了几次"的替身。
class FakeReminder implements ReminderBridge {
  final List<ReminderRequest> scheduled = <ReminderRequest>[];
  int cancels = 0;
  ReminderRequest? _current;

  @override
  Future<bool> isAllowed() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(ReminderRequest request) async {
    _current = request; // 与真身一致：同一时刻只留一条
    scheduled.add(request);
  }

  @override
  Future<void> cancel() async {
    cancels++;
    _current = null;
  }

  @override
  Future<int?> scheduledAtMs() async => _current?.atMs;
}

/// 本地时间的某个时刻（测试里不依赖机器时区：用 DateTime 构造，天然是本地时间）。
int _at(int y, int mo, int d, int h, int mi, [int s = 0]) =>
    DateTime(y, mo, d, h, mi, s).millisecondsSinceEpoch;

void main() {
  group('什么时候该提醒（纯函数）', () {
    test('今天还没练、点还没到 → 就今天那个点', () {
      final int at = nextReminderAtMs(
        nowMs: _at(2026, 10, 4, 9, 0),
        minutesOfDay: 20 * 60,
        trainedToday: false,
      )!;
      expect(at, _at(2026, 10, 4, 20, 0));
    });

    test('今天还没练、但那个点已经过去了 → 明天那个点（不补发）', () {
      final int at = nextReminderAtMs(
        nowMs: _at(2026, 10, 4, 21, 30),
        minutesOfDay: 20 * 60,
        trainedToday: false,
      )!;
      expect(at, _at(2026, 10, 5, 20, 0));
    });

    test('★ 今天练过了 → 顺延到明天（提醒是叫人回来，不是每天准点响）', () {
      final int at = nextReminderAtMs(
        nowMs: _at(2026, 10, 4, 9, 0),
        minutesOfDay: 20 * 60,
        trainedToday: true,
      )!;
      expect(at, _at(2026, 10, 5, 20, 0));
    });

    test('跨月与跨年也算得对（不是"加 24 小时"那种近似）', () {
      expect(
        nextReminderAtMs(
            nowMs: _at(2026, 10, 31, 23, 0),
            minutesOfDay: 20 * 60,
            trainedToday: true),
        _at(2026, 11, 1, 20, 0),
      );
      expect(
        nextReminderAtMs(
            nowMs: _at(2026, 12, 31, 23, 0),
            minutesOfDay: 20 * 60,
            trainedToday: true),
        _at(2027, 1, 1, 20, 0),
      );
    });

    test('非法时间（<0 或 ≥1440）不排 —— 宁可没有提醒，也不要排在错的钟点', () {
      expect(nextReminderAtMs(nowMs: 0, minutesOfDay: -1, trainedToday: false),
          isNull);
      expect(nextReminderAtMs(nowMs: 0, minutesOfDay: 1440, trainedToday: false),
          isNull);
    });

    test('今天练过没有：只算正式组，热身不算（热身了不等于练了）', () {
      final DateTime day = DateTime(2026, 10, 4);
      final SetRecord warmup = SetRecord(
        id: 'w',
        workoutId: 'w1',
        exerciseId: 'ex',
        setIndex: 1,
        reps: 15,
        completedAtMs: _at(2026, 10, 4, 9, 0),
        setType: SetType.warmup,
      );
      final SetRecord normal = SetRecord(
        id: 'n',
        workoutId: 'w1',
        exerciseId: 'ex',
        setIndex: 2,
        reps: 8,
        completedAtMs: _at(2026, 10, 4, 9, 5),
      );
      expect(hasTrainedOn(sets: <SetRecord>[warmup], day: day), isFalse);
      expect(hasTrainedOn(sets: <SetRecord>[warmup, normal], day: day), isTrue);
      // 昨天的记录不算今天
      expect(
        hasTrainedOn(
          sets: <SetRecord>[normal],
          day: DateTime(2026, 10, 5),
        ),
        isFalse,
      );
    });
  });

  group('「下次提醒：…」这一行（真机反馈的直接产物）', () {
    test('没开提醒 → 不显示', () {
      expect(
        reminderHint(
            settings: ReminderSettings.off,
            trainedToday: false,
            nowMs: _at(2026, 10, 4, 9, 0)),
        isNull,
      );
    });

    test('今天还没练、点还没到 → 就说今天', () {
      final String? h = reminderHint(
        settings: const ReminderSettings(enabled: true, minutesOfDay: 18 * 60 + 2),
        trainedToday: false,
        nowMs: _at(2026, 10, 4, 18, 0),
      );
      expect(h, contains('今天 18:02'));
    });

    test('★ 今天练过了 → 必须说清"顺延到明天、因为今天练过了"', () {
      final String? h = reminderHint(
        settings: const ReminderSettings(enabled: true, minutesOfDay: 20 * 60),
        trainedToday: true,
        nowMs: _at(2026, 10, 4, 9, 0),
      );
      expect(h, contains('明天 20:00'));
      expect(h, contains('今天已经练过'),
          reason: '真机上就是这一条把人绕住了：设完看不到任何反馈，以为坏了');
    });

    test('今天的点已经过了 → 说明是"点已过"而不是"练过了"', () {
      final String? h = reminderHint(
        settings: const ReminderSettings(enabled: true, minutesOfDay: 17 * 60 + 58),
        trainedToday: false,
        nowMs: _at(2026, 10, 4, 17, 58, 30),
      );
      expect(h, contains('明天 17:58'));
      expect(h, contains('已经过'));
    });

    test('★ 今晚响的是"训练结束那条预告"时，这一行必须跟着改（否则界面会撒谎）', () {
      final String? h = reminderHint(
        settings: const ReminderSettings(enabled: true, minutesOfDay: 20 * 60),
        trainedToday: true,
        nowMs: _at(2026, 10, 4, 10, 0),
        nextMuscleKey: 'chest',
      );
      expect(h, contains('今天 20:00'),
          reason: '系统里真的排着今晚 20:00 —— 这一行还写"明天"就是句假话');
      expect(h, contains('明天该练胸了'),
          reason: '顺带把"今晚响的是哪条"说清楚');
    });

    test('说不出下次部位 → 这一行一个字不改（还是老文案）', () {
      final String? h = reminderHint(
        settings: const ReminderSettings(enabled: true, minutesOfDay: 20 * 60),
        trainedToday: true,
        nowMs: _at(2026, 10, 4, 10, 0),
        nextMuscleKey: null,
      );
      expect(h, contains('明天 20:00'));
      expect(h, contains('今天已经练过'));
    });

    test('练完了但那个点今天已经过了 → 预告不发，这一行也不提它', () {
      final String? h = reminderHint(
        settings: const ReminderSettings(enabled: true, minutesOfDay: 20 * 60),
        trainedToday: true,
        nowMs: _at(2026, 10, 4, 21, 30),
        nextMuscleKey: 'chest',
      );
      expect(h, contains('明天 20:00'));
      expect(h!.contains('明天该练胸了'), isFalse,
          reason: '那一刻不排预告，界面上就不该说它');
    });
  });

  group('服务：把设置 + 今天的事实 + 桥捏在一起', () {
    late AppDatabase db;
    late DriftLocalStore store;
    late ReminderRepository repo;
    late FakeReminder bridge;
    late ReminderService service;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftLocalStore(db);
      repo = ReminderRepository(db);
      bridge = FakeReminder();
      service = ReminderService(repository: repo, bridge: bridge, store: store);
    });

    tearDown(() => db.close());

    test('开关关着（默认）→ 不排，而且要把旧的撤掉', () async {
      await service.sync(nowMs: _at(2026, 10, 4, 9, 0));
      expect(bridge.scheduled, isEmpty);
      expect(bridge.cancels, 1, reason: '关掉开关之后系统里不该还留着一条');
    });

    test('开着 + 今天没练 → 排今天那个点', () async {
      await repo.save(const ReminderSettings(enabled: true, minutesOfDay: 20 * 60));
      await service.sync(nowMs: _at(2026, 10, 4, 9, 0));

      expect(bridge.scheduled, hasLength(1));
      expect(bridge.scheduled.single.atMs, _at(2026, 10, 4, 20, 0));
      expect(bridge.scheduled.single.title, isNotEmpty);
      expect(bridge.scheduled.single.body, isNotEmpty);
    });

    test('★ 练完一组之后再 sync → 顺延到明天（不会刚练完又弹一条）', () async {
      await repo.save(const ReminderSettings(enabled: true, minutesOfDay: 20 * 60));
      await service.sync(nowMs: _at(2026, 10, 4, 9, 0));
      expect(bridge.scheduled.single.atMs, _at(2026, 10, 4, 20, 0));

      // 用户练了一组（正式组）
      await store.saveSet(SetRecord(
        id: 's1',
        workoutId: 'w1',
        exerciseId: 'ex_bb_bench_press',
        setIndex: 1,
        reps: 8,
        completedAtMs: _at(2026, 10, 4, 19, 0),
        weightKg: 60,
      ));
      await service.sync(nowMs: _at(2026, 10, 4, 19, 5));

      expect(bridge.scheduled.last.atMs, _at(2026, 10, 5, 20, 0),
          reason: '练过了就别打扰 —— 明天同一时间再看');
      expect(await bridge.scheduledAtMs(), _at(2026, 10, 5, 20, 0),
          reason: '同一时刻只该排着一条（真身会先取旧再排新的）');
    });

    test('幂等：同一个设置连 sync 三次，排的还是同一条（不会叠三条）', () async {
      await repo.save(const ReminderSettings(enabled: true, minutesOfDay: 20 * 60));
      for (int i = 0; i < 3; i++) {
        await service.sync(nowMs: _at(2026, 10, 4, 9, 0));
      }
      expect(await bridge.scheduledAtMs(), _at(2026, 10, 4, 20, 0));
    });
  });

  group('训练结束那条预告：composeReminder（纯函数）', () {
    const ReminderSettings on20 =
        ReminderSettings(enabled: true, minutesOfDay: 20 * 60);

    test('★ 练完了 + 知道下次部位 + 那个点还没到 → 今晚说"明天该练胸了"', () {
      final ReminderRequest? r = composeReminder(
        nowMs: _at(2026, 10, 5, 10, 0),
        settings: on20,
        trainedToday: true,
        nextMuscleKey: 'chest',
      );
      expect(r, isNotNull);
      expect(r!.atMs, _at(2026, 10, 5, 20, 0));
      expect(r.title, '明天该练胸了');
      expect(r.body, contains('点开直接开始'));
    });

    test('★ 那个点今天已经过了 → 不发预告，退回通用那条（"明天"会说错日子）', () {
      final ReminderRequest? r = composeReminder(
        nowMs: _at(2026, 10, 5, 21, 30),
        settings: on20,
        trainedToday: true,
        nextMuscleKey: 'chest',
      );
      expect(r!.atMs, _at(2026, 10, 6, 20, 0));
      expect(r.title, kTrainingReminderTitle,
          reason: '预告顺延到明天就成了假话（那时"明天"是后天）—— 宁可不发');
    });

    test('说不出下次部位 → 一字不改地退回通用那条', () {
      final ReminderRequest? r = composeReminder(
        nowMs: _at(2026, 10, 5, 10, 0),
        settings: on20,
        trainedToday: true,
        nextMuscleKey: null,
      );
      expect(r!.atMs, _at(2026, 10, 6, 20, 0));
      expect(r.title, kTrainingReminderTitle);
    });

    test('没练过 → 与预告无关，通用那条照旧（哪怕传了部位）', () {
      final ReminderRequest? r = composeReminder(
        nowMs: _at(2026, 10, 5, 10, 0),
        settings: on20,
        trainedToday: false,
        nextMuscleKey: 'chest',
      );
      expect(r!.atMs, _at(2026, 10, 5, 20, 0));
      expect(r.title, kTrainingReminderTitle);
    });

    test('开关关着 → 不排（调用方负责把系统里旧的撤掉）', () {
      expect(
        composeReminder(
          nowMs: _at(2026, 10, 5, 10, 0),
          settings: ReminderSettings.off,
          trainedToday: true,
          nextMuscleKey: 'chest',
        ),
        isNull,
      );
    });

    test('非法时间 → 不排（连预告也不排，而不是夹到别的钟点）', () {
      expect(
        composeReminder(
          nowMs: _at(2026, 10, 5, 10, 0),
          settings: const ReminderSettings(enabled: true, minutesOfDay: 1440),
          trainedToday: true,
          nextMuscleKey: 'chest',
        ),
        isNull,
      );
    });

    test('是不是同一个本地日：按年月日比，不是按"相差 24 小时"', () {
      expect(isSameLocalDay(_at(2026, 10, 5, 0, 1), _at(2026, 10, 5, 23, 59)),
          isTrue);
      // 相差 20.5 小时，但跨了日 —— 正是要挡掉的那种
      expect(isSameLocalDay(_at(2026, 10, 5, 23, 30), _at(2026, 10, 6, 20, 0)),
          isFalse);
    });
  });

  group('训练结束那条预告：服务（接上"下次练哪儿"之后）', () {
    late AppDatabase db;
    late DriftLocalStore store;
    late ReminderRepository repo;
    late FakeReminder bridge;
    late ReminderService service;
    String? muscle;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftLocalStore(db);
      repo = ReminderRepository(db);
      bridge = FakeReminder();
      muscle = 'chest';
      service = ReminderService(
        repository: repo,
        bridge: bridge,
        store: store,
        nextMuscle: () async => muscle,
      );
    });

    tearDown(() => db.close());

    Future<void> logOneSet(int atMs) => store.saveSet(SetRecord(
          id: 's_$atMs',
          workoutId: 'w1',
          exerciseId: 'ex_bb_bench_press',
          setIndex: 1,
          reps: 8,
          completedAtMs: atMs,
          weightKg: 60,
        ));

    test('★ 练完一次就把今天那条「今天还没练」换成「明天该练胸了」', () async {
      await repo.save(const ReminderSettings(enabled: true, minutesOfDay: 20 * 60));
      await service.sync(nowMs: _at(2026, 10, 5, 9, 0));
      expect(bridge.scheduled.single.title, kTrainingReminderTitle);
      expect(bridge.scheduled.single.atMs, _at(2026, 10, 5, 20, 0));

      await logOneSet(_at(2026, 10, 5, 10, 30));
      await service.sync(nowMs: _at(2026, 10, 5, 10, 35));

      expect(bridge.scheduled.last.title, '明天该练胸了',
          reason: '练完了，今晚该说的是"明天练哪儿"，不是"今天还没练"');
      expect(bridge.scheduled.last.atMs, _at(2026, 10, 5, 20, 0));
      expect(await bridge.scheduledAtMs(), _at(2026, 10, 5, 20, 0),
          reason: '同一时刻只该有一条（真身会先撤再排）');
    });

    test('说不出下次部位（没有训练历史）→ 退回通用那条、顺延到明天', () async {
      muscle = null;
      await repo.save(const ReminderSettings(enabled: true, minutesOfDay: 20 * 60));
      await logOneSet(_at(2026, 10, 5, 10, 30));
      await service.sync(nowMs: _at(2026, 10, 5, 10, 35));

      expect(bridge.scheduled.single.title, kTrainingReminderTitle);
      expect(bridge.scheduled.single.atMs, _at(2026, 10, 6, 20, 0));
    });

    test('幂等：同一个事实连 sync 三次，排的还是同一条', () async {
      await repo.save(const ReminderSettings(enabled: true, minutesOfDay: 20 * 60));
      await logOneSet(_at(2026, 10, 5, 10, 30));
      for (int i = 0; i < 3; i++) {
        await service.sync(nowMs: _at(2026, 10, 5, 10, 35));
      }
      expect(bridge.scheduled, hasLength(3));
      expect(bridge.scheduled.map((ReminderRequest r) => r.atMs).toSet(),
          <int>{_at(2026, 10, 5, 20, 0)});
      expect(await bridge.scheduledAtMs(), _at(2026, 10, 5, 20, 0));
    });

    test('问不出答案（planner 抛了）→ 静默退回通用那条，绝不往上抛', () async {
      service = ReminderService(
        repository: repo,
        bridge: bridge,
        store: store,
        nextMuscle: () async => throw StateError('planner 挂了'),
      );
      await repo.save(const ReminderSettings(enabled: true, minutesOfDay: 20 * 60));
      await logOneSet(_at(2026, 10, 5, 10, 30));
      await expectLater(service.sync(nowMs: _at(2026, 10, 5, 10, 35)), completes);

      expect(bridge.scheduled.single.title, kTrainingReminderTitle,
          reason: '排不上预告是小事，影响记录训练才是大事');
    });

    test('开关关着 → 不排，而且把旧的撤掉（与从前一致）', () async {
      await logOneSet(_at(2026, 10, 5, 10, 30));
      await service.sync(nowMs: _at(2026, 10, 5, 10, 35));
      expect(bridge.scheduled, isEmpty);
      expect(bridge.cancels, 1);
    });
  });

  group('通知不新增权限（第 6 条施工清单的最后一条）', () {
    test('源码 manifest 里仍然只有三项 uses-permission，且没有精确闹钟那两条', () {
      final String xml =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final List<String> perms = RegExp(r'<uses-permission\s+android:name="([^"]+)"')
          .allMatches(xml)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();
      expect(perms, <String>[
        'android.permission.INTERNET',
        'android.permission.WRITE_EXTERNAL_STORAGE',
        'android.permission.POST_NOTIFICATIONS',
      ], reason: '加一条"训练结束预告"不该多要任何权限 —— 它复用通知权限');

      // ⚠️ 要先把注释剥掉再看：这份 manifest 的注释里**故意提到了** SCHEDULE_EXACT_ALARM
      // （解释"为什么不需要它"），直接 contains 会把自己的说明当成权限命中。
      final String bare =
          xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      expect(bare.contains('SCHEDULE_EXACT_ALARM'), isFalse,
          reason: '用非精确闹钟换来的一整个权限面，别又加回来');
      expect(bare.contains('USE_EXACT_ALARM'), isFalse);
    });
  });

  group('通道载荷（Kotlin / Swift 两边按这些键取值）', () {
    testWidgets('schedule / cancel / scheduledAtMs / isAllowed / requestPermission',
        (WidgetTester tester) async {
      final List<MethodCall> calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannelReminder.channel,
        (MethodCall call) async {
          calls.add(call);
          switch (call.method) {
            case 'isAllowed':
              return true;
            case 'requestPermission':
              return true;
            case 'scheduledAtMs':
              return 1790612345678;
            default:
              return null;
          }
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelReminder.channel, null));

      const MethodChannelReminder bridge = MethodChannelReminder();
      expect(await bridge.isAllowed(), isTrue);
      expect(await bridge.requestPermission(), isTrue);
      await bridge.schedule(const ReminderRequest(
          atMs: 1790612345678, title: '今天还没练', body: '打开就是今天的安排'));
      await bridge.cancel();
      expect(await bridge.scheduledAtMs(), 1790612345678);

      expect(calls.map((MethodCall c) => c.method).toList(), <String>[
        'isAllowed',
        'requestPermission',
        'schedule',
        'cancel',
        'scheduledAtMs',
      ]);
      final Map<Object?, Object?> args =
          calls[2].arguments as Map<Object?, Object?>;
      expect(args.keys.toSet(), <String>{'atMs', 'title', 'body'});
      expect(args['atMs'], 1790612345678);
    });

    testWidgets('平台没有实现时**静默**（不支持的平台上不该崩）',
        (WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannelReminder.channel,
        (MethodCall call) async => throw MissingPluginException('没有实现'),
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelReminder.channel, null));

      const MethodChannelReminder bridge = MethodChannelReminder();
      expect(await bridge.isAllowed(), isFalse);
      expect(await bridge.requestPermission(), isFalse);
      await expectLater(
        bridge.schedule(const ReminderRequest(atMs: 1, title: 't', body: 'b')),
        completes,
      );
      await expectLater(bridge.cancel(), completes);
      expect(await bridge.scheduledAtMs(), isNull);
    });
  });
}
