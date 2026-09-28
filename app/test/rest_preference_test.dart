/// 练了么 · 默认休息时长偏好测试
///
/// 这里要守住的核心：**默认必须"跟随动作"**。种子里各动作的休息时长差异很大
/// （核心 45s、深蹲 180s），如果默认变成全局覆盖，等于把这份信息悄悄抹掉。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/db.dart' hide UserProfile;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/profile_screen.dart';
import 'package:lianleme/features/workout/workout_controller.dart';

/// 深蹲：动作自带 180 秒
const ExerciseSpec _squat = ExerciseSpec(
  id: 'ex_bb_squat',
  name: '杠铃深蹲',
  weightIncrement: 2.5,
  defaultWeightKg: 60,
  defaultRestSec: 180,
);

/// 卷腹：动作自带 45 秒 —— 和深蹲差 4 倍，正是"不该被统一覆盖"的例子
const ExerciseSpec _crunch = ExerciseSpec(
  id: 'ex_crunch',
  name: '卷腹',
  weightIncrement: 0,
  defaultRestSec: 45,
);

const PlanTarget _plan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

WorkoutController _controller(ExerciseSpec e, {int? restOverrideSec}) {
  final WorkoutController c = WorkoutController(
    exercise: e,
    plan: _plan,
    analytics: RecordingAnalytics(),
    store: InMemoryLocalStore(),
    syncQueue: InMemorySyncQueue(),
    profile: UserProfile(restOverrideSec: restOverrideSec),
  );
  return c;
}

void main() {
  group('控制器：休息时长怎么定', () {
    test('没设偏好 → 跟随动作（深蹲 180s、卷腹 45s 各用各的）', () {
      expect(_controller(_squat).plannedRestSec, 180);
      expect(_controller(_crunch).plannedRestSec, 45);
    });

    test('设了偏好 → 全局覆盖，两个动作都一样', () {
      expect(_controller(_squat, restOverrideSec: 60).plannedRestSec, 60);
      expect(_controller(_crunch, restOverrideSec: 60).plannedRestSec, 60);
    });

    test('倒计时真的按生效值走，不是按动作自带值', () {
      final WorkoutController c = _controller(_squat, restOverrideSec: 90);
      c.onBigButtonTap(); // 记一组会自动开始休息
      expect(c.restRemainingSec, 90, reason: '覆盖值没生效的话这里会是 180');
    });

    test('埋点的 planned_sec 用生效值 —— 否则数据分析会误判', () {
      final RecordingAnalytics a = RecordingAnalytics();
      final WorkoutController c = WorkoutController(
        exercise: _squat,
        plan: _plan,
        analytics: a,
        store: InMemoryLocalStore(),
        syncQueue: InMemorySyncQueue(),
        profile: const UserProfile(restOverrideSec: 90),
      );
      c.onBigButtonTap();

      final Map<String, Object?> started = a.propsOf('rest_started').single;
      expect(started['planned_sec'], 90,
          reason: '用动作自带的 180 会把"用户改了休息时长"这件事完全掩盖掉');
    });
  });

  group('仓库：偏好读写', () {
    late AppDatabase db;
    late ProfileRepository profile;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      profile = ProfileRepository(db);
    });

    tearDown(() => db.close());

    test('默认是"跟随动作"（null），而不是某个具体秒数', () async {
      expect(await profile.restOverrideSec(), isNull,
          reason: '默认必须是跟随动作；默认成 90 秒就等于把所有动作统一成 90 了');
    });

    test('设具体值再读回来', () async {
      await profile.setRestOverrideSec(60, nowMs: 1000);
      expect(await profile.restOverrideSec(), 60);
    });

    test('设回 null 就是回到"跟随动作"', () async {
      await profile.setRestOverrideSec(60, nowMs: 1000);
      await profile.setRestOverrideSec(null, nowMs: 2000);
      expect(await profile.restOverrideSec(), isNull);
    });

    test('哨兵值 0 不会被当成一个合法的休息时长', () async {
      await profile.setRestOverrideSec(0, nowMs: 1000);
      expect(await profile.restOverrideSec(), isNull, reason: '0 = 跟随动作');
    });

    test('⚠️ 改休息时长不会把单位 / 渐进 / 隐私开关带回去', () async {
      await profile.setUnit(WeightUnit.lb, nowMs: 1000);
      await profile.setProgressionMode(ProgressionMode.off, nowMs: 1000);
      await profile.setAnalyticsEnabled(false, nowMs: 1000);

      await profile.setRestOverrideSec(60, nowMs: 2000);

      expect(await profile.restOverrideSec(), 60);
      expect(await profile.unit(), WeightUnit.lb);
      expect(await profile.progressionMode(), ProgressionMode.off);
      expect(await profile.analyticsEnabled(), isFalse);
    });

    test('反向也成立：改单位不会把休息时长带回去', () async {
      await profile.setRestOverrideSec(120, nowMs: 1000);
      await profile.setUnit(WeightUnit.lb, nowMs: 2000);
      expect(await profile.restOverrideSec(), 120);
    });
  });

  group('S10 的休息时长开关', () {
    late AppDatabase db;
    late DriftLocalStore store;
    late ExerciseRepository repo;
    late ProfileRepository profile;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftLocalStore(db);
      repo = ExerciseRepository(db);
      profile = ProfileRepository(db);
      await repo.importSeed(
        loadJson: () => File('assets/exercises.json').readAsString(),
      );
    });

    tearDown(() => db.close());

    /// 有状态的宿主：模拟 main.dart 的行为 —— 用户改了之后 setState 重建，
    /// 新的偏好值再传给页面。少了这一层，页面永远拿着旧 prop，
    /// "已选中"的高亮和说明文字都不会变，测的就不是真实行为。
    Future<void> pump(WidgetTester tester,
        {int? restOverrideSec, ValueChanged<int?>? onChanged}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: _RestHost(
            store: store,
            repository: repo,
            profile: profile,
            initial: restOverrideSec,
            onChanged: onChanged,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tapRest(WidgetTester tester, String key) async {
      await tester.dragUntilVisible(
        find.byKey(Key(key)),
        find.byType(ListView),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('默认高亮「跟随动作」，并解释各动作自带的值不一样',
        (WidgetTester tester) async {
      await pump(tester);
      await tapRest(tester, 'rest-follow'); // 先滚到这一区

      expect(find.text('跟随动作'), findsOneWidget);
      expect(find.textContaining('每个动作用它自带的休息时长'), findsOneWidget);
    });

    testWidgets('选 60 秒 → 落库 + 通知上层', (WidgetTester tester) async {
      int? notified;
      await pump(tester, onChanged: (int? v) => notified = v);

      await tapRest(tester, 'rest-60');

      expect(await profile.restOverrideSec(), 60, reason: '必须落库');
      expect(notified, 60, reason: '必须通知上层，否则训练屏还用旧值');
      expect(find.textContaining('所有动作统一休息 60 秒'), findsOneWidget);
    });

    testWidgets('再点「跟随动作」能回到默认', (WidgetTester tester) async {
      await profile.setRestOverrideSec(60, nowMs: 1000);
      int? notified;
      await pump(tester, restOverrideSec: 60, onChanged: (int? v) => notified = v);

      await tapRest(tester, 'rest-follow');

      expect(await profile.restOverrideSec(), isNull);
      expect(notified, isNull);
    });

    testWidgets('已经是同一个值时不再重复写库', (WidgetTester tester) async {
      int calls = 0;
      await pump(tester, onChanged: (int? _) => calls++);

      await tapRest(tester, 'rest-follow'); // 默认就是 follow
      expect(calls, 0, reason: '没变化就不该通知');
    });
  });
}

/// 模拟 main.dart：持有偏好值，收到变更后重建页面。
class _RestHost extends StatefulWidget {
  const _RestHost({
    required this.store,
    required this.repository,
    required this.profile,
    required this.initial,
    this.onChanged,
  });

  final LocalStore store;
  final ExerciseRepository repository;
  final ProfileRepository profile;
  final int? initial;
  final ValueChanged<int?>? onChanged;

  @override
  State<_RestHost> createState() => _RestHostState();
}

class _RestHostState extends State<_RestHost> {
  int? _rest;

  @override
  void initState() {
    super.initState();
    _rest = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return ProfileScreen(
      store: widget.store,
      repository: widget.repository,
      profile: widget.profile,
      restOverrideSec: _rest,
      onRestOverrideChanged: (int? v) {
        setState(() => _rest = v);
        widget.onChanged?.call(v);
      },
    );
  }
}
