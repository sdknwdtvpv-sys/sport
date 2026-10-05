/// 等级（Lv）的口径自测。
///
/// 等级是**最容易显得随意**的那种数字：门槛一改，每个人看到的等级都变。
/// 所以边界逐条钉住，而且钉住"门槛表是有序的、不重复的"——
/// 表排错了不会报错，只会让某两级永远升不上去。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/profile_screen.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/features/progress/level.dart';

void main() {
  _levelUi();

  test('门槛表：从 0 开始、严格递增、称号不重复', () {
    expect(kLevelThresholds.first.at, 0, reason: '第一次练就该是 Lv1');
    for (int i = 1; i < kLevelThresholds.length; i++) {
      expect(kLevelThresholds[i].at, greaterThan(kLevelThresholds[i - 1].at),
          reason: '第 ${i + 1} 级的门槛没有严格大于上一级');
    }
    expect(kLevelThresholds.map((({int at, String title}) t) => t.title).toSet().length,
        kLevelThresholds.length,
        reason: '两个等级用了同一个称号');
  });

  test('边界：0 次是 Lv1，差 1 次不升级，刚好到门槛就升', () {
    expect(levelFor(0).level, 1);
    expect(levelFor(4).level, 1);
    expect(levelFor(4).toNext, 1);
    expect(levelFor(5).level, 2);
    expect(levelFor(5).title, '开始上道');
  });

  test('负数当 0 处理（数据坏了也不该算出 Lv.0）', () {
    expect(levelFor(-7).level, 1);
    expect(levelFor(-7).workouts, 0);
  });

  test('到顶：nextAt 为 null、progress 为 1、文案不说"还差 0 次"', () {
    final int top = kLevelThresholds.last.at;
    final LevelInfo info = levelFor(top);
    expect(info.isMax, isTrue);
    expect(info.nextAt, isNull);
    expect(info.progress, 1);
    expect(info.toNext, 0);
    expect(levelHint(info), '已经是最高等级');
    expect(levelFor(top + 999).level, kLevelThresholds.length);
  });

  test('进度是**当前级别内**的比例（不是全局比例）', () {
    // Lv2 从 5 到 15：10 次在区间中点
    expect(levelFor(5).progress, 0);
    expect(levelFor(10).progress, closeTo(0.5, 0.001));
    expect(levelFor(14).progress, closeTo(0.9, 0.001));
  });

  test('标签：一行念出等级与称号，说明里带"还差 N 次"', () {
    final LevelInfo info = levelFor(60);
    expect(levelLabel(info), 'Lv.5 · 力量进阶者');
    expect(levelHint(info), '还差 60 次训练升到 Lv.6');
  });

  test('一路升上去不会跳级：每次刚好跨门槛只加一级', () {
    int last = 1;
    for (final ({int at, String title}) t in kLevelThresholds) {
      final LevelInfo info = levelFor(t.at);
      expect(info.level, greaterThanOrEqualTo(last));
      expect(info.level - last, lessThanOrEqualTo(1), reason: '${t.at} 次时跳了一级以上');
      expect(info.title, t.title);
      last = info.level;
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 「我」页上的那一块（等级卡）
// ─────────────────────────────────────────────────────────────────────────────

void _levelUi() {
  testWidgets('「我」页显示 Lv.N 与称号，且数字与数据层一致', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final DriftLocalStore store = DriftLocalStore(db);
    // 6 次训练 → Lv.2（门槛 5）
    for (int w = 0; w < 6; w++) {
      for (int s = 0; s < 2; s++) {
        await store.saveSet(SetRecord(
          id: 'w$w-s$s',
          workoutId: 'w$w',
          exerciseId: 'ex_bb_bench_press',
          setIndex: s,
          weightKg: 60,
          reps: 8,
          completedAtMs: DateTime(2026, 9, 20 + w, 9).millisecondsSinceEpoch,
        ));
      }
    }
    await ProfileRepository(db).setPrivacyConsent(nowMs: 1);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      // 与 `profile_structure_test` 同一个形状：这一屏返回的是 ListView，
      // 需要一个 Scaffold 当壳（真实调用点在 `main.dart` 的外壳里）
      home: Scaffold(
        body: ProfileScreen(
          store: store,
          repository: ExerciseRepository(db),
          profile: ProfileRepository(db),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('profile-level-number'))).data, '2');
    expect(tester.widget<Text>(find.byKey(const Key('profile-level-label'))).data,
        'Lv.2 · 开始上道');
    expect(find.textContaining('还差'), findsWidgets);
  });
}
