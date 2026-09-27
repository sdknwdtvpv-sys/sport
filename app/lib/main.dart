/// 练了么 · 应用入口
///
/// 当前阶段刻意使用内存实现（InMemoryLocalStore / RecordingAnalytics）：
/// 目标是把"契约可执行 + CI 能跑"这件事做扎实，而不是假装功能完整。
/// 接 drift 时替换 `_store` 的构造即可，UI 与控制器一行不用改。
library;

import 'package:flutter/material.dart';

import 'analytics/analytics.dart';
import 'core/theme.dart';
// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，
// 同时裸 import 两个库时，一用到同名类就 ambiguity_import。这里预先 hide 掉。
import 'data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'data/drift_local_store.dart';
import 'data/exercise_repository.dart';
import 'data/local_store.dart';
import 'data/sync_queue.dart';
import 'domain/models.dart';
import 'features/exercise/exercise_picker_screen.dart';
import 'features/today/today_screen.dart';
import 'features/workout/workout_controller.dart';
import 'features/workout/workout_screen.dart';

void main() {
  runApp(const LianLeMeApp());
}

/// 从动作库选中的动作统一用这个处方：3 组 8–10 次。
///
/// 简化：真实产品应当按动作给不同区间（核心动作 3×8-12、平板支撑按秒等），
/// 那是 S2 今日建议卡 / S11 计划模板的活儿。这里先统一，好让阶段 3 能开跑。
const PlanTarget kDefaultPlan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

class LianLeMeApp extends StatelessWidget {
  const LianLeMeApp({super.key, this.database});

  /// 测试注入内存库；生产传 null，由 [HomeShell] 打开真实库。
  /// 不注入的话 widget 测试会去碰 path_provider —— 那里没有平台通道。
  final AppDatabase? database;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '练了么',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeShell(database: database),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.database});

  final AppDatabase? database;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final Analytics _analytics = RecordingAnalytics();
  final SyncQueue _syncQueue = InMemorySyncQueue();

  /// 持久化：drift（SQLite）。数据活过重启 —— 见 ROADMAP 阶段 1。
  /// 换回内存实现只需把下面两行改成 `InMemoryLocalStore()`。
  late final AppDatabase _db = widget.database ?? openAppDatabase();
  late final LocalStore _store = DriftLocalStore(_db);
  late final ExerciseRepository _repo = ExerciseRepository(_db);

  @override
  void dispose() {
    // 外部注入的库由注入方负责关闭，我们只关自己打开的
    if (widget.database == null) _db.close();
    super.dispose();
  }

  Future<void> _startSession() async {
    // 幂等，所以每次开始训练都调一次，保证种子一定在库里
    await _repo.importSeed();
    if (!mounted) return;

    // 一次训练 = 一个 workoutId。选动作 → 练 → 回来再选下一个，
    // 所有记录都挂在这一条 workout 下（而不是拆成多次训练）。
    final String workoutId = 'w_${DateTime.now().millisecondsSinceEpoch}';

    while (mounted) {
      final ExerciseData? picked = await Navigator.of(context).push<ExerciseData>(
        MaterialPageRoute<ExerciseData>(
          builder: (_) => ExercisePickerScreen(repository: _repo),
        ),
      );
      if (picked == null || !mounted) break; // 用户从选择页返回 = 结束本次训练

      final controller = WorkoutController(
        workoutId: workoutId,
        exercise: _repo.specOf(picked),
        plan: kDefaultPlan,
        analytics: _analytics,
        store: _store,
        syncQueue: _syncQueue,
      );
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => WorkoutScreen(controller: controller)),
      );
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TodayScreen(onStart: _startSession);
  }
}
