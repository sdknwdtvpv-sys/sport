/// 练了么 · **动作库**（2026-10-05，新 VI 的 `vi/complete-library.html` 第二屏）
///
/// 与「选动作」的关系：那一个是**训练里选一个动作**（点完带着结果返回），
/// 这一个是**看**——搜、按部位筛、翻分类，点进去看这个动作的历史与做法。
/// 两者共用同一个列表实现（`ExercisePickerScreen`，靠 `onBrowse` 区分行为），
/// 因为**列表的样子与筛选手感必须一致** —— 同一份数据两套界面迟早会长歪。
///
/// ⚠️ 首页那个「动作库」磁贴以前是**过渡状态**：跳去的是「全部数据」（按动作看历史）。
/// 这一版把它换成真正的动作库，那处偏差就此收掉。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/db.dart' show ExerciseData;
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import 'exercise_detail_screen.dart';
import 'exercise_picker_screen.dart';

class ExerciseLibraryScreen extends StatelessWidget {
  const ExerciseLibraryScreen({
    super.key,
    required this.repository,
    this.store,
    this.unit = WeightUnit.kg,
  });

  final ExerciseRepository repository;

  /// 「最近做过 / 置顶」两个分区要用。可选，但生产环境会传。
  final LocalStore? store;

  final WeightUnit unit;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Tokens.bg,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        key: const Key('library-back'),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: Tokens.s3),
                    const Text('动作库',
                        style: TextStyle(
                            color: Tokens.text, fontSize: Tokens.fsHeadline, fontWeight: Tokens.fwBold)),
                  ],
                ),
              ),
              Expanded(
                // 浏览态：点动作**打开详情**，而不是把这个页面关掉
                child: ExercisePickerScreen(
                  repository: repository,
                  store: store,
                  unit: unit,
                  onBrowse: (ExerciseData e) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ExerciseDetailScreen(
                          exercise: e,
                          store: store,
                          unit: unit,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
}
