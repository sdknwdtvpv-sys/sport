/// 练了么 · 「今天的安排」编辑器（2026-10-09，10.9 清单第 6 条）
///
/// 用户原话：「今天的安排」要能**长按拖动**调整顺序 / 删除 / 替换动作。
///
/// ## 为什么编辑放在一个弹层里，而不是直接在首页上拖
///
/// 首页整块是**一条滚动列表**里的卡片：就地拖动会与"上下滚页面"抢同一个手势，
/// 而且首页上那几行本来就点得动（点整块进建议卡）。真机上"想滚一下却把动作拖走了"
/// 比"少一步"更糟。所以：**长按首页那一行 → 进这个弹层**，弹层里长按行即可拖动。
/// 弹层里只有这一件事，手势不会打架 —— 而且它一眼看得出"我在改什么"。
///
/// ## 三种操作怎么落地
///
///   * **拖动排序** → 长按任意一行（`ReorderableDelayedDragStartListener`）；
///   * **替换** → 打开动作选择器（**按这个动作的部位预筛** —— 换的是"同一块肌肉的另一个动作"，
///     而不是从 351 个里重找一遍），选中的动作**沿用原来那一格的处方**；
///   * **删除** → 就地从清单里去掉。全删光也是允许的（"今天不想练这些"），
///     那种情况下首页会如实显示「今天还没有排动作」，`换一批` 能重新生成。
///
/// ⚠️ **只改"练哪几个"，不改"练多少"**：处方（组数/次数）沿用原来那一格 ——
/// 用户要的是换个动作，不是重新定计划（与训练屏「器械被占 → 换一个动作」同一条纪律）。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/db.dart' show ExerciseData;
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../exercise/exercise_picker_screen.dart';
import 'today_planner.dart';

/// 打开编辑器。[plan] 是当前那份安排。
///
/// 返回**用户确认后的新清单**（顺序 / 增删都定了）；直接关掉弹层返回 null
/// （= 什么都没改，调用方一个字都不用动）。
Future<List<PlannedExercise>?> showDayPlanEditor(
  BuildContext context, {
  required List<PlannedExercise> plan,
  required TodayPlanner planner,
  required ExerciseRepository repository,
  LocalStore? store,
  WeightUnit unit = WeightUnit.kg,
}) {
  return showModalBottomSheet<List<PlannedExercise>>(
    context: context,
    backgroundColor: Tokens.surface,
    // 清单可能有 6 行 + 两个按钮：默认高度（半屏）会把它挤成"只能看两行"。
    isScrollControlled: true,
    // ⚠️ **关掉"往下拖关掉弹层"**：弹层内容本身就要接收竖直拖动（拖动排序），
    // 而 BottomSheet 自带的下滑手势会**先赢下手势竞技场** —— 结果是"按住一行往上推，
    // 整个弹层被拖下去了、顺序一点没变"（写这一条时测试当场抓到）。
    // 关掉它不损失什么：右上角有「完成」，点外面也能关。
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.rCard)),
    ),
    builder: (BuildContext ctx) => _DayPlanEditor(
      plan: plan,
      planner: planner,
      repository: repository,
      store: store,
      unit: unit,
    ),
  );
}

class _DayPlanEditor extends StatefulWidget {
  const _DayPlanEditor({
    required this.plan,
    required this.planner,
    required this.repository,
    this.store,
    this.unit = WeightUnit.kg,
  });

  final List<PlannedExercise> plan;
  final TodayPlanner planner;
  final ExerciseRepository repository;
  final LocalStore? store;
  final WeightUnit unit;

  @override
  State<_DayPlanEditor> createState() => _DayPlanEditorState();
}

class _DayPlanEditorState extends State<_DayPlanEditor> {
  late List<PlannedExercise> _items = List<PlannedExercise>.of(widget.plan);

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      // ⚠️ 用的是 `onReorderItem`（新的那个回调）：它给的 `newIndex`
      // **已经**按"移走之后"算过了，所以这里不需要再 `if (newIndex > oldIndex) newIndex--`
      // —— 老的 `onReorder` 才要那一步（老 API 在 3.41 起废弃）。
      final PlannedExercise moved = _items.removeAt(oldIndex);
      _items.insert(newIndex, moved);
    });
  }

  void _remove(int index) {
    setState(() => _items.removeAt(index));
  }

  /// 替换第 [index] 个动作：同部位预筛 → 选一个 → **沿用原来那一格的处方**。
  Future<void> _replace(int index) async {
    final PlannedExercise old = _items[index];
    final ExerciseData? picked = await Navigator.of(context).push<ExerciseData>(
      MaterialPageRoute<ExerciseData>(
        builder: (_) => ExercisePickerScreen(
          repository: widget.repository,
          store: widget.store,
          unit: widget.unit,
          initialMuscle: old.exercise.muscleGroup,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final List<PlannedExercise> built = await widget.planner.planFromRoutine(
      entries: <RoutineEntry>[
        RoutineEntry(exerciseId: picked.id, plan: old.plan),
      ],
      unit: widget.unit,
    );
    if (!mounted) return;
    if (built.isEmpty) {
      // 动作刚被删掉了 / 库里查不到：如实说一句，不静默什么都不做
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个动作现在取不到了，换一个试试')),
      );
      return;
    }
    setState(() => _items[index] = built.first);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          key: const Key('plan-editor'),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Tokens.s5, Tokens.s4, Tokens.s3, Tokens.s2),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text('调整今天的安排',
                        style: TextStyle(
                            color: Tokens.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w600)),
                  ),
                  TextButton(
                    key: const Key('plan-edit-done'),
                    onPressed: () => Navigator.of(context).pop(_items),
                    style: TextButton.styleFrom(foregroundColor: Tokens.accent),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
            // 说法要摆在这儿：只改"练哪几个"，不改组数次数
            const Padding(
              padding: EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, Tokens.s2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('长按一行可以拖动排序；只改练哪几个，组数次数不动',
                    style: TextStyle(color: Tokens.text3, fontSize: 12.5, height: 1.4)),
              ),
            ),
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(Tokens.s5, Tokens.s5, Tokens.s5, Tokens.s6),
                child: Text('今天的动作都删光了 —— 回首页点「换一批」可以重新生成一份。',
                    key: Key('plan-edit-empty'),
                    style: TextStyle(color: Tokens.text3, fontSize: 14, height: 1.6)),
              )
            else
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
                  itemCount: _items.length,
                  // 默认的拖动把手是"长按整块"（Android/iOS），但那样与下面的
                  // 替换/删除按钮共处一行时，长按按钮也会被当成拖动。
                  // 自己包一层延迟监听，把"长按拖动"的范围说清楚（整行都能拖）。
                  buildDefaultDragHandles: false,
                  onReorderItem: _reorder,
                  itemBuilder: (BuildContext ctx, int i) {
                    final PlannedExercise e = _items[i];
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey<String>('plan-edit-${e.exercise.id}'),
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.drag_handle,
                                size: 18, color: Tokens.text3),
                            const SizedBox(width: Tokens.s2),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(e.exercise.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Tokens.text, fontSize: 14)),
                                  Text(e.loadLabel,
                                      style: const TextStyle(
                                          color: Tokens.text3, fontSize: 12)),
                                ],
                              ),
                            ),
                            IconButton(
                              key: Key('plan-edit-replace-${e.exercise.id}'),
                              tooltip: '换一个',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.swap_horiz,
                                  size: 18, color: Tokens.text2),
                              onPressed: () => _replace(i),
                            ),
                            IconButton(
                              key: Key('plan-edit-delete-${e.exercise.id}'),
                              tooltip: '删掉',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close,
                                  size: 18, color: Tokens.text3),
                              onPressed: () => _remove(i),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: Tokens.s4),
          ],
        ),
      ),
    );
  }
}
