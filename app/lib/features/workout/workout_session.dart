/// 练了么 · 一次训练里的全部动作（S6）
///
/// 为什么需要这一层：原来的多动作流程是「每个动作 push/pop 一次训练屏」，
/// 于是训练屏里根本没有"其它动作"这个概念 —— 底部那条
/// 「‹ 上一个动作　动作 1 / 1　下一个动作 ›」是**死的装饰**，
/// 而假的可点按元件比没有更糟（项目在 Tab 栏上已经踩过一次）。
///
/// 这里把一次训练里的多个动作收进一个会话，训练屏只渲染当前那个，
/// 底部条与左右滑动在它们之间切换。规格明确要求**不弹全屏列表**：
/// 训练中不该迷路。
library;

import 'package:flutter/foundation.dart';

import '../../data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import '../../domain/models.dart';
import '../../domain/tap_meter.dart';
import 'workout_controller.dart';

/// 会话里的一项：练哪个动作、按什么处方。
///
/// 处方必须**逐项**带着 —— 计划模板（S11）里每个动作的组数与次数区间是分开的，
/// 一律套用默认处方会让计划模板形同虚设。
class SessionEntry {
  const SessionEntry({required this.exercise, required this.plan});

  final ExerciseData exercise;
  final PlanTarget plan;
}

class WorkoutSession extends ChangeNotifier {
  WorkoutSession(List<WorkoutController> controllers)
      : assert(controllers.isNotEmpty, '会话至少要有一个动作'),
        _controllers = List<WorkoutController>.unmodifiable(controllers) {
    for (final WorkoutController c in _controllers) {
      c.addListener(_relay);
    }
  }

  /// 只有一个动作的会话 —— 「我自己选」那条流程每次只加一个动作。
  factory WorkoutSession.single(WorkoutController c) =>
      WorkoutSession(<WorkoutController>[c]);

  final List<WorkoutController> _controllers;
  int _index = 0;

  List<WorkoutController> get controllers => _controllers;
  int get index => _index;
  int get length => _controllers.length;

  WorkoutController get current => _controllers[_index];

  /// 多于一个动作时才值得显示切换条：只有一个时那条「1 / 1」没有信息量，
  /// 还会让人以为可以滑。
  bool get hasMultiple => _controllers.length > 1;

  bool get canGoPrevious => _index > 0;
  bool get canGoNext => _index < _controllers.length - 1;

  /// 换到上一个 / 下一个动作。
  ///
  /// 切换**要计一次点击**（端到端口径）：用户为得到下一组多操作了一次，
  /// 而"底部条是不是常用"正是产品要回答的问题 —— 不计就等于假装它不存在。
  /// 计在**切换后**的那个控制器上，因为那一组是它记的。
  void previous() {
    if (!canGoPrevious) return;
    _index--;
    current.analytics.countTap(TapKind.exerciseSwitch);
    notifyListeners();
  }

  void next() {
    if (!canGoNext) return;
    _index++;
    current.analytics.countTap(TapKind.exerciseSwitch);
    notifyListeners();
  }

  /// 前一个 / 后一个动作的名字，给底部条显示（规格的示意图就是这两个名字）。
  /// 没有时返回 null，由界面决定显示什么。
  String? get previousName => canGoPrevious ? _controllers[_index - 1].exercise.name : null;
  String? get nextName => canGoNext ? _controllers[_index + 1].exercise.name : null;

  /// 当前动作之前所有动作记了多少组 —— 总结页与"今天练了啥"要用。
  int get totalSetsSoFar =>
      _controllers.fold<int>(0, (int sum, WorkoutController c) => sum + c.loggedSets.length);

  void _relay() => notifyListeners();

  @override
  void dispose() {
    // **控制器由调用方持有并 dispose** —— 沿用 WorkoutScreen 原本的约定，
    // 这样测试可以在页面销毁之后继续断言控制器状态。
    // 这里只摘掉自己挂上去的监听，避免泄漏。
    for (final WorkoutController c in _controllers) {
      c.removeListener(_relay);
    }
    super.dispose();
  }
}
