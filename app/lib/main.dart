/// 练了么 · 应用入口
///
/// 当前阶段刻意使用内存实现（InMemoryLocalStore / RecordingAnalytics）：
/// 目标是把"契约可执行 + CI 能跑"这件事做扎实，而不是假装功能完整。
/// 接 drift 时替换 `_store` 的构造即可，UI 与控制器一行不用改。
library;

import 'package:flutter/material.dart';

import 'analytics/analytics.dart';
import 'core/theme.dart';
import 'data/local_store.dart';
import 'data/sync_queue.dart';
import 'domain/models.dart';
import 'features/today/today_screen.dart';
import 'features/workout/workout_controller.dart';
import 'features/workout/workout_screen.dart';

void main() {
  runApp(const LianLeMeApp());
}

/// MVP 阶段的处方：杠铃卧推 3 组 8–10 次。
/// 数值与 `seed/exercises.json` 里的 ex_bb_bench_press 保持一致。
const ExerciseSpec kStarterExercise = ExerciseSpec(
  id: 'ex_bb_bench_press',
  name: '杠铃卧推',
  weightIncrement: 2.5,
  defaultWeightKg: 40,
  defaultRestSec: 120,
);

const PlanTarget kStarterPlan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

class LianLeMeApp extends StatelessWidget {
  const LianLeMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '练了么',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final Analytics _analytics = RecordingAnalytics();
  final LocalStore _store = InMemoryLocalStore();
  final SyncQueue _syncQueue = InMemorySyncQueue();

  Future<void> _startWorkout() async {
    final controller = WorkoutController(
      exercise: kStarterExercise,
      plan: kStarterPlan,
      analytics: _analytics,
      store: _store,
      syncQueue: _syncQueue,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutScreen(controller: controller),
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TodayScreen(onStart: _startWorkout);
  }
}
