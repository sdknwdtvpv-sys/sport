/// 练了么 · S8「进步」的测试（数据 + 界面）
///
/// 日期边界是这一屏最容易错的地方：窗口是「含今天在内的最近 7 天」，
/// 第 8 天前的记录不能算进来，边界那天要算进来。全部用固定时间测，不依赖"现在"。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/progress_data.dart';
import 'package:lianleme/features/progress/progress_screen.dart';

/// 固定「今天」：2026-09-27 15:00（本地时间）
final DateTime kToday = DateTime(2026, 9, 27, 15);

int at(DateTime d) => d.millisecondsSinceEpoch;

SetRecord _set({
  required String id,
  String workoutId = 'w1',
  String exerciseId = 'ex_bb_bench_press',
  int setIndex = 1,
  int reps = 8,
  double? weightKg = 60,
  required DateTime when,
}) =>
    SetRecord(
      id: id,
      workoutId: workoutId,
      exerciseId: exerciseId,
      setIndex: setIndex,
      reps: reps,
      weightKg: weightKg,
      completedAtMs: at(when),
    );

void main() {
  group('最近 7 天', () {
    test('永远返回 7 天，且最后一天是今天', () {
      final List<DailyVolume> week = lastSevenDays(<SetRecord>[], kToday);
      expect(week.length, 7);
      expect(week.last.day, DateTime(2026, 9, 27), reason: '最后一天是今天');
      expect(week.first.day, DateTime(2026, 9, 21), reason: '往前数 6 天');
    });

    test('同一天的记录合并到一格', () {
      final List<DailyVolume> week = lastSevenDays(<SetRecord>[
        _set(id: 'a', when: DateTime(2026, 9, 27, 9)),
        _set(id: 'b', setIndex: 2, when: DateTime(2026, 9, 27, 20)),
      ], kToday);

      expect(week.last.volumeKg, 60 * 8 * 2);
      expect(week[0].volumeKg, 0);
    });

    test('窗口边界：第 7 天前（9/20）不算进来', () {
      final List<DailyVolume> week = lastSevenDays(<SetRecord>[
        _set(id: 'old', when: DateTime(2026, 9, 20, 23, 59)),
      ], kToday);

      expect(week.every((DailyVolume d) => d.isEmpty), isTrue);
    });

    test('窗口边界：第一天（9/21）要算进来', () {
      final List<DailyVolume> week = lastSevenDays(<SetRecord>[
        _set(id: 'edge', when: DateTime(2026, 9, 21, 0, 1)),
      ], kToday);

      expect(week.first.volumeKg, 60 * 8, reason: '9/21 是窗口第一天');
    });

    test('今天之后的时间不落进任何一格（防止时钟偏移导致错乱）', () {
      final List<DailyVolume> week = lastSevenDays(<SetRecord>[
        _set(id: 'future', when: DateTime(2026, 9, 28, 10)),
      ], kToday);

      expect(week.every((DailyVolume d) => d.isEmpty), isTrue);
    });
  });

  group('本周训练次数', () {
    test('按 workoutId 去重', () {
      final int n = weekWorkoutCount(<SetRecord>[
        _set(id: 'a', workoutId: 'w1', when: DateTime(2026, 9, 27, 9)),
        _set(id: 'b', workoutId: 'w1', setIndex: 2, when: DateTime(2026, 9, 27, 9)),
        _set(id: 'c', workoutId: 'w2', when: DateTime(2026, 9, 25, 9)),
      ], kToday);

      expect(n, 2);
    });

    test('窗口外的训练不算', () {
      final int n = weekWorkoutCount(<SetRecord>[
        _set(id: 'old', workoutId: 'w_old', when: DateTime(2026, 9, 1, 9)),
      ], kToday);

      expect(n, 0);
    });
  });

  group('PR 墙', () {
    final Map<String, String> names = <String, String>{
      'ex_bb_bench_press': '杠铃卧推',
      'ex_bb_squat': '杠铃深蹲',
      'ex_pull_up': '引体向上',
    };

    test('有重量的比重量', () {
      final List<ExercisePr> prs = personalBests(
        sets: <SetRecord>[
          _set(id: 'a', weightKg: 60, when: DateTime(2026, 9, 27, 9)),
          _set(id: 'b', setIndex: 2, weightKg: 80, when: DateTime(2026, 9, 27, 9)),
          _set(id: 'c', setIndex: 3, weightKg: 70, when: DateTime(2026, 9, 27, 9)),
        ],
        exerciseNames: names,
      );

      expect(prs.single.weightKg, 80);
      expect(prs.single.label, '80kg');
      expect(prs.single.name, '杠铃卧推');
    });

    test('自重的比次数，不比公斤', () {
      final List<ExercisePr> prs = personalBests(
        sets: <SetRecord>[
          _set(id: 'a', exerciseId: 'ex_pull_up', reps: 8, weightKg: null, when: DateTime(2026, 9, 27, 9)),
          _set(id: 'b', exerciseId: 'ex_pull_up', setIndex: 2, reps: 15, weightKg: null, when: DateTime(2026, 9, 27, 9)),
        ],
        exerciseNames: names,
      );

      expect(prs.single.isBodyweight, isTrue);
      expect(prs.single.reps, 15);
      expect(prs.single.label, '15 次');
    });

    test('按数值降序（重的在前）', () {
      final List<ExercisePr> prs = personalBests(
        sets: <SetRecord>[
          _set(id: 'a', weightKg: 60, when: DateTime(2026, 9, 27, 9)),
          _set(id: 'b', exerciseId: 'ex_bb_squat', weightKg: 100, when: DateTime(2026, 9, 27, 9)),
          _set(id: 'c', exerciseId: 'ex_pull_up', reps: 12, weightKg: null, when: DateTime(2026, 9, 27, 9)),
        ],
        exerciseNames: names,
      );

      expect(prs.map((ExercisePr p) => p.exerciseId).toList(),
          <String>['ex_bb_squat', 'ex_bb_bench_press', 'ex_pull_up']);
    });

    test('名字查不到时用 id 兜底', () {
      final List<ExercisePr> prs = personalBests(
        sets: <SetRecord>[_set(id: 'a', exerciseId: 'ex_unknown', when: DateTime(2026, 9, 27, 9))],
        exerciseNames: names,
      );

      expect(prs.single.name, 'ex_unknown');
    });
  });

  group('曲线与总量', () {
    test('全 0 时曲线也全是 0（不除以 0）', () {
      final ProgressData d = buildProgress(
        sets: <SetRecord>[],
        exerciseNames: <String, String>{},
        today: kToday,
      );
      expect(d.sparkline.every((double v) => v == 0), isTrue);
      expect(d.weekVolumeLabel, '—');
      expect(d.isEmpty, isTrue);
    });

    test('峰值归一化为 1', () {
      final ProgressData d = buildProgress(
        sets: <SetRecord>[
          _set(id: 'a', reps: 10, weightKg: 100, when: DateTime(2026, 9, 27, 9)), // 1000
          _set(id: 'b', when: DateTime(2026, 9, 26, 9)), // 480
        ],
        exerciseNames: <String, String>{},
        today: kToday,
      );

      expect(d.sparkline.last, 1.0, reason: '今天是峰值');
      expect(d.sparkline[5], closeTo(480 / 1000, 0.0001));
      expect(d.weekVolume, 1480);
      expect(d.weekVolumeLabel, '1,480 kg');
    });
  });

  group('界面', () {
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

    Future<void> pumpProgress(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProgressScreen(store: store, repository: repo, now: kToday),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('没有记录时给明确说明，而不是一张空图表', (WidgetTester tester) async {
      await pumpProgress(tester);

      expect(find.textContaining('还没有训练记录'), findsOneWidget);
      expect(find.byKey(const Key('progress-sparkline')), findsNothing);
    });

    testWidgets('有记录时显示本周容量、次数与 PR 墙', (WidgetTester tester) async {
      await store.saveSet(_set(id: 'a', when: DateTime(2026, 9, 27, 10)));
      await store.saveSet(_set(id: 'b', setIndex: 2, when: DateTime(2026, 9, 27, 10)));
      await pumpProgress(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('progress-week-volume'))).data,
        '960 kg',
      );
      expect(find.textContaining('这 7 天练了 1 次'), findsOneWidget);
      expect(find.byKey(const Key('progress-sparkline')), findsOneWidget);
      expect(find.byKey(const Key('pr-ex_bb_bench_press')), findsOneWidget);
      expect(find.text('杠铃卧推'), findsOneWidget);
      expect(find.text('60kg'), findsOneWidget);
    });

    testWidgets('窗口外的记录不显示（本周为空但历史有记录）',
        (WidgetTester tester) async {
      await store.saveSet(_set(id: 'old', when: DateTime(2026, 9, 1, 10)));
      await pumpProgress(tester);

      // PR 墙仍然有（历史最佳），但本周容量是 —
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('这 7 天还没练'), findsOneWidget);
      expect(find.byKey(const Key('pr-ex_bb_bench_press')), findsOneWidget);
    });
  });
}
